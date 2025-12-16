import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../providers/customer_provider.dart';
import '../../utils/theme.dart';
import '../../utils/order_schedule.dart';
import '../../utils/responsive.dart';
import 'order_detail_screen.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../models/notification.dart';
import '../../providers/notification_provider.dart';
import '../../providers/chat_provider.dart';
import '../chat/chat_screen.dart';
import '../../services/supabase_service.dart';
import 'order_rating_screen.dart';

class OrderPhasesScreen extends StatefulWidget {
  const OrderPhasesScreen({super.key});

  @override
  State<OrderPhasesScreen> createState() => _OrderPhasesScreenState();
}

class _OrderPhasesScreenState extends State<OrderPhasesScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  RealtimeChannel? _ordersChannel;
  Timer? _periodicRefreshTimer;
  String? _expandedOrderId;
  
  List<Order> _allOrders = [];
  bool _isLoading = false;
  bool _hasLoadedInitialData = false; // Track if initial data load has completed
  final Set<String> _sentNotifications = {}; // Track sent notifications to prevent duplicates
  
  // Fallback pickup details for orders that don't have complete pickup data
  final Map<String, Map<String, String>> _orderPickupFallbacks = {};

  final List<OrderPhase> _phases = [
    OrderPhase(
      title: 'All Orders',
      short: 'All',
      status: 'all',
      icon: Icons.all_inbox_rounded,
      color: AppTheme.primaryColor,
    ),
    OrderPhase(
      title: 'Pending Orders',
      short: 'Pending',
      status: 'pending',
      icon: Icons.pending_actions,
      color: AppTheme.warningColor,
    ),
    OrderPhase(
      title: 'Confirmed Orders',
      short: 'Confirmed',
      status: 'confirmed',
      icon: Icons.check_circle,
      color: AppTheme.infoColor,
    ),
    OrderPhase(
      title: 'To Receive',
      short: 'To Receive',
      status: 'to_receive',
      icon: Icons.local_shipping,
      color: AppTheme.primaryColor,
    ),
    OrderPhase(
      title: 'To Rate',
      short: 'To Rate',
      status: 'delivered',
      icon: Icons.star_rate,
      color: AppTheme.successColor,
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Initialize tab controller
    _tabController = TabController(length: _phases.length, vsync: this);

    // Initialize page controller for smooth swiping
    _pageController = PageController();

    // Sync tab controller with page controller
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
    
    // Add listener for order schedule changes
    OrderSchedule.addListener(_onOrderScheduleChanged);
    
    // Load orders with a small delay to ensure auth provider is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _initializeOrderLoading();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Listen for auth changes and reinitialize if needed
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentCustomer != null && _allOrders.isEmpty) {
      // User is logged in but we have no orders, reinitialize
      print('🔄 Auth state changed, reinitializing order loading...');
      _initializeOrderLoading();
    } else if (authProvider.currentCustomer == null && _allOrders.isNotEmpty) {
      // User logged out, clear orders
      print('🧹 User logged out, clearing orders...');
      setState(() {
        _allOrders.clear();
      });
    }
  }
  
  void _initializeOrderLoading() {
    print('🚀 Initializing order loading...');
    
    // CRITICAL: Clear orders first to prevent cross-account contamination
    setState(() {
      _allOrders.clear();
      _hasLoadedInitialData = false; // Reset loading flag
    });
    
    // Load orders from local storage first for immediate display
    _loadOrdersFromLocalStorage();
    
    // Load orders from Supabase (async, will update UI when complete)
    _loadOrdersFromSupabase();
    
    // Set up Supabase real-time listener (filtered by customer_id)
    _setupSupabaseOrdersListener();
    
    // Set up notifications listener
    _setupNotificationsListener();
    
    // Backup periodic refresh every 30 seconds (real-time listener is primary)
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        print('⏰ Periodic refresh triggered');
        _loadOrdersFromSupabase();
        // Note: Status change notifications are handled by _checkForStatusChanges() to prevent duplicates
      } else {
        timer.cancel();
      }
    });
  }
  

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _ordersChannel?.unsubscribe();
    _periodicRefreshTimer?.cancel();
    OrderSchedule.removeListener(_onOrderScheduleChanged);
    super.dispose();
  }

  // Handle order schedule changes
  void _onOrderScheduleChanged() {
    if (mounted) {
      print('🔄 Order schedule changed, refreshing orders...');
      _loadOrdersFromProvider();
    }
  }

  // Clear all data when user logs out
  void _clearAllData() {
    print('🧹 Clearing all order data...');
    setState(() {
      _allOrders.clear();
    });
  }

  // Load orders from local storage for immediate display
  void _loadOrdersFromLocalStorage() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      
      if (authProvider.currentCustomer != null) {
        final currentCustomerId = authProvider.currentCustomer!.uid;
        await customerProvider.loadOrdersFromStorage(currentCustomerId);
        
        if (mounted) {
          // Double-check: Only include orders for the current customer
          final customerOrders = customerProvider.orders.where((order) => 
            order.customerId == currentCustomerId
          ).toList();
          
          setState(() {
            _allOrders = customerOrders;
            // If no orders in local storage, mark as loaded so we show "No orders" immediately
            // instead of waiting for Supabase query (which will update if orders exist)
            if (customerOrders.isEmpty) {
              _hasLoadedInitialData = true;
            }
          });
          print('📦 Loaded ${_allOrders.length} orders from local storage for customer: $currentCustomerId');
          
          // Resolve pickup details for pickup orders (only if there are orders)
          if (customerOrders.isNotEmpty) {
            for (final order in customerOrders) {
              if (order.deliveryOption.toLowerCase() == 'pickup') {
                _resolvePickupDetailsForOrder(order);
              }
            }
          }
        }
      } else {
        // No customer - mark as loaded
        if (mounted) {
          setState(() {
            _hasLoadedInitialData = true;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading orders from local storage: $e');
      // Mark as loaded even on error so UI doesn't hang
      if (mounted) {
        setState(() {
          _hasLoadedInitialData = true;
        });
      }
    }
  }

  Future<void> _loadOrdersFromSupabase() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentCustomer == null) {
      if (mounted) {
        setState(() {
          _hasLoadedInitialData = true;
        });
      }
      return;
    }
    
    try {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final customerId = authProvider.currentCustomer!.uid;
      
      print('📦 Loading orders from Supabase for customer: $customerId');
      
      final previousOrders = List<Order>.from(_allOrders);
      
      // Use customer provider's loadOrders which handles Supabase loading
      await customerProvider.loadOrders(customerId);
      
      // Check and update order statuses based on schedule (only if there are orders)
      if (customerProvider.orders.isNotEmpty) {
        await customerProvider.checkAndUpdateOrderStatuses();
      }
      
      if (mounted) {
        // Get orders from provider (already filtered by customer)
        final customerOrders = customerProvider.orders.where((order) => 
          order.customerId == customerId
        ).toList();
        
        // Sort orders by creation date (newest first)
        customerOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // Update orders list
        setState(() {
          _allOrders = customerOrders;
          _hasLoadedInitialData = true; // Mark as loaded
        });
        
        // Resolve pickup details for pickup orders (only if there are orders)
        if (customerOrders.isNotEmpty) {
          for (final order in customerOrders) {
            if (order.deliveryOption.toLowerCase() == 'pickup') {
              _resolvePickupDetailsForOrder(order);
            }
          }
          
          // Save updated orders to local storage
          await customerProvider.saveOrdersToStorage(customerId);
          
          // Check for status changes with delay to ensure UI is ready
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _checkForStatusChanges(previousOrders);
            }
          });
        } else {
          // No orders - mark as loaded immediately
          await customerProvider.saveOrdersToStorage(customerId);
        }
      }
    } catch (e) {
      print('❌ Error loading orders from Supabase: $e');
      if (mounted) {
        setState(() {
          _hasLoadedInitialData = true; // Mark as loaded even on error
        });
      }
    }
  }

  void _setupSupabaseOrdersListener() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.currentCustomer == null) return;
    
    try {
      final supabase = SupabaseService.client;
      final customerId = authProvider.currentCustomer!.uid;
      
      print('🔗 Setting up Supabase real-time listener for customer: $customerId');
      
      // Subscribe to orders table changes filtered by customer_id
      _ordersChannel = supabase
          .channel('orders_$customerId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: customerId,
            ),
            callback: (payload) {
              if (mounted) {
                print('📡 Supabase real-time update received: ${payload.eventType}');
                // Reload orders when changes occur
                _loadOrdersFromSupabase();
              }
            },
          )
          .subscribe();
      
      print('✅ Supabase real-time listener subscribed');
    } catch (e) {
      print('❌ Error setting up Supabase real-time listener: $e');
      // Fallback to periodic refresh if real-time fails
    }
  }

  void _setupOrdersListener() {
    // Legacy Firebase listener - replaced by Supabase
    // This method is no longer used - orders are loaded via _loadOrdersFromSupabase()
    // and real-time updates are handled by _setupSupabaseOrdersListener()
  }

  void _loadOrdersFromProvider() async {
    try {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      if (authProvider.currentCustomer != null) {
        final previousOrders = List<Order>.from(_allOrders);
        final currentOrderCount = _allOrders.length;
        
        await customerProvider.loadOrders(authProvider.currentCustomer!.uid);
        
        // Check and update order statuses based on schedule
        await customerProvider.checkAndUpdateOrderStatuses();
        
        if (mounted) {
          // Double-check: Only include orders for the current customer
          final currentCustomerId = authProvider.currentCustomer!.uid;
          final customerOrders = customerProvider.orders.where((order) => 
            order.customerId == currentCustomerId
          ).toList();
          
          setState(() {
            _allOrders = customerOrders;
          });
          
          // Save orders to local storage
          await customerProvider.saveOrdersToStorage(authProvider.currentCustomer!.uid);
          
          // Check if any pending order became confirmed and auto-navigate to confirmed tab
          _checkForStatusChanges(previousOrders);
          
          // Note: Status change notifications are handled by _checkForStatusChanges() to prevent duplicates
          
          // Debug: Check if orders were lost
          if (currentOrderCount > 0 && _allOrders.length < currentOrderCount) {
            print('⚠️ WARNING: Orders count decreased from $currentOrderCount to ${_allOrders.length}');
            print('⚠️ Previous orders: ${previousOrders.map((o) => o.id).toList()}');
            print('⚠️ Current orders: ${_allOrders.map((o) => o.id).toList()}');
          }
        }
      }
    } catch (e) {
      // Silent error handling
    }
  }
  
  void _checkForStatusChanges(List<Order> previousOrders) {
    
    // Check if any order changed from pending to confirmed
    for (final currentOrder in _allOrders) {
      final previousOrder = previousOrders.firstWhere(
        (order) => order.id == currentOrder.id,
        orElse: () => Order(
          id: '',
          customerId: '',
          customerName: '',
          customerPhone: '',
          customerAddress: '',
          items: [],
          subtotal: 0,
          deliveryFee: 0,
          total: 0,
          status: '',
          paymentMethod: '',
          paymentStatus: '',
          deliveryOption: '',
          orderDate: DateTime.now(),
          farmerId: '',
          farmerName: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          totalOrders: 0,
          totalSpent: 0,
        ),
      );
      
      print('🔍 Order ${currentOrder.id}: ${previousOrder.status} → ${currentOrder.status}');
      
      // If order status changed from pending to confirmed, navigate to confirmed tab
      if (previousOrder.status == 'pending' && currentOrder.status == 'confirmed') {
        final notificationKey = 'confirmed_${currentOrder.id}';
        if (!_sentNotifications.contains(notificationKey)) {
          print('✅ Status change detected: pending → confirmed for order ${currentOrder.id}');
          
          // Mark notification as sent
          _sentNotifications.add(notificationKey);
          
          // Create and send notification
          _sendOrderConfirmationNotification(currentOrder);
          
          // Navigate to confirmed tab immediately
          final confirmedIndex = _phases.indexWhere((phase) => phase.status == 'confirmed');
          if (confirmedIndex != -1 && _pageController.hasClients) {
            _tabController.animateTo(confirmedIndex);
            _pageController.animateToPage(
              confirmedIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
          break; // Only navigate to the first confirmed order
        } else {
          print('⚠️ Confirmation notification already sent for order ${currentOrder.id}');
        }
      }
      
      // remove packed status handling
      
      // If order status changed to out_for_delivery, send notification
      // CRITICAL: Only send notification if this is an actual status change (previous order exists and had different status)
      // Don't send notification if previousOrder.id is empty (newly loaded order, not a status change)
      if (previousOrder.id.isNotEmpty) {
        final currentStatus = currentOrder.status.toLowerCase().trim();
        final previousStatus = previousOrder.status.toLowerCase().trim();
        
        // Simple check for out for delivery status
        final isOutForDelivery = currentStatus.contains('out') && currentStatus.contains('delivery');
        final wasNotOutForDelivery = !(previousStatus.contains('out') && previousStatus.contains('delivery'));
        
        if (wasNotOutForDelivery && isOutForDelivery) {
          final notificationKey = 'out_for_delivery_${currentOrder.id}';
          if (!_sentNotifications.contains(notificationKey)) {
            print('✅ Status change detected: ${previousOrder.status} → ${currentOrder.status} for order ${currentOrder.id}');
            
            // Mark notification as sent
            _sentNotifications.add(notificationKey);
            
            // Create and send notification (will check Supabase for duplicates before sending)
            _sendOrderOutForDeliveryNotification(currentOrder);
            break; // Only send notification for the first out_for_delivery order
          }
        }
      } else {
        // Previous order doesn't exist (newly loaded order) - don't send notification
        // The notification was already sent when the status actually changed
        print('ℹ️ Order ${currentOrder.id} is newly loaded (not a status change), skipping notification');
      }
      
      // Check if pickup order became ready for pickup (readyForPickup changed from false to true)
      if (previousOrder.id.isNotEmpty) {
        final isPickupOrder = currentOrder.deliveryOption.toLowerCase() == 'pickup';
        final wasNotReadyForPickup = previousOrder.readyForPickup != true;
        final isNowReadyForPickup = currentOrder.readyForPickup == true;
        
        if (isPickupOrder && wasNotReadyForPickup && isNowReadyForPickup) {
          final notificationKey = 'pickup_ready_${currentOrder.id}';
          if (!_sentNotifications.contains(notificationKey)) {
            print('✅ Pickup ready change detected for order ${currentOrder.id}');
            
            // Mark notification as sent
            _sentNotifications.add(notificationKey);
            
            // Send pickup ready notification
            _sendPickupReadyNotification(currentOrder);
            break; // Only send notification for the first pickup ready order
          }
        }
      }
      
      // If order status changed to delivered, picked_up, or failed_pickup, navigate to "To Rate" tab
      if ((previousOrder.status != 'delivered' && currentOrder.status == 'delivered') ||
          (previousOrder.status != 'picked_up' && currentOrder.status == 'picked_up') ||
          (previousOrder.status != 'failed_pickup' && currentOrder.status == 'failed_pickup')) {
        final notificationKey = 'completed_${currentOrder.id}';
        if (!_sentNotifications.contains(notificationKey)) {
          print('✅ Status change detected: ${previousOrder.status} → ${currentOrder.status} for order ${currentOrder.id}');
          
          // Mark notification as sent
          _sentNotifications.add(notificationKey);
          
          // Navigate to "To Rate" tab (delivered status includes both delivered and picked_up orders)
          final toRateIndex = _phases.indexWhere((phase) => phase.status == 'delivered');
          if (toRateIndex != -1 && _pageController.hasClients) {
            _tabController.animateTo(toRateIndex);
            _pageController.animateToPage(
              toRateIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
          break; // Only navigate to the first completed order
        } else {
          print('⚠️ Completion navigation already handled for order ${currentOrder.id}');
        }
      }
    }
  }
  
  void _setupNotificationsListener() {
    // Notifications are handled by NotificationProvider
    // This method is kept for compatibility but doesn't need to do anything
    // Real-time notifications are handled by the notification provider's listener
  }
  
  
  void _sendOrderConfirmationNotification(Order order) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.currentCustomer != null) {
        // Format the order total
        final formattedTotal = '\u20B1${order.total.toStringAsFixed(2)}';
        
        // Get last 8 characters of order ID for display
        final orderDisplayId = order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id;
        
        // Create notification
        final notification = CustomerNotification(
          id: 'order_confirmed_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Order Confirmed! 🎉',
          message: 'Your order #${orderDisplayId.toUpperCase()} with a total of $formattedTotal has been confirmed and is being prepared for you!',
          type: 'order_confirmed',
          timestamp: DateTime.now(),
          isRead: false,
          orderId: order.id,
        );
        
        // Send notification to database
        await NotificationService.sendNotification(
          authProvider.currentCustomer!.uid,
          notification,
        );
      }
    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  void _sendOrderPackedNotification(Order order) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.currentCustomer != null) {
        // Format the order total
        final formattedTotal = '\u20B1${order.total.toStringAsFixed(2)}';
        
        // Get last 8 characters of order ID for display
        final orderDisplayId = order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id;
        
        // Create notification
        final notification = CustomerNotification(
          id: 'order_packed_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Order Being Packed! 📦',
          message: 'Your order #${orderDisplayId.toUpperCase()} with a total of $formattedTotal is now being packed and will be ready for delivery soon!',
          type: 'order_packed',
          timestamp: DateTime.now(),
          isRead: false,
          orderId: order.id,
        );
        
        // Send notification to database
        await NotificationService.sendNotification(
          authProvider.currentCustomer!.uid,
          notification,
        );
      }
    } catch (e) {
      print('❌ Error sending packed notification: $e');
    }
  }

  Future<void> _sendPickupReadyNotification(Order order) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.currentCustomer?.uid;
      
      if (customerId == null) {
        print('⚠️ No customer ID available, skipping pickup ready notification');
        return;
      }
      
      // Check if notification already exists in Supabase to prevent duplicates
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        
        final existingResponse = await supabase
            .from('customer_notifications')
            .select('id')
            .eq('customer_id', customerId)
            .eq('order_id', order.id)
            .eq('type', 'order_ready_to_pickup')
            .limit(1);
        
        if (existingResponse != null && existingResponse is List && existingResponse.isNotEmpty) {
          print('📭 Pickup ready notification already exists in Supabase for order ${order.id}, skipping duplicate');
          // Mark as sent in memory to prevent duplicate checks
          final notificationKey = 'pickup_ready_${order.id}';
          _sentNotifications.add(notificationKey);
          return; // Don't send duplicate notification
        }
      } catch (e) {
        print('⚠️ Error checking Supabase for existing notification: $e');
        // Continue to send notification if check fails (better to show duplicate than miss notification)
      }
      
      // Format the order total
      final formattedTotal = '\u20B1${order.total.toStringAsFixed(2)}';
      
      // Get last 8 characters of order ID for display
      final orderDisplayId = order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id;
      
      // Create notification
      final notification = CustomerNotification(
        id: 'order_pickup_ready_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Order Ready To PickUp!',
        message: 'Your order #${orderDisplayId.toUpperCase()} is ready for pickup! Total: $formattedTotal',
        type: 'order_ready_to_pickup',
        timestamp: DateTime.now(),
        isRead: false,
        orderId: order.id,
      );
      
      // Send notification to database
      await NotificationService.sendNotification(
        customerId,
        notification,
      );
      
      print('✅ Pickup ready notification sent for order ${order.id}');
    } catch (e) {
      print('❌ Error sending pickup ready notification: $e');
    }
  }

  void _sendOrderOutForDeliveryNotification(Order order) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.currentCustomer != null) {
        final customerId = authProvider.currentCustomer!.uid;
        
        // CRITICAL: Check if notification already exists in Supabase before sending
        // This prevents duplicate notifications when app is reopened
        try {
          await SupabaseService.initialize();
          final supabase = SupabaseService.client;
          
          final existingResponse = await supabase
              .from('customer_notifications')
              .select('id')
              .eq('customer_id', customerId)
              .eq('order_id', order.id)
              .eq('type', 'order_out_for_delivery')
              .limit(1);
          
          if (existingResponse != null && existingResponse is List && existingResponse.isNotEmpty) {
            print('📭 Out for delivery notification already exists in Supabase for order ${order.id}, skipping duplicate');
            // Mark as sent in memory to prevent duplicate checks
            final notificationKey = 'out_for_delivery_${order.id}';
            _sentNotifications.add(notificationKey);
            return; // Don't send duplicate notification
          }
        } catch (e) {
          print('⚠️ Error checking Supabase for existing notification: $e');
          // Continue to send notification if check fails (better to show duplicate than miss notification)
        }
        
        // Format the order total
        final formattedTotal = '\u20B1${order.total.toStringAsFixed(2)}';
        
        // Get last 8 characters of order ID for display
        final orderDisplayId = order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id;
        
        // Create notification
        final notification = CustomerNotification(
          id: 'order_out_for_delivery_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Order Out for Delivery! 🚚',
          message: 'Your order #${orderDisplayId.toUpperCase()} with a total of $formattedTotal is now out for delivery and will arrive soon! Please prepare the payment amount.',
          type: 'order_out_for_delivery',
          timestamp: DateTime.now(),
          isRead: false,
          orderId: order.id,
        );
        
        // Send notification to database
        await NotificationService.sendNotification(
          customerId,
          notification,
        );
        
        print('✅ Out for delivery notification sent for order ${order.id}');
      }
    } catch (e) {
      print('❌ Error sending out for delivery notification: $e');
    }
  }

  // Check for orders with out_for_delivery status and send notifications
  void _checkForOutForDeliveryNotifications() {
    for (final order in _allOrders) {
      final status = order.status.toLowerCase().trim();
      final isOutForDelivery = status.contains('out') && status.contains('delivery');
      
      if (isOutForDelivery) {
        final notificationKey = 'out_for_delivery_${order.id}';
        if (!_sentNotifications.contains(notificationKey)) {
          print('✅ Found out_for_delivery order ${order.id}, sending notification...');
          _sentNotifications.add(notificationKey);
          _sendOrderOutForDeliveryNotification(order);
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(color: AppTheme.primaryColor, width: 3),
              insets: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16)),
            ),
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: Colors.grey[500],
            tabs: _phases
                .map(
                  (phase) => Builder(
                    builder: (context) => Tab(
                      child: SizedBox(
                        width: Responsive.isTabletOrLarger(context) ? 110 : 90,
                        child: Center(
                          child: Text(
                            phase.short,
                            style: TextStyle(
                              fontSize: Responsive.getFontSize(context, mobile: 13),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _phases.map((phase) => _buildPhaseOrders(phase)).toList(),
      ),
    );
  }

  Widget _buildPhaseOrders(OrderPhase phase) {
    // Filter orders based on phase
    List<Order> phaseOrders = _getOrdersForPhase(phase);
    
    // Check if user is authenticated
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isAuthenticated = authProvider.currentCustomer != null;
    
    // Show loading only if user is authenticated, we haven't received any data yet, AND initial load hasn't completed
    if (isAuthenticated && _allOrders.isEmpty && !_hasLoadedInitialData) {
      return Builder(
        builder: (context) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
              Text(
                'Loading orders...',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
              ),
              SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
              Text(
                'Loading orders from Supabase...',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 12),
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show login prompt if user is not authenticated
    if (!isAuthenticated) {
      return Builder(
        builder: (context) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.login,
                size: Responsive.getImageSize(context, mobile: 64),
                color: Colors.grey[400],
              ),
              SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
              Text(
                'Please log in to view your orders',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 18),
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
              Text(
                'Your orders will appear here after logging in',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 14),
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _loadOrdersFromProvider();
            },
            child: Consumer<CustomerProvider>(
              builder: (context, customerProvider, child) {
                // CRITICAL: Re-filter orders using provider's orders to ensure we have latest data
                // This matches how order detail screen works - always use provider as source of truth
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                final currentCustomerId = authProvider.currentCustomer?.uid ?? '';
                
                final providerOrders = customerProvider.orders.where((order) => 
                  order.customerId == currentCustomerId
                ).toList();
                
                // Re-filter for this phase using provider orders
                final freshPhaseOrders = providerOrders.where((order) {
                  final orderStatus = order.status.toLowerCase();
                  switch (phase.status) {
                    case 'pending':
                      return orderStatus == 'pending';
                    case 'confirmed':
                      return orderStatus == 'confirmed';
                    case 'to_receive':
                      // CRITICAL: Exclude orders that are already picked_up, failed_pickup, or delivered
                      // Check both status and timestamps to prevent glitching
                      final hasPickedUpTimestamp = order.pickedUpAt != null;
                      final hasFailedPickupTimestamp = order.failedPickupAt != null;
                      final isFinalState = orderStatus == 'picked_up' || 
                                          orderStatus == 'failed_pickup' || 
                                          orderStatus == 'delivered' ||
                                          hasPickedUpTimestamp || 
                                          hasFailedPickupTimestamp;
                      
                      // If order is in final state, exclude it from "To Receive"
                      if (isFinalState) {
                        return false;
                      }
                      
                      // Include orders that are ready to be received
                      if (orderStatus == 'to_receive' || orderStatus == 'out_for_delivery') {
                        return true;
                      }
                      // Include pickup orders that are ready for pickup
                      if (orderStatus == 'to_receive' && order.deliveryOption.toLowerCase() == 'pickup' && (order.readyForPickup == true)) {
                        return true;
                      }
                      return false;
                    case 'delivered':
                      // CRITICAL: Include only delivered and picked_up orders (successful completions)
                      // Exclude failed_pickup orders - they should not be in "To Rate" tab
                      // Check both status and timestamps to ensure we catch all final states
                      final hasPickedUpTimestamp = order.pickedUpAt != null;
                      return orderStatus == 'delivered' || 
                             orderStatus == 'picked_up' || 
                             hasPickedUpTimestamp;
                    case 'all':
                      return true;
                    default:
                      return false;
                  }
                }).toList();
                
                // Sort by creation date (newest first)
                freshPhaseOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                
                // Show empty state if no orders
                if (freshPhaseOrders.isEmpty) {
                  return _buildNoOrdersFound(phase);
                }
                
                return ListView.builder(
                  padding: Responsive.getPadding(context),
                  itemCount: freshPhaseOrders.length,
                  itemBuilder: (context, index) {
                    final order = freshPhaseOrders[index];
                    return _buildOrderCard(order);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseHeader(OrderPhase phase) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16)),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
            decoration: BoxDecoration(
              color: phase.color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(phase.icon, color: phase.color, size: Responsive.getIconSize(context, mobile: 20)),
          ),
          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: Responsive.getFontSize(context, mobile: 15)),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 2)),
                Text(
                  '${_getOrdersForPhase(phase).length} active orders',
                  style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12), color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Order> _getOrdersForPhase(OrderPhase phase) {
    if (phase.status == 'all') {
      return _allOrders;
    }
    
    final filteredOrders = _allOrders.where((order) {
      final orderStatus = order.status.toLowerCase();
      
      switch (phase.status) {
        case 'pending':
          return orderStatus == 'pending';
        case 'confirmed':
          return orderStatus == 'confirmed';
        case 'to_receive':
          // CRITICAL: Exclude orders that are already picked_up, failed_pickup, or delivered
          // Check both status and timestamps to prevent glitching
          final hasPickedUpTimestamp = order.pickedUpAt != null;
          final hasFailedPickupTimestamp = order.failedPickupAt != null;
          final isFinalState = orderStatus == 'picked_up' || 
                              orderStatus == 'failed_pickup' || 
                              orderStatus == 'delivered' ||
                              hasPickedUpTimestamp || 
                              hasFailedPickupTimestamp;
          
          // If order is in final state, exclude it from "To Receive"
          if (isFinalState) {
            return false;
          }
          
          // Include all orders that are ready to be received:
          // - Regular delivery orders that are out for delivery or to_receive
          // - Pickup orders that are to_receive (regardless of readyForPickup status)
          // - Pickup orders that are ready for pickup (pickup_ready status)
          if (orderStatus == 'to_receive' || orderStatus == 'out_for_delivery') {
            return true;
          }
          // Include pickup orders that are ready for pickup
          if (orderStatus == 'to_receive' && order.deliveryOption.toLowerCase() == 'pickup' && (order.readyForPickup == true)) {
            return true;
          }
          return false;
        case 'delivered':
          // CRITICAL: Include only delivered and picked_up orders (successful completions)
          // Exclude failed_pickup orders - they should not be in "To Rate" tab
          // Check both status and timestamps to ensure we catch all final states and prevent glitching
          final hasPickedUpTimestamp = order.pickedUpAt != null;
          return orderStatus == 'delivered' || 
                 orderStatus == 'picked_up' || 
                 hasPickedUpTimestamp;
        default:
          return false;
      }
    }).toList();
    
    // Force UI update if orders change
    if (mounted) {
      setState(() {});
    }
    
    return filteredOrders;
  }

  Widget _buildNoOrdersFound(OrderPhase phase) {
    return Builder(
      builder: (context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: Responsive.getImageSize(context, mobile: 120),
              height: Responsive.getImageSize(context, mobile: 120),
              decoration: BoxDecoration(
                gradient: AppTheme.creamGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                phase.icon,
                size: Responsive.getImageSize(context, mobile: 60),
                color: Colors.grey[400],
              ),
            ),
            
            SizedBox(height: Responsive.getSpacing(context, mobile: 24)),
            
            Text(
              'No Orders Found',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 24),
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            
            SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
            
            Text(
              'You don\'t have any orders in the "${phase.title}" phase yet.',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 16),
                color: Colors.grey[500],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            
            SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
            
            Text(
              'Orders will appear here as they progress through different stages.',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 14),
                color: Colors.grey[400],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final isCancelled = order.status.toLowerCase() == 'cancelled';
    final isCancellationRequested = order.cancellationRequested == true;
    final initiatedByStaff = (order.cancellationInitiatedBy ?? 'customer') == 'staff';
    // Check if pickup order is ready for pickup - show as "pickup_ready" status
    // CRITICAL: Don't show "Ready to Pickup" if order is already picked_up or failed_pickup
    final orderStatus = order.status.toLowerCase();
    
    // CRITICAL: Check timestamps to ensure we never show "Ready to Pickup" for completed orders
    // This is a defensive check in case database has inconsistent data
    final hasPickedUpTimestamp = order.pickedUpAt != null;
    final hasFailedPickupTimestamp = order.failedPickupAt != null;
    final isFinalPickupState = orderStatus == 'picked_up' || 
                               orderStatus == 'failed_pickup' ||
                               hasPickedUpTimestamp || 
                               hasFailedPickupTimestamp;
    final isPickupFinal = isFinalPickupState; // For button display logic
    
    // CRITICAL: If order is in final pickup state, ALWAYS use the actual status
    // Never override with "pickup_ready" even if readyForPickup flag is true
    // If timestamps indicate final state but status doesn't, use status from timestamp
    String finalStatus = order.status;
    if (hasPickedUpTimestamp && orderStatus != 'picked_up') {
      finalStatus = 'picked_up';
    } else if (hasFailedPickupTimestamp && orderStatus != 'failed_pickup') {
      finalStatus = 'failed_pickup';
    }
    
    final displayStatus = isFinalPickupState
        ? finalStatus // Use actual status (picked_up or failed_pickup)
        : (isCancelled
            ? 'cancellation_confirmed'
            : (() {
                // Only show pickup_ready if order is NOT in final state AND is actually ready
                if (!isFinalPickupState && 
                    order.deliveryOption.toLowerCase() == 'pickup' && 
                    order.readyForPickup == true && 
                    orderStatus == 'to_receive') {
                  return 'pickup_ready';
                }
                return (isCancellationRequested && !initiatedByStaff) 
                    ? 'request_cancellation_sent' 
                    : order.status;
              }()));
    final isExpanded = false; // Always collapsed - details shown in detail screen
    
    // CRITICAL: Use Consumer to ensure order card rebuilds when provider updates
    // This ensures rating data is always current, matching how delivered orders work
    return Consumer<CustomerProvider>(
      builder: (context, customerProvider, child) {
        // CRITICAL: Always get the latest order from provider to ensure we have current data
        // This matches how delivered orders work - always use provider as source of truth
        // Try multiple ways to get the order to ensure we have the latest data
        Order? providerOrder = customerProvider.getOrderById(order.id);
        if (providerOrder == null) {
          // If not found by ID, try to find in orders list
          try {
            providerOrder = customerProvider.orders.firstWhere(
              (o) => o.id == order.id,
              orElse: () => order,
            );
          } catch (e) {
            providerOrder = order;
          }
        }
        final latestOrder = providerOrder;
        
        // Recalculate all status-related variables using latestOrder to prevent glitching
        final latestIsCancelled = latestOrder.status.toLowerCase() == 'cancelled';
        final latestIsCancellationRequested = latestOrder.cancellationRequested == true;
        final latestInitiatedByStaff = (latestOrder.cancellationInitiatedBy ?? 'customer') == 'staff';
        
        // Recalculate displayStatus using latestOrder to prevent glitching
        final latestOrderStatus = latestOrder.status.toLowerCase();
        final latestHasPickedUpTimestamp = latestOrder.pickedUpAt != null;
        final latestHasFailedPickupTimestamp = latestOrder.failedPickupAt != null;
        final latestIsFinalPickupState = latestOrderStatus == 'picked_up' || 
                                         latestOrderStatus == 'failed_pickup' ||
                                         latestHasPickedUpTimestamp || 
                                         latestHasFailedPickupTimestamp;
        
        String latestFinalStatus = latestOrder.status;
        if (latestHasPickedUpTimestamp && latestOrderStatus != 'picked_up') {
          latestFinalStatus = 'picked_up';
        } else if (latestHasFailedPickupTimestamp && latestOrderStatus != 'failed_pickup') {
          latestFinalStatus = 'failed_pickup';
        }
        
        final latestDisplayStatus = latestIsFinalPickupState
            ? latestFinalStatus
            : (latestIsCancelled
                ? 'cancellation_confirmed'
                : (() {
                    if (!latestIsFinalPickupState && 
                        latestOrder.deliveryOption.toLowerCase() == 'pickup' && 
                        latestOrder.readyForPickup == true && 
                        latestOrderStatus == 'to_receive') {
                      return 'pickup_ready';
                    }
                    return (latestIsCancellationRequested && !latestInitiatedByStaff) 
                        ? 'request_cancellation_sent' 
                        : latestOrder.status;
                  }()));
        
        // CRITICAL: Calculate rating status directly in Consumer scope to ensure it's always fresh
        // This ensures picked_up orders work the same as delivered orders
        final isOrderRated = latestOrder.isRated == true || 
                             latestOrder.orderRating != null || 
                             latestOrder.orderRatedAt != null;
        
        // Determine if order should show rating section (successful delivery/pickup)
        final currentOrderStatus = latestOrderStatus;
        final hasPickedUpTimestamp = latestOrder.pickedUpAt != null;
        final hasFailedTimestamp = latestOrder.failedPickupAt != null;
        String actualStatus = currentOrderStatus;
        if (hasPickedUpTimestamp && currentOrderStatus != 'picked_up') {
          actualStatus = 'picked_up';
        } else if (hasFailedTimestamp && currentOrderStatus != 'failed_pickup') {
          actualStatus = 'failed_pickup';
        }
        if (hasPickedUpTimestamp) {
          actualStatus = 'picked_up';
        }
        final isSuccessfulDelivery = actualStatus == 'delivered' || actualStatus == 'picked_up';
        final isFailed = actualStatus == 'failed' || actualStatus == 'delivery_failed' || actualStatus == 'failed_pickup';
        final shouldShowRatingSection = isSuccessfulDelivery && !isFailed;
        
        return Container(
        margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
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
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OrderDetailScreen(order: latestOrder),
                ),
              );
            },
            child: Padding(
              padding: Responsive.getPadding(context).copyWith(
                left: Responsive.getSpacing(context, mobile: 18),
                right: Responsive.getSpacing(context, mobile: 18),
                top: Responsive.getSpacing(context, mobile: 18),
                bottom: Responsive.getSpacing(context, mobile: 18),
              ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${latestOrder.id.length > 8 ? latestOrder.id.substring(latestOrder.id.length - 8).toUpperCase() : latestOrder.id.toUpperCase()}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: Responsive.getFontSize(context, mobile: 15),
                            ),
                          ),
                          SizedBox(height: Responsive.getSpacing(context, mobile: 6)),
                          Row(
                            children: [
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _OrderChip(
                                    icon: _getStatusIcon(latestDisplayStatus),
                                    label: _getPhaseName(latestDisplayStatus),
                                    color: _getStatusColor(latestDisplayStatus),
                                  ),
                                ),
                              ),
                              // Re-Scheduled indicator (always show if order is rescheduled)
                              if (latestOrder.rescheduledNextWeek == true || latestOrder.rescheduledNextWeek == 1) ...[
                                SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: Responsive.getSpacing(context, mobile: 10),
                                    vertical: Responsive.getSpacing(context, mobile: 6),
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.yellow.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: Responsive.getIconSize(context, mobile: 14),
                                        color: Colors.yellow[800],
                                      ),
                                      SizedBox(width: Responsive.getWidth(context, mobile: 6)),
                                      Text(
                                        'Re-Scheduled',
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 12),
                                          fontWeight: FontWeight.w600,
                                          color: Colors.yellow[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                              Text(
                                '\u20B1${latestOrder.total.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: Responsive.getFontSize(context, mobile: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                Row(
                  children: [
                    _OrderChip(
                      icon: Icons.shopping_bag_outlined,
                      label: '${latestOrder.items.length} items',
                      color: Colors.grey.shade600,
                      subtle: true,
                    ),
                    SizedBox(width: Responsive.getSpacing(context, mobile: 8)),
                    _OrderChip(
                      icon: Icons.calendar_today_outlined,
                      label: _formatDate(latestOrder.orderDate),
                      color: Colors.grey.shade600,
                      subtle: true,
                    ),
                  ],
                ),

                // Order Received button (show when ready for pickup, even when not expanded)
                // CRITICAL: Check status and timestamps FIRST - never show button if already picked_up or failed_pickup
                // Must check both status and timestamps to handle any database inconsistencies
                // Use latestOrder to ensure current state
                if (!latestIsFinalPickupState && 
                    latestOrderStatus == 'to_receive' &&
                    !latestHasPickedUpTimestamp &&
                    !latestHasFailedPickupTimestamp &&
                    latestOrder.deliveryOption.toLowerCase() == 'pickup' && 
                    latestOrder.readyForPickup == true) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _markOrderAsReceived(latestOrder),
                      icon: Icon(Icons.check_circle, size: Responsive.getIconSize(context, mobile: 18)),
                      label: Text(
                        'Order Received',
                        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14), fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        ),
                      ),
                    ),
                  ),
                ],
                
                // Order Received button removed for out_for_delivery orders
                // Delivery rider will confirm delivery/failed delivery, not the customer
                
                // Rating section (show ONLY for successful deliveries/pickups confirmed by rider)
                // CRITICAL: Check rating status FIRST - if rated, always show rated info
                // This works for both delivered and picked_up orders
                if (isOrderRated && shouldShowRatingSection) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  // Display rating details
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade50, Colors.green.shade100],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                      border: Border.all(color: Colors.green.shade300, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green[700], size: Responsive.getIconSize(context, mobile: 24)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Order Rated',
                              style: TextStyle(
                                fontSize: Responsive.getFontSize(context, mobile: 16),
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                        // Order Rating
                        if (latestOrder.orderRating != null) ...[
                          Row(
                            children: [
                              const Text('Order Rating: ', style: TextStyle(fontWeight: FontWeight.w600)),
                              ...List.generate(5, (index) => Icon(
                                index < latestOrder.orderRating! ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: Responsive.getIconSize(context, mobile: 20),
                              )),
                              Text(' (${latestOrder.orderRating}/5)', style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12))),
                            ],
                          ),
                          if (latestOrder.orderComment?.isNotEmpty == true) ...[
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            Text('Comment: ${latestOrder.orderComment}', style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12))),
                          ],
                        ],
                        // Rider or Pickup Experience
                        if (latestOrder.deliveryOption.toLowerCase() == 'delivery' && latestOrder.riderRating != null) ...[
                          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                          const Divider(),
                          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                          Row(
                            children: [
                              const Text('Rider Rating: ', style: TextStyle(fontWeight: FontWeight.w600)),
                              ...List.generate(5, (index) => Icon(
                                index < latestOrder.riderRating! ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: Responsive.getIconSize(context, mobile: 20),
                              )),
                              Text(' (${latestOrder.riderRating}/5)', style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12))),
                            ],
                          ),
                          if (latestOrder.riderComment?.isNotEmpty == true) ...[
                            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                            Text('Comment: ${latestOrder.riderComment}', style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12))),
                          ],
                        ],
                        if (latestOrder.deliveryOption.toLowerCase() == 'pickup' && latestOrder.pickupExperienceComment?.isNotEmpty == true) ...[
                          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                          const Divider(),
                          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                          const Text('Pickup Experience:', style: TextStyle(fontWeight: FontWeight.w600)),
                          SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                          Text(latestOrder.pickupExperienceComment!, style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12))),
                        ],
                        // Media preview
                        if (latestOrder.orderMedia != null && latestOrder.orderMedia!.isNotEmpty) ...[
                          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                          const Divider(),
                          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                          const Text('Media:', style: TextStyle(fontWeight: FontWeight.w600)),
                          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: latestOrder.orderMedia!.take(3).map((url) {
                              final isVideo = url.toLowerCase().contains('.mp4') || 
                                              url.toLowerCase().contains('.mov') ||
                                              url.toLowerCase().contains('.webm');
                              return Container(
                                width: Responsive.getWidth(context, mobile: 60),
                                height: Responsive.getHeight(context, mobile: 60),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                                ),
                                child: isVideo
                                    ? Center(child: Icon(Icons.videocam, size: Responsive.getIconSize(context, mobile: 30)))
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                                        child: Image.network(url, fit: BoxFit.cover),
                                      ),
                              );
                            }).toList(),
                          ),
                          if (latestOrder.orderMedia!.length > 3)
                            Padding(
                              padding: EdgeInsets.only(top: Responsive.getSpacing(context, mobile: 8)),
                              child: Text(
                                '+${latestOrder.orderMedia!.length - 3} more',
                                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 11), color: Colors.grey),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ] else if (!isOrderRated && shouldShowRatingSection) ...[
                  // Show Rate Order button if not rated but is successful delivery/pickup
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openRatingScreen(latestOrder),
                      icon: Icon(Icons.star, size: Responsive.getIconSize(context, mobile: 18)),
                      label: Text(
                        'Rate Order!',
                        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14), fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                        ),
                      ),
                    ),
                  ),
                ],
                
                // Pickup Details (removed - only show in detail screen)
                if (false && isExpanded && latestOrder.deliveryOption.toLowerCase() == 'pickup') ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  // Debug: Print pickup data and trigger resolution
                  Builder(
                    builder: (context) {
                      print('🔍 Order Phases - Pickup Data Debug for Order ${latestOrder.id}:');
                      print('  - pickupName: ${latestOrder.pickupName}');
                      print('  - pickupLandmark: ${latestOrder.pickupLandmark}');
                      print('  - pickupInstructions: ${latestOrder.pickupInstructions}');
                      print('  - pickupMapLink: ${latestOrder.pickupMapLink}');
                      
                      // Trigger pickup details resolution for this order
                      Future.microtask(() => _resolvePickupDetailsForOrder(latestOrder));
                      
                      return const SizedBox.shrink();
                    },
                  ),
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.store, color: Colors.blue[600], size: Responsive.getIconSize(context, mobile: 16)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Pickup Details',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: Responsive.getFontSize(context, mobile: 12),
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                        if (order.pickupName?.isNotEmpty == true) ...[
                          Text(
                            order.pickupName!,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: Responsive.getFontSize(context, mobile: 14),
                            ),
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                        ],
                        if (order.pickupAddress?.isNotEmpty == true || 
                            (order.pickupStreet?.isNotEmpty == true || order.pickupBarangay?.isNotEmpty == true)) ...[
                          Text(
                            order.pickupAddress ?? 
                            '${order.pickupStreet ?? ''}${order.pickupStreet?.isNotEmpty == true && order.pickupBarangay?.isNotEmpty == true ? ', ' : ''}${order.pickupBarangay ?? ''}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: Responsive.getFontSize(context, mobile: 12),
                            ),
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                        ],
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
                                  Builder(
                                    builder: (context) {
                                      final landmark = (order.pickupLandmark?.isNotEmpty == true)
                                          ? order.pickupLandmark!
                                          : (_orderPickupFallbacks[order.id]?['landmark'] ?? 'Landmark not available');
                                      
                                      // Debug: Log landmark source for this order
                                      print('🔍 Order ${order.id} landmark: "$landmark" (from ${order.pickupLandmark?.isNotEmpty == true ? 'order' : 'fallback'})');
                                      
                                      return Text(
                                        landmark,
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
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
                                  Builder(
                                    builder: (context) {
                                      final instructions = (order.pickupInstructions?.isNotEmpty == true)
                                          ? order.pickupInstructions!
                                          : (_orderPickupFallbacks[order.id]?['instructions'] ?? 'Instructions not available');
                                      
                                      // Debug: Log instructions source for this order
                                      print('🔍 Order ${order.id} instructions: "$instructions" (from ${order.pickupInstructions?.isNotEmpty == true ? 'order' : 'fallback'})');
                                      
                                      return Text(
                                        instructions,
                                        style: TextStyle(
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Always show navigate button if map link exists
                        if ((order.pickupMapLink?.isNotEmpty == true) || 
                            (_orderPickupFallbacks[order.id]?['mapLink']?.isNotEmpty == true)) ...[
                          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: () => _launchGoogleMaps(
                                order.pickupMapLink?.isNotEmpty == true 
                                    ? order.pickupMapLink! 
                                    : _orderPickupFallbacks[order.id]?['mapLink'] ?? ''
                              ),
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
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],
                
                // Cancellation Reason (removed - only show in detail screen)
                if (false && isExpanded && latestOrder.status.toLowerCase() == 'cancelled' && (latestOrder.cancellationReason ?? '').isNotEmpty) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.cancel, color: Colors.red),
                        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cancellation Reason',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                              SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                              Text(order.cancellationReason!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],

                // Cancellation Request Reason (removed - only show in detail screen)
                if (false && isExpanded && displayStatus == 'request_cancellation_sent' && 
                    order.status.toLowerCase() != 'confirmed' && 
                    (order.cancellationReason ?? '').isNotEmpty) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange),
                        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cancellation Request Reason',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                              ),
                              SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                              Text(order.cancellationReason!),
                              if (order.cancellationRequestedAt != null) ...[
                                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                                Text(
                                  'Cancellation requested at: ${_formatDate(order.cancellationRequestedAt!)}',
                                  style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12), color: Colors.orange, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],

                // GCash Cancellation Reason (removed - only show in detail screen)
                if (false && isExpanded && latestOrder.status.toLowerCase() == 'confirmed' && 
                    latestOrder.cancellationRequested == true && 
                    (order.paymentMethod ?? '').toLowerCase() == 'gcash' && 
                    (order.cancellationReason ?? '').isNotEmpty) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade200),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.payment, color: Colors.amber),
                        SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GCash Order Cancellation Reason',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                              ),
                              SizedBox(height: Responsive.getHeight(context, mobile: 4)),
                              Text(order.cancellationReason!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],

                // Failed Pickup Date/Time (removed - only show in detail screen)
                if (false && isExpanded && latestOrder.deliveryOption.toLowerCase() == 'pickup' && latestOrder.status.toLowerCase() == 'failed_pickup' && latestOrder.failedPickupAt != null) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red.shade700, size: Responsive.getIconSize(context, mobile: 16)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Pickup Failed',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: Responsive.getFontSize(context, mobile: 14),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.red.shade700, size: Responsive.getIconSize(context, mobile: 14)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Failed pickup at: ${_formatDateTime(order.failedPickupAt!)}',
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.w600,
                                fontSize: Responsive.getFontSize(context, mobile: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],
                
                // Picked Up Date/Time (show for pickup orders that have been picked up)
                if (isExpanded && latestOrder.deliveryOption.toLowerCase() == 'pickup' && latestOrder.status.toLowerCase() == 'picked_up' && latestOrder.pickedUpAt != null) ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green.shade200),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: Responsive.getIconSize(context, mobile: 16)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Order Picked Up',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: Responsive.getFontSize(context, mobile: 14),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.green.shade700, size: Responsive.getIconSize(context, mobile: 14)),
                            SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                            Text(
                              'Picked up at: ${_formatDateTime(latestOrder.pickedUpAt!)}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600,
                                fontSize: Responsive.getFontSize(context, mobile: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],
                
                // GCash Receipt (show for all GCash orders for transparency)
                if (isExpanded && latestOrder.paymentMethod.toLowerCase() == 'gcash') ...[
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Official GCash Receipt (amount paid)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: Responsive.getFontSize(context, mobile: 12),
                            color: Colors.grey[700],
                          ),
                        ),
                        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                        Builder(
                          builder: (context) {
                            final receiptUrl = _getGcashReceiptUrl(latestOrder.gcashReceiptUrl, latestOrder.id);
                            if (latestOrder.gcashReceiptUrl != null && latestOrder.gcashReceiptUrl!.startsWith('pending:')) {
                              return Row(
                                children: [
                                  Icon(Icons.receipt_long, color: Colors.grey[400], size: Responsive.getIconSize(context, mobile: 16)),
                                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                                  Text(
                                    '(placeholder)',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: Responsive.getFontSize(context, mobile: 12),
                                    ),
                                  ),
                                ],
                              );
                            } else if (receiptUrl.isNotEmpty) {
                              return GestureDetector(
                                onTap: () => _showReceiptLightbox(context, receiptUrl, 'GCash Receipt'),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 6)),
                                  child: Stack(
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: receiptUrl,
                                        height: Responsive.getHeight(context, mobile: 80),
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        placeholder: (c, _) => Container(
                                          height: Responsive.getHeight(context, mobile: 80),
                                          color: Colors.grey[200],
                                          alignment: Alignment.center,
                                          child: const CircularProgressIndicator(),
                                        ),
                                        errorWidget: (c, _, __) => Container(
                                          height: Responsive.getHeight(context, mobile: 80),
                                          color: Colors.grey[200],
                                          alignment: Alignment.center,
                                          child: Text('Failed to load', style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 10))),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Container(
                                          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 4)),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                          ),
                                          child: Icon(
                                            Icons.fullscreen,
                                            color: Colors.white,
                                            size: Responsive.getIconSize(context, mobile: 14),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              return Row(
                                children: [
                                  Icon(Icons.receipt_long, color: Colors.grey[400], size: Responsive.getIconSize(context, mobile: 16)),
                                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                                  Text(
                                    '(placeholder)',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: Responsive.getFontSize(context, mobile: 12),
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                ],
                
                // Action buttons (removed - only show in detail screen)
                // if (isExpanded) _buildOrderActions(order),
              ],
            ),
          ),
        ),
      ),
      );
      },
    );
  }

  Widget _buildOrderActions(Order order) {
    final canCancel = _canCancelOrder(order);
    final requestSent = order.cancellationRequested;
    if (!canCancel) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: requestSent
                ? null
                : () async {
                    String? reason = '';
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => StatefulBuilder(
                        builder: (context, setState) => AlertDialog(
                        title: const Text('Cancel Order'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Are you sure you want to cancel this order? This action cannot be undone'),
                            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'Reason for cancellation',
                                hintText: 'Please provide a reason',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 3,
                              onChanged: (v) {
                                setState(() {
                                  reason = v;
                                });
                              },
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('No'),
                          ),
                          ElevatedButton(
                            onPressed: (reason != null && reason!.trim().isNotEmpty) ? () => Navigator.of(context).pop(true) : null,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Yes, Cancel'),
                          ),
                        ],
                      )),
                    );

                    if (confirm == true) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(child: CircularProgressIndicator()),
                      );

                      final provider = Provider.of<CustomerProvider>(context, listen: false);
                      final ok = await provider.cancelOrder(order.id, reason: reason);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? 'Order cancelled' : 'Failed to cancel order'),
                            backgroundColor: ok ? Colors.red : Colors.red,
                          ),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.cancel),
            label: Text(
              requestSent
                  ? 'Request Sent'
                  : (order.paymentMethod.toLowerCase() == 'gcash' ? 'Request to Cancel' : 'Cancel Order'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: requestSent ? Colors.grey : Colors.red,
              side: BorderSide(color: requestSent ? Colors.grey : Colors.red),
              padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummarySection(Order order) {
    final paymentText = '${_formatTitleCase(order.paymentMethod)} • ${_formatTitleCase(order.paymentStatus)}';
    final fulfillmentText = _formatFulfillmentText(order);
    final scheduleText = _formatScheduleWindow(order);
    final contactText = order.customerPhone.isNotEmpty ? order.customerPhone : 'No phone number provided';
    final farmerText = order.farmerName.isNotEmpty ? order.farmerName : 'Assigned farmer pending';

    return Container(
      width: double.infinity,
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
        decoration: BoxDecoration(
          gradient: AppTheme.creamGradient,
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Details',
            style: TextStyle(
              fontSize: Responsive.getFontSize(context, mobile: 16),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
          _buildSummaryRow(
            icon: Icons.payments_outlined,
            label: 'Payment',
            value: paymentText,
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
          _buildSummaryRow(
            icon: Icons.local_shipping_outlined,
            label: 'Fulfillment',
            value: fulfillmentText,
          ),
          if (scheduleText.isNotEmpty) ...[
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            _buildSummaryRow(
              icon: Icons.schedule_outlined,
              label: 'Schedule',
              value: scheduleText,
            ),
          ],
          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
          _buildSummaryRow(
            icon: Icons.phone_iphone,
            label: 'Contact',
            value: contactText,
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
          _buildSummaryRow(
            icon: Icons.eco_outlined,
            label: 'Farmer',
            value: farmerText,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
          ),
          child: Icon(icon, size: Responsive.getIconSize(context, mobile: 18), color: AppTheme.primaryColor),
        ),
        SizedBox(width: Responsive.getWidth(context, mobile: 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 12),
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 4)),
              Text(
                value,
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 14),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatFulfillmentText(Order order) {
    final option = _formatTitleCase(order.deliveryOption);
    if (order.deliveryOption.toLowerCase() == 'pickup') {
      final pickupName = (order.pickupName?.isNotEmpty == true) ? order.pickupName! : 'AgriCart staff pickup';
      return '$option • $pickupName';
    }

    final address = (order.deliveryAddress?.isNotEmpty == true)
        ? order.deliveryAddress!
        : (order.customerAddress.isNotEmpty ? order.customerAddress : 'Delivery address unavailable');
    return '$option • $address';
  }

  String _formatScheduleWindow(Order order) {
    final start = order.estimatedDeliveryStart;
    final end = order.estimatedDeliveryEnd;
    if (start != null && end != null) {
      return '${_formatDate(start)} - ${_formatDate(end)}';
    }
    if (start != null) return _formatDate(start);
    if (end != null) return _formatDate(end);
    if (order.deliveryOption.toLowerCase() == 'pickup') {
      return 'Pickup on ${_formatDate(order.orderDate)}';
    }
    return '';
  }

  String _formatTitleCase(String value) {
    if (value.isEmpty) return '';
    return value
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppTheme.warningColor;
      case 'confirmed':
        return AppTheme.infoColor;
      case 'to_receive':
      case 'out_for_delivery':
        return AppTheme.primaryColor;
      case 'pickup_ready':
        return Colors.orange;
      case 'picked_up':
        return Colors.green;
      case 'delivered':
        return AppTheme.successColor;
      case 'failed_pickup':
        return Colors.red;
      case 'cancelled':
      case 'rejected':
        return AppTheme.errorColor;
      case 'request_cancellation_sent':
        return Colors.orange;
      case 'cancellation_confirmed':
        return AppTheme.successColor;
      case 'refund_denied':
        return AppTheme.errorColor;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending_actions;
      case 'confirmed':
        return Icons.check_circle;
      case 'to_receive':
        return Icons.local_shipping;
      case 'out_for_delivery':
        return Icons.local_shipping;
      case 'pickup_ready':
        return Icons.store;
      case 'picked_up':
        return Icons.check_circle;
      case 'delivered':
        return Icons.done_all;
      case 'failed_pickup':
        return Icons.cancel;
      case 'cancelled':
        return Icons.cancel;
      case 'request_cancellation_sent':
        return Icons.hourglass_empty;
      case 'cancellation_confirmed':
        return Icons.check_circle;
      default:
        return Icons.info_outline;
    }
  }

  String _getStatusLabel(String status, [Order? order]) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'to_receive':
        // CRITICAL: Don't show "Ready to Pickup" if order is already picked_up or failed_pickup
        // Check status first to prevent glitching back to "Ready to Pickup"
        final orderStatus = order?.status.toLowerCase() ?? '';
        if (orderStatus == 'picked_up' || orderStatus == 'failed_pickup') {
          // Order is in final state, don't check readyForPickup flag
          if (orderStatus == 'picked_up') {
            return 'Order picked up successfully!';
          } else {
            return 'Failed to Pickup';
          }
        }
        // Check if pickup order is ready for pickup
        if (order?.deliveryOption.toLowerCase() == 'pickup' && order?.readyForPickup == true) {
          return 'Ready to Pickup';
        }
        // Check if order has a rider assigned
        if (order?.riderName != null && order!.riderName!.isNotEmpty) {
          final contactInfo = order.riderPhone != null && order.riderPhone!.isNotEmpty 
              ? ' (${order.riderPhone})' 
              : '';
          return 'To Receive\nRider: ${order.riderName}$contactInfo';
        }
        return 'To Receive';
      case 'pickup_ready':
        return 'Pickup Ready';
      case 'picked_up':
        return 'Order picked up successfully!';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'failed_pickup':
        return 'Failed to Pickup';
      case 'cancelled':
        return 'Cancelled';
      case 'request_cancellation_sent':
        return 'Request Cancellation Sent';
      case 'cancellation_confirmed':
        return 'Ordered Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // Get Supabase GCash receipt URL - handles both full URLs and file paths
  String _getGcashReceiptUrl(String? receiptUrl, String orderId) {
    if (receiptUrl == null || receiptUrl.isEmpty) return '';
    if (receiptUrl.startsWith('pending:')) return '';
    
    // If it's already a full URL, return as is
    if (receiptUrl.startsWith('http://') || receiptUrl.startsWith('https://')) {
      // Fix duplicate bucket names if present
      if (receiptUrl.contains('/gcash_receipt/gcash_receipt/')) {
        return receiptUrl.replaceAll('/gcash_receipt/gcash_receipt/', '/gcash_receipt/');
      }
      return receiptUrl;
    }
    
    // If it's a file path, construct Supabase public URL
    const supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
    const bucketName = 'gcash_receipt';
    
    // Remove bucket name if already present
    String filePath = receiptUrl;
    if (filePath.startsWith('$bucketName/')) {
      filePath = filePath.substring(bucketName.length + 1);
    }
    // Remove leading slashes
    filePath = filePath.replaceAll(RegExp(r'^/+'), '');
    
    // If it doesn't contain order ID, add it (optional - depends on storage structure)
    // For now, use the path as-is
    if (!filePath.startsWith('$orderId/') && !filePath.contains('/')) {
      filePath = '$orderId/$filePath';
    }
    
    return '$supabaseUrl/storage/v1/object/public/$bucketName/$filePath';
  }

  String _formatDateTime(DateTime dateTime) {
    final date = _formatDate(dateTime);
    
    // Convert to 12-hour format
    int hour = dateTime.hour;
    final String period = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12; // 12 AM
    } else if (hour > 12) {
      hour = hour - 12; // 1 PM to 11 PM
    }
    
    final time = '$hour:${dateTime.minute.toString().padLeft(2, '0')} $period';
    return '$date at $time';
  }

  // Open rider chat
  Future<void> _openRiderChat(BuildContext context, Order order) async {
    if (order.riderId == null || order.riderName == null || order.riderName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider information not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    if (authProvider.currentCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to chat'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Initialize chat if not already initialized
    if (chatProvider.currentCustomerId != authProvider.currentCustomer!.uid) {
      chatProvider.initializeChat(authProvider.currentCustomer!.uid);
    }

    // Create or get rider conversation (will create new one if deleted)
    final conversationId = await chatProvider.createRiderConversation(
      order.riderId!,
      order.riderName!,
    );

    if (conversationId != null) {
      // Select the conversation immediately
      chatProvider.selectConversation(conversationId);
      
      // Navigate to chat screen - it will show the conversation directly
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(initialConversationId: conversationId),
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open chat. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markOrderAsReceived(Order order) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Order Received'),
          content: const Text('Are you sure you have received your order? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Update order status to picked up in Supabase
        try {
          await SupabaseService.initialize();
          final supabase = SupabaseService.client;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          
          await supabase
              .from('orders')
              .update({
                'status': 'picked_up',
                'picked_up_at': nowMs,
                'updated_at': nowMs,
              })
              .eq('id', order.id);

          // Send notification to customer
          try {
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            final customerId = authProvider.currentCustomer?.uid;
            
            if (customerId != null) {
              // Get last 8 characters of order ID for display
              final orderDisplayId = order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id;
              final formattedTotal = '\u20B1${order.total.toStringAsFixed(2)}';
              
              // Create notification
              final notification = CustomerNotification(
                id: 'order_picked_up_${order.id}_${nowMs}',
                title: 'Order Picked Up Successfully!',
                message: 'Your order #${orderDisplayId.toUpperCase()} has been marked as picked up. Total: $formattedTotal',
                type: 'order_picked_up',
                timestamp: DateTime.now(),
                isRead: false,
                orderId: order.id,
              );
              
              // Send notification to database
              await NotificationService.sendNotification(
                customerId,
                notification,
              );
              
              // CRITICAL: Refresh notification provider so it appears in notification history
              try {
                final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
                await notificationProvider.loadNotifications(customerId);
                print('✅ Notification provider refreshed, notification should appear in history');
              } catch (refreshError) {
                print('⚠️ Error refreshing notification provider: $refreshError');
                // Don't fail the whole operation if refresh fails
              }
              
              print('✅ Order picked up notification sent for order ${order.id}');
            }
          } catch (notificationError) {
            print('⚠️ Error sending picked up notification: $notificationError');
            // Don't fail the whole operation if notification fails
          }

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Order marked as received successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Refresh the orders list
          if (mounted) {
            setState(() {});
          }
        } catch (updateError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error updating order: ${updateError.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openRatingScreen(Order order) async {
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OrderRatingScreen(
            orderId: order.id,
            order: order,
          ),
        ),
      );

      // If rating was submitted successfully, refresh orders
      if (result == true && mounted) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.currentCustomer != null) {
          final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
          await customerProvider.loadOrders(authProvider.currentCustomer!.uid);
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening rating screen: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markOrderAsFailedPickup(Order order) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark as Failed Pickup'),
          content: const Text('Are you sure you want to mark this order as failed pickup? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Update order status to failed_pickup in Supabase
        try {
          await SupabaseService.initialize();
          final supabase = SupabaseService.client;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          
          await supabase
              .from('orders')
              .update({
                'status': 'failed_pickup',
                'failed_pickup_at': nowMs,
                'updated_at': nowMs,
              })
              .eq('id', order.id);

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Order marked as failed pickup successfully!'),
                backgroundColor: Colors.orange,
              ),
            );
          }

          // Refresh the orders list
          if (mounted) {
            setState(() {});
          }
        } catch (updateError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error updating order: ${updateError.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getPhaseName(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'to_receive':
        return 'To Receive';
      case 'pickup_ready':
        return 'Pickup Ready';
      case 'picked_up':
        return 'Order picked up successfully!';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'failed_pickup':
        return 'Failed to Pickup';
      case 'cancelled':
        return 'Cancelled';
      case 'request_cancellation_sent':
        return 'Cancellation Requested';
      case 'cancellation_confirmed':
        return 'Cancellation Confirmed';
      case 'rejected':
        return 'Rejected';
      case 'refund_denied':
        return 'Refund Denied';
      case 'refund_pending':
        return 'Refund Pending';
      case 'refund_processed':
        return 'Refund Processed';
      default:
        return _formatTitleCase(status.replaceAll('_', ' '));
    }
  }

  bool _canCancelOrder(Order order) {
    final status = order.status.toLowerCase();
    if (status == 'packed' || status == 'out_for_delivery' || status == 'delivered') return false;
    if (status == 'pending' || status == 'confirmed') {
      return OrderSchedule.canCancelOrder();
    }
    return false;
  }

  void _showReceiptLightbox(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Full-screen image viewer with zoom capability
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black,
                    child: Center(
                      child: Icon(Icons.error, color: Colors.white, size: Responsive.getIconSize(context, mobile: 48)),
                    ),
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 24)),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Title
            Positioned(
              top: 40,
              left: 20,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12), vertical: Responsive.getSpacing(context, mobile: 8)),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: Responsive.getFontSize(context, mobile: 16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Hint text at bottom
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16), vertical: Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                  ),
                  child: Text(
                    'Pinch to zoom • Tap outside to close',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: Responsive.getFontSize(context, mobile: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchGoogleMaps(String mapLink) async {
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

  Future<void> _resolvePickupDetailsForOrder(Order order) async {
    try {
      if (order.deliveryOption.toLowerCase() != 'pickup') return;
      
      final pickupName = (order.pickupName ?? '').trim();
      if (pickupName.isEmpty) {
        print('🔍 Order ${order.id}: No pickup name available');
        return;
      }

      // Always try to resolve pickup details, even if we already have some
      // This ensures we get the most complete data available
      final currentLandmark = order.pickupLandmark ?? '';
      final currentInstructions = order.pickupInstructions ?? '';
      final currentMapLink = order.pickupMapLink ?? '';
      
      final needsLandmark = currentLandmark.isEmpty;
      final needsInstructions = currentInstructions.isEmpty;
      final needsMap = currentMapLink.isEmpty;

      print('🔍 Resolving pickup details for order ${order.id} with pickup name: $pickupName');
      print('🔍 Order ${order.id}: needsLandmark=$needsLandmark, needsInstructions=$needsInstructions, needsMap=$needsMap');
      print('🔍 Order ${order.id}: current landmark="$currentLandmark", instructions="$currentInstructions"');
      print('🔍 Order ${order.id}: current mapLink="$currentMapLink"');
      
      // Try to get pickup details from Firebase
      // Query Supabase for pickup area matching the name
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        
        // Get all pickup areas and find matching one
        final areas = await supabase
            .from('pickup_area')
            .select('*') as List;
        
        if (areas.isNotEmpty) {
          // Find exact match (case-insensitive)
          final matchingAreaResult = areas.firstWhere(
            (area) {
              final areaMap = area as Map<String, dynamic>;
              final areaName = (areaMap['name']?.toString().trim().toLowerCase() ?? '');
              return areaName == pickupName.toLowerCase();
            },
            orElse: () => null,
          );
          
          if (matchingAreaResult != null) {
            final matchingArea = matchingAreaResult as Map<String, dynamic>;
            // Merge with existing fallback data or create new
            final existingFallback = _orderPickupFallbacks[order.id] ?? <String, String>{};
            final fallbackData = Map<String, String>.from(existingFallback);
            
            if (needsLandmark && (matchingArea['landmark'] ?? '').toString().isNotEmpty) {
              fallbackData['landmark'] = matchingArea['landmark'].toString();
            }
            if (needsInstructions && (matchingArea['instructions'] ?? '').toString().isNotEmpty) {
              fallbackData['instructions'] = matchingArea['instructions'].toString();
            }
            if (needsMap && (matchingArea['map_link'] ?? '').toString().isNotEmpty) {
              fallbackData['mapLink'] = matchingArea['map_link'].toString();
            }
            
            if (fallbackData.isNotEmpty) {
              _orderPickupFallbacks[order.id] = fallbackData;
              print('🔍 Set fallback data for order ${order.id} from Supabase: $fallbackData');
              if (mounted) setState(() {});
              return;
            }
          }
        }
      } catch (e) {
        print('🔍 Error fetching pickup area from Supabase: $e');
      }
    } catch (e) {
      print('🔍 Error resolving pickup details for order ${order.id}: $e');
    }
  }

  // Force refresh pickup details for all pickup orders
  Future<void> _refreshAllPickupDetails() async {
    print('🔍 Refreshing pickup details for all orders...');
    int refreshedCount = 0;
    for (final order in _allOrders) {
      if (order.deliveryOption.toLowerCase() == 'pickup') {
        print('🔍 Refreshing pickup details for order ${order.id}...');
        await _resolvePickupDetailsForOrder(order);
        refreshedCount++;
      }
    }
    print('🔍 Refreshed pickup details for $refreshedCount orders');
    
    // Show a message to the user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refreshed pickup details for $refreshedCount orders'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

class OrderPhase {
  final String title;
  final String short;
  final String status;
  final IconData icon;
  final Color color;

  OrderPhase({
    required this.title,
    required this.short,
    required this.status,
    required this.icon,
    required this.color,
  });
}

class _OrderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool subtle;

  const _OrderChip({
    required this.icon,
    required this.label,
    required this.color,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = subtle ? Colors.grey.shade100 : color.withOpacity(0.15);
    final textColor = subtle ? Colors.grey[700]! : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 10), vertical: Responsive.getSpacing(context, mobile: 6)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Responsive.getIconSize(context, mobile: 14), color: textColor),
          SizedBox(width: Responsive.getWidth(context, mobile: 4)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: textColor,
                  fontSize: Responsive.getFontSize(context, mobile: 12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
