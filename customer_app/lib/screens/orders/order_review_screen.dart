import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/order.dart';
import '../../models/delivery_address.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/order_schedule.dart';
import '../../utils/theme.dart';
import '../../services/delivery_fee_service.dart';
import '../../services/pickup_address_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/searchable_barangay_dropdown.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../utils/responsive.dart';

class OrderReviewScreen extends StatefulWidget {
  const OrderReviewScreen({super.key});

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  String deliveryOption = 'delivery'; // delivery or pickup
  String paymentMethod = 'cash'; // cash or gcash
  final TextEditingController addressController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController addressLabelController = TextEditingController();
  File? _gcashReceiptFile;
  String? _gcashReceiptUrl;
  bool _uploadingReceipt = false;
  final GlobalKey _qrKey = GlobalKey();
  bool _qrAssetExists = true;
  DeliveryAddress? _selectedAddress;
  bool _addressesLoadedOnce = false;
  bool _isPolicyDropdownExpanded = false;
  double _deliveryFee = 0.0;
  String _deliveryFeeStatus = 'loading'; // 'loading', 'available', 'unavailable'
  bool _isLoadingDeliveryFee = false;
  
  // Pickup address related state
  PickupAddress? _activePickupAddress;
  bool _isLoadingPickupAddress = true;
  StreamSubscription<PickupAddress?>? _pickupAddressSubscription;

  @override
  void dispose() {
    addressController.dispose();
    notesController.dispose();
    addressLabelController.dispose();
    _pickupAddressSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDeliveryAddresses();
      await _loadActivePickupAddress();
      _setupPickupAddressListener();
    });
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


  Future<void> _pickReceiptImage() async {
    try {
      final picker = ImagePicker();
      final result = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (result == null) return;
      setState(() {
        _gcashReceiptFile = File(result.path);
      });
      await _uploadReceiptToStorage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadReceiptToStorage() async {
    if (_gcashReceiptFile == null) return;
    try {
      setState(() {
        _uploadingReceipt = true;
      });
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final customerId = auth.currentCustomer?.uid ?? 'unknown';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'receipts/$customerId/gcash_$ts.jpg';
      
      // Upload to Supabase bucket gcash_receipt
      final url = await SupabaseService.uploadGcashReceipt(_gcashReceiptFile!, fileName);
      
      setState(() {
        _gcashReceiptUrl = url;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt uploaded successfully'), backgroundColor: Colors.green),
      );
    } catch (e) {
      // Supabase Storage might be unavailable
      // Fallback: mark receipt as pending so order can proceed.
      setState(() {
        _gcashReceiptUrl = 'pending:gcash_receipt';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Storage unavailable. Receipt marked as pending and will sync later. Error: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingReceipt = false;
        });
      }
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

  Future<void> _loadActivePickupAddress() async {
    try {
      print('🏪 🔄 Loading active pickup address...');
      print('🏪 🔄 Firebase app initialized: ${Firebase.apps.isNotEmpty}');
      print('🏪 🔄 Firebase apps: ${Firebase.apps.map((app) => app.name).toList()}');
      
      if (mounted) {
        setState(() {
          _isLoadingPickupAddress = true;
        });
      }
      
      // Test Firebase connection first
      try {
        final database = FirebaseDatabase.instance;
        print('🏪 🔄 Firebase database instance created');
        print('🏪 🔄 Database URL: ${database.databaseURL}');
        
        // Test read from a simple path
        final testRef = database.ref('test');
        await testRef.set({'timestamp': DateTime.now().millisecondsSinceEpoch});
        print('🏪 🔄 Firebase write test successful');
        await testRef.remove();
        print('🏪 🔄 Firebase cleanup successful');
      } catch (e) {
        print('🏪 ❌ Firebase connection test failed: $e');
      }
      
      final pickupAddress = await PickupAddressService.getActivePickupAddress();
      
      print('🏪 Loaded pickup address: $pickupAddress');
      if (pickupAddress != null) {
        print('🏪 Pickup address details:');
        print('  - name: ${pickupAddress.name}');
        print('  - landmark: ${pickupAddress.landmark}');
        print('  - instructions: ${pickupAddress.instructions}');
        print('  - mapLink: ${pickupAddress.mapLink}');
      }
      
      if (mounted) {
        setState(() {
          _activePickupAddress = pickupAddress;
          _isLoadingPickupAddress = false;
        });
        
        if (pickupAddress != null) {
          print('🏪 ✅ Active pickup address loaded: ${pickupAddress.name} - ${pickupAddress.address}');
        } else {
          print('🏪 ❌ No active pickup address found');
        }
      }
    } catch (e) {
      print('🏪 ❌ Error loading active pickup address: $e');
      print('🏪 ❌ Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          _activePickupAddress = null;
          _isLoadingPickupAddress = false;
        });
      }
    }
  }

  void _setupPickupAddressListener() {
    print('🏪 Setting up pickup address listener...');
    _pickupAddressSubscription = PickupAddressService.listenToActivePickupAddress().listen(
      (pickupAddress) {
        if (mounted) {
          print('🏪 📱 UI Update: Setting pickup address to: ${pickupAddress?.name ?? 'null'}');
          
          setState(() {
            _activePickupAddress = pickupAddress;
          });
          
          if (pickupAddress != null) {
            print('🏪 ✅ Real-time update received: ${pickupAddress.name} - ${pickupAddress.address}');
            
            // Removed debug notification - no longer showing SnackBar for pickup location updates
          } else {
            print('🏪 Pickup address cleared via listener');
          }
        } else {
          print('🏪 Widget not mounted, skipping UI update');
        }
      },
      onError: (error) {
        print('🏪 Error in pickup address listener: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection error: ${error.toString()}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Removed duplicate loading - only load from initState to prevent duplicates
    // Addresses are loaded once in initState and reloaded only when needed
  }

  Future<void> _calculateDeliveryFee() async {
    if (deliveryOption != 'delivery' || _selectedAddress == null) {
      setState(() {
        _deliveryFee = 0.0;
        _deliveryFeeStatus = 'unavailable';
        _isLoadingDeliveryFee = false;
      });
      return;
    }

    setState(() {
      _isLoadingDeliveryFee = true;
      _deliveryFeeStatus = 'loading';
    });

    try {
      print('🔍 Selected address: ${_selectedAddress!.address}');
      
      // Extract barangay from selected address
      final barangayName = DeliveryFeeService.extractBarangayFromAddress(_selectedAddress!.address);
      
      print('🔍 Extracted barangay: "$barangayName"');
      
      if (barangayName.isEmpty) {
        print('❌ No barangay found in address');
        setState(() {
          _deliveryFee = 0.0;
          _deliveryFeeStatus = 'unavailable';
          _isLoadingDeliveryFee = false;
        });
        return;
      }

      // Get delivery fee for the barangay
      final fee = await DeliveryFeeService.getDeliveryFeeForBarangay(barangayName);
      
      print('🔍 Final delivery fee: $fee');
      
      setState(() {
        _deliveryFee = fee;
        _deliveryFeeStatus = fee > 0 ? 'available' : 'unavailable';
        _isLoadingDeliveryFee = false;
      });

      print('🚚 Delivery fee calculated: \u20B1$_deliveryFee for barangay: $barangayName');
      
    } catch (e) {
      print('🚚 Error calculating delivery fee: $e');
      setState(() {
        _deliveryFee = 0.0;
        _deliveryFeeStatus = 'unavailable';
        _isLoadingDeliveryFee = false;
      });
    }
  }

  Future<void> _loadDeliveryAddresses() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentCustomer != null) {
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      
      // Show loading state immediately
      if (mounted) {
        setState(() {});
      }
      
      final previouslySelectedId = _selectedAddress?.id;
      await provider.loadDeliveryAddresses(auth.currentCustomer!.uid);
      
      print('📍 Loaded ${provider.deliveryAddresses.length} delivery addresses');
      print('📍 Customer ID: ${auth.currentCustomer!.uid}');
      print('📍 Customer address: ${auth.currentCustomer!.address}');
      
      // If no addresses are found, create one from the customer's profile
      // Only create once per session to prevent duplicates
      if (provider.deliveryAddresses.isEmpty && !_addressesLoadedOnce) {
        print('📍 No saved addresses found, creating from profile...');
        final customer = auth.currentCustomer!;
        final fullAddress = '${customer.address}, ${customer.city}, ${customer.state} ${customer.zipCode}'.trim();
        
        print('📍 Creating address: $fullAddress');
        print('📍 Customer details: address=${customer.address}, city=${customer.city}, state=${customer.state}, zipCode=${customer.zipCode}');
        
        final success = await provider.saveDeliveryAddress(
          customerId: customer.uid,
          address: fullAddress,
          label: 'Home',
          phoneNumber: customer.phoneNumber.isNotEmpty ? customer.phoneNumber : null,
          isDefault: true,
        );
        
        print('📍 Address creation result: $success');
        
        if (success) {
          // Reload addresses after creating
          await provider.loadDeliveryAddresses(customer.uid);
          print('📍 Reloaded addresses: ${provider.deliveryAddresses.length}');
        }
      } else {
        print('📍 Found existing addresses: ${provider.deliveryAddresses.map((a) => '${a.label}: ${a.address}').join(', ')}');
      }
      
      // Keep previously selected address if it still exists; otherwise fall back to default
      if (provider.deliveryAddresses.isNotEmpty) {
        final stillExists = previouslySelectedId != null
            ? provider.deliveryAddresses.firstWhere(
                (a) => a.id == previouslySelectedId,
                orElse: () => provider.defaultDeliveryAddress ?? provider.deliveryAddresses.first,
              )
            : (provider.defaultDeliveryAddress ?? provider.deliveryAddresses.first);

        if (_selectedAddress == null || _selectedAddress!.id != stillExists.id) {
          setState(() {
            _selectedAddress = stillExists;
          });
          // Calculate delivery fee for the selected address
          _calculateDeliveryFee();
        }
      }
      
      // Final UI update
      if (mounted) {
        setState(() {});
      }
      _addressesLoadedOnce = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final provider = Provider.of<CustomerProvider>(context);

    // Prefer Buy Now buffer if present; otherwise use cart items
    final buyNow = provider.buyNowItems;
    final items = buyNow.isNotEmpty ? buyNow : provider.cartItems;
    final subtotal = items.fold<double>(0, (sum, it) => sum + it.total);
    final deliveryFee = deliveryOption == 'delivery' ? _deliveryFee : 0.0; // dynamic barangay-based fee
    final total = subtotal + deliveryFee;

    if (auth.currentCustomer == null) {
      return const Scaffold(
        body: Center(child: Text('Please login again')),
      );
    }

    // Do not re-initialize here to avoid flicker; handled in _loadDeliveryAddresses()

    return Scaffold(
      appBar: AppBar(title: const Text('Review Order')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
          children: [
            // Items summary
            Text('Items', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            ...items.map((it) {
              final product = provider.getProductById(it.productId);
              return ListTile(
                leading: _buildProductMediaCarousel(product, 60),
                title: Text(it.productName),
                subtitle: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${it.quantity} ${it.unit} × ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                      TextSpan(
                        text: '\u20B1',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontFamilyFallback: const ['Arial', 'sans-serif'],
                          color: Colors.grey[600],
                        ),
                      ),
                      TextSpan(
                        text: it.price.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                trailing: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '\u20B1',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontFamilyFallback: const ['Arial', 'sans-serif'],
                        ),
                      ),
                      TextSpan(
                        text: it.total.toStringAsFixed(2),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 32),

            // Ordering and Cancellation Schedule Note (Dropdown)
            _buildOrderingPolicyDropdown(),
            SizedBox(height: Responsive.getHeight(context, mobile: 16)),

            // Delivery or Pickup
            Text('Fulfillment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Delivery'),
                    value: 'delivery',
                    groupValue: deliveryOption,
                    onChanged: (v) {
                      setState(() => deliveryOption = v ?? 'delivery');
                      _calculateDeliveryFee();
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Pick-up'),
                    value: 'pickup',
                    groupValue: deliveryOption,
                    onChanged: (v) {
                      setState(() => deliveryOption = v ?? 'pickup');
                      _calculateDeliveryFee();
                      
                      // If switching to pickup, refresh the pickup address
                      if (v == 'pickup') {
                        print('🏪 User selected pickup, refreshing pickup address...');
                        _loadActivePickupAddress();
                      }
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            if (deliveryOption == 'delivery') ...[
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          ),
                          child: Icon(Icons.location_on, color: Colors.blue[600], size: Responsive.getIconSize(context, mobile: 20)),
                        ),
                        SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivery Address',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                              Text(
                                'Select from your saved addresses',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                    
                    // Saved Addresses Section
                    Container(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Saved Addresses',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const Spacer(),
                              // Add Address Button
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue[600],
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    _showAddAddressDialog();
                                  },
                                  icon: Icon(Icons.add, color: Colors.white, size: Responsive.getIconSize(context, mobile: 18)),
                                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                          
                          // Address List
                          if (provider.isLoading) ...[
                            // Loading state
                            Container(
                              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ] else if (provider.deliveryAddresses.isNotEmpty) ...[
                            // Address cards with proper constraints
                            // Deduplicate addresses by ID to prevent duplicate displays
                            Builder(
                              builder: (context) {
                                // Deduplicate by ID
                                final seenIds = <String>{};
                                final uniqueAddresses = provider.deliveryAddresses.where((address) {
                                  if (seenIds.contains(address.id)) {
                                    return false;
                                  }
                                  seenIds.add(address.id);
                                  return true;
                                }).toList();
                                
                                return ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 300, // Limit height to prevent overflow
                                  ),
                                  child: SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: Column(
                                      children: uniqueAddresses.map((address) => 
                                        _buildAddressCard(address, uniqueAddresses.indexOf(address) == 0)
                                      ).toList(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ] else ...[
                            // Empty state for new customers
                            Container(
                              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.location_off, color: Colors.grey[400], size: Responsive.getIconSize(context, mobile: 32)),
                                  SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                                  Text(
                                    'No saved addresses yet',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                                  Text(
                                    'Add your first address to get started',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (deliveryOption == 'pickup') ...[
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, color: Colors.grey[600], size: Responsive.getIconSize(context, mobile: 20)),
                        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                        Text(
                          'Pick-up Information',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        // Real-time indicator
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 4)),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            border: Border.all(color: Colors.green[300]!, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: Responsive.getWidth(context, mobile: 6),
                                height: Responsive.getHeight(context, mobile: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green[600],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: Responsive.getWidth(context, mobile: 4)),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: Responsive.getFontSize(context, mobile: 10),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    
                    // Display active pickup address
                    if (_isLoadingPickupAddress) ...[
                      Container(
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: Responsive.getWidth(context, mobile: 20),
                              height: Responsive.getHeight(context, mobile: 20),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                            Text(
                              'Loading pickup location...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_activePickupAddress != null) ...[
                      Container(
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.store, color: Colors.green[600], size: Responsive.getIconSize(context, mobile: 16)),
                                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                                Text(
                                  _activePickupAddress!.name,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[700],
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 2)),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.bold,
                                      fontSize: Responsive.getFontSize(context, mobile: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            Text(
                              _activePickupAddress!.getFormattedAddress().split(' - ').skip(1).join(' - '),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[700],
                              ),
                            ),
                            // Always show landmark section
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.place, color: Colors.grey[600], size: Responsive.getIconSize(context, mobile: 16)),
                                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Landmark',
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 12),
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                                      Text(
                                        _activePickupAddress!.landmark?.isNotEmpty == true
                                            ? _activePickupAddress!.landmark!
                                            : 'No landmark provided',
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            // Always show instructions section
                            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline, color: Colors.grey[600], size: Responsive.getIconSize(context, mobile: 16)),
                                SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Instructions',
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 12),
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                                      Text(
                                        _activePickupAddress!.instructions?.isNotEmpty == true
                                            ? _activePickupAddress!.instructions!
                                            : 'No pickup instructions provided',
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            // Always show navigate button if map link exists
                            if (_activePickupAddress!.mapLink?.isNotEmpty == true) ...[
                              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ElevatedButton.icon(
                                  onPressed: () => _launchGoogleMaps(_activePickupAddress!.mapLink),
                                  icon: Icon(Icons.navigation, size: Responsive.getIconSize(context, mobile: 16)),
                                  label: const Text('Navigate'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12), vertical: Responsive.getSpacing(context, mobile: 8)),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.store_outlined, color: Colors.orange[600], size: Responsive.getIconSize(context, mobile: 32)),
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            Text(
                              'No Active Pickup Location',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[700],
                              ),
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                            Text(
                              'Please contact staff to set up a pickup location',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.orange[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  print('🔍 Debug: Testing pickup address service...');
                                  print('🔍 Debug: Current state - _isLoadingPickupAddress: $_isLoadingPickupAddress');
                                  print('🔍 Debug: Current state - _activePickupAddress: $_activePickupAddress');
                                  
                                  // Test Firebase connection first
                                  try {
                                    final database = FirebaseDatabase.instance;
                                    print('🔍 Debug: Firebase database instance: $database');
                                    print('🔍 Debug: Database URL: ${database.databaseURL}');
                                    
                                    // Test basic Firebase access
                                    final testRef = database.ref('test');
                                    await testRef.set({'timestamp': DateTime.now().millisecondsSinceEpoch});
                                    print('🔍 Debug: Firebase write test successful');
                                    await testRef.remove();
                                    print('🔍 Debug: Firebase cleanup successful');
                                    
                                    // Test reading from Supabase
                                    await SupabaseService.initialize();
                                    final supabase = SupabaseService.client;
                                    final areas = await supabase
                                        .from('pickup_area')
                                        .select('*') as List;
                                    
                                    print('🔍 Debug: Supabase pickup_area data: $areas');
                                    
                                    if (areas.isNotEmpty) {
                                      print('🔍 Debug: pickup_area count: ${areas.length}');
                                      for (final area in areas) {
                                        final areaMap = area as Map<String, dynamic>;
                                        print('🔍 Debug: Area ${areaMap['id']}: ${areaMap['name']} (active: ${areaMap['active']})');
                                      }
                                    }
                                    
                                  } catch (e) {
                                    print('🔍 Debug: Error accessing Supabase: $e');
                                    print('🔍 Debug: Stack trace: ${StackTrace.current}');
                                  }
                                  
                                  final allLocations = await PickupAddressService.getAllPickupLocations();
                                  print('🔍 Debug: Found ${allLocations.length} pickup locations');
                                  for (final location in allLocations) {
                                    print('🔍 Debug: Location - ${location.name}: ${location.address} (active: ${location.active})');
                                  }
                                  
                                  final activeLocation = await PickupAddressService.getActivePickupAddress();
                                  print('🔍 Debug: Active location: $activeLocation');
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Debug: Found ${allLocations.length} locations, active: ${activeLocation?.name ?? 'none'}'),
                                        backgroundColor: Colors.blue,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(Icons.bug_report, size: Responsive.getIconSize(context, mobile: 16)),
                                label: const Text('Debug'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[100],
                                  foregroundColor: Colors.blue[700],
                                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 8)),
                                ),
                              ),
                            ),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  print('🔄 Manually reloading pickup address...');
                                  await _loadActivePickupAddress();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Reloaded: ${_activePickupAddress?.name ?? 'No pickup found'}'),
                                        backgroundColor: Colors.green,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(Icons.refresh, size: Responsive.getIconSize(context, mobile: 16)),
                                label: const Text('Reload'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[100],
                                  foregroundColor: Colors.green[700],
                                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 8)),
                                ),
                              ),
                            ),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  print('🧪 Testing real-time listener...');
                                  // Cancel current subscription and restart it
                                  _pickupAddressSubscription?.cancel();
                                  _setupPickupAddressListener();
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Restarted real-time listener'),
                                        backgroundColor: Colors.orange,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(Icons.sync, size: Responsive.getIconSize(context, mobile: 16)),
                                label: const Text('Test RT'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange[100],
                                  foregroundColor: Colors.orange[700],
                                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            // Payment method
            Text('Payment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Cash on Delivery'),
                    value: 'cash',
                    groupValue: paymentMethod,
                    onChanged: (v) => setState(() => paymentMethod = v ?? 'cash'),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('GCash (Online)'),
                    value: 'gcash',
                    groupValue: paymentMethod,
                    onChanged: (v) => setState(() => paymentMethod = v ?? 'gcash'),
                  ),
                ),
              ],
            ),

            if (paymentMethod == 'gcash') ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.qr_code, size: Responsive.getIconSize(context, mobile: 20)),
                        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                        Text('GCash Payment QR'),
                      ],
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    Center(
                      child: RepaintBoundary(
                        key: _qrKey,
                        child: Container(
                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.green, width: 3),
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Show official personal QR image if provided
                              // Ensure file exists at assets/images/order_gcash_qr.JPG
                              if (_qrAssetExists)
                                Image.asset(
                                  'assets/images/order_gcash_qr.JPG',
                                  width: Responsive.getWidth(context, mobile: 220),
                                  height: Responsive.getHeight(context, mobile: 220),
                                  fit: BoxFit.contain,
                                )
                              else
                                Container(
                                  width: Responsive.getWidth(context, mobile: 220),
                                  height: Responsive.getHeight(context, mobile: 220),
                                  color: Colors.grey[200],
                                  alignment: Alignment.center,
                                  child: const Text('GCash QR not found'),
                                ),
                              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                              Text(
                                'Joylyn Mae P. Olacao',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                              SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                              Text(
                                '09525818621',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                              Text(
                                'Amount: \u20B1${total.toStringAsFixed(2)}',
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
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () => _saveQrToGallery(total),
                        icon: const Icon(Icons.download),
                        label: const Text('Download QR'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.receipt_long, size: Responsive.getIconSize(context, mobile: 20)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Expanded(
                              child: Text(
                                'Upload GCash Receipt (Required)',
                                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _uploadingReceipt ? null : () => _pickReceiptImage(),
                            icon: const Icon(Icons.photo_library),
                            label: Text(_gcashReceiptFile != null ? 'Change Receipt' : 'Upload Receipt'),
                          ),
                        ),
                      ],
                    ),
                    if (_gcashReceiptFile != null || _gcashReceiptUrl?.startsWith('pending:') == true) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Expanded(
                            child: Text(
                              _gcashReceiptFile != null
                                  ? 'Receipt selected. ${_gcashReceiptFile!.path.split('/').last}'
                                  : 'Receipt pending upload (will sync when storage is available)',
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_gcashReceiptFile != null) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Receipt Preview:',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                              child: Image.file(
                                _gcashReceiptFile!,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_uploadingReceipt) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                      const LinearProgressIndicator(),
                      SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                      const Text('Uploading receipt...'),
                    ],
                  ],
                ),
              ),
            ],

            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            // Order notes indicator
            Container(
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: Responsive.getIconSize(context, mobile: 18)),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  Expanded(
                    child: Text(
                      deliveryOption == 'pickup' 
                          ? 'You can provide an order or pickup notes for your concerns!'
                          : 'You can provide an order or delivery notes for your concerns!',
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 13),
                        color: Colors.blue[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            TextFormField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),

            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
            // Totals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal',
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 14),
                    color: Colors.black87,
                  ),
                ),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '\u20B1',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontFamilyFallback: const ['Arial', 'sans-serif'],
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.black87,
                        ),
                      ),
                      TextSpan(
                        text: subtotal.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 14),
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Delivery Fee${deliveryOption == "pickup" ? ' (pickup)' : ''}',
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 14),
                    color: Colors.black87,
                  ),
                ),
                if (_isLoadingDeliveryFee)
                  SizedBox(
                    width: Responsive.getWidth(context, mobile: 16),
                    height: Responsive.getHeight(context, mobile: 16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '\u20B1',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontFamilyFallback: const ['Arial', 'sans-serif'],
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            color: Colors.black87,
                          ),
                        ),
                        TextSpan(
                          text: deliveryFee.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: Responsive.getFontSize(context, mobile: 14),
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (deliveryOption == 'delivery') ...[
              if (_deliveryFeeStatus == 'loading')
                Padding(
                  padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 4)),
                  child: Text(
                    'Calculating delivery fee...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else if (_deliveryFeeStatus == 'unavailable')
                Padding(
                  padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 4)),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[600], size: Responsive.getIconSize(context, mobile: 16)),
                      SizedBox(width: Responsive.getWidth(context, mobile: 4)),
                      Text(
                        'Delivery not available to this location',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_deliveryFeeStatus == 'available')
                Padding(
                  padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 4)),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[600], size: Responsive.getIconSize(context, mobile: 16)),
                      SizedBox(width: Responsive.getWidth(context, mobile: 4)),
                      Text(
                        'Delivery available to ${_selectedAddress != null ? DeliveryFeeService.extractBarangayFromAddress(_selectedAddress!.address) : 'selected location'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            SizedBox(height: Responsive.getHeight(context, mobile: 4)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: Responsive.getFontSize(context, mobile: 16),
                    color: Colors.black87,
                  ),
                ),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '\u20B1',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontFamilyFallback: const ['Arial', 'sans-serif'],
                          fontWeight: FontWeight.bold,
                          fontSize: Responsive.getFontSize(context, mobile: 16),
                          color: Colors.black87,
                        ),
                      ),
                      TextSpan(
                        text: total.toStringAsFixed(2),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: Responsive.getFontSize(context, mobile: 16),
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: Responsive.getHeight(context, mobile: 24)),
            ElevatedButton.icon(
              onPressed: OrderSchedule.canPlaceOrder() ? () async {
                print('🛒 Starting order placement process...');
                print('🛒 Current customer: ${auth.currentCustomer?.uid}');
                print('🛒 Selected address: ${_selectedAddress?.address}');
                
                // Check if ordering is currently allowed
                if (!OrderSchedule.canPlaceOrder()) {
                  final nextStart = OrderSchedule.getNextOrderingPeriodStart();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ordering is currently closed. Next ordering period starts ${OrderSchedule.formatDateTime(nextStart)}'),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                  return;
                }
                
                if (!_formKey.currentState!.validate()) {
                  print('❌ Form validation failed');
                  return;
                }
                
                // Validate pickup address availability
                if (deliveryOption == 'pickup' && _activePickupAddress == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No active pickup location available. Please contact staff.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                
                // Validate delivery address selection
                if (deliveryOption == 'delivery' && _selectedAddress == null) {
                  print('❌ No delivery address selected');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a delivery address'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                // Validate delivery availability
                if (deliveryOption == 'delivery' && _deliveryFeeStatus == 'unavailable') {
                  print('❌ Delivery not available to selected address');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Delivery is not available to the selected address. Please choose pickup or select a different address.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                  return;
                }
                
                // Check if delivery fee is still loading
                if (deliveryOption == 'delivery' && _deliveryFeeStatus == 'loading') {
                  print('❌ Delivery fee still loading');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please wait while we calculate the delivery fee...'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                
                if (paymentMethod == 'gcash') {
                  if (_gcashReceiptUrl == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please upload your GCash payment receipt to continue'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                print('🛒 Creating order object...');
                print('🛒 Delivery option: $deliveryOption');
                print('🛒 Active pickup address: $_activePickupAddress');
                if (_activePickupAddress != null) {
                  print('🛒 Pickup address details:');
                  print('  - name: ${_activePickupAddress!.name}');
                  print('  - landmark: ${_activePickupAddress!.landmark}');
                  print('  - instructions: ${_activePickupAddress!.instructions}');
                  print('  - mapLink: ${_activePickupAddress!.mapLink}');
                }
                final customer = auth.currentCustomer!;
                // Use phone from selected address if available, otherwise fallback to customer phone
                final phoneNumber = deliveryOption == 'delivery' && _selectedAddress?.phoneNumber != null && _selectedAddress!.phoneNumber!.isNotEmpty
                    ? _selectedAddress!.phoneNumber!
                    : customer.phoneNumber;
                final order = Order(
                  id: '',
                  customerId: customer.uid,
                  customerName: customer.fullName,
                  customerPhone: phoneNumber,
                  customerAddress: customer.address,
                  items: items,
                  subtotal: subtotal,
                  deliveryFee: deliveryFee,
                  total: total,
                  status: paymentMethod == 'cash' ? 'confirmed' : 'pending',
                  paymentMethod: paymentMethod,
                  paymentStatus: 'pending',
                  gcashReceiptUrl: _gcashReceiptUrl,
                  deliveryOption: deliveryOption,
                  deliveryAddress: deliveryOption == 'delivery' 
                      ? (_selectedAddress?.address ?? addressController.text.trim()) 
                      : null,
                  pickupAddress: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.getFormattedAddress()
                      : null,
                  pickupMapLink: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.mapLink
                      : null,
                  // Structured pickup data
                  pickupName: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.name
                      : null,
                  pickupStreet: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.street
                      : null,
                  pickupSitio: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.sitio
                      : null,
                  pickupBarangay: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.barangay
                      : null,
                  pickupCity: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.city
                      : null,
                  pickupProvince: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.province
                      : null,
                  pickupLandmark: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.landmark
                      : null,
                  pickupInstructions: deliveryOption == 'pickup' && _activePickupAddress != null 
                      ? _activePickupAddress!.instructions
                      : null,
                  orderDate: DateTime.now(),
                  deliveryDate: null,
                  deliveryNotes: notesController.text.trim(),
                  farmerId: '',
                  farmerName: '',
                  trackingNumber: null,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                print('🛒 Order object created, calling placeOrder...');
                print('🛒 Order pickup data saved:');
                print('  - pickupName: ${order.pickupName}');
                print('  - pickupLandmark: ${order.pickupLandmark}');
                print('  - pickupInstructions: ${order.pickupInstructions}');
                print('  - pickupMapLink: ${order.pickupMapLink}');
                print('🛒 Customer still authenticated: ${auth.currentCustomer != null}');
                
                // Check account status immediately before placing order
                final isAccountActive = await auth.checkAccountStatusImmediately();
                if (!isAccountActive) {
                  // Account was deactivated - the checkAccountStatusImmediately method
                  // already handles deactivation, so we just need to stop here
                  if (mounted) {
                    Navigator.of(context).pop(); // Close any dialogs/modals
                  }
                  return; // Exit early - user will be redirected to login by auth provider
                }
                
                // Temporarily disable account status monitoring during order placement
                auth.temporarilyDisableMonitoring();

                final ok = await Provider.of<CustomerProvider>(context, listen: false).placeOrder(order);
                
                // Re-enable account status monitoring after order placement
                auth.reEnableMonitoring();
                
                print('🛒 placeOrder completed. Result: $ok');
                print('🛒 Customer still authenticated after placeOrder: ${auth.currentCustomer != null}');
                
                if (ok) {
                  // Refresh customer data to update totalOrders and totalSpent in the dashboard
                  await auth.refreshCustomerData();
                  print('🛒 Customer data refreshed');
                  
                  // Refresh notifications to show the order placed notification
                  if (context.mounted) {
                    try {
                      final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
                      await notificationProvider.loadNotifications(auth.currentCustomer!.uid);
                      print('🔔 Notifications refreshed after order placement');
                    } catch (e) {
                      print('⚠️ Error refreshing notifications: $e');
                    }
                  }
                  
                  print('🛒 Order successful, clearing cart...');
                  // Clear only what was used
                  final prov = Provider.of<CustomerProvider>(context, listen: false);
                  if (buyNow.isNotEmpty) {
                    prov.clearBuyNow();
                  } else {
                    prov.clearCart();
                  }
                  
                  print('🛒 Cart cleared, checking if context is mounted...');
                  if (context.mounted) {
                    print('🛒 Context mounted, showing success message...');
                    final now = DateTime.now();
                    final hour = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
                    final amPm = now.hour < 12 ? 'AM' : 'PM';
                    final formattedDateTime = '${now.day}/${now.month}/${now.year} at $hour:${now.minute.toString().padLeft(2, '0')} $amPm';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Order placed successfully on $formattedDateTime'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    print('🛒 Navigating back to home...');
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else {
                    print('❌ Context not mounted after order placement');
                  }
                } else {
                  print('❌ Order placement failed');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to place order'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } : null,
              icon: const Icon(Icons.check_circle),
              label: const Text('Place Order'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(DeliveryAddress address, bool isFirst) {
    final isSelected = _selectedAddress?.id == address.id;
    
    return Container(
      margin: EdgeInsets.only(bottom: isFirst ? 0 : 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[50] : Colors.white,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        border: Border.all(
          color: isSelected ? Colors.blue[300]! : Colors.grey[200]!,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedAddress = address;
          });
          _calculateDeliveryFee();
        },
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        child: Padding(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
          child: Row(
            children: [
              Container(
                width: Responsive.getWidth(context, mobile: 44),
                height: Responsive.getHeight(context, mobile: 44),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue[100] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 22)),
                ),
                child: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? Colors.blue[600] : Colors.grey[400],
                  size: Responsive.getIconSize(context, mobile: 22),
                ),
              ),
              SizedBox(width: Responsive.getWidth(context, mobile: 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          address.label,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.blue[800] : Colors.grey[800],
                            fontSize: Responsive.getFontSize(context, mobile: 15),
                          ),
                        ),
                        if (address.isDefault) ...[
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8), vertical: Responsive.getSpacing(context, mobile: 3)),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                            ),
                            child: Text(
                              'Default',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                                fontSize: Responsive.getFontSize(context, mobile: 11),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                    Text(
                      address.address,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                        fontSize: Responsive.getFontSize(context, mobile: 13),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (address.phoneNumber != null && address.phoneNumber!.isNotEmpty) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                      Row(
                        children: [
                          Icon(Icons.phone, color: Colors.grey[500], size: Responsive.getIconSize(context, mobile: 14)),
                          SizedBox(width: Responsive.getWidth(context, mobile: 6)),
                          Text(
                            address.phoneNumber!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                              fontSize: Responsive.getFontSize(context, mobile: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditAddressDialog(address);
                  } else if (value == 'delete') {
                    _showDeleteAddressDialog(address);
                  } else if (value == 'set_default') {
                    _setAsDefaultAddress(address);
                  }
                },
                itemBuilder: (context) {
                  final menuItems = <PopupMenuItem<String>>[];
                  
                  menuItems.add(
                    PopupMenuItem(
                      value: 'set_default',
                      child: Row(
                        children: [
                          Icon(Icons.star, size: Responsive.getIconSize(context, mobile: 16)),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          const Text('Set as Default'),
                        ],
                      ),
                    ),
                  );
                  
                  menuItems.add(
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: Responsive.getIconSize(context, mobile: 16)),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          const Text('Edit'),
                        ],
                      ),
                    ),
                  );
                  
                  // Only show delete option if it's not a Home address
                  if (address.label != 'Home') {
                    menuItems.add(
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: Responsive.getIconSize(context, mobile: 16), color: Colors.red),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            const Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  return menuItems;
                },
                child: Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                  ),
                  child: Icon(
                    Icons.more_vert,
                    color: Colors.grey[500],
                    size: Responsive.getIconSize(context, mobile: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddAddressDialog() {
    final labelController = TextEditingController();
    final streetController = TextEditingController();
    final sitioController = TextEditingController();
    final cityController = TextEditingController(text: 'Ormoc');
    final provinceController = TextEditingController(text: 'Leyte');
    final phoneController = TextEditingController();
    // Pre-fill phone with customer's current phone number if available
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentCustomer?.phoneNumber != null && auth.currentCustomer!.phoneNumber.isNotEmpty) {
      phoneController.text = auth.currentCustomer!.phoneNumber;
    }
    String? selectedBarangay;
    bool isDefault = false;
    bool isValidatingPhone = false;
    String? phoneValidationError;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16))),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 400, 
              maxHeight: 600,
              minHeight: 400,
            ),
            padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 10)),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                      ),
                      child: Icon(Icons.add_location, color: Colors.blue[600], size: Responsive.getIconSize(context, mobile: 22)),
                    ),
                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                    Expanded(
                      child: Text(
                        'Add New Address',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                
                // Form Fields
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: labelController,
                          decoration: InputDecoration(
                            labelText: 'Address Label',
                            hintText: 'e.g., Home, Office, Mom\'s House',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            ),
                            prefixIcon: const Icon(Icons.label_outline),
                            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 16)),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter an address label';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        TextFormField(
                          controller: streetController,
                          decoration: InputDecoration(
                            labelText: 'Street (Optional)',
                            hintText: 'Enter street name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            ),
                            prefixIcon: const Icon(Icons.streetview),
                            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 16)),
                          ),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        TextFormField(
                          controller: sitioController,
                          decoration: InputDecoration(
                            labelText: 'Sitio (Optional)',
                            hintText: 'Enter your sitio',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            ),
                            prefixIcon: const Icon(Icons.location_on),
                            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 16)),
                          ),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        SearchableBarangayDropdown(
                          value: selectedBarangay,
                          labelText: 'Barangay *',
                          hintText: 'Select your barangay',
                          prefixIcon: Icons.location_city,
                          onChanged: (value) {
                            setState(() {
                              selectedBarangay = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please select your barangay';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        TextFormField(
                          controller: cityController,
                          decoration: InputDecoration(
                            labelText: 'City',
                            hintText: 'Ormoc',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            ),
                            prefixIcon: const Icon(Icons.location_city),
                            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 16)),
                          ),
                          readOnly: true,
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        TextFormField(
                          controller: provinceController,
                          decoration: InputDecoration(
                            labelText: 'Province',
                            hintText: 'Leyte',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            ),
                            prefixIcon: const Icon(Icons.map),
                            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 16)),
                          ),
                          readOnly: true,
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'Enter 11-digit phone number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            ),
                            prefixIcon: const Icon(Icons.phone),
                            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 16)),
                            errorText: phoneValidationError,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            // Clear error when user types
                            if (phoneValidationError != null) {
                              setState(() {
                                phoneValidationError = null;
                              });
                            }
                          },
                        ),
                        if (isValidatingPhone)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Checking availability...',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                        Container(
                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: isDefault,
                                onChanged: (value) {
                                  setState(() {
                                    isDefault = value ?? false;
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Set as default address',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                                    Text(
                                      'This address will be selected by default for future orders',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[600],
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                
                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 12)),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                      ElevatedButton(
                        onPressed: isValidatingPhone ? null : () async {
                        // Validate required fields
                        if (labelController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter an address label'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        
                        // Prevent duplicate "Home" label
                        final label = labelController.text.trim();
                        if (label.toLowerCase() == 'home') {
                          final provider = Provider.of<CustomerProvider>(context, listen: false);
                          final hasHomeAddress = provider.deliveryAddresses.any((addr) => addr.label.toLowerCase() == 'home');
                          if (hasHomeAddress) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('A "Home" address already exists. Only one Home address is allowed and it is connected to your customer account.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                        }
                        
                        if (selectedBarangay == null || selectedBarangay!.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select your barangay'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        
                        // Validate phone number if provided
                        final phoneInput = phoneController.text.trim();
                        String? normalizedPhone;
                        if (phoneInput.isNotEmpty) {
                          // Remove any non-digit characters for validation
                          normalizedPhone = phoneInput.replaceAll(RegExp(r'[^\d]'), '');
                          
                          if (normalizedPhone.length != 11) {
                            setState(() {
                              phoneValidationError = 'Phone number must be exactly 11 digits';
                            });
                            return;
                          }
                          
                          // Check availability
                          setState(() {
                            isValidatingPhone = true;
                            phoneValidationError = null;
                          });
                          
                          try {
                            final auth = Provider.of<AuthProvider>(context, listen: false);
                            final isAvailable = await auth.checkPhoneAvailability(normalizedPhone);
                            
                            if (!isAvailable) {
                              setState(() {
                                isValidatingPhone = false;
                                phoneValidationError = 'This phone number is already in use by another account';
                              });
                              return;
                            }
                            
                            // Phone is available, continue with save
                            setState(() {
                              isValidatingPhone = false;
                            });
                          } catch (e) {
                            setState(() {
                              isValidatingPhone = false;
                              phoneValidationError = 'Failed to check availability. Please try again.';
                            });
                            return;
                          }
                        }
                        
                        // Construct complete address (sitio and street are optional)
                        final streetPart = streetController.text.trim().isNotEmpty ? '${streetController.text.trim()}, ' : '';
                        final sitioPart = sitioController.text.trim().isNotEmpty ? '${sitioController.text.trim()}, ' : '';
                        final completeAddress = '${streetPart}${sitioPart}$selectedBarangay, ${cityController.text.trim()}, ${provinceController.text.trim()}';
                        
                        final auth = Provider.of<AuthProvider>(context, listen: false);
                        final provider = Provider.of<CustomerProvider>(context, listen: false);
                        
                        final success = await provider.saveDeliveryAddress(
                          customerId: auth.currentCustomer!.uid,
                          address: completeAddress,
                          label: label,
                          phoneNumber: normalizedPhone,
                          isDefault: isDefault || provider.deliveryAddresses.isEmpty,
                        );
                        
                        if (success && context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Address "${label}" added successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 12)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                          ),
                        ),
                        child: const Text(
                          'Add Address',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditAddressDialog(DeliveryAddress address) {
    final labelController = TextEditingController(text: address.label);
    final phoneController = TextEditingController(text: address.phoneNumber ?? '');
    bool isValidatingPhone = false;
    String? phoneValidationError;
    
    // For Home address, use customer profile data instead of parsing address string
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isHomeAddress = address.label.toLowerCase() == 'home';
    final customer = auth.currentCustomer;
    
    String street = '';
    String sitio = '';
    String barangay = '';
    String city = 'Ormoc';
    String province = 'Leyte';
    
    if (isHomeAddress && customer != null) {
      // Use customer profile data for Home address
      street = customer.street;
      sitio = customer.sitio;
      barangay = customer.barangay;
      city = customer.city.isNotEmpty ? customer.city : 'Ormoc';
      province = customer.state.isNotEmpty ? customer.state : 'Leyte';
    } else {
      // Parse existing address to extract components for other addresses
      // Address format: "Street, Sitio, Barangay, City, State ZipCode"
      final addressParts = address.address.split(',').map((p) => p.trim()).toList();
      
      if (addressParts.isNotEmpty) {
        // Handle zipcode which might be attached to state/province (e.g., "Leyte 6541")
        String lastPart = addressParts.isNotEmpty ? addressParts[addressParts.length - 1] : '';
        String statePart = '';
        String zipCodePart = '';
        
        // Check if last part contains zipcode (numbers at the end)
        final zipMatch = RegExp(r'(.+?)\s+(\d+)$').firstMatch(lastPart);
        if (zipMatch != null) {
          statePart = zipMatch.group(1)!.trim();
          zipCodePart = zipMatch.group(2)!;
        } else {
          statePart = lastPart;
        }
        
        if (addressParts.length >= 3) {
          // Format: "Street, Sitio, Barangay, City, State ZipCode" or "Sitio, Barangay, City, State ZipCode"
          if (addressParts.length >= 5) {
            // Has street: "Street, Sitio, Barangay, City, State ZipCode"
            street = addressParts[0];
            sitio = addressParts[1];
            barangay = addressParts[2];
            city = addressParts[3];
            province = statePart;
          } else if (addressParts.length >= 4) {
            // No street: "Sitio, Barangay, City, State ZipCode"
            sitio = addressParts[0];
            barangay = addressParts[1];
            city = addressParts[2];
            province = statePart;
          } else {
            // Minimal: "Sitio, Barangay, City"
            sitio = addressParts[0];
            barangay = addressParts[1];
            city = addressParts[2];
            province = statePart.isNotEmpty ? statePart : 'Leyte';
          }
        } else {
          // Fallback: use the whole address as sitio
          sitio = address.address;
        }
      }
    }
    
    final streetController = TextEditingController(text: street);
    final sitioController = TextEditingController(text: sitio);
    final cityController = TextEditingController(text: city);
    final provinceController = TextEditingController(text: province);
    String? selectedBarangay = barangay.isNotEmpty ? barangay : null;
    bool isDefault = address.isDefault;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: labelController,
                  decoration: InputDecoration(
                    labelText: 'Address Label',
                    border: const OutlineInputBorder(),
                    helperText: address.label.toLowerCase() == 'home' 
                        ? 'Home address label cannot be changed (connected to customer account)'
                        : null,
                  ),
                  enabled: address.label.toLowerCase() != 'home', // Disable editing Home label
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an address label';
                    }
                    return null;
                  },
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextFormField(
                  controller: streetController,
                  decoration: const InputDecoration(
                    labelText: 'Street (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextFormField(
                  controller: sitioController,
                  decoration: const InputDecoration(
                    labelText: 'Sitio (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                SearchableBarangayDropdown(
                  value: selectedBarangay,
                  labelText: 'Barangay *',
                  hintText: 'Select your barangay',
                  onChanged: (value) {
                    setState(() {
                      selectedBarangay = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please select your barangay';
                    }
                    return null;
                  },
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextFormField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextFormField(
                  controller: provinceController,
                  decoration: const InputDecoration(
                    labelText: 'Province',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'Enter 11-digit phone number',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.phone),
                    errorText: phoneValidationError,
                    counterText: '',
                  ),
                  onChanged: (value) {
                    // Clear error when user types
                    if (phoneValidationError != null) {
                      setState(() {
                        phoneValidationError = null;
                      });
                    }
                  },
                ),
                if (isValidatingPhone)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Checking availability...',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                Row(
                  children: [
                    Checkbox(
                      value: isDefault,
                      onChanged: (value) {
                        setState(() {
                          isDefault = value ?? false;
                        });
                      },
                    ),
                    const Text('Set as default address'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isValidatingPhone ? null : () async {
                // Validate required fields
                if (labelController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter an address label'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                // Prevent duplicate "Home" label (unless editing the existing Home address)
                final label = labelController.text.trim();
                if (label.toLowerCase() == 'home' && address.label.toLowerCase() != 'home') {
                  final provider = Provider.of<CustomerProvider>(context, listen: false);
                  final hasHomeAddress = provider.deliveryAddresses.any((addr) => addr.label.toLowerCase() == 'home');
                  if (hasHomeAddress) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('A "Home" address already exists. Only one Home address is allowed and it is connected to your customer account.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }
                
                if (selectedBarangay == null || selectedBarangay!.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select your barangay'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                // Determine if this is a home address (needed for phone validation)
                final isHomeAddress = address.label.toLowerCase() == 'home';
                
                // Validate phone number if provided
                final phoneInput = phoneController.text.trim();
                if (phoneInput.isNotEmpty) {
                  // Remove any non-digit characters for validation
                  final digitsOnly = phoneInput.replaceAll(RegExp(r'[^\d]'), '');
                  
                  if (digitsOnly.length != 11) {
                    setState(() {
                      phoneValidationError = 'Phone number must be exactly 11 digits';
                    });
                    return;
                  }
                  
                  // Check availability (exclude current customer if Home address)
                  setState(() {
                    isValidatingPhone = true;
                    phoneValidationError = null;
                  });
                  
                  try {
                    final auth = Provider.of<AuthProvider>(context, listen: false);
                    final currentCustomer = auth.currentCustomer;
                    final excludeCustomerId = (isHomeAddress && currentCustomer != null) ? currentCustomer.uid : null;
                    
                    final isAvailable = await auth.checkPhoneAvailability(
                      digitsOnly,
                      excludeCustomerId: excludeCustomerId,
                    );
                    
                    if (!isAvailable) {
                      setState(() {
                        isValidatingPhone = false;
                        phoneValidationError = 'This phone number is already in use by another account';
                      });
                      return;
                    }
                    
                    // Phone is available, continue with update
                    setState(() {
                      isValidatingPhone = false;
                    });
                  } catch (e) {
                    setState(() {
                      isValidatingPhone = false;
                      phoneValidationError = 'Failed to check availability. Please try again.';
                    });
                    return;
                  }
                }
                
                // Construct complete address (sitio and street are optional)
                final streetPart = streetController.text.trim().isNotEmpty ? '${streetController.text.trim()}, ' : '';
                final sitioPart = sitioController.text.trim().isNotEmpty ? '${sitioController.text.trim()}, ' : '';
                final completeAddress = '${streetPart}${sitioPart}$selectedBarangay, ${cityController.text.trim()}, ${provinceController.text.trim()}';
                
                final provider = Provider.of<CustomerProvider>(context, listen: false);
                final auth = Provider.of<AuthProvider>(context, listen: false);
                
                // Normalize phone number (digits only)
                final normalizedPhone = phoneInput.isNotEmpty 
                    ? phoneInput.replaceAll(RegExp(r'[^\d]'), '')
                    : null;
                
                final success = await provider.updateDeliveryAddress(
                  addressId: address.id,
                  address: completeAddress,
                  label: label,
                  phoneNumber: normalizedPhone,
                  isDefault: isDefault,
                );
                
                // If updating Home address, also sync to customer profile
                if (success && isHomeAddress && auth.currentCustomer != null) {
                  try {
                    // Parse address components for customer profile update
                    final newStreet = streetController.text.trim();
                    final newSitio = sitioController.text.trim();
                    final newBarangay = selectedBarangay!;
                    final newCity = cityController.text.trim();
                    final newState = provinceController.text.trim();
                    final newPhoneNumber = normalizedPhone ?? '';
                    
                    // Construct address with zipcode if available from customer profile
                    final customer = auth.currentCustomer!;
                    final zipCode = customer.zipCode.isNotEmpty ? customer.zipCode : '';
                    final streetPartForProfile = newStreet.isNotEmpty ? '$newStreet, ' : '';
                    final sitioPartForProfile = newSitio.isNotEmpty ? '$newSitio, ' : '';
                    final zipCodePart = zipCode.isNotEmpty ? ' $zipCode' : '';
                    final completeAddressForProfile = '${streetPartForProfile}${sitioPartForProfile}$newBarangay, $newCity, $newState$zipCodePart';
                    
                    final updatedCustomer = customer.copyWith(
                      address: completeAddressForProfile,
                      street: newStreet,
                      sitio: newSitio,
                      barangay: newBarangay,
                      city: newCity,
                      state: newState,
                      phoneNumber: newPhoneNumber.isNotEmpty ? newPhoneNumber : customer.phoneNumber,
                    );
                    await auth.updateCustomerProfile(updatedCustomer);
                  } catch (e) {
                    print('Error syncing Home address to customer profile: $e');
                    // Continue even if sync fails - address was updated successfully
                  }
                }
                
                if (success && context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Address updated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAddressDialog(DeliveryAddress address) {
    // Prevent deletion of Home address (connected to customer account)
    if (address.label == 'Home') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete Address'),
          content: const Text('The "Home" address cannot be deleted as it is connected to your customer account. You can only edit it from your profile.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Address'),
        content: Text('Are you sure you want to delete "${address.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final provider = Provider.of<CustomerProvider>(context, listen: false);
              
              final success = await provider.deleteDeliveryAddress(address.id);
              
              if (success && context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Address deleted successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _setAsDefaultAddress(DeliveryAddress address) async {
    final provider = Provider.of<CustomerProvider>(context, listen: false);
    
    final success = await provider.updateDeliveryAddress(
      addressId: address.id,
      address: address.address,
      label: address.label,
      isDefault: true,
    );
    
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default address updated!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildOrderingPolicyDropdown() {
    // Get current week's Monday (not next week)
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    final daysFromMonday = weekday - 1; // 0 if Monday, 1 if Tuesday, etc.
    final currentMonday = DateTime(now.year, now.month, now.day - daysFromMonday, 0, 0);
    final currentThursday = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + 3, 20, 0);
    final currentSunday = DateTime(currentMonday.year, currentMonday.month, currentMonday.day + 6, 23, 59);
    
    String _formatDateShort(DateTime d) {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final month = months[d.month - 1];
      return '$month ${d.day}, ${d.year}';
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
        border: Border.all(color: Colors.orange[300]!, width: 1.5),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 6)),
            onTap: () {
              setState(() {
                _isPolicyDropdownExpanded = !_isPolicyDropdownExpanded;
              });
            },
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.orange[100],
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange[700],
                size: Responsive.getIconSize(context, mobile: 24),
              ),
            ),
            title: Text(
              'Ordering & Cancellation Schedule',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: Responsive.getFontSize(context, mobile: 16),
              ),
            ),
            trailing: Icon(
              _isPolicyDropdownExpanded ? Icons.keyboard_arrow_up_outlined : Icons.keyboard_arrow_down_outlined,
              color: Colors.grey[600],
            ),
          ),
          if (_isPolicyDropdownExpanded) Divider(color: Colors.grey.shade200, height: 1),
          if (_isPolicyDropdownExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PolicyTableRow(
                    label: 'Order window',
                    value:
                        'Mon ${_formatDateShort(currentMonday)} · 12:00 AM  —  Thu ${_formatDateShort(currentThursday)} · 8:00 PM',
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                  _PolicyTableRow(
                    label: 'Cut-off',
                    value:
                        'Thu ${_formatDateShort(currentThursday)} · 8:00 PM  —  Sun ${_formatDateShort(currentSunday)} · 11:59 PM',
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                  _PolicyTableRow(
                    label: 'Delivery & pickup',
                    value: 'One-day schedule on weekends (estimate: Saturday or Sunday)',
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 18)),
                  Text(
                    'Policy',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: Responsive.getFontSize(context, mobile: 14),
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                  Text(
                    '• Missed pickups/deliveries are cancelled automatically.\n'
                    '• No rescheduling; GCash payments cannot be refunded once processed.\n'
                    '• Help our farmers reduce waste by receiving orders on time.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                          color: Colors.grey[700],
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _launchGoogleMaps(String? mapLink) async {
    if (mapLink == null || mapLink.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No map link available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final Uri url = Uri.parse(mapLink);
      
      // Check if the URL can be launched
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication, // This will open in the default app (Google Maps)
        );
      } else {
        // Fallback: try to open in browser
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Get Supabase image URL - handles both full URLs and file paths
  String _getSupabaseImageUrl(String imageUrl, String productId) {
    if (imageUrl.isEmpty) return '';
    
    // If it's already a full URL, return as is
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      // Fix duplicate bucket names if present
      if (imageUrl.contains('/product_image/product_image/')) {
        return imageUrl.replaceAll('/product_image/product_image/', '/product_image/');
      }
      return imageUrl;
    }
    
    // If it's a file path, construct Supabase public URL
    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'product_image';
    
    // Remove bucket name if already present
    String filePath = imageUrl;
    if (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1);
    }
    
    // If it doesn't contain product ID, add it
    if (!filePath.startsWith('$productId/') && !filePath.contains('/')) {
      filePath = '$productId/$filePath';
    }
    
    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  String _getSupabaseVideoUrl(String videoUrl, String productId) {
    if (videoUrl.isEmpty) return '';

    if (videoUrl.startsWith('http://') || videoUrl.startsWith('https://')) {
      if (videoUrl.contains('/product_video/product_video/')) {
        return videoUrl.replaceAll('/product_video/product_video/', '/product_video/');
      }
      return videoUrl;
    }

    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'product_video';

    String filePath = videoUrl;
    if (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1);
    }

    if (!filePath.startsWith('$productId/')) {
      filePath = '$productId/$filePath';
    }

    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  // Build combined media list for carousel
  List<_ProductMediaItem> _getProductMedia(Product? product) {
    if (product == null) return [];
    
    final List<_ProductMediaItem> media = [];

    final imageUrls = <String>[];
    if (product.imageUrls.isNotEmpty) {
      imageUrls.addAll(product.imageUrls);
    }
    if (product.imageUrl.isNotEmpty && !imageUrls.contains(product.imageUrl)) {
      imageUrls.add(product.imageUrl);
    }
    media.addAll(
      imageUrls
          .map((url) => _getSupabaseImageUrl(url, product.id))
          .where((url) => url.isNotEmpty)
          .map((url) => _ProductMediaItem(url: url, type: _ProductMediaType.image)),
    );

    final videoUrls = <String>[];
    if (product.videoUrls.isNotEmpty) {
      videoUrls.addAll(product.videoUrls);
    }
    if (product.videoUrl.isNotEmpty && !videoUrls.contains(product.videoUrl)) {
      videoUrls.add(product.videoUrl);
    }
    media.addAll(
      videoUrls
          .map((url) => _getSupabaseVideoUrl(url, product.id))
          .where((url) => url.isNotEmpty)
          .map((url) => _ProductMediaItem(url: url, type: _ProductMediaType.video)),
    );

    return media;
  }

  Widget _buildProductMediaCarousel(Product? product, double size) {
    final mediaItems = _getProductMedia(product);
    
    if (mediaItems.isEmpty) {
      // Show placeholder if no media
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
          child: Icon(
            Icons.image_outlined,
            color: Colors.grey,
            size: size * 0.4,
          ),
        ),
      );
    }

    // Single media item - no carousel needed
    if (mediaItems.length == 1) {
      return _buildMediaItem(mediaItems[0], size);
    }

    // Multiple media items - carousel
    return SizedBox(
      width: size,
      height: size,
      child: PageView.builder(
        itemCount: mediaItems.length,
        itemBuilder: (context, index) {
          return _buildMediaItem(mediaItems[index], size);
        },
      ),
    );
  }

  Widget _buildMediaItem(_ProductMediaItem item, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
        child: item.type == _ProductMediaType.image
            ? Image.network(
                item.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[200],
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: size * 0.4,
                    ),
                  );
                },
              )
            : Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Icon(
                        Icons.play_circle_filled,
                        color: Colors.white70,
                        size: size * 0.5,
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 6), vertical: Responsive.getSpacing(context, mobile: 2)),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 4)),
                        ),
                        child: Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Responsive.getFontSize(context, mobile: 10),
                            fontWeight: FontWeight.bold,
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
}

// Helper classes for media items
enum _ProductMediaType { image, video }

class _ProductMediaItem {
  final String url;
  final _ProductMediaType type;

  _ProductMediaItem({required this.url, required this.type});
}

class _PolicyTableRow extends StatelessWidget {
  final String label;
  final String value;

  const _PolicyTableRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.3),
        1: FlexColumnWidth(0.7),
      },
      children: [
        TableRow(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 8)),
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[800],
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}



