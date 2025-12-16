import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/theme.dart';
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';


class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController? controller;
  bool _isFlashOn = false;
  bool _isFrontCamera = false;
  bool _hasPermission = false;
  String _scannedData = '';
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasPermission = status.isGranted;
    });
  }



  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }



  Future<void> _handleScannedData(String data) async {
    Map<String, dynamic>? payload;
    
    // Try to extract JSON from hybrid format (human-readable text + JSON)
    // For customer app, we ONLY want the JSON, not the human-readable text
    String jsonData = data;
    if (data.contains('---JSON---')) {
      // Extract JSON part after the marker
      final jsonIndex = data.indexOf('---JSON---');
      if (jsonIndex >= 0) {
        // Get everything after the marker
        jsonData = data.substring(jsonIndex + '---JSON---'.length);
        // Remove all leading whitespace, newlines, carriage returns, and control characters
        // Control characters: form feed (\f), vertical tab (\v), record separator (\x1E), etc.
        jsonData = jsonData.replaceAll(RegExp(r'^[\s\n\r\f\v\x1E]+'), '');
        // Also trim any trailing whitespace and control characters
        jsonData = jsonData.replaceAll(RegExp(r'[\s\n\r\f\v\x1E]+$'), '');
      }
    }
    
    // Try to parse as JSON (works for both pure JSON and extracted JSON)
    try {
      payload = json.decode(jsonData) as Map<String, dynamic>;
    } catch (e) {
      // If parsing fails, try parsing the original data (backward compatibility for old QR codes)
      try {
        payload = json.decode(data) as Map<String, dynamic>;
      } catch (_) {
        payload = null;
      }
    }

    // If no JSON payload found, try to extract order ID from human-readable text
    // This allows customer app to work with QR codes that only contain human-readable text
    if (payload == null) {
      debugPrint('🔍 QR Scanner: No JSON payload found, extracting from human-readable text');
      debugPrint('🔍 QR Scanner: Scanned data preview: ${data.length > 200 ? data.substring(0, 200) + "..." : data}');
      
      // Look for "Full Order ID: YYYYYYYYYYYYYYYY" pattern first (full ID)
      // Updated regex to match any alphanumeric characters (including lowercase)
      final fullOrderIdMatch = RegExp(r'Full Order ID:\s*([A-Za-z0-9]+)', caseSensitive: false).firstMatch(data);
      if (fullOrderIdMatch != null) {
        final fullOrderId = fullOrderIdMatch.group(1);
        debugPrint('✅ QR Scanner: Extracted Full Order ID: $fullOrderId');
        
        // Also get the order code (last 8 characters)
        final orderCodeMatch = RegExp(r'Order Code:\s*([A-Z0-9]{8})', caseSensitive: false).firstMatch(data);
        final orderCode = orderCodeMatch?.group(1) ?? (fullOrderId != null && fullOrderId.length >= 8 
          ? fullOrderId.substring(fullOrderId.length - 8).toUpperCase() 
          : '');
        
        if (fullOrderId != null && fullOrderId.isNotEmpty) {
          // Create a payload with the full order ID - app will fetch full details from Supabase
          payload = {
            'type': 'order_packaging',
            'header': orderCode.isNotEmpty ? orderCode : fullOrderId.substring(fullOrderId.length - 8).toUpperCase(),
            'orderId': fullOrderId, // Full order ID to fetch order details
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'contributions': [],
          };
          debugPrint('✅ QR Scanner: Created payload with orderId: ${payload['orderId']}');
        }
      } else {
        // Fallback: Look for "Order Code: XXXXXXXX" pattern (8-character code only)
        debugPrint('⚠️ QR Scanner: Full Order ID not found, trying Order Code pattern');
        final orderCodeMatch = RegExp(r'Order Code:\s*([A-Z0-9]{8})', caseSensitive: false).firstMatch(data);
        if (orderCodeMatch != null) {
          final orderCode = orderCodeMatch.group(1);
          if (orderCode != null && orderCode.isNotEmpty) {
            debugPrint('✅ QR Scanner: Extracted Order Code: $orderCode');
            // Create a payload with order code - app will try to fetch using this
            payload = {
              'type': 'order_packaging',
              'header': orderCode,
              'orderId': orderCode, // Will be used to fetch order details
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'contributions': [],
            };
          }
        } else {
          debugPrint('❌ QR Scanner: Could not extract Order ID or Order Code from scanned data');
        }
      }
    }

    if (payload != null && (payload['type'] == 'order_packaging')) {
      final String header = (payload['header'] ?? '').toString();
      final String orderId = (payload['orderId'] ?? '').toString();
      List<dynamic> cons = (payload['contributions'] is List) ? (payload['contributions'] as List) : [];
      final int ts = (payload['timestamp'] is int) ? payload['timestamp'] as int : 0;
      final DateTime? generatedAt = ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : null;

      // If contributions are empty (extracted from human-readable text), fetch from qr_packaging table
      if (cons.isEmpty && orderId.isNotEmpty) {
        cons = await _fetchContributionsFromQrPackaging(orderId);
      }

      // Fetch order details from Supabase
      final order = await _fetchOrderDetails(orderId);
      final customerName = (order['customerName'] ?? '').toString();
      String customerPhone = (order['customerPhone'] ?? '').toString();
      
      // If phone number is missing from DB, try to parse from scanned text
      if (customerPhone.isEmpty) {
        final phoneMatch = RegExp(r'Phone:\s*([^\n]+)', caseSensitive: false).firstMatch(data);
        if (phoneMatch != null) {
          customerPhone = phoneMatch.group(1)?.trim() ?? '';
          if (customerPhone.isNotEmpty) {
            debugPrint('✅ QR Scanner: Parsed phone number from text: $customerPhone');
          }
        }
      }
      
      final deliveryOption = (order['deliveryOption'] ?? 'delivery').toString().toLowerCase();
      
      // Determine address based on delivery option
      String address = '';
      if (deliveryOption == 'pickup') {
        // Build pickup address from structured fields
        final pickupParts = <String>[];
        if ((order['pickupStreet'] ?? '').toString().isNotEmpty) {
          pickupParts.add((order['pickupStreet'] ?? '').toString());
        }
        if ((order['pickupSitio'] ?? '').toString().isNotEmpty) {
          pickupParts.add((order['pickupSitio'] ?? '').toString());
        }
        if ((order['pickupBarangay'] ?? '').toString().isNotEmpty) {
          pickupParts.add((order['pickupBarangay'] ?? '').toString());
        }
        if ((order['pickupCity'] ?? '').toString().isNotEmpty) {
          pickupParts.add((order['pickupCity'] ?? '').toString());
        }
        if ((order['pickupProvince'] ?? '').toString().isNotEmpty) {
          pickupParts.add((order['pickupProvince'] ?? '').toString());
        }
        
        String baseAddress = '';
        if (pickupParts.isNotEmpty) {
          baseAddress = pickupParts.join(', ');
        } else if ((order['pickupAddress'] ?? '').toString().isNotEmpty) {
          baseAddress = (order['pickupAddress'] ?? '').toString();
        }
        
        // Add pickup name, landmark, and instructions if available
        final pickupDetails = <String>[];
        if ((order['pickupName'] ?? '').toString().isNotEmpty) {
          pickupDetails.add('📍 ${(order['pickupName'] ?? '').toString()}');
        }
        if (baseAddress.isNotEmpty) {
          pickupDetails.add(baseAddress);
        }
        if ((order['pickupLandmark'] ?? '').toString().isNotEmpty) {
          pickupDetails.add('Landmark: ${(order['pickupLandmark'] ?? '').toString()}');
        }
        if ((order['pickupInstructions'] ?? '').toString().isNotEmpty) {
          pickupDetails.add('Instructions: ${(order['pickupInstructions'] ?? '').toString()}');
        }
        
        address = pickupDetails.isNotEmpty ? pickupDetails.join('\n') : 'Pickup address not available';
      } else {
        // Delivery order - show customer/delivery address
        address = (order['deliveryAddress'] ?? order['customerAddress'] ?? '').toString();
      }
      
      final paymentMethod = (order['paymentMethod'] ?? '').toString().toUpperCase();
      final createdAtMs = order['createdAt'] is int ? order['createdAt'] as int : 0;
      final createdAt = createdAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(createdAtMs) : null;
      final subtotalRaw = order['subtotal'] ?? order['totalAmount'] ?? order['total'];
      final deliveryFeeRaw = order['deliveryFee'] ?? order['delivery_fee'];
      final totalRaw = order['totalAmount'] ?? order['total'] ?? subtotalRaw;
      final totalNum = (totalRaw is num) ? totalRaw.toDouble() : double.tryParse(totalRaw?.toString() ?? '') ?? 0.0;
      final subtotalNum =
          (subtotalRaw is num) ? subtotalRaw.toDouble() : double.tryParse(subtotalRaw?.toString() ?? '') ?? totalNum;
      final deliveryFeeNum = (deliveryFeeRaw is num)
          ? deliveryFeeRaw.toDouble()
          : double.tryParse(deliveryFeeRaw?.toString() ?? '') ??
              (totalNum - subtotalNum >= 0 ? totalNum - subtotalNum : 0);
      List<Map<String, dynamic>> items = (order['items'] is List)
          ? List<Map<String, dynamic>>.from(
              (order['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];

      // If items are missing from the DB, try to parse from the scanned human-readable text
      if (items.isEmpty) {
        final parsedItems = _parseItemsFromText(data);
        if (parsedItems.isNotEmpty) {
          debugPrint('✅ QR Scanner: Parsed ${parsedItems.length} items from text');
          items = parsedItems;
        }
      }

      // If contributions still empty, try to parse from the scanned human-readable text
      if (cons.isEmpty) {
        final parsedCons = _parseContributionsFromText(data);
        if (parsedCons.isNotEmpty) {
          debugPrint('✅ QR Scanner: Parsed ${parsedCons.length} contributions from text');
          cons = parsedCons;
        }
      }

      // Show dialog with details
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          final Color primaryGreen = const Color(0xFF2E7D32);
          final Color softGreen = const Color(0xFFE8F5E9);
          final Color borderGreen = const Color(0xFFB7D7C5);

          BoxDecoration cardDecoration({bool elevated = false}) => BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
                border: Border.all(color: borderGreen),
                boxShadow: elevated
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              );

          Widget sectionLabel(String label) => Padding(
                padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
                child: Text(
                  label,
                  style: TextStyle(
                    color: primaryGreen,
                    fontSize: Responsive.getFontSize(context, mobile: 15),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );

          return Dialog(
            insetPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 22), vertical: Responsive.getSpacing(context, mobile: 32)),
            backgroundColor: softGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18))),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
                decoration: BoxDecoration(
                  color: softGreen,
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryGreen, primaryGreen.withOpacity(0.85)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
                        boxShadow: [
                          BoxShadow(
                            color: primaryGreen.withOpacity(0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Packaging QR',
                            style: TextStyle(color: Colors.white70, fontSize: Responsive.getFontSize(context, mobile: 14), letterSpacing: 1),
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                          Text(
                            header.isNotEmpty ? header : 'ORDER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: Responsive.getFontSize(context, mobile: 26),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (generatedAt != null) ...[
                            SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                            Text(
                              'Generated ${_formatTs(generatedAt)}',
                              style: TextStyle(color: Colors.white70, fontSize: Responsive.getFontSize(context, mobile: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 18)),
                    Container(
                      decoration: cardDecoration(elevated: true),
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionLabel('Order Overview'),
                          _infoRow('Customer', customerName),
                          if (customerPhone.isNotEmpty) _infoRow('Phone', customerPhone),
                          _infoRow(deliveryOption == 'pickup' ? 'Pickup Address' : 'Address', address),
                          _infoRow('Payment', paymentMethod),
                          if (createdAt != null) _infoRow('Order Date', _formatTs(createdAt)),
                          SizedBox(height: Responsive.getHeight(context, mobile: 10)),
                          Text(
                            'Cost Breakdown',
                            style: TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                          _metaRow('Subtotal', '\u20B1${subtotalNum.toStringAsFixed(2)}'),
                          _metaRow('Delivery Fee', '\u20B1${deliveryFeeNum.toStringAsFixed(2)}'),
                          Divider(height: Responsive.getHeight(context, mobile: 18), thickness: 0.6),
                          _metaRow('Total', '\u20B1${totalNum.toStringAsFixed(2)}', emphasize: true),
                        ],
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    if (items.isNotEmpty) ...[
                      Container(
                        decoration: cardDecoration(),
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sectionLabel('Items'),
                            _tableHeader(['Product', 'Quantity', 'Unit'], primaryGreen),
                            ...items.map((it) {
                              final name = (it['productName'] ?? 'Item').toString();
                              final qty = (it['quantity'] ?? '').toString();
                              final unit = (it['unit'] ?? '').toString();
                              return _tableRow([name, qty, unit]);
                            }),
                          ],
                        ),
                      ),
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    ] else
                      Container(
                        decoration: cardDecoration(),
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sectionLabel('Items'),
                            Text(
                              'No items found',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      decoration: cardDecoration(),
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionLabel('Farmer Contributions'),
                          if (cons.isEmpty)
                            Text(
                              'No contributions provided',
                              style: TextStyle(color: Colors.grey.shade600),
                            )
                          else ...[
                            _tableHeader(['Farmer', 'Product', 'Qty (kg)'], primaryGreen),
                            ...cons.map((c) {
                              final farmerName =
                                  (c is Map && c['farmerName'] != null) ? c['farmerName'].toString() : 'Farmer';
                              final productName =
                                  (c is Map && c['productName'] != null) ? c['productName'].toString() : 'Product';
                              final qty = (c is Map && c['quantity'] != null) ? c['quantity'].toString() : '0';
                              return _tableRow([
                                farmerName,
                                productName,
                                qty,
                              ]);
                            }),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: primaryGreen,
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Close'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isScanning = true;
                            _scannedData = '';
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    // Fallback: show raw data
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('QR Code Scanned'),
          content: Text(data),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isScanning = true;
                  _scannedData = '';
                });
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _toggleFlash() async {
    await controller?.toggleTorch();
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  void _switchCamera() async {
    await controller?.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<Map<String, dynamic>> _fetchOrderDetails(String orderId) async {
    if (orderId.isEmpty) {
      debugPrint('❌ QR Scanner: Order ID is empty');
      return {};
    }

    debugPrint('🔍 QR Scanner: Fetching order details for orderId: $orderId');

    try {
      await SupabaseService.initialize();
      
      // Try querying with both 'id' and 'order_id' fields (similar to customer_provider.dart)
      final response = await SupabaseService.client
          .from('orders')
          .select(
            'id, customer_name, customer_phone, customer_address, delivery_address, delivery_option, payment_method, '
            'order_date, created_at, total, total_amount, subtotal, delivery_fee, items, '
            'pickup_address, pickup_name, pickup_street, pickup_sitio, pickup_barangay, '
            'pickup_city, pickup_province, pickup_landmark, pickup_instructions, pickup_map_link',
          )
          .or('id.eq.$orderId,order_id.eq.$orderId')
          .maybeSingle();

      if (response != null) {
        debugPrint('✅ QR Scanner: Order found - items count: ${response['items']?.length ?? 0}');
        return {
          'customerName': response['customer_name'],
          'customerPhone': response['customer_phone'],
          'customerAddress': response['customer_address'],
          'deliveryAddress': response['delivery_address'],
          'deliveryOption': response['delivery_option'],
          'paymentMethod': response['payment_method'],
          'createdAt': response['order_date'] ?? response['created_at'],
          'totalAmount': response['total_amount'] ?? response['total'] ?? response['subtotal'],
          'subtotal': response['subtotal'],
          'deliveryFee': response['delivery_fee'],
          'items': response['items'] ?? [],
          'pickupAddress': response['pickup_address'],
          'pickupName': response['pickup_name'],
          'pickupStreet': response['pickup_street'],
          'pickupSitio': response['pickup_sitio'],
          'pickupBarangay': response['pickup_barangay'],
          'pickupCity': response['pickup_city'],
          'pickupProvince': response['pickup_province'],
          'pickupLandmark': response['pickup_landmark'],
          'pickupInstructions': response['pickup_instructions'],
          'pickupMapLink': response['pickup_map_link'],
        };
      } else {
        debugPrint('❌ QR Scanner: Order not found in database for orderId: $orderId');
      }
    } catch (e) {
      debugPrint('❌ QR Scanner: Error loading order from Supabase: $e');
      debugPrint('❌ QR Scanner: Stack trace: ${StackTrace.current}');
    }

    return {};
  }

  Future<List<dynamic>> _fetchContributionsFromQrPackaging(String orderId) async {
    if (orderId.isEmpty) {
      debugPrint('❌ QR Scanner: Order ID is empty for contributions fetch');
      return [];
    }

    debugPrint('🔍 QR Scanner: Fetching contributions for orderId: $orderId');

    try {
      await SupabaseService.initialize();
      
      final response = await SupabaseService.client
          .from('qr_packaging')
          .select('contributions')
          .eq('order_id', orderId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && response['contributions'] != null) {
        final contributions = response['contributions'];
        if (contributions is List) {
          debugPrint('✅ QR Scanner: Found ${contributions.length} contributions');
          return contributions;
        } else {
          debugPrint('⚠️ QR Scanner: Contributions is not a List: ${contributions.runtimeType}');
        }
      } else {
        debugPrint('❌ QR Scanner: No contributions found in qr_packaging for orderId: $orderId');
      }
    } catch (e) {
      debugPrint('❌ QR Scanner: Error loading contributions from qr_packaging: $e');
      debugPrint('❌ QR Scanner: Stack trace: ${StackTrace.current}');
    }

    return [];
  }

  // Parse items from the human-readable text section in the scanned QR payload
  List<Map<String, dynamic>> _parseItemsFromText(String data) {
    final items = <Map<String, dynamic>>[];
    // Extract the ITEMS section
    final itemsSectionMatch = RegExp(r'ITEMS:\s*(.+?)(?:\n\n|$)', dotAll: true, caseSensitive: false).firstMatch(data);
    if (itemsSectionMatch == null) return items;

    final lines = itemsSectionMatch.group(1)!.split('\n');
    for (final line in lines) {
      // Format: Product: 2 kg × ₱100.00 = ₱200.00
      final match = RegExp(
        r'^(.+?):\s*([\d.]+)\s+([A-Za-z]+)\s+×\s*₱([\d.]+)',
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (match != null) {
        final productName = match.group(1)?.trim() ?? 'Product';
        final qty = double.tryParse(match.group(2) ?? '') ?? 0;
        final unit = match.group(3)?.trim() ?? 'kg';
        final price = double.tryParse(match.group(4) ?? '') ?? 0;
        items.add({
          'productName': productName,
          'quantity': qty,
          'unit': unit,
          'price': price,
        });
      }
    }
    return items;
  }

  // Parse farmer contributions from the human-readable text section in the scanned QR payload
  List<Map<String, dynamic>> _parseContributionsFromText(String data) {
    final cons = <Map<String, dynamic>>[];
    // Extract the FARMER CONTRIBUTIONS section
    final consSectionMatch =
        RegExp(r'FARMER CONTRIBUTIONS:\s*(.+?)(?:\n\n|$)', dotAll: true, caseSensitive: false).firstMatch(data);
    if (consSectionMatch == null) return cons;

    final lines = consSectionMatch.group(1)!.split('\n');
    for (final line in lines) {
      // Format: Farmer Name: Product - 2 kg
      final match = RegExp(
        r'^(.+?):\s*(.+?)\s*-\s*([\d.]+)\s*kg',
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (match != null) {
        final farmerName = match.group(1)?.trim() ?? 'Farmer';
        final productName = match.group(2)?.trim() ?? 'Product';
        final qty = double.tryParse(match.group(3) ?? '') ?? 0;
        cons.add({
          'farmerName': farmerName,
          'productName': productName,
          'quantity': qty,
        });
      }
    }
    return cons;
  }

  Widget _infoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 4)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
                fontSize: Responsive.getFontSize(context, mobile: 13),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black87,
                fontSize: Responsive.getFontSize(context, mobile: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 3)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? Colors.black : Colors.black54,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? Colors.black : Colors.black87,
              fontSize: emphasize ? 16 : 14,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(List<String> columns, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
      ),
      child: Row(
        children: columns
            .map(
              (col) => Expanded(
                child: Text(
                  col,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: Responsive.getFontSize(context, mobile: 13),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _tableRow(List<String> values) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
      ),
      child: Row(
        children: values
            .map(
              (value) => Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: Responsive.getFontSize(context, mobile: 13),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  String _formatTs(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final hour12 = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$day/$month/$year • $hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('QR Scanner'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: Responsive.getIconSize(context, mobile: 64),
                color: Colors.grey,
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              Text(
                'Camera Permission Required',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              const Text(
                'This app needs camera access to scan QR codes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 24)),
              ElevatedButton(
                onPressed: _requestCameraPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
          IconButton(
            icon: Icon(_isFrontCamera ? Icons.camera_front : Icons.camera_rear),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) async {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null && _isScanning) {
                    setState(() {
                      _scannedData = barcode.rawValue!;
                      _isScanning = false;
                    });
                    await _handleScannedData(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
              child: Column(
                children: [
                  Text(
                    'Position QR code within the frame',
                    style: TextStyle(
                      fontSize: Responsive.getFontSize(context, mobile: 16),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                  Text(
                    _scannedData.isNotEmpty ? 'Scanned: $_scannedData' : 'No QR code detected',
                    style: TextStyle(
                      fontSize: Responsive.getFontSize(context, mobile: 14),
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
