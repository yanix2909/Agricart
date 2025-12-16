import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'utils/rider_session.dart';
import 'services/supabase_service.dart';
import 'screens/chat_screen.dart';
import 'utils/theme.dart';
import 'utils/responsive.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? _riderId;
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _staffNotesChannel;
  Timer? _refreshTimer;
  Timer? _accountStatusTimer;
  Future<List<Map<String, dynamic>>>? _ordersFuture;
  DateTime? _selectedWeekStart;
  final GlobalKey _qrKey = GlobalKey();
  bool _qrAssetExists = true;
  // Map to store staff notes for each order: orderId -> List<Map<String, dynamic>>
  final Map<String, List<Map<String, dynamic>>> _staffNotesCache = {};
  // Map to store dialog rebuild callbacks: orderId -> setState callback
  final Map<String, VoidCallback> _dialogRebuildCallbacks = {};

  @override
  void initState() {
    super.initState();
    _initRider();
    _verifyQrAsset();
  }

  Future<void> _verifyQrAsset() async {
    const path = 'assets/images/order_gcash_qr.JPG';
    try {
      await rootBundle.load(path);
      setState(() {
        _qrAssetExists = true;
      });
    } catch (_) {
      setState(() {
        _qrAssetExists = false;
      });
    }
  }

  Future<void> _saveQrToGallery(double amount) async {
    try {
      // Request permissions on Android (Photos permission on iOS is handled by the saver)
      final status = await Permission.photos.request();
      if (!status.isGranted && Platform.isAndroid) {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied'), backgroundColor: Colors.red),
          );
          return;
        }
      }

      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR not ready yet'), backgroundColor: Colors.red),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture QR'), backgroundColor: Colors.red),
        );
        return;
      }

      final file = Uint8List.fromList(pngBytes);
      final success = await Gal.putImageBytes(file).then((_) => true).catchError((_) => false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'QR saved to gallery' : 'Failed to save QR'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving QR: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _initRider() async {
    final id = await RiderSession.getId();
    final email = await RiderSession.getEmail();
    debugPrint('DEBUG: Rider ID from session: $id');
    
      if (mounted) {
        setState(() {
          _riderId = id;
          if (id != null && id.isNotEmpty) {
            _ordersFuture = _fetchOrdersFromSupabase(id);
            _startAccountStatusMonitoring(id, email);
          }
        });
        // Removed automatic refresh - app will only load once on init
        // if (id != null && id.isNotEmpty) {
        //   _setupSupabaseRealtimeListener(id);
        //   _startPeriodicRefresh(id);
        // }
      }
  }

  void _startAccountStatusMonitoring(String riderId, String? email) {
    _accountStatusTimer?.cancel();
    
    _accountStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        if (!SupabaseService.isInitialized) {
          await SupabaseService.initialize();
        }

        final supabase = SupabaseService.client;
        
        // Check if rider account exists and is active
        final response = await supabase
            .from('riders')
            .select('uid, is_active')
            .eq('uid', riderId)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));

        if (response == null || response.isEmpty) {
          // Rider account not found (removed)
          debugPrint('⚠️ Rider account not found - account removed');
          _handleAccountDeactivation();
          timer.cancel();
          return;
        }

        final isActive = response['is_active'] as bool?;
        if (isActive != true) {
          // Rider account is deactivated
          debugPrint('⚠️ Rider account deactivated');
          _handleAccountDeactivation();
          timer.cancel();
          return;
        }

        debugPrint('✅ Rider account is active');
      } on TimeoutException {
        // Network timeout - don't treat as deactivation, just skip this check
        debugPrint('⏱️ Account status check timed out - skipping');
      } catch (e) {
        // Network or other errors - don't treat as deactivation
        debugPrint('⚠️ Error checking account status: $e - skipping');
      }
    });
  }

  void _handleAccountDeactivation() {
    debugPrint('🚫 Handling rider account deactivation...');
    
    // Clear session
    RiderSession.clear().then((_) {
      debugPrint('✅ Rider session cleared');
    });
    
    // Navigate to login screen
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }
  
  void _refreshOrders() {
    if (_riderId != null && _riderId!.isNotEmpty) {
      setState(() {
        _ordersFuture = _fetchOrdersFromSupabase(_riderId!);
      });
    }
  }

  void _setupSupabaseRealtimeListener(String riderId) {
    try {
      if (!SupabaseService.isInitialized) {
        SupabaseService.initialize().then((_) => _setupSupabaseRealtimeListener(riderId));
        return;
      }

      final supabase = SupabaseService.client;
      
      debugPrint('🔗 Setting up Supabase real-time listener for rider: $riderId');
      
      _ordersChannel?.unsubscribe();
      _ordersChannel = supabase
          .channel('delivery_orders_$riderId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'delivery_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'rider_id',
              value: riderId,
            ),
            callback: (payload) {
              if (mounted) {
                debugPrint('📡 Supabase real-time update received: ${payload.eventType}');
                // Removed automatic refresh - user must manually refresh
                // _refreshOrders();
              }
            },
          )
          .subscribe();
      
      // Setup real-time listener for staff notes
      _setupStaffNotesRealtimeListener(riderId);
      
      debugPrint('✅ Supabase real-time listener subscribed');
    } catch (e) {
      debugPrint('❌ Error setting up Supabase real-time listener: $e');
    }
  }

  void _setupStaffNotesRealtimeListener(String riderId) {
    try {
      if (!SupabaseService.isInitialized) return;

      final supabase = SupabaseService.client;
      
      debugPrint('🔗 Setting up staff notes real-time listener for rider: $riderId');
      
      // Listen to all staff notes changes (we'll filter by order_id in callback)
      // This way we catch notes for any order assigned to this rider, even if not currently loaded
      _staffNotesChannel?.unsubscribe();
      _staffNotesChannel = supabase
          .channel('staff_notes_$riderId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_staff_notes',
            callback: (payload) {
              if (mounted) {
                debugPrint('📝 Staff notes real-time update: ${payload.eventType}');
                final orderId = payload.newRecord?['order_id']?.toString() ?? 
                                payload.oldRecord?['order_id']?.toString() ?? '';
                
                if (orderId.isNotEmpty) {
                  // Check if this order belongs to the current rider
                  _ordersFuture?.then((orders) {
                    final orderIds = orders.map((o) => o['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
                    if (orderIds.contains(orderId)) {
                      // Refresh staff notes for this order
                      _fetchStaffNotesForOrder(orderId).then((notes) {
                        if (mounted) {
                          setState(() {
                            _staffNotesCache[orderId] = notes;
                            // Force rebuild of any open dialogs
                            // The StatefulBuilder in _buildNotesSection will detect the cache change
                          });
                        }
                      });
                    }
                  });
                }
              }
            },
          )
          .subscribe();
      
      debugPrint('✅ Staff notes real-time listener subscribed');
    } catch (e) {
      debugPrint('❌ Error setting up staff notes real-time listener: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchStaffNotesForOrder(String orderId) async {
    try {
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }

      final supabase = SupabaseService.client;
      
      debugPrint('🔍 Fetching staff notes for order: $orderId');
      
      final response = await supabase
          .from('order_staff_notes')
          .select('*')
          .eq('order_id', orderId)
          .order('noted_at', ascending: false);
      
      if (response == null) {
        debugPrint('⚠️ Staff notes query returned null for order $orderId');
        return [];
      }
      
      final notes = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ Fetched ${notes.length} staff notes for order $orderId');
      
      if (notes.isNotEmpty) {
        debugPrint('📝 Staff notes data: ${notes.map((n) {
          final noteText = n['note_text']?.toString() ?? '';
          if (noteText.isEmpty) return 'empty';
          final length = noteText.length;
          return noteText.substring(0, length > 50 ? 50 : length);
        }).join(', ')}');
      }
      
      return notes;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching staff notes for order $orderId: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return [];
    }
  }

  void _startPeriodicRefresh(String riderId) {
    _refreshTimer?.cancel();
    // Refresh every 30 seconds as backup (less frequent to reduce glitching)
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _refreshOrders(); // Refresh orders without glitching
      }
    });
  }

  @override
  void dispose() {
    _ordersChannel?.unsubscribe();
    _staffNotesChannel?.unsubscribe();
    _refreshTimer?.cancel();
    _accountStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final riderId = _riderId;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Assigned Orders'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            tooltip: 'Open Chats',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RiderChatScreen()),
              );
            },
          ),
        ],
      ),
      body: riderId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Orders List
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _ordersFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      if (snapshot.hasError) {
                        debugPrint('DEBUG: Error fetching orders: ${snapshot.error}');
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading orders',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                snapshot.error.toString(),
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      
                      final allOrders = snapshot.data ?? [];
                      debugPrint('DEBUG: Found ${allOrders.length} total delivery orders for rider $riderId');

                      // Group orders by week (Monday-Sunday) based on assigned_at or created_at
                      final Map<DateTime, List<Map<String, dynamic>>> weekGroups = {};
                      for (final o in allOrders) {
                        final ts = (o['assigned_at'] ?? o['created_at'] ?? 0) as int? ?? 0;
                        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                        final weekStart = dt.subtract(Duration(days: (dt.weekday - DateTime.monday) % 7));
                        final weekKey = DateTime(weekStart.year, weekStart.month, weekStart.day);
                        weekGroups.putIfAbsent(weekKey, () => []).add(o);
                      }

                      // Build a sorted list of weeks (newest first)
                      final weeks = weekGroups.keys.toList()
                        ..sort((a, b) => b.millisecondsSinceEpoch.compareTo(a.millisecondsSinceEpoch));

                      // Determine currently selected week (default to this week or most recent)
                      final nowDt = DateTime.now();
                      final thisWeekStart = DateTime(nowDt.year, nowDt.month, nowDt.day)
                          .subtract(Duration(days: (nowDt.weekday - DateTime.monday) % 7));

                      DateTime? selectedWeek;
                      if (_selectedWeekStart != null && weeks.contains(_selectedWeekStart)) {
                        selectedWeek = _selectedWeekStart!;
                      } else if (weeks.isNotEmpty) {
                        // Prefer the current week if it exists in the data
                        final matchingWeek = weeks.firstWhere(
                          (w) =>
                              w.year == thisWeekStart.year &&
                              w.month == thisWeekStart.month &&
                              w.day == thisWeekStart.day,
                          orElse: () => weeks.first,
                        );
                        selectedWeek = matchingWeek;
                      }

                      final orders =
                          selectedWeek != null ? (weekGroups[selectedWeek] ?? []) : allOrders;
                      debugPrint(
                          'DEBUG: Showing ${orders.length} assigned orders for week starting ${selectedWeek?.toIso8601String() ?? 'all weeks'} (including delivered/failed)');
                      
                      if (allOrders.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No Assigned Orders',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'You have no orders assigned to you.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      orders.sort((a, b) {
                        final at = (a['created_at'] ?? a['assigned_at'] ?? 0) as int? ?? 0;
                        final bt = (b['created_at'] ?? b['assigned_at'] ?? 0) as int? ?? 0;
                        return bt.compareTo(at);
                      });

                      // Show orders grouped by week, with a dropdown selector as the first list item.
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            // Week selector dropdown header
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Align(
                                alignment: Alignment.center,
                                child: DropdownButton<DateTime>(
                                  value: selectedWeek,
                                  icon: const Icon(Icons.arrow_drop_down),
                                  isExpanded: true,
                                  underline: const SizedBox.shrink(),
                                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                                  items: weeks.map((week) {
                                    final end = week.add(const Duration(days: 6));
                                    final label =
                                        'Week of ${week.month}/${week.day} - ${end.month}/${end.day}';
                                    return DropdownMenuItem<DateTime>(
                                      value: week,
                                      child: Text(label),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedWeekStart = value;
                                    });
                                  },
                                ),
                              ),
                            );
                          }

                          if (selectedWeek == null) {
                            // Safety: no orders should be built when no week is selected
                            return const SizedBox.shrink();
                          }

                          final o = orders[index - 1];
                          final id = (o['id'] ?? '').toString();
                          final rawStatus = (o['status'] ?? '').toString();
                          final status = _normalizeStatus(rawStatus);
                          final customer = (o['customer_name'] ?? '').toString();
                          final rawAddress =
                              (o['delivery_address'] ?? o['customer_address'] ?? '').toString();
                          final address = _cleanAddress(rawAddress);
                          final total = (o['total_amount'] ?? 0).toString();
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              gradient: AppTheme.cardGradient,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _showOrderDetails(context, o),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Order Header
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              gradient: AppTheme.primaryGradient,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Order #${id.substring(id.length - 8)}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  customer,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.chat, color: AppTheme.primaryColor, size: 24),
                                            tooltip: 'Chat with Customer',
                                            onPressed: () async {
                                              final customerId = (o['customer_id'] ?? '').toString();
                                              final customerName = (o['customer_name'] ?? 'Customer').toString();
                                              if (customerId.isEmpty) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Missing customer info'),
                                                    backgroundColor: Colors.orange,
                                                  ),
                                                );
                                                return;
                                              }

                                              // Before opening chat, verify that the customer account is still active.
                                              try {
                                                if (!SupabaseService.isInitialized) {
                                                  await SupabaseService.initialize();
                                                }
                                                final supabase = SupabaseService.client;
                                                final customerRow = await supabase
                                                    .from('customers')
                                                    .select('uid, status')
                                                    .eq('uid', customerId)
                                                    .maybeSingle();

                                                if (customerRow == null ||
                                                    customerRow.isEmpty) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'This customer account has been deactivated or removed. '
                                                        'Chat is not available.',
                                                      ),
                                                      backgroundColor: Colors.orange,
                                                    ),
                                                  );
                                                  return;
                                                }

                                                final status = customerRow['status']?.toString().toLowerCase();
                                                if (status != 'active') {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'This customer account has been deactivated or removed. '
                                                        'Chat is not available.',
                                                      ),
                                                      backgroundColor: Colors.orange,
                                                    ),
                                                  );
                                                  return;
                                                }
                                              } catch (e) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Unable to verify customer account status: ${e.toString()}',
                                                    ),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                                return;
                                              }

                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => RiderChatScreen(
                                                    initialCustomerId: customerId,
                                                    initialCustomerName: customerName,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      
                                      // Address
                                      Row(
                                        children: [
                                          Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              address,
                                              style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      
                                      // Payment Method & Status Row
                                      Row(
                                        children: [
                                          // Payment Method Badge
                                          if ((o['payment_method'] ?? '').toString().toLowerCase() == 'gcash')
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.blue[100],
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blue[300]!, width: 1),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.payment, size: 14, color: Colors.blue[700]),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'GCash',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.blue[700],
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if ((o['payment_method'] ?? '').toString().toLowerCase() != 'gcash')
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.green[100],
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.green[300]!, width: 1),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.money, size: 14, color: Colors.green[700]),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'COD',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.green[700],
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const Spacer(),
                                          
                                          // Total Amount
                                          Text(
                                            '₱$total',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      
                                      // Status Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _getStatusIcon(status),
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _getStatusLabel(status),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      // Delivered/Failed Details
                                      if (status == 'delivered') ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.green[50],
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.green[200]!),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '✓ Delivered on ${o['delivered_at'] != null ? DateTime.fromMillisecondsSinceEpoch(o['delivered_at'] as int).toString().substring(0, 16) : 'Unknown'}',
                                                style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w600),
                                              ),
                                              if ((o['payment_method'] == 'cash_on_delivery' || o['cash_received'] != null) && (o['cash_received'] ?? 0) > 0) ...[
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                Text(
                                                      'Cash Received: ',
                                                      style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w500),
                                                    ),
                                                    Text(
                                                      '₱${o['cash_received']}',
                                                      style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Text(
                                                      'Change: ',
                                                      style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w500),
                                                    ),
                                                    Text(
                                                      '₱${o['change'] ?? 0}',
                                                      style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                      
                                      if (status == 'failed') ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.red[50],
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.red[200]!),
                                          ),
                                          child: Text(
                                            '✕ Failed: ${o['failure_reason'] ?? 'No reason provided'}',
                                            style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOrdersFromSupabase(String riderId) async {
    try {
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }

      final supabase = SupabaseService.client;
      
      debugPrint('🔍 Fetching orders from Supabase for rider: $riderId');
      
      final response = await supabase
          .from('delivery_orders')
          .select()
          .eq('rider_id', riderId)
          .order('assigned_at', ascending: false);
      
      if (response == null) {
        debugPrint('⚠️ Supabase query returned null');
        return [];
      }
      
      debugPrint('✅ Fetched ${response.length} orders from Supabase');
      
      // Batch fetch customer notes from orders table (more efficient than N+1 queries)
      final ordersWithNotes = <Map<String, dynamic>>[];
      if (response.isNotEmpty) {
        try {
          // Extract all order IDs
          final orderIds = response
              .map((o) => o['id']?.toString())
              .where((id) => id != null && id.isNotEmpty)
              .toList();
          
          if (orderIds.isNotEmpty) {
            // Fetch all order_notes in a single batch query
            final notesResponse = await supabase
                .from('orders')
                .select('id, order_notes')
                .inFilter('id', orderIds);
            
            // Create a map for quick lookup: orderId -> order_notes
            final notesMap = <String, String>{};
            if (notesResponse != null) {
              for (final noteData in notesResponse) {
                final id = noteData['id']?.toString() ?? '';
                final notes = noteData['order_notes']?.toString() ?? '';
                if (id.isNotEmpty) {
                  notesMap[id] = notes;
                }
              }
            }
            
            // Merge order_notes into delivery_orders
            for (final order in response) {
              final orderId = order['id']?.toString() ?? '';
              if (orderId.isNotEmpty && notesMap.containsKey(orderId)) {
                order['order_notes'] = notesMap[orderId];
              }
              ordersWithNotes.add(order);
            }
          } else {
            // No valid order IDs, just add orders as-is
            ordersWithNotes.addAll(response);
          }
        } catch (e) {
          debugPrint('⚠️ Error batch fetching order_notes: $e');
          // Fallback: add orders without notes if batch fetch fails
          ordersWithNotes.addAll(response);
        }
      } else {
        ordersWithNotes.addAll(response);
      }
      
      // Log first order for debugging
      if (ordersWithNotes.isNotEmpty) {
        final firstOrder = ordersWithNotes[0];
        debugPrint('📦 Sample order: id=${firstOrder['id']}, status=${firstOrder['status']}, rider_id=${firstOrder['rider_id']}');
        debugPrint('💳 GCash receipt URL: ${firstOrder['gcash_receipt_url']}');
        debugPrint('💳 Payment method: ${firstOrder['payment_method']}');
        debugPrint('📸 Delivery proof: ${firstOrder['delivery_proof']}');
        debugPrint('📝 Order notes: ${firstOrder['order_notes']}');
      } else {
        debugPrint('⚠️ No orders found for rider $riderId');
        // Try to check if there are any delivery_orders at all
        final allOrders = await supabase.from('delivery_orders').select('id, rider_id, status').limit(5);
        debugPrint('📊 Sample of all delivery_orders: $allOrders');
      }
      
      return ordersWithNotes;
    } catch (e) {
      debugPrint('❌ Error fetching orders from Supabase: $e');
      rethrow;
    }
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    final rawStatus = (order['status'] ?? '').toString();
    final status = _normalizeStatus(rawStatus);
    final idStr = (order['id'] ?? '').toString();
    final idSuffix = idStr.length > 8 ? idStr.substring(idStr.length - 8) : idStr;
    final orderId = idStr;
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        // Use StatefulBuilder for entire dialog to make it reactive to cache changes
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Listen to cache changes and rebuild dialog when notes update
            // Reading from cache here makes StatefulBuilder reactive to cache changes
            // This ensures the dialog rebuilds when staff notes are fetched or updated
            final currentNotes = _staffNotesCache[orderId] ?? [];
            
            // Store callback to rebuild dialog when cache updates (register BEFORE fetching)
            _dialogRebuildCallbacks[orderId] = () {
              if (mounted) {
                setDialogState(() {
                  // Reading cache here triggers rebuild
                  final _ = _staffNotesCache[orderId] ?? [];
                });
              }
            };
            
            // Always fetch fresh staff notes when dialog opens (ensures latest data)
            // Fetch after callback is registered so rebuild happens
            // Always fetch, even if cached, to get latest data
            _fetchStaffNotesForOrder(orderId).then((notes) {
              if (mounted) {
                debugPrint('📦 Updating staff notes cache for order $orderId with ${notes.length} notes');
                setState(() {
                  _staffNotesCache[orderId] = notes;
                });
                // Trigger dialog rebuild if it's open
                final rebuildCallback = _dialogRebuildCallbacks[orderId];
                if (rebuildCallback != null) {
                  debugPrint('🔄 Triggering dialog rebuild for order $orderId');
                  rebuildCallback();
                } else {
                  debugPrint('⚠️ No rebuild callback found for order $orderId');
                }
              } else {
                debugPrint('⚠️ Widget not mounted, skipping cache update for order $orderId');
              }
            }).catchError((error) {
              debugPrint('❌ Error in fetch callback for order $orderId: $error');
            });
            
            // Build dialog - it will read from cache which is reactive
            return _buildOrderDetailsDialog(
              context,
              order,
              rawStatus,
              status,
              idSuffix,
              orderId,
            );
          },
        );
      },
    );
  }

  Widget _buildOrderDetailsDialog(
    BuildContext context,
    Map<String, dynamic> order,
    String rawStatus,
    String status,
    String idSuffix,
    String orderId,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogMaxHeight = screenHeight * 0.9;

    return Dialog(
      backgroundColor: AppTheme.creamLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: dialogMaxHeight,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.primaryColor.withOpacity(0.1), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Order #$idSuffix',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusLabel(status),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStyledSection(
                        'Customer Information',
                        Icons.person,
                        [
                          _buildInfoRow('Name', order['customer_name'] ?? ''),
                          _buildInfoRow('Phone', order['customer_phone'] ?? ''),
                          _buildInfoRow(
                            'Address',
                            _cleanAddress(order['delivery_address'] ?? order['customer_address'] ?? ''),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildStyledSection(
                        'Payment Information',
                        Icons.payment,
                        [
                          _buildInfoRow('Method', (order['payment_method'] ?? '').toString().toUpperCase()),
                          _buildInfoRow('Total Amount', '₱${order['total_amount'] ?? 0}'),
                          if ((order['delivery_fee'] ?? 0) > 0)
                            _buildInfoRow('Delivery Fee', '₱${order['delivery_fee']}'),
                          // GCash Receipt display (only for original GCash orders, not COD paid through GCash)
                          // If payment_proof exists, it means rider uploaded it (COD paid through GCash), so don't show customer receipt
                          if ((order['payment_method'] ?? '').toString().toLowerCase() == 'gcash' &&
                              (order['payment_proof'] == null || 
                               order['payment_proof'].toString().isEmpty)) ...[
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final receiptUrl = _getGcashReceiptUrl(order['gcash_receipt_url']);
                                if (receiptUrl.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.receipt_long, color: Colors.orange.shade700, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Pending customer upload',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.orange.shade900,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.receipt_long, color: AppTheme.primaryColor, size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'GCash Receipt (Customer Upload)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey[700],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => Dialog(
                                            backgroundColor: Colors.black,
                                            child: Stack(
                                              children: [
                                                InteractiveViewer(
                                                  child: Image.network(
                                                    receiptUrl,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 10,
                                                  right: 10,
                                                  child: IconButton(
                                                    icon: const Icon(Icons.close,
                                                        color: Colors.white, size: 30),
                                                    onPressed: () => Navigator.pop(ctx),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          receiptUrl,
                                          width: double.infinity,
                                          height: 200,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              height: 200,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.error_outline, color: Colors.grey[600], size: 32),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Failed to load receipt',
                                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Container(
                                              height: 200,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: CircularProgressIndicator(
                                                  value: loadingProgress.expectedTotalBytes != null
                                                      ? loadingProgress.cumulativeBytesLoaded /
                                                          loadingProgress.expectedTotalBytes!
                                                      : null,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Order items
                      if (order['items'] != null &&
                          order['items'] is List &&
                          (order['items'] as List).isNotEmpty) ...[
                        _buildStyledSection(
                          'Order Items (${(order['items'] as List).length})',
                          Icons.shopping_bag,
                          (order['items'] as List).map<Widget>((item) {
                            final map = Map<String, dynamic>.from(item as Map);
                            final name = (map['product_name'] ?? map['productName'] ?? '').toString();
                            final quantity = (map['quantity'] ?? 0).toString();
                            final unit = (map['unit'] ?? '').toString();
                            final price = (map['price'] ?? 0).toString();
                            final total = (map['quantity'] ?? 0) * (map['price'] ?? 0);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.creamAccent1,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.1)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$quantity $unit × ₱$price',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₱$total',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Customer contact actions
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _navigateToCustomer(
                                _cleanAddress(order['delivery_address'] ?? order['customer_address'] ?? ''),
                              ),
                              icon: const Icon(Icons.navigation, size: 18),
                              label: const Text('Navigate', style: TextStyle(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 44)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _callCustomer(order['customer_phone'] ?? ''),
                              icon: const Icon(Icons.phone, size: 18),
                              label: const Text('Call', style: TextStyle(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 44)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (status == 'delivered')
                        _buildStyledSection(
                          'Delivered Details',
                          Icons.check_circle,
                          [
                            _buildInfoRow(
                              'Delivered At',
                              order['delivered_at'] != null
                                  ? DateTime.fromMillisecondsSinceEpoch(order['delivered_at'] as int)
                                      .toString()
                                      .substring(0, 19)
                                  : 'Unknown',
                            ),
                            // Cash payment details (if paid through cash)
                            if ((order['payment_method'] == 'cash_on_delivery' || order['cash_received'] != null) && 
                                (order['cash_received'] ?? 0) > 0) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow('Cash Received', '₱${order['cash_received']}'),
                              _buildInfoRow('Change', '₱${order['change'] ?? 0}'),
                            ],
                          ],
                        ),
                      // Proof of delivery images (for delivered orders)
                      if (status == 'delivered') ...[
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final rawList = (order['delivery_proof'] ?? order['proof_delivery_images']);
                            if (rawList == null || rawList is! List || rawList.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final urls = rawList
                                .map((e) => e?.toString() ?? '')
                                .where((u) => u.isNotEmpty)
                                .map(_fixDeliveryProofUrl)
                                .toList();

                            if (urls.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return _buildStyledSection(
                              'Proof of Delivery (${urls.length} photo${urls.length > 1 ? 's' : ''})',
                              Icons.camera_alt,
                              [
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    // Use 1 column on narrow screens to avoid horizontal overflow
                                    final crossAxisCount = constraints.maxWidth < 320 ? 1 : 2;
                                    return GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                        childAspectRatio: 1,
                                      ),
                                      itemCount: urls.length,
                                      itemBuilder: (context, index) {
                                        final url = urls[index];
                                        return GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => Dialog(
                                                backgroundColor: Colors.black,
                                                child: Stack(
                                                  children: [
                                                    InteractiveViewer(
                                                      child: Image.network(
                                                        url,
                                                        fit: BoxFit.contain,
                                                      ),
                                                    ),
                                                    Positioned(
                                                      top: 10,
                                                      right: 10,
                                                      child: IconButton(
                                                        icon: const Icon(Icons.close,
                                                            color: Colors.white, size: 30),
                                                        onPressed: () => Navigator.pop(ctx),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: Image.network(
                                              url,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        // Proof of Payment (for GCash orders)
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final paymentProof = order['payment_proof'];
                            final paymentMethod = (order['payment_method'] ?? '').toString().toLowerCase();
                            
                            if (paymentProof == null || 
                                paymentProof.toString().isEmpty ||
                                (paymentMethod != 'gcash' && paymentMethod != 'gcash_on_delivery')) {
                              return const SizedBox.shrink();
                            }

                            final paymentProofUrl = _fixPaymentProofUrl(paymentProof.toString());

                            if (paymentProofUrl.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return _buildStyledSection(
                              'Proof of Payment',
                              Icons.qr_code,
                              [
                                GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => Dialog(
                                        backgroundColor: Colors.black,
                                        child: Stack(
                                          children: [
                                            InteractiveViewer(
                                              child: Image.network(
                                                paymentProofUrl,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            Positioned(
                                              top: 10,
                                              right: 10,
                                              child: IconButton(
                                                icon: const Icon(Icons.close,
                                                    color: Colors.white, size: 30),
                                                onPressed: () => Navigator.pop(ctx),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      paymentProofUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: 200,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          height: 200,
                                          color: Colors.grey[200],
                                          alignment: Alignment.center,
                                          child: const Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.error_outline, color: Colors.grey, size: 40),
                                              SizedBox(height: 8),
                                              Text(
                                                'Failed to load payment proof',
                                                style: TextStyle(color: Colors.grey, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      if (status == 'failed')
                        _buildStyledSection(
                        'Failed Details',
                          Icons.cancel,
                          [
                            _buildInfoRow('Failure Reason', order['failure_reason'] ?? 'No reason provided'),
                            _buildInfoRow(
                              'Delivery Schedule',
                              order['delivery_schedule'] != null
                                  ? DateTime.fromMillisecondsSinceEpoch(order['delivery_schedule'] as int)
                                      .toString()
                                      .substring(0, 19)
                                  : 'Unknown',
                            ),
                          ],
              ),
              const SizedBox(height: 16),
                      // Order/Delivery Notes Section
                      _buildNotesSection(context, order),
                      const SizedBox(height: 16),
                      // Delivery action buttons
              if (status == 'pending' || rawStatus == 'to_receive') ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () => _showDeliveryProofDialog(context, order),
                      icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Delivered', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 44)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () => _showFailedReasonDialog(context, order),
                      icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Failed', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 44)),
                      ),
                    ),
                  ),
                ],
              ),
              ],
                    ],
                  ),
                ),
              ),
              // Close button (outside scrollable area, fixed at bottom)
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Clean up callback when dialog closes
                      _dialogRebuildCallbacks.remove(orderId);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Close', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 44)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
  
  Widget _buildStyledSection(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.creamAccent1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? 'N/A' : value),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(BuildContext context, Map<String, dynamic> order) {
    final orderId = (order['id'] ?? '').toString();
    // Fetch customer notes from order_notes column (from orders table)
    final customerNotes = (order['order_notes'] ?? '').toString().trim();
    final hasCustomerNotes = customerNotes.isNotEmpty;
    
    // Always read from cache (updated by real-time listener)
    // This will be reactive when StatefulBuilder rebuilds
    final currentStaffNotes = _staffNotesCache[orderId] ?? [];
    final hasStaffNotes = currentStaffNotes.isNotEmpty;
    
    debugPrint('📋 _buildNotesSection for order $orderId:');
    debugPrint('   - Customer notes: ${hasCustomerNotes ? "YES (${customerNotes.length} chars)" : "NO"}');
    debugPrint('   - Staff notes in cache: ${currentStaffNotes.length}');
    debugPrint('   - Cache keys: ${_staffNotesCache.keys.toList()}');
    if (currentStaffNotes.isNotEmpty) {
      debugPrint('   - Staff notes data: ${currentStaffNotes.map((n) => n['note_text']?.toString().substring(0, (n['note_text']?.toString().length ?? 0) > 50 ? 50 : (n['note_text']?.toString().length ?? 0)) ?? 'empty').join(', ')}');
    }
    
    // If no notes at all, don't show section
    if (!hasCustomerNotes && !hasStaffNotes) {
      debugPrint('   - Returning empty section (no notes)');
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Customer Notes
        if (hasCustomerNotes) ...[
          _buildStyledSection(
            'Order/Delivery Notes (Customer)',
            Icons.note,
            [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  customerNotes,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Staff/Admin Notes - reads from cache (updated by real-time listener)
        if (hasStaffNotes) ...[
          _buildStyledSection(
            'Order/Delivery Notes (Staff/Admin)',
            Icons.admin_panel_settings,
            [
              ...currentStaffNotes.map((note) {
                final noteText = (note['note_text'] ?? '').toString();
                final notedBy = (note['noted_by_name'] ?? '').toString();
                final notedRole = (note['noted_by_role'] ?? '').toString();
                final notedAt = note['noted_at'] as int?;
                final updatedAt = note['note_updated_at'] as int?;
                final updatedBy = (note['note_updated_by_name'] ?? '').toString();
                final updatedRole = (note['note_updated_by_role'] ?? '').toString();
                
                String formatTimestamp(int? timestamp) {
                  if (timestamp == null) return 'Unknown';
                  try {
                    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
                    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                  } catch (e) {
                    return 'Invalid date';
                  }
                }
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        noteText,
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Noted by: $notedBy ($notedRole)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'Noted at: ${formatTimestamp(notedAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (updatedAt != null && updatedBy.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Updated by: $updatedBy ($updatedRole)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          'Updated at: ${formatTimestamp(updatedAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ],
      ],
    );
  }

  // Extract barangay, city, and province from address for better Google Maps navigation
  // Ignores street and sitio as they're not commonly recognized by Google Maps
  String _extractLocationForNavigation(String address) {
    if (address.isEmpty) return address;
    
    // First clean the address to remove duplicates
    final cleanedAddress = _cleanAddress(address);
    
    // Split by comma and trim
    final parts = cleanedAddress.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    
    if (parts.isEmpty) return cleanedAddress;
    
    // Common city names in the area
    final commonCities = ['ormoc', 'tacloban', 'baybay', 'palompon'];
    // Common provinces
    final commonProvinces = ['leyte', 'samar', 'biliran'];
    
    // Find city and province (usually last two parts)
    String? city;
    String? province;
    String? barangay;
    
    // Try to find city and province from the end
    if (parts.length >= 2) {
      final lastPart = parts[parts.length - 1].toLowerCase();
      final secondLastPart = parts[parts.length - 2].toLowerCase();
      
      // Check if last part is a province
      for (final prov in commonProvinces) {
        if (lastPart.contains(prov)) {
          province = parts[parts.length - 1];
          break;
        }
      }
      
      // Check if second last is a city
      for (final cit in commonCities) {
        if (secondLastPart.contains(cit) || secondLastPart.contains('city')) {
          city = parts[parts.length - 2];
          break;
        }
      }
      
      // If we found city and province, try to find barangay (third from end or earlier)
      if (city != null && province != null) {
        // Look for barangay starting from third from end
        for (int i = parts.length - 3; i >= 0; i--) {
          if (i < 0) break;
          final part = parts[i].toLowerCase();
          
          // Skip if it looks like street/sitio/purok
          if (part.contains('sitio') || 
              part.contains('purok') || 
              part.contains('street') ||
              part.contains('st.') ||
              part.length < 3) {
            continue;
          }
          
          // If it contains barangay indicators, use it
          if (part.contains('barangay') || 
              part.contains('brgy') || 
              part.contains('br.')) {
            // Extract barangay name (remove "Barangay", "Brgy", etc.)
            String barangayName = parts[i]
                .replaceAll(RegExp(r'barangay\s*', caseSensitive: false), '')
                .replaceAll(RegExp(r'brgy\.?\s*', caseSensitive: false), '')
                .replaceAll(RegExp(r'br\.\s*', caseSensitive: false), '')
                .trim();
            if (barangayName.isNotEmpty) {
              barangay = barangayName;
              break;
            }
          } else {
            // If no barangay indicator but it's a reasonable length name, assume it's barangay
            // (but skip if it's too short or looks like a number)
            if (parts[i].length >= 3 && !RegExp(r'^\d+$').hasMatch(parts[i])) {
              barangay = parts[i];
              break;
            }
          }
        }
      }
    }
    
    // Build the navigation address
    final List<String> navParts = [];
    
    // Add barangay if found, otherwise skip (Google Maps can work with just city and province)
    if (barangay != null && barangay.isNotEmpty) {
      // Format barangay nicely for Google Maps
      String formattedBarangay = barangay;
      if (!formattedBarangay.toLowerCase().contains('barangay') && 
          !formattedBarangay.toLowerCase().contains('brgy')) {
        formattedBarangay = 'Barangay $formattedBarangay';
      }
      navParts.add(formattedBarangay);
    }
    
    if (city != null) navParts.add(city);
    if (province != null) navParts.add(province);
    
    // If we found at least city and province, use them
    if (navParts.length >= 2) {
      return navParts.join(', ');
    }
    
    // Fallback: if address has 3+ parts, use last 3 parts (likely barangay, city, province)
    // But skip if first part looks like street/sitio
    if (parts.length >= 3) {
      final lastThree = parts.sublist(parts.length - 3);
      // Check if first of last three looks like street/sitio
      final firstPart = lastThree[0].toLowerCase();
      if (!firstPart.contains('sitio') && 
          !firstPart.contains('purok') && 
          !firstPart.contains('street') &&
          firstPart.length >= 3) {
        return lastThree.join(', ');
      }
      // Otherwise use last 2 (city, province)
      return lastThree.sublist(1).join(', ');
    }
    
    // Fallback: use last 2 parts if available (city, province)
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join(', ');
    }
    
    // Last resort: return cleaned address
    return cleanedAddress;
  }

  // Navigate to customer location using Google Maps
  Future<void> _navigateToCustomer(String address) async {
    if (address.isEmpty) {
      _showSnackBar('Customer address not available');
      return;
    }

    // Extract only barangay, city, and province for better Google Maps accuracy
    final locationAddress = _extractLocationForNavigation(address);

    // Enhance address for better Google Maps results
    // Add Philippines to ensure proper geolocation
    String enhancedAddress = locationAddress;
    if (!enhancedAddress.toLowerCase().contains('philippines')) {
      enhancedAddress = '$enhancedAddress, Philippines';
    }
    
    debugPrint('🗺️ Original address: $address');
    debugPrint('🗺️ Navigating to: $enhancedAddress');
    
    final encodedAddress = Uri.encodeComponent(enhancedAddress);
    
    // Try different Google Maps URLs in order of preference
    final List<Map<String, String>> navigationOptions = [
      {'url': 'google.navigation:q=$encodedAddress', 'name': 'Google Maps Navigation'},
      {'url': 'https://www.google.com/maps/dir/?api=1&destination=$encodedAddress', 'name': 'Google Maps Directions'},
      {'url': 'geo:0,0?q=$encodedAddress', 'name': 'Maps App'},
      {'url': 'https://www.google.com/maps/search/?api=1&query=$encodedAddress', 'name': 'Google Maps Search'},
    ];
    
    bool launched = false;
    
    for (var option in navigationOptions) {
      try {
        final url = option['url'];
        if (url != null) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            launched = true;
            debugPrint('✅ Opened ${option['name']}');
            _showSnackBar('Opening ${option['name']}...');
            break;
          }
        }
      } catch (e) {
        debugPrint('❌ Failed to launch ${option['name']}: $e');
        continue; // Try next option
      }
    }
    
    if (!launched) {
      _showSnackBar('No navigation app available. Please install Google Maps.');
    }
  }

  // Call customer directly
  Future<void> _callCustomer(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      _showSnackBar('Customer phone number not available');
      return;
    }

    // Clean phone number (remove spaces, dashes, etc.)
    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Add +63 for Philippines if number doesn't start with +
    if (!cleanNumber.startsWith('+')) {
      if (cleanNumber.startsWith('09')) {
        cleanNumber = '+63${cleanNumber.substring(1)}';
      } else if (cleanNumber.startsWith('63')) {
        cleanNumber = '+$cleanNumber';
      }
    }

    // Try different calling methods
    final List<Map<String, String>> callOptions = [
      {'url': 'tel:$cleanNumber', 'name': 'Phone App'},
      {'url': 'tel:$cleanNumber', 'name': 'Dialer App'},
    ];
    
    bool launched = false;
    
    for (var option in callOptions) {
      try {
        final url = option['url'];
        if (url != null) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            launched = true;
            _showSnackBar('Opening ${option['name']}...');
            break;
          }
        }
      } catch (e) {
        print('Failed to launch ${option['name']}: $e');
        continue; // Try next option
      }
    }
    
    if (!launched) {
      _showSnackBar('Could not make phone call. Please check if phone app is available.');
    }
  }

  // Show delivery proof dialog with image upload
  Future<void> _showDeliveryProofDialog(BuildContext context, Map<String, dynamic> order) async {
    List<File> selectedImages = [];
    final ImagePicker picker = ImagePicker();
    double cashReceived = 0.0;
    final TextEditingController cashController = TextEditingController();
    String? selectedPaymentMethod; // 'cash' or 'gcash'
    File? paymentProofImage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final screenHeight = MediaQuery.of(context).size.height;
          final dialogMaxHeight = screenHeight * 0.9;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: dialogMaxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    const Text(
                      'Delivery Proof',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add 1 or 2 images as proof of delivery:',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // Scrollable body (images + COD)
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (selectedImages.isNotEmpty)
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                ),
                                itemCount: selectedImages.length,
                                itemBuilder: (context, index) {
                                  return Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade400),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(
                                            selectedImages[index],
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              selectedImages.removeAt(index);
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            const SizedBox(height: 12),
                            // Add image buttons
                            if (selectedImages.length < 2)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final XFile? image = await picker.pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 80,
                                        );
                                        if (image != null) {
                                          setState(() {
                                            selectedImages.add(File(image.path));
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.camera_alt, size: 18),
                                      label: const Text('Camera', style: TextStyle(fontSize: 13)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final XFile? image = await picker.pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 80,
                                        );
                                        if (image != null) {
                                          setState(() {
                                            selectedImages.add(File(image.path));
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.photo_library, size: 18),
                                      label: const Text('Gallery', style: TextStyle(fontSize: 13)),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 16),
                            // Check if this is a GCash order that has already been paid by customer
                            Builder(
                              builder: (context) {
                                final paymentMethod = (order['payment_method'] ?? '').toString().toLowerCase();
                                final paymentProof = order['payment_proof'];
                                final isGcashAlreadyPaid = paymentMethod == 'gcash' && 
                                    (paymentProof == null || paymentProof.toString().isEmpty);
                                
                                if (isGcashAlreadyPaid) {
                                  // Show indicator that GCash order is already paid
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blue[300]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Colors.blue[700],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'This GCash order has already been paid by the customer.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blue[900],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                
                                // Show payment method selection for non-paid GCash orders or COD orders
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Delivery Order Paid By:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () {
                                                setState(() {
                                                  selectedPaymentMethod = 'cash';
                                                  paymentProofImage = null;
                                                });
                                              },
                                              style: OutlinedButton.styleFrom(
                                                backgroundColor: selectedPaymentMethod == 'cash'
                                                    ? Colors.blue[50]
                                                    : Colors.white,
                                                side: BorderSide(
                                                  color: selectedPaymentMethod == 'cash'
                                                      ? Colors.blue
                                                      : Colors.grey[300]!,
                                                  width: selectedPaymentMethod == 'cash' ? 2 : 1,
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.money,
                                                    size: 18,
                                                    color: selectedPaymentMethod == 'cash'
                                                        ? Colors.blue[700]
                                                        : Colors.grey[700],
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Cash',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: selectedPaymentMethod == 'cash'
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                      color: selectedPaymentMethod == 'cash'
                                                          ? Colors.blue[700]
                                                          : Colors.grey[700],
                                                    ),
                                                  ),
                                                  if (selectedPaymentMethod == 'cash')
                                                    const SizedBox(width: 6),
                                                  if (selectedPaymentMethod == 'cash')
                                                    Icon(
                                                      Icons.check_circle,
                                                      size: 16,
                                                      color: Colors.blue[700],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () {
                                                setState(() {
                                                  selectedPaymentMethod = 'gcash';
                                                  cashReceived = 0.0;
                                                  cashController.clear();
                                                });
                                              },
                                              style: OutlinedButton.styleFrom(
                                                backgroundColor: selectedPaymentMethod == 'gcash'
                                                    ? Colors.green[50]
                                                    : Colors.white,
                                                side: BorderSide(
                                                  color: selectedPaymentMethod == 'gcash'
                                                      ? Colors.green
                                                      : Colors.grey[300]!,
                                                  width: selectedPaymentMethod == 'gcash' ? 2 : 1,
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.qr_code,
                                                    size: 18,
                                                    color: selectedPaymentMethod == 'gcash'
                                                        ? Colors.green[700]
                                                        : Colors.grey[700],
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'GCash',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: selectedPaymentMethod == 'gcash'
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                      color: selectedPaymentMethod == 'gcash'
                                                          ? Colors.green[700]
                                                          : Colors.grey[700],
                                                    ),
                                                  ),
                                                  if (selectedPaymentMethod == 'gcash')
                                                    const SizedBox(width: 6),
                                                  if (selectedPaymentMethod == 'gcash')
                                                    Icon(
                                                      Icons.check_circle,
                                                      size: 16,
                                                      color: Colors.green[700],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            // Cash Payment Section (only show if order is not already paid)
                            Builder(
                              builder: (context) {
                                final paymentMethod = (order['payment_method'] ?? '').toString().toLowerCase();
                                final paymentProof = order['payment_proof'];
                                final isGcashAlreadyPaid = paymentMethod == 'gcash' && 
                                    (paymentProof == null || paymentProof.toString().isEmpty);
                                
                                if (isGcashAlreadyPaid) {
                                  return const SizedBox.shrink();
                                }
                                
                                if (selectedPaymentMethod == 'cash') {
                                  return Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue[200]!),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.money, color: Colors.blue[700], size: 18),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Cash on Delivery',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue[700],
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Total Amount: ₱${order['total_amount'] ?? 0}',
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: cashController,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Cash Received',
                                                hintText: 'Enter amount received',
                                                prefixText: '₱',
                                                border: OutlineInputBorder(),
                                              ),
                                              style: const TextStyle(fontSize: 13),
                                              onChanged: (value) {
                                                setState(() {
                                                  cashReceived = double.tryParse(value) ?? 0.0;
                                                });
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: cashReceived >= (order['total_amount'] ?? 0)
                                                    ? Colors.green[100]
                                                    : Colors.red[100],
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    cashReceived >= (order['total_amount'] ?? 0)
                                                        ? Icons.check_circle
                                                        : Icons.warning,
                                                    color: cashReceived >= (order['total_amount'] ?? 0)
                                                        ? Colors.green[700]
                                                        : Colors.red[700],
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Change: ₱${(cashReceived - ((order['total_amount'] ?? 0).toDouble())).toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                        color: cashReceived >= (order['total_amount'] ?? 0)
                                                            ? Colors.green[700]
                                                            : Colors.red[700],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            // GCash Payment Section (only show if order is not already paid)
                            Builder(
                              builder: (context) {
                                final paymentMethod = (order['payment_method'] ?? '').toString().toLowerCase();
                                final paymentProof = order['payment_proof'];
                                final isGcashAlreadyPaid = paymentMethod == 'gcash' && 
                                    (paymentProof == null || paymentProof.toString().isEmpty);
                                
                                if (isGcashAlreadyPaid) {
                                  return const SizedBox.shrink();
                                }
                                
                                if (selectedPaymentMethod == 'gcash') {
                                  return Column(
                                    children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.qr_code, color: Colors.green[700], size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          'GCash Payment',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[700],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // GCash QR Code with name and phone number
                                    Center(
                                      child: RepaintBoundary(
                                        key: _qrKey,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(color: Colors.green, width: 3),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // QR Image
                                              if (_qrAssetExists)
                                                Image.asset(
                                                  'assets/images/order_gcash_qr.JPG',
                                                  width: 220,
                                                  height: 220,
                                                  fit: BoxFit.contain,
                                                )
                                              else
                                                Container(
                                                  width: 220,
                                                  height: 220,
                                                  color: Colors.grey[200],
                                                  alignment: Alignment.center,
                                                  child: const Text('GCash QR not found'),
                                                ),
                                              const SizedBox(height: 8),
                                              // Name
                                              Text(
                                                'Joylyn Mae P. Olacao',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.black,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              // Phone Number
                                              Text(
                                                '09525818621',
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              // Amount
                                              Text(
                                                'Amount: \u20B1${((order['total_amount'] ?? 0).toDouble()).toStringAsFixed(2)}',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Download QR Button
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        onPressed: () => _saveQrToGallery((order['total_amount'] ?? 0).toDouble()),
                                        icon: const Icon(Icons.download),
                                        label: const Text('Download QR'),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.green[700]!),
                                          foregroundColor: Colors.green[700],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Please scan the QR code above for payment',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 12),
                                    // Payment Proof Upload Requirement Indicator
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange[300]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Payment proof image is required before confirming delivery',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.orange[900],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Payment Proof Upload
                                    if (paymentProofImage != null)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: Stack(
                                          children: [
                                            Container(
                                              height: 100,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.green[300]!),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: Image.file(
                                                  paymentProofImage!,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    paymentProofImage = null;
                                                  });
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.close,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              final XFile? image = await picker.pickImage(
                                                source: ImageSource.camera,
                                                imageQuality: 80,
                                              );
                                              if (image != null) {
                                                setState(() {
                                                  paymentProofImage = File(image.path);
                                                });
                                              }
                                            },
                                            icon: const Icon(Icons.camera_alt, size: 18),
                                            label: const Text(
                                              'Camera',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green[700],
                                              side: BorderSide(color: Colors.green[300]!),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              final XFile? image = await picker.pickImage(
                                                source: ImageSource.gallery,
                                                imageQuality: 80,
                                              );
                                              if (image != null) {
                                                setState(() {
                                                  paymentProofImage = File(image.path);
                                                });
                                              }
                                            },
                                            icon: const Icon(Icons.photo_library, size: 18),
                                            label: const Text(
                                              'Gallery',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green[700],
                                              side: BorderSide(color: Colors.green[300]!),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                                    ],
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Action buttons (fixed at bottom of dialog)
                    Builder(
                      builder: (context) {
                        final paymentMethod = (order['payment_method'] ?? '').toString().toLowerCase();
                        final paymentProof = order['payment_proof'];
                        final isGcashAlreadyPaid = paymentMethod == 'gcash' && 
                            (paymentProof == null || paymentProof.toString().isEmpty);
                        
                        // For already paid GCash orders, payment method selection is not required
                        final requiresPaymentMethod = !isGcashAlreadyPaid && selectedPaymentMethod == null;
                        
                        // For GCash payment, payment proof image is required
                        final requiresPaymentProof = selectedPaymentMethod == 'gcash' && paymentProofImage == null;
                        
                        return Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 40)),
                                ),
                                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: selectedImages.isEmpty || requiresPaymentMethod || requiresPaymentProof
                                    ? null
                                    : () => _markAsDelivered(
                                          order,
                                          selectedImages,
                                          context,
                                          cashReceived: cashReceived,
                                          paymentMethod: isGcashAlreadyPaid ? 'gcash' : selectedPaymentMethod,
                                          paymentProofImage: paymentProofImage,
                                        ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 40)),
                                ),
                                child: Text(
                                  selectedImages.isEmpty
                                      ? 'Add at least 1 image'
                                      : requiresPaymentMethod
                                          ? 'Select payment method'
                                      : requiresPaymentProof
                                          ? 'Upload payment proof'
                                      : 'Confirm Delivery (${selectedImages.length}/2)',
                                  style: const TextStyle(fontSize: 14),
                                ),
                          ),
                        ),
                      ],
                    );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Show failed delivery reason dialog
  Future<void> _showFailedReasonDialog(BuildContext context, Map<String, dynamic> order) async {
    final List<String> failureReasons = [
      'Customer not available',
      'Wrong address',
      'Customer refused delivery',
      'Package damaged',
      'Incorrect phone number',
      'Other'
    ];
    
    String selectedReason = failureReasons.first;
    String otherReason = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delivery Failed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please select the reason for failed delivery:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Reason selection
                ...failureReasons.map((reason) => RadioListTile<String>(
                  title: Text(reason),
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setState(() {
                      selectedReason = value!;
                    });
                  },
                )).toList(),
                
                // Other reason text field
                if (selectedReason == 'Other')
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Please specify',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => otherReason = value,
                      maxLines: 2,
                    ),
                  ),
                
                const SizedBox(height: 20),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markAsFailed(
                          order, 
                          selectedReason == 'Other' ? otherReason : selectedReason, 
                          context
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Mark as Failed'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Mark order as delivered with proof images
  Future<void> _markAsDelivered(
    Map<String, dynamic> order,
    List<File> images,
    BuildContext context, {
    double cashReceived = 0.0,
    String? paymentMethod,
    File? paymentProofImage,
  }) async {
    try {
      final orderId = order['id'].toString();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Upload images to Supabase Storage and get URLs
      final proofImageUrls = <String>[];
      
      if (images.isNotEmpty) {
        _showSnackBar('Uploading proof images...');
        
        for (int i = 0; i < images.length; i++) {
          try {
            final imageFile = images[i];
            final extension = imageFile.path.split('.').last.toLowerCase();
            final fileName = '${orderId}_${now}_$i.$extension';
            
            debugPrint('📤 Uploading delivery proof image $i: $fileName');
            final imageUrl = await SupabaseService.uploadDeliveryProofImage(imageFile, fileName);
            proofImageUrls.add(imageUrl);
            debugPrint('✅ Uploaded image $i: $imageUrl');
          } catch (e) {
            debugPrint('❌ Error uploading image $i: $e');
            // Continue with other images even if one fails
            _showSnackBar('Warning: Failed to upload image ${i + 1}');
          }
        }
        
        if (proofImageUrls.isEmpty) {
          _showSnackBar('Error: No images were uploaded. Please try again.');
          return;
        }
        
        debugPrint('✅ Successfully uploaded ${proofImageUrls.length} proof images');
      }
      
      // Upload payment proof image if GCash payment
      String? paymentProofUrl;
      if (paymentMethod == 'gcash' && paymentProofImage != null) {
        try {
          _showSnackBar('Uploading payment proof...');
          final extension = paymentProofImage.path.split('.').last.toLowerCase();
          final fileName = '${orderId}_${now}_payment.$extension';
          
          debugPrint('📤 Uploading payment proof: $fileName');
          paymentProofUrl = await SupabaseService.uploadPaymentProofImage(paymentProofImage, fileName);
          debugPrint('✅ Uploaded payment proof: $paymentProofUrl');
        } catch (e) {
          debugPrint('❌ Error uploading payment proof: $e');
          _showSnackBar('Warning: Failed to upload payment proof');
          // Continue with delivery even if payment proof fails
        }
      }
      
      // Get rider info
      final riderId = await RiderSession.getId();
      final riderName = await RiderSession.getName() ?? 'Unknown Rider';
      
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }
      
      final supabase = SupabaseService.client;
      
      // Prepare update data for delivery_orders table
      final deliveryUpdate = <String, dynamic>{
        'status': 'delivered',
        'delivered_at': now,
        'delivery_proof': proofImageUrls, // Array of image URLs for proof of delivery
        'delivered_by': riderId,
        'delivered_by_name': riderName,
        'updated_at': now,
      };
      
      // Add payment method and related data
      if (paymentMethod == 'cash') {
        final totalAmount = (order['total_amount'] ?? 0).toDouble();
        final change = cashReceived - totalAmount;
        deliveryUpdate['cash_received'] = cashReceived;
        deliveryUpdate['change'] = change;
        deliveryUpdate['payment_method'] = 'cash_on_delivery';
      } else if (paymentMethod == 'gcash') {
        deliveryUpdate['payment_method'] = 'gcash';
        if (paymentProofUrl != null) {
          deliveryUpdate['payment_proof'] = paymentProofUrl;
        }
      }
      
      // Update delivery_orders table in Supabase
      await supabase
          .from('delivery_orders')
          .update(deliveryUpdate)
          .eq('id', orderId);
      
      debugPrint('✅ Updated delivery_orders in Supabase');

      // Update main orders table (for staff dashboard)
      final ordersUpdate = <String, dynamic>{
        'status': 'delivered',
        'delivered_at': now,
        'updated_at': now,
      };
      
      // Add payment method and related data
      if (paymentMethod == 'cash') {
        final totalAmount = (order['total_amount'] ?? 0).toDouble();
        final change = cashReceived - totalAmount;
        ordersUpdate['cash_received'] = cashReceived;
        ordersUpdate['change'] = change;
        ordersUpdate['payment_method'] = 'cash_on_delivery';
      } else if (paymentMethod == 'gcash') {
        ordersUpdate['payment_method'] = 'gcash';
        if (paymentProofUrl != null) {
          ordersUpdate['payment_proof'] = paymentProofUrl;
        }
      }
      
      try {
        // Try updating by 'id' first (primary key)
        await supabase
            .from('orders')
            .update(ordersUpdate)
            .eq('id', orderId);
        
        debugPrint('✅ Updated orders table in Supabase');
      } catch (e) {
        debugPrint('⚠️ Warning: Failed to update orders table with id: $e');
        // Try updating by 'uid' as fallback
        try {
          await supabase
              .from('orders')
              .update(ordersUpdate)
              .eq('uid', orderId);
          debugPrint('✅ Updated orders table in Supabase using uid');
        } catch (e2) {
          debugPrint('⚠️ Warning: Failed to update orders table with uid: $e2');
          // Continue even if orders table update fails - delivery_orders is the primary table
        }
      }

      // Create notification for customer about successful delivery
      try {
        final customerId = order['customer_id']?.toString() ?? order['customerId']?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          // Check if notification already exists to prevent duplicates
          final existingResponse = await supabase
              .from('customer_notifications')
              .select('id')
              .eq('customer_id', customerId)
              .eq('order_id', orderId)
              .eq('type', 'order_delivered')
              .limit(1);
          
          if (existingResponse != null && existingResponse is List && existingResponse.isNotEmpty) {
            debugPrint('📭 Delivery notification already exists for order $orderId, skipping duplicate');
          } else {
            // Format order code (last 8 characters, uppercase)
            final orderCode = orderId.length > 8 
                ? orderId.substring(orderId.length - 8).toUpperCase() 
                : orderId.toUpperCase();
            
            // Get total amount
            final totalAmount = (order['total_amount'] ?? order['total'] ?? 0).toDouble();
            final formattedAmount = '₱${totalAmount.toStringAsFixed(2)}';
            
            // Create notification
            final notificationId = 'order_${orderId}_delivered_$now';
            final notificationData = <String, dynamic>{
              'id': notificationId,
              'customer_id': customerId,
              'title': 'Order Delivered',
              'message': 'Your order #$orderCode has been delivered successfully! Total: $formattedAmount',
              'type': 'order_delivered',
              'timestamp': now,
              'is_read': false,
              'order_id': orderId,
              'fcm_sent': false, // Will be set to true by Edge Function after sending FCM
            };
            
            await supabase.from('customer_notifications').insert(notificationData);
            debugPrint('✅ Created delivery notification for customer: $customerId');
          }
        } else {
          debugPrint('⚠️ Warning: Customer ID not found in order, skipping notification');
        }
      } catch (notificationError) {
        debugPrint('⚠️ Warning: Failed to create delivery notification: $notificationError');
        // Don't fail the delivery update if notification creation fails
      }

      if (mounted) {
        Navigator.pop(context); // Close delivery proof dialog
        Navigator.pop(context); // Close order details dialog
        _showSnackBar('Order marked as delivered successfully');
        _refreshOrders(); // Refresh the orders list without glitching
      }
      
    } catch (e) {
      debugPrint('❌ Error updating order: $e');
      if (mounted) {
        _showSnackBar('Error updating order: $e');
      }
    }
  }

  // Mark order as failed with reason
  Future<void> _markAsFailed(Map<String, dynamic> order, String reason, BuildContext context) async {
    try {
      final orderId = order['id'].toString();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Get rider info
      final riderId = await RiderSession.getId();
      final riderName = await RiderSession.getName() ?? 'Unknown Rider';
      
      // Get delivery schedule (out_for_delivery_at or assigned_at)
      final deliverySchedule = order['out_for_delivery_at'] ?? order['assigned_at'] ?? now;
      
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }
      
      final supabase = SupabaseService.client;
      
      // Update delivery_orders table in Supabase
      await supabase
          .from('delivery_orders')
          .update({
            'status': 'failed',
            'failed_at': now,
            'failure_reason': reason,
            'failed_by': riderId,
            'failed_by_name': riderName,
            'delivery_schedule': deliverySchedule,
            'updated_at': now,
          })
          .eq('id', orderId);
      
      debugPrint('✅ Updated delivery_orders in Supabase with failed status');

      // Update main orders table (for staff dashboard)
      try {
        // Try updating by 'id' first (primary key)
        await supabase
            .from('orders')
            .update({
              'status': 'failed',
              'failed_at': now,
              'failure_reason': reason,
              'failed_by': riderId,
              'failed_by_name': riderName,
              'delivery_schedule': deliverySchedule,
              'updated_at': now,
            })
            .eq('id', orderId);
        
        debugPrint('✅ Updated orders table in Supabase with failed status');
      } catch (e) {
        debugPrint('⚠️ Warning: Failed to update orders table with id: $e');
        // Try updating by 'uid' as fallback
        try {
          await supabase
              .from('orders')
              .update({
                'status': 'failed',
                'failed_at': now,
                'failure_reason': reason,
                'failed_by': riderId,
                'failed_by_name': riderName,
                'delivery_schedule': deliverySchedule,
                'updated_at': now,
              })
              .eq('uid', orderId);
          debugPrint('✅ Updated orders table in Supabase with failed status using uid');
        } catch (e2) {
          debugPrint('⚠️ Warning: Failed to update orders table with uid: $e2');
        }
      }

      // Create notification for customer about failed delivery
      try {
        final customerId = order['customer_id']?.toString() ?? order['customerId']?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          // Check if notification already exists to prevent duplicates
          final existingResponse = await supabase
              .from('customer_notifications')
              .select('id')
              .eq('customer_id', customerId)
              .eq('order_id', orderId)
              .eq('type', 'order_failed')
              .limit(1);
          
          if (existingResponse != null && existingResponse is List && existingResponse.isNotEmpty) {
            debugPrint('📭 Failed delivery notification already exists for order $orderId, skipping duplicate');
          } else {
            // Format order code (last 8 characters, uppercase)
            final orderCode = orderId.length > 8 
                ? orderId.substring(orderId.length - 8).toUpperCase() 
                : orderId.toUpperCase();
            
            // Get total amount
            final totalAmount = (order['total_amount'] ?? order['total'] ?? 0).toDouble();
            final formattedAmount = '₱${totalAmount.toStringAsFixed(2)}';
            
            // Create notification
            final notificationId = 'order_${orderId}_failed_$now';
            final notificationData = <String, dynamic>{
              'id': notificationId,
              'customer_id': customerId,
              'title': 'Delivery Failed',
              'message': 'Your order #$orderCode has failed to deliver. Reason: ${reason.isNotEmpty ? reason : "No reason provided"}. Total: $formattedAmount. Please contact support.',
              'type': 'order_failed',
              'timestamp': now,
              'is_read': false,
              'order_id': orderId,
              'fcm_sent': false, // Will be set to true by Edge Function after sending FCM
            };
            
            await supabase.from('customer_notifications').insert(notificationData);
            debugPrint('✅ Created failed delivery notification for customer: $customerId');
          }
        } else {
          debugPrint('⚠️ Warning: Customer ID not found in order, skipping notification');
        }
      } catch (notificationError) {
        debugPrint('⚠️ Warning: Failed to create failed delivery notification: $notificationError');
        // Don't fail the order update if notification creation fails
      }

      if (mounted) {
        Navigator.pop(context); // Close failed reason dialog
        Navigator.pop(context); // Close order details dialog
        _showSnackBar('Order marked as failed');
        _refreshOrders(); // Refresh the orders list without glitching
      }
      
    } catch (e) {
      debugPrint('❌ Error updating order: $e');
      if (mounted) {
        _showSnackBar('Error updating order: $e');
      }
    }
  }

  // Show snackbar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Normalize status for display and logic
  String _normalizeStatus(String rawStatus) {
    switch (rawStatus.toLowerCase()) {
      case 'to_receive':
      case 'assigned':
      case 'out_for_delivery':
      case 'pending':
        return 'pending';
      case 'delivered':
      case 'completed':
        return 'delivered';
      case 'failed':
      case 'cancelled':
        return 'failed';
      default:
        return rawStatus;
    }
  }
  
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'delivered':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.check_circle;
      case 'failed':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }
  
  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'PENDING';
      case 'delivered':
        return 'DELIVERED';
      case 'failed':
        return 'DELIVERY FAILED';
      default:
        return status.toUpperCase();
    }
  }
  
  // Helper to remove duplicate city/province in addresses
  String _cleanAddress(String address) {
    if (address.isEmpty) return address;
    
    // Split by comma and trim each part
    final parts = address.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length < 4) return address; // Need at least 4 parts to have duplication
    
    // Check if last two parts duplicate the previous two parts
    // Pattern: "X, Y, City, Province, City, Province"
    // For "Coob, Tambulilid, Ormoc, Leyte, Ormoc, Leyte":
    //   parts[2]="Ormoc", parts[3]="Leyte" (original)
    //   parts[4]="Ormoc", parts[5]="Leyte" (duplicate)
    final lastPart = parts[parts.length - 1];
    final secondLastPart = parts[parts.length - 2];
    final thirdLastPart = parts.length >= 3 ? parts[parts.length - 3] : "";
    final fourthLastPart = parts.length >= 4 ? parts[parts.length - 4] : "";
    
    // Normalize for comparison (case-insensitive)
    final lastLower = lastPart.toLowerCase();
    final secondLastLower = secondLastPart.toLowerCase();
    final thirdLastLower = thirdLastPart.toLowerCase();
    final fourthLastLower = fourthLastPart.toLowerCase();
    
    // Check if last two parts match fourth and third last parts (duplicate pattern)
    // secondLastPart should match fourthLastPart, lastPart should match thirdLastPart
    if (parts.length >= 4) {
      // Simple check: if secondLast matches fourthLast AND last matches thirdLast
      if (secondLastLower == fourthLastLower && lastLower == thirdLastLower) {
        // Remove duplicate (last two parts)
        return parts.sublist(0, parts.length - 2).join(', ');
      }
      
      // Also check for partial matches (e.g., "Ormoc" matches "Ormoc City")
      if ((secondLastLower == fourthLastLower || 
           secondLastLower.contains(fourthLastLower) || 
           fourthLastLower.contains(secondLastLower)) &&
          (lastLower == thirdLastLower || 
           lastLower.contains(thirdLastLower) || 
           thirdLastLower.contains(lastLower))) {
        // Remove duplicate (last two parts)
        return parts.sublist(0, parts.length - 2).join(', ');
      }
    }
    
    // Check for longer patterns: "X, Y, Z, City, Province, City, Province"
    if (parts.length >= 6) {
      final fifthLastPart = parts[parts.length - 5];
      final sixthLastPart = parts[parts.length - 6];
      final fifthLastLower = fifthLastPart.toLowerCase();
      final sixthLastLower = sixthLastPart.toLowerCase();
      
      // Check if last two match fifth and sixth (for pattern: X, Y, Z, City, Province, City, Province)
      if ((secondLastLower == fifthLastLower || 
           secondLastLower.contains(fifthLastLower) || 
           fifthLastLower.contains(secondLastLower)) &&
          (lastLower == sixthLastLower || 
           lastLower.contains(sixthLastLower) || 
           sixthLastLower.contains(lastLower))) {
        // Remove duplicate (last two parts)
        return parts.sublist(0, parts.length - 2).join(', ');
      }
    }
    
    return parts.join(', ');
  }
  
  // Get Supabase GCash receipt URL - handles full URLs, various Supabase formats, and file paths
  String _getGcashReceiptUrl(String? receiptUrl) {
    if (receiptUrl == null) return '';
    String urlStr = receiptUrl.trim();
    if (urlStr.isEmpty) return '';

    // Treat explicit "pending" markers as no URL
    if (urlStr == 'pending:gcash_receipt' || urlStr == 'pending') {
      return '';
    }

    const String supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const String bucketName = 'gcash_receipt';

    // If it's already a full URL starting with http/https
    if (urlStr.startsWith('http://') || urlStr.startsWith('https://')) {
      // If it's already a proper Supabase public URL for the gcash_receipt bucket
      if (urlStr.contains('supabase.co/storage/v1/object/public/gcash_receipt')) {
        // Fix duplicate bucket names if present
        if (urlStr.contains('/gcash_receipt/gcash_receipt/')) {
          final fixedUrl = urlStr.replaceAll(
            '/gcash_receipt/gcash_receipt/',
            '/gcash_receipt/',
          );
          debugPrint('[GCash Receipt] Fixed duplicate bucket URL: $fixedUrl');
          return fixedUrl;
        }
        return urlStr;
      }

      // If it's some kind of Supabase URL but in a different format, try to extract the file path
      if (urlStr.contains('supabase.co')) {
        final patterns = <RegExp>[
          RegExp(r'gcash_receipt\/(.+?)(?:\?|$)'),
          RegExp(r'\/storage\/v1\/object\/public\/gcash_receipt\/(.+?)(?:\?|$)'),
          RegExp(r'\/gcash_receipt\/(.+?)(?:\?|$)'),
        ];

        for (final pattern in patterns) {
          final match = pattern.firstMatch(urlStr);
          if (match != null && match.groupCount >= 1 && match.group(1) != null) {
            String filePath = Uri.decodeComponent(match.group(1)!);
            // Clean up the file path - remove duplicate bucket name and extra slashes
            filePath = filePath.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
            if (filePath.startsWith('$bucketName/')) {
              filePath = filePath.substring(bucketName.length + 1).replaceAll(RegExp(r'^/+'), '');
            }
            final fixedUrl = '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
            debugPrint('[GCash Receipt] Reconstructed Supabase URL: $fixedUrl');
            return fixedUrl;
          }
        }
      }

      // Not a Supabase URL we recognize, but still a full URL – use as-is
      return urlStr;
    }

    // Otherwise it's a file path – construct the full Supabase public URL
    String filePath = urlStr.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');

    // Remove any leading bucket names (handle multiple occurrences)
    while (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1).replaceAll(RegExp(r'^/+'), '');
    }

    final constructedUrl = '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
    debugPrint('[GCash Receipt] Constructed URL from path: $constructedUrl');
    return constructedUrl;
  }
  
  // Fix delivery proof URLs that have duplicate paths from old uploads
  String _fixDeliveryProofUrl(String url) {
    if (url.isEmpty) return url;
    
    // Fix duplicate bucket path in URL
    if (url.contains('/delivery_proof/delivery_proof/')) {
      final fixed = url.replaceAll('/delivery_proof/delivery_proof/', '/delivery_proof/');
      debugPrint('🔧 Fixed delivery proof URL: $url -> $fixed');
      return fixed;
    }
    
    return url;
  }

  String _fixPaymentProofUrl(String url) {
    if (url.isEmpty) return url;
    
    const SUPABASE_URL = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const BUCKET_NAME = 'delivery_proof_payment';
    
    // If already a full URL, check and fix if needed
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // Fix duplicate bucket name if present
      if (url.contains('/$BUCKET_NAME/$BUCKET_NAME/')) {
        final fixed = url.replaceAll('/$BUCKET_NAME/$BUCKET_NAME/', '/$BUCKET_NAME/');
        debugPrint('🔧 Fixed payment proof URL: $url -> $fixed');
        return fixed;
      }
      // If it's already a valid Supabase URL, return as is
      if (url.contains('supabase.co/storage/v1/object/public/$BUCKET_NAME/')) {
        return url;
      }
      // If it's a Supabase URL but wrong format, try to extract path
      if (url.contains('supabase.co')) {
        final pathMatch = RegExp(r'delivery_proof_payment/(.+?)(?:\?|$)').firstMatch(url);
        if (pathMatch != null && pathMatch.groupCount > 0) {
          var filePath = Uri.decodeComponent(pathMatch.group(1)!);
          // Remove duplicate bucket name if present
          if (filePath.startsWith('$BUCKET_NAME/')) {
            filePath = filePath.substring(BUCKET_NAME.length + 1);
          }
          final fixed = '$SUPABASE_URL/storage/v1/object/public/$BUCKET_NAME/$filePath';
          debugPrint('🔧 Fixed payment proof URL: $url -> $fixed');
          return fixed;
        }
      }
      return url;
    }
    
    // If it's a file path, clean it up
    var cleanPath = url;
    
    // Remove leading slash if present
    if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    
    // Remove duplicate bucket name if present in path
    if (cleanPath.startsWith('$BUCKET_NAME/')) {
      cleanPath = cleanPath.substring(BUCKET_NAME.length + 1);
    }
    
    // Construct full public URL
    final fixed = '$SUPABASE_URL/storage/v1/object/public/$BUCKET_NAME/$cleanPath';
    debugPrint('🔧 Constructed payment proof URL: $url -> $fixed');
    return fixed;
  }
}


