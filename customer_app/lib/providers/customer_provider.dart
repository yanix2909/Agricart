import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../models/delivery_address.dart';
import '../models/notification.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';

class CustomerProvider with ChangeNotifier {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  List<Product> _products = [];
  // Top products aggregation (productId -> total sold quantity)
  final Map<String, int> _productSalesCount = {};
  // Simple in-memory cart
  List<OrderItem> _cartItems = [];
  // Temporary one-off Buy Now items (takes precedence on review screen)
  List<OrderItem>? _buyNowItems;
  List<Order> _orders = [];
  List<Product> _favoriteProducts = [];
  List<DeliveryAddress> _deliveryAddresses = [];
  bool _isLoading = false;
  String? _error;
  String? _currentCustomerId;
  bool _productsRealtimeListenerAttached = false;
  RealtimeChannel? _productsRealtimeChannel;
  RealtimeChannel? _ordersSalesRealtimeChannel;
  
  // Helper method to check if notification was deleted by user (reads from SharedPreferences)
  Future<bool> _isNotificationDeletedByUser(String? orderId, String notificationType, String customerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deletedKey = 'user_deleted_notifications_$customerId';
      final deletedJson = prefs.getString(deletedKey);
      if (deletedJson != null) {
        final deletedList = (jsonDecode(deletedJson) as List).map((e) => e.toString()).toList();
        final deletedSet = deletedList.toSet();
        
        if (orderId != null && orderId.isNotEmpty && notificationType.isNotEmpty) {
          final checkKey = '${orderId}_$notificationType';
          return deletedSet.contains(checkKey);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error checking deleted notifications: $e');
    }
    return false;
  }

  List<Product> get products => _products;
  List<OrderItem> get cartItems => List.unmodifiable(_cartItems);
  List<OrderItem> get buyNowItems => List.unmodifiable(_buyNowItems ?? const []);
  String _checkoutSource = 'none'; // 'none' | 'buy_now' | 'cart_selection'
  String get checkoutSource => _checkoutSource;
  List<Order> get orders => _orders;
  List<Product> get favoriteProducts => _favoriteProducts;
  List<DeliveryAddress> get deliveryAddresses => List.unmodifiable(_deliveryAddresses);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Calculate cumulative total orders (cumulative - includes all qualifying orders)
  // Included: pending (gcash), confirmed (gcash/cash), to_receive, out_for_delivery, pickup_ready, delivered/picked_up, failed (gcash only)
  // Excluded: rejected (gcash), cancelled (cash and gcash), failed (cash)
  int get cumulativeTotalOrders {
    int count = 0;
    for (final order in _orders) {
      final status = order.status.toLowerCase();
      final paymentMethod = order.paymentMethod.toLowerCase();
      
      // First, check for excluded statuses
      // Exclude rejected orders
      if (status == 'rejected') {
        continue;
      }
      
      // Exclude cancelled orders (cash and gcash)
      final isCancelled = order.status.toLowerCase() == 'cancelled' ||
                         order.cancellationConfirmed == true ||
                         order.refundConfirmedAt != null ||
                         order.refundDenied == true ||
                         (order.refundReceiptUrl != null && order.refundReceiptUrl!.isNotEmpty);
      
      if (isCancelled) {
        continue;
      }
      
      // Exclude failed orders if payment method is cash
      if (status == 'failed' || status == 'delivery_failed' || status == 'failed_pickup') {
        if (paymentMethod == 'cash' || paymentMethod == 'cod' || paymentMethod == 'cash_on_delivery' || paymentMethod == 'cash on delivery') {
          continue; // Exclude failed cash orders
        }
        // Include failed GCash orders
        count++;
        continue;
      }
      
      // Include pending orders ONLY if payment method is GCash
      if (status == 'pending') {
        if (paymentMethod == 'gcash') {
          count++;
        }
        continue;
      }
      
      // Include these statuses regardless of payment method
      if (status == 'confirmed' || 
          status == 'to_receive' || 
          status == 'out_for_delivery' ||
          status == 'pickup_ready' ||
          status == 'delivered' || 
          status == 'picked_up') {
        count++;
        continue;
      }
    }
    return count;
  }

  // Calculate cumulative total spent (cumulative - includes all qualifying orders)
  // Included: pending (gcash), confirmed (gcash/cash), to_receive, out_for_delivery, pickup_ready, delivered/picked_up, failed (gcash only)
  // Excluded: rejected (gcash), cancelled (cash and gcash), failed (cash)
  double get cumulativeTotalSpent {
    double total = 0.0;
    for (final order in _orders) {
      final status = order.status.toLowerCase();
      final paymentMethod = order.paymentMethod.toLowerCase();
      
      // First, check for excluded statuses
      // Exclude rejected orders
      if (status == 'rejected') {
        continue;
      }
      
      // Exclude cancelled orders (cash and gcash)
      final isCancelled = order.status.toLowerCase() == 'cancelled' ||
                         order.cancellationConfirmed == true ||
                         order.refundConfirmedAt != null ||
                         order.refundDenied == true ||
                         (order.refundReceiptUrl != null && order.refundReceiptUrl!.isNotEmpty);
      
      if (isCancelled) {
        continue;
      }
      
      // Exclude failed orders if payment method is cash
      if (status == 'failed' || status == 'delivery_failed' || status == 'failed_pickup') {
        if (paymentMethod == 'cash' || paymentMethod == 'cod' || paymentMethod == 'cash_on_delivery' || paymentMethod == 'cash on delivery') {
          continue; // Exclude failed cash orders
        }
        // Include failed GCash orders
        total += order.total;
        continue;
      }
      
      // Include pending orders ONLY if payment method is GCash
      if (status == 'pending') {
        if (paymentMethod == 'gcash') {
          total += order.total;
        }
        continue;
      }
      
      // Include these statuses regardless of payment method
      if (status == 'confirmed' || 
          status == 'to_receive' || 
          status == 'out_for_delivery' ||
          status == 'pickup_ready' ||
          status == 'delivered' || 
          status == 'picked_up') {
        total += order.total;
        continue;
      }
    }
    return total;
  }

  // Helper: Get current week date range (Monday 12:00 AM to Sunday 11:59:59 PM)
  Map<String, DateTime> _getCurrentWeekRange() {
    final now = DateTime.now();
    
    // Find Monday of current week (weekday 1 = Monday, 7 = Sunday)
    final currentWeekday = now.weekday;
    final daysFromMonday = currentWeekday - 1; // 0 if Monday, 6 if Sunday
    
    // Calculate Monday 12:00 AM
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysFromMonday));
    
    // Calculate Sunday 11:59:59 PM
    final sunday = monday.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
    
    return {
      'start': monday,
      'end': sunday,
    };
  }

  // Expose top 5 product IDs sorted by sales desc (cumulative, globally)
  // Uses _productSalesCount which is populated by loadTopProducts() from all orders
  List<String> get topProductIds {
    final entries = _productSalesCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).take(5).toList(); // Limit to top 5
  }

  // Expose top 5 products joined with product details (cumulative, globally)
  List<Product> get topProducts {
    final ids = topProductIds;
    final productsById = { for (final p in _products) p.id: p };
    return ids.map((id) => productsById[id]).whereType<Product>().toList();
  }

  // Load all available products from Supabase
  Future<void> loadProducts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Start realtime updates for sold kg to stay in sync with web
    _ensureOrdersSalesRealtimeSubscribed();

    bool loaded = await _loadProductsFromSupabase();

    if (!loaded && _error == null) {
      _error = 'No products available at the moment.';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Load customer orders
  Future<void> loadOrders(String customerId) async {
    debugPrint('🔄 Loading orders for customer: $customerId');
    _currentCustomerId = customerId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final loaded = await _loadOrdersFromSupabase(customerId);
    if (!loaded && _error == null) {
      _error = 'Failed to load orders. Please try again later.';
    }

    // Check for missed notifications (status changes that happened while app was closed)
    // NOTE: _notificationProvider should be set via setNotificationProvider() before calling this
    await _checkForMissedNotifications(customerId);

    // Set up Firebase Realtime Database listener for order status updates
    _setupRealtimeListener(customerId);

    _isLoading = false;
    notifyListeners();
  }

  // Manually sync order status with database
  Future<void> syncOrderStatus(String orderId) async {
    try {
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;

      final response = await supabase
          .from('orders')
          .select()
          .or('id.eq.$orderId,order_id.eq.$orderId')
          .maybeSingle();

      if (response != null) {
        final transformed = _transformSupabaseOrder(Map<String, dynamic>.from(response as Map));
        final order = Order.fromMap(transformed, transformed['id']?.toString() ?? orderId);
        _upsertOrder(order);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Supabase syncOrderStatus failed: $e');
    }
  }

  // Firebase Realtime Database listener for order status updates
  DatabaseReference? _orderStatusUpdatesRef;
  StreamSubscription<DatabaseEvent>? _orderStatusUpdatesSubscription;
  
  // Check for missed notifications when app loads (status changes that happened while app was closed)
  Future<void> _checkForMissedNotifications(String customerId) async {
    try {
      debugPrint('🔍 Checking for missed notifications for customer: $customerId');
      
      final database = FirebaseDatabase.instance;
      final statusUpdatesRef = database.ref('order_status_updates');
      
      // Get all order status updates from Firebase
      final statusSnapshot = await statusUpdatesRef.get();
      
      if (!statusSnapshot.exists || statusSnapshot.value == null) {
        debugPrint('📭 No order status updates found in Firebase');
        return;
      }
      
      // Get all existing notifications from Supabase to check what's already been shown
      // CRITICAL: Check Supabase, not Firebase Database, since notifications are stored in Supabase
      // This prevents recreating notifications that were deleted by the user
      final existingNotifications = <String>{};
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        final response = await supabase
            .from('customer_notifications')
            .select('order_id, type, id')
            .eq('customer_id', customerId);
        
        if (response != null && response is List) {
          for (final notificationData in response) {
            final notificationOrderId = notificationData['order_id']?.toString() ?? '';
            final notificationType = notificationData['type']?.toString() ?? '';
            if (notificationOrderId.isNotEmpty && notificationType.isNotEmpty) {
              // Store by orderId and type to check if notification already exists
              // CRITICAL: If notification exists, don't recreate it (even if user deleted it and it was recreated)
              final key = '${notificationOrderId}_$notificationType';
              existingNotifications.add(key);
            }
          }
        }
        debugPrint('📭 Found ${existingNotifications.length} existing notifications in Supabase - these will NOT be recreated');
      } catch (e) {
        debugPrint('⚠️ Error checking Supabase for existing notifications: $e');
        // Continue anyway - better to show duplicate than miss a notification
      }
      
      final statusUpdates = statusSnapshot.value as Map<dynamic, dynamic>;
      final notificationStatuses = {
        'confirmed': 'order_confirmed',
        'rejected': 'order_rejected',
        'cancelled': 'order_cancelled',
        'cancellation_confirmed': 'order_cancellation_confirmed',
        'to_receive': 'order_to_receive',
        // CRITICAL: Skip 'out_for_delivery' - these notifications are already handled by
        // order_phases_screen.dart when status changes in real-time. Checking for missed
        // notifications here causes duplicates when app is reopened.
        // 'out_for_delivery': 'order_out_for_delivery',
        'pickup_ready': 'order_ready_to_pickup',
        'delivered': 'order_delivered',
        // CRITICAL: Skip 'picked_up' - staff already creates this notification
        // 'picked_up': 'order_successful',
        'failed': 'order_failed',
        'delivery_failed': 'order_failed',
        'failed_pickup': 'order_failed_pickup',
      };
      
      final now = DateTime.now().millisecondsSinceEpoch;
      // Only show notifications for status changes in the last 7 days
      final sevenDaysAgo = now - (7 * 24 * 60 * 60 * 1000);
      
      // Group status updates by orderId to find the latest one for each order
      final orderStatusUpdates = <String, Map<String, dynamic>>{};
      
      for (final entry in statusUpdates.entries) {
        final orderId = entry.key.toString();
        final statusData = entry.value as Map<dynamic, dynamic>;
        final statusCustomerId = statusData['customerId']?.toString() ?? '';
        final status = statusData['status']?.toString() ?? '';
        final updatedAt = statusData['updatedAt'];
        
        // Only process if this is for the current customer and status should trigger notification
        if (statusCustomerId == customerId && 
            status.isNotEmpty && 
            notificationStatuses.containsKey(status.toLowerCase())) {
          
          // Check if this is a recent update (within last 7 days)
          final updateTimestamp = updatedAt is int 
              ? updatedAt 
              : (updatedAt is String 
                  ? (int.tryParse(updatedAt) ?? now)
                  : now);
          
          // Skip if timestamp is invalid or too old
          if (updateTimestamp < sevenDaysAgo) {
            continue; // Skip old status updates
          }
          
          // Keep only the latest status update for each order
          final existingTimestamp = orderStatusUpdates[orderId]?['updatedAt'] as int? ?? 0;
          if (!orderStatusUpdates.containsKey(orderId) || existingTimestamp < updateTimestamp) {
            orderStatusUpdates[orderId] = {
              'status': status,
              'updatedAt': updateTimestamp,
            };
          }
        }
      }
      
      // Now check each order's latest status update
      for (final entry in orderStatusUpdates.entries) {
        final orderId = entry.key;
        final statusData = entry.value;
        final status = statusData['status'] as String;
        final updateTimestamp = statusData['updatedAt'] as int;
        final notificationType = notificationStatuses[status.toLowerCase()] ?? '';
        
        if (notificationType.isEmpty) continue;
        
        // Check if notification already exists for this order and status
        final notificationKey = '${orderId}_$notificationType';
        if (existingNotifications.contains(notificationKey)) {
          debugPrint('📭 Notification already exists for order $orderId status $status, skipping popup (but will be in history)');
          continue;
        }
        
        // CRITICAL: Check if this notification was deleted by the user
        // If user explicitly deleted it, don't recreate it even if order status matches
        final wasDeletedByUser = await _isNotificationDeletedByUser(orderId, notificationType, customerId);
        if (wasDeletedByUser) {
          debugPrint('🔒 Notification for order $orderId type $notificationType was deleted by user - will NOT recreate');
          continue; // Skip creating this notification
        }
        
        // Find the order locally
        final orderIndex = _orders.indexWhere((order) => order.id == orderId);
        
        if (orderIndex != -1) {
          final order = _orders[orderIndex];
          final currentStatus = order.status.toLowerCase();
          final newStatus = status.toLowerCase();

          // For "to_receive" statuses, sync from Supabase first so we have the latest readyForPickup flag
          Order orderToUse = order;
          if (newStatus == 'to_receive') {
            try {
              await syncOrderStatus(orderId);
              final syncedIndex = _orders.indexWhere((o) => o.id == orderId);
              if (syncedIndex != -1) {
                orderToUse = _orders[syncedIndex];
              }
            } catch (e) {
              debugPrint('⚠️ Error syncing order $orderId for missed notification check: $e');
            }
          }
          
          // If the order's current status matches the Firebase status, show notification
          if (currentStatus == newStatus) {
            debugPrint('🔔 Found missed notification: Order $orderId has status $newStatus (change happened while app was closed)');
            await _showOrderStatusNotification(orderId, status, orderToUse);
          } else {
            // Status mismatch - update local order to match Firebase
            debugPrint('🔄 Order $orderId status mismatch: local=$currentStatus, firebase=$newStatus, updating...');
            _orders[orderIndex] = orderToUse.copyWith(status: status);
            await _showOrderStatusNotification(orderId, status, orderToUse);
          }
        } else {
          // Order not found locally, sync from Supabase first
          debugPrint('⚠️ Order $orderId not found locally, syncing from Supabase...');
          await syncOrderStatus(orderId);
          
          // After syncing, check again if we need to show notification
          final syncedOrderIndex = _orders.indexWhere((order) => order.id == orderId);
          if (syncedOrderIndex != -1) {
            final syncedOrder = _orders[syncedOrderIndex];
            final syncedStatus = syncedOrder.status.toLowerCase();
            final newStatus = status.toLowerCase();
            
            if (syncedStatus == newStatus || syncedStatus != newStatus) {
              // Update to match Firebase if needed
              if (syncedStatus != newStatus) {
                _orders[syncedOrderIndex] = syncedOrder.copyWith(status: status);
              }
              await _showOrderStatusNotification(orderId, status, syncedOrder);
            }
          }
        }
      }
      
      debugPrint('✅ Finished checking for missed notifications');
    } catch (e) {
      debugPrint('❌ Error checking for missed notifications: $e');
    }
  }
  
  // Set up Firebase Realtime Database listener for order status updates
  void _setupRealtimeListener(String customerId) {
    // Cancel previous listener
    _orderStatusUpdatesSubscription?.cancel();
    
    try {
      final database = FirebaseDatabase.instance;
      // Listen to order_status_updates filtered by customerId
      _orderStatusUpdatesRef = database.ref('order_status_updates');
      
      _orderStatusUpdatesSubscription = _orderStatusUpdatesRef!.onChildAdded.listen((event) {
        if (event.snapshot.value != null) {
          final statusData = event.snapshot.value as Map<dynamic, dynamic>;
          final orderId = statusData['orderId']?.toString() ?? '';
          final status = statusData['status']?.toString() ?? '';
          final statusCustomerId = statusData['customerId']?.toString() ?? '';
          
          // Only process if this is for the current customer
          if (statusCustomerId == customerId && orderId.isNotEmpty && status.isNotEmpty) {
            _handleOrderStatusUpdate(orderId, status);
          }
        }
      });
      
      // Also listen for updates (in case status changes again)
      _orderStatusUpdatesRef!.onChildChanged.listen((event) {
        if (event.snapshot.value != null) {
          final statusData = event.snapshot.value as Map<dynamic, dynamic>;
          final orderId = statusData['orderId']?.toString() ?? '';
          final status = statusData['status']?.toString() ?? '';
          final statusCustomerId = statusData['customerId']?.toString() ?? '';
          
          if (statusCustomerId == customerId && orderId.isNotEmpty && status.isNotEmpty) {
            _handleOrderStatusUpdate(orderId, status);
          }
        }
      });
      
      debugPrint('✅ Firebase Realtime Database listener for order status updates set up');
    } catch (e) {
      debugPrint('Error setting up Firebase order status listener: $e');
    }
  }
  
  // Handle order status update from Firebase Realtime Database
  Future<void> _handleOrderStatusUpdate(String orderId, String status) async {
    debugPrint('🔔 Order status update detected: $orderId -> $status');
    
    // Find the order locally
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    if (orderIndex == -1) {
      debugPrint('⚠️ Order $orderId not found locally, syncing from Supabase...');
      await syncOrderStatus(orderId);
      return;
    }
    
    final order = _orders[orderIndex];
    final previousStatus = order.status.toLowerCase();
    final newStatus = status.toLowerCase();
    
    // CRITICAL: Prevent status regression (e.g., delivered → out_for_delivery)
    if (!_canStatusProgress(previousStatus, newStatus)) {
      debugPrint('⚠️ Preventing status regression in _handleOrderStatusUpdate for order $orderId: $previousStatus → $newStatus');
      return; // Don't update if it would be a regression
    }
    
    // Only show notification if status actually changed
    if (previousStatus != newStatus) {
      // Always use the latest order data from Supabase for "to_receive" status
      // This ensures we see the correct readyForPickup flag and rescheduled_next_week flag
      Order orderToUse = order;
      if (newStatus == 'to_receive') {
        try {
          // Sync order status to get latest data including rescheduled_next_week
          await syncOrderStatus(orderId);
          // Add a small delay to ensure the sync is complete
          await Future.delayed(const Duration(milliseconds: 300));
          final syncedIndex = _orders.indexWhere((o) => o.id == orderId);
          if (syncedIndex != -1) {
            orderToUse = _orders[syncedIndex];
            debugPrint('✅ Synced order $orderId for to_receive notification - rescheduledNextWeek=${orderToUse.rescheduledNextWeek}');
          }
        } catch (e) {
          debugPrint('⚠️ Error syncing order $orderId for status update: $e');
        }
      }

      // Update local order status
      _orders[orderIndex] = orderToUse.copyWith(status: status);
      notifyListeners();
      
      // Show notification based on status (await to ensure notification is sent with correct data)
      await _showOrderStatusNotification(orderId, status, orderToUse);
    }
  }
  
  // Helper function to format order ID (matches order_detail_screen.dart _shortId)
  String _formatOrderCode(String orderId) {
    return orderId.length > 8 ? orderId.substring(orderId.length - 8).toUpperCase() : orderId.toUpperCase();
  }

  /// Calculate Saturday and Sunday dates of the next week
  /// Always returns the weekend of the NEXT week (not the current week)
  Map<String, DateTime> _getNextWeekendDates() {
    final now = DateTime.now();
    final currentDay = now.weekday; // 1 = Monday, 7 = Sunday
    
    // Calculate days until next week's Saturday
    int daysUntilNextSaturday;
    if (currentDay == 7) {
      // Today is Sunday, next week's Saturday is 6 + 7 = 13 days away
      daysUntilNextSaturday = 13;
    } else if (currentDay == 6) {
      // Today is Saturday, next week's Saturday is 7 days away
      daysUntilNextSaturday = 7;
    } else {
      // Monday-Friday: days until this Saturday, then add 7 for next week
      daysUntilNextSaturday = (6 - currentDay) + 7;
    }
    
    final nextSaturday = DateTime(now.year, now.month, now.day + daysUntilNextSaturday);
    final nextSunday = DateTime(nextSaturday.year, nextSaturday.month, nextSaturday.day + 1);
    
    return {
      'saturday': nextSaturday,
      'sunday': nextSunday,
    };
  }

  /// Format date as MM/DD/YY
  String _formatDateMMDDYY(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString().substring(2);
    return '$month/$day/$year';
  }

  // Show notification for order status change
  Future<void> _showOrderStatusNotification(String orderId, String status, Order order) async {
    final statusLower = status.toLowerCase();
    String title;
    String message;
    String type;
    
    // Format order code to match order detail screen (last 8 chars, uppercase)
    final orderCode = _formatOrderCode(orderId);
    
    // Format total amount with currency
    final totalAmount = order.total.toStringAsFixed(2);
    final formattedAmount = '₱$totalAmount';
    
    switch (statusLower) {
      case 'confirmed':
        title = 'Order Confirmed';
        message = 'Your order #$orderCode has been confirmed! Total: $formattedAmount';
        type = 'order_confirmed';
        break;
      case 'rejected':
        title = 'Order Rejected';
        message = 'Your order #$orderCode has been rejected. Total: $formattedAmount';
        type = 'order_rejected';
        break;
      case 'cancelled':
        title = 'Order Cancelled';
        message = 'Your order #$orderCode has been cancelled. Total: $formattedAmount';
        type = 'order_cancelled';
        break;
      case 'cancellation_confirmed':
        title = 'Cancellation Confirmed';
        message = 'Your cancellation request for order #$orderCode has been confirmed. Total: $formattedAmount';
        type = 'order_cancellation_confirmed';
        break;
      case 'to_receive':
        // For pickup orders, if readyForPickup is already true, skip the "to_receive" notification.
        // The "Order Ready To PickUp!" notification is created by the staff web dashboard (or rider app),
        // so we do not send another notification here to avoid duplicates.
        if (order.deliveryOption.toLowerCase() == 'pickup' && order.readyForPickup == true) {
          debugPrint('🔕 Skipping "to_receive" notification for pickup order $orderId - readyForPickup is true (handled by pickup_ready notification)');
          return;
        }

        // CRITICAL: For "to_receive" status, ALWAYS fetch from Supabase to get the latest rescheduled flag
        // This ensures we have the correct data even if the local order object is stale
        // Add a delay and retry mechanism to ensure the database commit is complete after rescheduling
        bool isRescheduled = false;
        bool foundInSupabase = false;
        int maxRetries = 3;
        int retryCount = 0;
        
        while (retryCount < maxRetries && !foundInSupabase) {
          // Add delay before each retry (longer delay for first attempt to ensure DB commit)
          if (retryCount > 0) {
            await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
          } else {
            await Future.delayed(const Duration(milliseconds: 1200));
          }
          
          try {
            await SupabaseService.initialize();
            final supabase = SupabaseService.client;
            
            // Try multiple queries to find the order (handle different ID formats)
            Map<String, dynamic>? latestOrderResponse;
            
            // First try: by id
            try {
              latestOrderResponse = await supabase
                  .from('orders')
                  .select('rescheduled_next_week')
                  .eq('id', orderId)
                  .maybeSingle() as Map<String, dynamic>?;
              if (latestOrderResponse != null && latestOrderResponse.isNotEmpty) {
                debugPrint('✅ [Retry $retryCount] Found order by id');
                foundInSupabase = true;
              }
            } catch (e) {
              debugPrint('⚠️ [Retry $retryCount] Query by id failed: $e');
            }
            
            // Second try: by order_id if first failed
            if (!foundInSupabase) {
              try {
                latestOrderResponse = await supabase
                    .from('orders')
                    .select('rescheduled_next_week')
                    .eq('order_id', orderId)
                    .maybeSingle() as Map<String, dynamic>?;
                if (latestOrderResponse != null && latestOrderResponse.isNotEmpty) {
                  debugPrint('✅ [Retry $retryCount] Found order by order_id');
                  foundInSupabase = true;
                }
              } catch (e) {
                debugPrint('⚠️ [Retry $retryCount] Query by order_id failed: $e');
              }
            }
            
            // Third try: using or condition
            if (!foundInSupabase) {
              try {
                latestOrderResponse = await supabase
                    .from('orders')
                    .select('rescheduled_next_week')
                    .or('id.eq.$orderId,order_id.eq.$orderId')
                    .maybeSingle() as Map<String, dynamic>?;
                if (latestOrderResponse != null && latestOrderResponse.isNotEmpty) {
                  debugPrint('✅ [Retry $retryCount] Found order with or condition');
                  foundInSupabase = true;
                }
              } catch (e) {
                debugPrint('⚠️ [Retry $retryCount] Query with or condition failed: $e');
              }
            }
            
            if (foundInSupabase && latestOrderResponse != null) {
              final rescheduledNextWeek = latestOrderResponse['rescheduled_next_week'];
              isRescheduled = rescheduledNextWeek == true || 
                             rescheduledNextWeek == 1 || 
                             rescheduledNextWeek == 'true' ||
                             (rescheduledNextWeek != null && rescheduledNextWeek.toString().toLowerCase() == 'true');
              debugPrint('📋 Order $orderId to_receive notification [Retry $retryCount]: Fetched from Supabase - rescheduled_next_week=$rescheduledNextWeek (type: ${rescheduledNextWeek.runtimeType}), isRescheduled=$isRescheduled');
              break; // Exit retry loop if we found the data
            } else if (!foundInSupabase) {
              debugPrint('📋 Order $orderId to_receive notification [Retry $retryCount]: Supabase returned null/empty, will retry...');
            }
          } catch (e, stackTrace) {
            debugPrint('⚠️ [Retry $retryCount] Error fetching order from Supabase: $e');
            if (retryCount == maxRetries - 1) {
              debugPrint('Stack trace: $stackTrace');
            }
          }
          
          retryCount++;
        }
        
        // If all retries failed to find order in Supabase, fall back to local order data
        if (!foundInSupabase) {
          isRescheduled = order.rescheduledNextWeek == true || 
                         order.rescheduledNextWeek == 1;
          debugPrint('📋 Order $orderId to_receive notification: All retries exhausted, using local check - rescheduledNextWeek=${order.rescheduledNextWeek}, isRescheduled=$isRescheduled');
        }
        
        if (isRescheduled) {
          // For rescheduled orders: show custom message with Saturday and Sunday dates
          final weekendDates = _getNextWeekendDates();
          final satDate = _formatDateMMDDYY(weekendDates['saturday']!);
          final sunDate = _formatDateMMDDYY(weekendDates['sunday']!);
          
          title = 'Order Re-scheduled';
          message = 'Your Order: #$orderCode (Total: $formattedAmount) has been Re-scheduled on Estimated Delivery ($satDate - $sunDate). Thank you for your patience and feel free to chat our staff for your further concerns.';
          type = 'order_to_receive';
          debugPrint('✅ Sending rescheduled order notification for order $orderId');
        } else {
          // For delivery orders, or pickup orders that are not yet ready, send "Order Ready for Harvesting"
          title = 'Order Ready for Harvesting';
          message = 'Your order #$orderCode is ready for harvesting and packaging. Cancellation is no longer applicable. Total: $formattedAmount';
          type = 'order_to_receive';
          debugPrint('✅ Sending normal "Order Ready for Harvesting" notification for order $orderId');
        }
        break;
      case 'out_for_delivery':
        // Use same title with emoji as in order_phases_screen.dart to match existing notifications
        title = 'Order Out for Delivery! 🚚';
        message = 'Your order #$orderCode with a total of $formattedAmount is now out for delivery and will arrive soon! Please prepare the payment amount.';
        type = 'order_out_for_delivery';
        break;
      case 'pickup_ready':
        title = 'Order Ready To PickUp!';
        message = 'Your order #$orderCode is ready for pickup! Total: $formattedAmount';
        type = 'order_ready_to_pickup';
        break;
      case 'delivered':
        title = 'Order Delivered';
        message = 'Your order #$orderCode has been delivered successfully! Total: $formattedAmount';
        type = 'order_delivered';
        break;
      case 'picked_up':
        // CRITICAL: Skip notification creation for picked_up status
        // Staff/admin already creates the "Order Received" notification when marking order as picked up
        // This prevents duplicate notifications in the customer's notification history
        debugPrint('🔕 Skipping "picked_up" notification creation - staff already handles this notification');
        return; // Don't create notification - staff dashboard already created it
      case 'failed':
      case 'delivery_failed':
        title = 'Delivery Failed';
        message = 'Your order #$orderCode has been failed to delivery. Please contact support. Total: $formattedAmount';
        type = 'order_failed';
        break;
      case 'failed_pickup':
        title = 'Pickup Failed';
        message = 'Your order #$orderCode has been failed to pickup. Please contact support. Total: $formattedAmount';
        type = 'order_failed_pickup';
        break;
      default:
        return; // Don't show notification for unknown statuses
    }
    
    // Create notification in Firebase Database
    // The notification_provider listener will automatically show the notification
    // when it detects a new notification in Firebase Database
    // So we just save it here - don't show duplicate notification
    final notification = CustomerNotification(
      id: 'order_${orderId}_${status}_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      isRead: false,
      orderId: orderId,
    );
    
    if (_currentCustomerId != null) {
      // Always send via NotificationService to ensure push/local even when app is open
      try {
        await NotificationService.sendNotification(_currentCustomerId!, notification);
        debugPrint('✅ Notification sent via NotificationService (includes push + local)');
        return; // Avoid duplicate insert below; NotificationService handles Supabase insert + FCM
      } catch (e) {
        debugPrint('⚠️ Failed to send notification via NotificationService: $e. Falling back to direct Supabase insert.');
      }

      // CRITICAL: Save notification to Supabase (not Firebase Database)
      // This matches where notifications are actually stored and prevents duplicates
      // The notification_provider listener will show it automatically
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        
        // CRITICAL: Check if notification already exists in Supabase to prevent duplicates
        // This also prevents recreating notifications that were deleted by the user
        if (notification.orderId != null && notification.orderId!.isNotEmpty) {
          // First check if notification already exists in database
          final existingResponse = await supabase
              .from('customer_notifications')
              .select('id')
              .eq('customer_id', _currentCustomerId!)
              .eq('order_id', notification.orderId!)
              .eq('type', notification.type)
              .limit(1);
          
          if (existingResponse != null && existingResponse is List && existingResponse.isNotEmpty) {
            debugPrint('📭 Notification already exists in Supabase for order ${notification.orderId} type ${notification.type}, skipping duplicate');
            return; // Don't create duplicate - this also prevents recreating deleted notifications
          }
          
          // CRITICAL: Check if this notification was deleted by the user
          // If user explicitly deleted it, don't recreate it even if order status matches
          // This check only runs for NEW notifications (not already in database)
          final wasDeletedByUser = await _isNotificationDeletedByUser(
            notification.orderId, 
            notification.type, 
            _currentCustomerId!
          );
          if (wasDeletedByUser) {
            debugPrint('🔒 Notification for order ${notification.orderId} type ${notification.type} was deleted by user - will NOT recreate');
            return; // Don't create this notification
          }
        }
        
        // Save notification to Supabase
        final notificationData = <String, dynamic>{
          'id': notification.id,
          'customer_id': _currentCustomerId!,
          'title': notification.title,
          'message': notification.message,
          'type': notification.type,
          'timestamp': notification.timestamp.millisecondsSinceEpoch,
          'is_read': notification.isRead,
          'fcm_sent': false, // Will be set to true by Edge Function after sending FCM
        };
        
        if (notification.orderId != null && notification.orderId!.isNotEmpty) {
          notificationData['order_id'] = notification.orderId!;
        }
        
        await supabase.from('customer_notifications').insert(notificationData);
        debugPrint('✅ Order status notification saved to Supabase');
        // Don't call sendNotification here - it would show duplicate notification
        // The notification_provider listener will handle showing it
      } catch (e) {
        debugPrint('❌ Error saving notification to Supabase: $e');
        // Fallback: try Firebase Database if Supabase fails
        try {
          final database = FirebaseDatabase.instance;
          final notificationRef = database.ref('notifications/customers/$_currentCustomerId/${notification.id}');
          
          final notificationData = <String, dynamic>{
            'id': notification.id,
            'title': notification.title,
            'message': notification.message,
            'type': notification.type,
            'timestamp': notification.timestamp.millisecondsSinceEpoch,
            'isRead': notification.isRead,
          };
          
          if (notification.orderId != null && notification.orderId!.isNotEmpty) {
            notificationData['orderId'] = notification.orderId!;
          }
          
          await notificationRef.set(notificationData);
          debugPrint('✅ Order status notification saved to Firebase Database (fallback)');
        } catch (firebaseError) {
          debugPrint('❌ Error saving notification to Firebase Database: $firebaseError');
        }
      }
    }
  }
  
  @override
  void dispose() {
    _orderStatusUpdatesSubscription?.cancel();
    _orderStatusUpdatesRef = null;
    super.dispose();
  }

  Future<bool> _loadOrdersFromSupabase(String customerId) async {
    try {
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;

      final response = await supabase
          .from('orders')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      final List<Order> newOrders = [];
      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            try {
              final transformed = _transformSupabaseOrder(Map<String, dynamic>.from(item as Map));
              final orderId = transformed['id']?.toString() ??
                  transformed['orderId']?.toString() ??
                  transformed['order_id']?.toString() ??
                  '';
              if (orderId.isEmpty) continue;
              final order = Order.fromMap(transformed, orderId);
              newOrders.add(order);
            } catch (e, stackTrace) {
              debugPrint('❌ Error transforming Supabase order: $e');
              debugPrint('$stackTrace');
            }
          }
        }
      }

      await _mergeOrders(newOrders, customerId);
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading orders from Supabase: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  // Status progression hierarchy - prevents regression to earlier statuses
  int _getStatusPriority(String status) {
    final statusLower = status.toLowerCase();
    // Higher number = more advanced status (final states are highest)
    switch (statusLower) {
      case 'delivered':
      case 'picked_up':
        return 100; // Final states - highest priority
      case 'failed':
      case 'delivery_failed':
      case 'failed_pickup':
        return 90; // Failure states - high priority
      case 'cancelled':
      case 'cancellation_confirmed':
        return 85; // Cancellation - high priority
      case 'out_for_delivery':
        return 50;
      case 'pickup_ready':
        return 50;
      case 'to_receive':
        return 40;
      case 'confirmed':
        return 30;
      case 'rejected':
        return 25;
      case 'pending':
        return 10;
      default:
        return 0;
    }
  }
  
  // Check if status can progress from oldStatus to newStatus
  bool _canStatusProgress(String oldStatus, String newStatus) {
    final oldPriority = _getStatusPriority(oldStatus);
    final newPriority = _getStatusPriority(newStatus);
    
    // Can always progress forward (new priority >= old priority)
    if (newPriority >= oldPriority) {
      return true;
    }
    
    // Special cases: can go to cancelled or failed from any state
    final newStatusLower = newStatus.toLowerCase();
    if (newStatusLower == 'cancelled' || 
        newStatusLower == 'cancellation_confirmed' ||
        newStatusLower == 'rejected' ||
        newStatusLower == 'failed' ||
        newStatusLower == 'delivery_failed' ||
        newStatusLower == 'failed_pickup') {
      return true;
    }
    
    // Cannot regress (e.g., from delivered back to out_for_delivery)
    return false;
  }

  Future<void> _mergeOrders(List<Order> newOrders, String customerId) async {
    newOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final existingOrderIds = _orders.map((order) => order.id).toSet();
    final newOrderIds = newOrders.map((order) => order.id).toSet();

    for (final newOrder in newOrders) {
      if (!existingOrderIds.contains(newOrder.id)) {
        _orders.add(newOrder);
      } else {
        final index = _orders.indexWhere((order) => order.id == newOrder.id);
        if (index != -1) {
          final existingOrder = _orders[index];
          final existingStatus = existingOrder.status.toLowerCase();
          final newStatus = newOrder.status.toLowerCase();
          
          // Preserve local cancellation state if it exists and database doesn't have it
          // This prevents local cancellation requests from being overwritten by database sync
          final shouldPreserveCancellation = existingOrder.cancellationRequested == true &&
              existingOrder.cancellationInitiatedBy == 'customer' &&
              (newOrder.cancellationRequested != true || 
               newOrder.cancellationInitiatedBy != 'customer');
          
          // CRITICAL: Prevent status regression (e.g., delivered → out_for_delivery)
          // Check if the new status would be a regression
          final isStatusRegression = !_canStatusProgress(existingStatus, newStatus);
          
          if (isStatusRegression) {
            debugPrint('⚠️ Preventing status regression for order ${newOrder.id}: ${existingStatus} → ${newStatus}');
            // Keep existing status if it's more advanced, but update other fields
            _orders[index] = newOrder.copyWith(
              status: existingOrder.status, // Preserve the more advanced status
              cancellationRequested: shouldPreserveCancellation ? existingOrder.cancellationRequested : newOrder.cancellationRequested,
              cancellationRequestedAt: shouldPreserveCancellation ? existingOrder.cancellationRequestedAt : newOrder.cancellationRequestedAt,
              cancellationReason: shouldPreserveCancellation ? existingOrder.cancellationReason : newOrder.cancellationReason,
              cancellationInitiatedBy: shouldPreserveCancellation ? existingOrder.cancellationInitiatedBy : newOrder.cancellationInitiatedBy,
            );
          } else if (shouldPreserveCancellation) {
            // Merge: use database order but preserve local cancellation fields
            _orders[index] = newOrder.copyWith(
              cancellationRequested: existingOrder.cancellationRequested,
              cancellationRequestedAt: existingOrder.cancellationRequestedAt,
              cancellationReason: existingOrder.cancellationReason,
              cancellationInitiatedBy: existingOrder.cancellationInitiatedBy,
              // Also preserve status if it was changed locally for cancellation
              status: existingOrder.status == 'cancelled' && newOrder.status != 'cancelled'
                  ? existingOrder.status
                  : newOrder.status,
            );
          } else {
            // Normal merge - use database order (status progression is allowed)
            // CRITICAL: Final safety check - if existing order has final pickup state, preserve it
            final existingIsFinalPickup = existingStatus == 'picked_up' || existingStatus == 'failed_pickup';
            final existingHasPickedUpTimestamp = existingOrder.pickedUpAt != null;
            final existingHasFailedTimestamp = existingOrder.failedPickupAt != null;
            
            if (existingIsFinalPickup || existingHasPickedUpTimestamp || existingHasFailedTimestamp) {
              // Existing order is in final state - preserve it even if database shows different status
              final preservedStatus = existingHasPickedUpTimestamp && newOrder.status.toLowerCase() != 'picked_up'
                  ? 'picked_up'
                  : (existingHasFailedTimestamp && newOrder.status.toLowerCase() != 'failed_pickup'
                      ? 'failed_pickup'
                      : existingOrder.status);
              
              _orders[index] = newOrder.copyWith(
                status: preservedStatus,
                // Preserve timestamps if they exist
                pickedUpAt: existingHasPickedUpTimestamp ? existingOrder.pickedUpAt : newOrder.pickedUpAt,
                failedPickupAt: existingHasFailedTimestamp ? existingOrder.failedPickupAt : newOrder.failedPickupAt,
              );
              debugPrint('🔒 Preserved final pickup state for order ${newOrder.id}: $preservedStatus');
            } else {
              // Normal merge - use database order
              _orders[index] = newOrder;
            }
          }
        }
      }
    }

    // Only remove orders that aren't in Supabase AND are older than 10 minutes
      // This preserves newly placed orders that haven't synced to Supabase yet
      final now = DateTime.now();
      _orders.removeWhere((order) {
        if (newOrderIds.contains(order.id)) {
          return false; // Keep orders that are in Supabase
        }
        // Only remove orders older than 10 minutes that aren't in Supabase
        // This allows newly placed orders to remain until they sync
        final orderAge = now.difference(order.createdAt);
      if (orderAge.inMinutes > 10) {
        debugPrint('🗑️ Removing stale order ${order.id} (not in Supabase, older than 10 minutes)');
        return true;
      }
      debugPrint('💾 Preserving recent order ${order.id} (not yet in Supabase, age: ${orderAge.inMinutes} minutes)');
      return false; // Keep recent orders even if not in Supabase yet
    });

    _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _error = null;
    await saveOrdersToStorage(customerId);
    
    // Notify listeners after merging orders so UI updates with new calculations
    notifyListeners();
  }

  void _upsertOrder(Order order) {
    final index = _orders.indexWhere((o) => o.id == order.id);
    if (index != -1) {
      final existingOrder = _orders[index];
      final existingStatus = existingOrder.status.toLowerCase();
      final newStatus = order.status.toLowerCase();
      
      // Preserve local cancellation state if it exists and incoming order doesn't have it
      final shouldPreserveCancellation = existingOrder.cancellationRequested == true &&
          existingOrder.cancellationInitiatedBy == 'customer' &&
          (order.cancellationRequested != true || 
           order.cancellationInitiatedBy != 'customer');
      
      // CRITICAL: Preserve rating data if existing order has it and incoming order doesn't
      // This prevents rating data from being lost during syncs/updates
      // Prefer incoming rating data (from Supabase) if it exists, otherwise preserve existing
      final existingHasRating = existingOrder.isRated == true || 
                                 existingOrder.orderRating != null || 
                                 existingOrder.orderRatedAt != null;
      final incomingHasRating = order.isRated == true || 
                                order.orderRating != null || 
                                order.orderRatedAt != null;
      // Only preserve existing rating if incoming doesn't have it (incoming from Supabase is source of truth)
      final shouldPreserveRating = existingHasRating && !incomingHasRating;
      
      // CRITICAL: Prevent status regression (e.g., delivered → out_for_delivery)
      final isStatusRegression = !_canStatusProgress(existingStatus, newStatus);
      
      if (isStatusRegression) {
        debugPrint('⚠️ Preventing status regression in _upsertOrder for order ${order.id}: ${existingStatus} → ${newStatus}');
        // Keep existing status if it's more advanced, but update other fields
        _orders[index] = order.copyWith(
          status: existingOrder.status, // Preserve the more advanced status
          cancellationRequested: shouldPreserveCancellation ? existingOrder.cancellationRequested : order.cancellationRequested,
          cancellationRequestedAt: shouldPreserveCancellation ? existingOrder.cancellationRequestedAt : order.cancellationRequestedAt,
          cancellationReason: shouldPreserveCancellation ? existingOrder.cancellationReason : order.cancellationReason,
          cancellationInitiatedBy: shouldPreserveCancellation ? existingOrder.cancellationInitiatedBy : order.cancellationInitiatedBy,
          // Preserve rating data if existing has it and incoming doesn't
          isRated: shouldPreserveRating ? existingOrder.isRated : order.isRated,
          orderRating: shouldPreserveRating ? existingOrder.orderRating : order.orderRating,
          orderComment: shouldPreserveRating ? existingOrder.orderComment : order.orderComment,
          orderMedia: shouldPreserveRating ? existingOrder.orderMedia : order.orderMedia,
          orderRatedAt: shouldPreserveRating ? existingOrder.orderRatedAt : order.orderRatedAt,
          riderRating: shouldPreserveRating ? existingOrder.riderRating : order.riderRating,
          riderComment: shouldPreserveRating ? existingOrder.riderComment : order.riderComment,
          riderRatedAt: shouldPreserveRating ? existingOrder.riderRatedAt : order.riderRatedAt,
          pickupExperienceComment: shouldPreserveRating ? existingOrder.pickupExperienceComment : order.pickupExperienceComment,
          pickupExperienceRatedAt: shouldPreserveRating ? existingOrder.pickupExperienceRatedAt : order.pickupExperienceRatedAt,
        );
      } else if (shouldPreserveCancellation || shouldPreserveRating) {
        // Merge: use incoming order but preserve local cancellation and/or rating fields
        _orders[index] = order.copyWith(
          cancellationRequested: shouldPreserveCancellation ? existingOrder.cancellationRequested : order.cancellationRequested,
          cancellationRequestedAt: shouldPreserveCancellation ? existingOrder.cancellationRequestedAt : order.cancellationRequestedAt,
          cancellationReason: shouldPreserveCancellation ? existingOrder.cancellationReason : order.cancellationReason,
          cancellationInitiatedBy: shouldPreserveCancellation ? existingOrder.cancellationInitiatedBy : order.cancellationInitiatedBy,
          // Also preserve status if it was changed locally for cancellation
          status: existingOrder.status == 'cancelled' && order.status != 'cancelled'
              ? existingOrder.status
              : order.status,
          // Preserve rating data if existing has it and incoming doesn't
          isRated: shouldPreserveRating ? existingOrder.isRated : order.isRated,
          orderRating: shouldPreserveRating ? existingOrder.orderRating : order.orderRating,
          orderComment: shouldPreserveRating ? existingOrder.orderComment : order.orderComment,
          orderMedia: shouldPreserveRating ? existingOrder.orderMedia : order.orderMedia,
          orderRatedAt: shouldPreserveRating ? existingOrder.orderRatedAt : order.orderRatedAt,
          riderRating: shouldPreserveRating ? existingOrder.riderRating : order.riderRating,
          riderComment: shouldPreserveRating ? existingOrder.riderComment : order.riderComment,
          riderRatedAt: shouldPreserveRating ? existingOrder.riderRatedAt : order.riderRatedAt,
          pickupExperienceComment: shouldPreserveRating ? existingOrder.pickupExperienceComment : order.pickupExperienceComment,
          pickupExperienceRatedAt: shouldPreserveRating ? existingOrder.pickupExperienceRatedAt : order.pickupExperienceRatedAt,
        );
      } else {
        // Normal merge - use incoming order (status progression is allowed)
        _orders[index] = order;
      }
    } else {
      _orders.add(order);
    }
    _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Map<String, dynamic> _transformSupabaseOrder(Map<String, dynamic> row) {
    final createdAt = _parseSupabaseDateToMillis(row['created_at']) ?? DateTime.now().millisecondsSinceEpoch;
    final updatedAt = _parseSupabaseDateToMillis(row['updated_at']) ?? createdAt;
    final orderDate = _parseSupabaseDateToMillis(row['order_date']) ?? createdAt;

    final items = _normalizeSupabaseItems(row['items']);
    final deliveryAddress = row['delivery_address'] ?? row['customer_address'];
    
    // CRITICAL: Ensure status consistency - if timestamps indicate final state, use that status
    final pickedUpAt = _parseSupabaseDateToMillis(row['picked_up_at']);
    final failedPickupAt = _parseSupabaseDateToMillis(row['failed_pickup_at']);
    String status = (row['status'] ?? 'pending').toString();
    
    // If timestamps exist, ensure status matches (defensive check)
    if (pickedUpAt != null && status.toLowerCase() != 'picked_up') {
      debugPrint('⚠️ Order ${row['id']} has picked_up_at timestamp but status is $status, correcting to picked_up');
      status = 'picked_up';
    } else if (failedPickupAt != null && status.toLowerCase() != 'failed_pickup') {
      debugPrint('⚠️ Order ${row['id']} has failed_pickup_at timestamp but status is $status, correcting to failed_pickup');
      status = 'failed_pickup';
    }

    return <String, dynamic>{
      'id': row['id']?.toString() ?? row['order_id']?.toString(),
      'customerId': row['customer_id']?.toString() ?? '',
      'customerName': row['customer_name'] ?? '',
      'customerPhone': row['customer_phone'] ?? '',
      'customerAddress': row['customer_address'] ?? '',
      'items': items,
      'subtotal': _safeDouble(row['subtotal']) ?? 0.0,
      'deliveryFee': _safeDouble(row['delivery_fee']) ?? 0.0,
      'total': _safeDouble(row['total']) ?? 0.0,
      'status': status,
      'paymentMethod': row['payment_method'] ?? 'cash',
      'paymentStatus': row['payment_status'] ?? 'pending',
      'gcashReceiptUrl': row['gcash_receipt_url'],
      'refundReceiptUrl': row['refund_receipt_url'],
      'refundConfirmedAt': _parseSupabaseDateToMillis(row['refund_confirmed_at']),
      'deliveryOption': row['delivery_option'] ?? (deliveryAddress != null ? 'delivery' : 'pickup'),
      'deliveryAddress': deliveryAddress,
      'pickupAddress': row['pickup_address'],
      'pickupMapLink': row['pickup_map_link'],
      'pickupName': row['pickup_name'],
      'pickupStreet': row['pickup_street'],
      'pickupSitio': row['pickup_sitio'],
      'pickupBarangay': row['pickup_barangay'],
      'pickupCity': row['pickup_city'],
      'pickupProvince': row['pickup_province'],
      'pickupLandmark': row['pickup_landmark'],
      'pickupInstructions': row['pickup_instructions'],
      'orderDate': orderDate,
      'deliveryDate': _parseSupabaseDateToMillis(row['delivery_date']),
      'deliveryNotes': row['order_notes'] ?? row['delivery_notes'] ?? '',
      'estimatedDeliveryStart': _parseSupabaseDateToMillis(row['estimated_delivery_start']),
      'estimatedDeliveryEnd': _parseSupabaseDateToMillis(row['estimated_delivery_end']),
      'farmerId': row['farmer_id']?.toString() ?? '',
      'farmerName': row['farmer_name'] ?? '',
      'trackingNumber': row['tracking_number'],
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'totalOrders': _safeInt(row['total_orders']) ?? 0,
      'totalSpent': _safeDouble(row['total_spent']) ?? 0.0,
      'cancellationRequested': _safeBool(row['cancellation_requested']) ?? false,
      'cancellationRequestedAt': _parseSupabaseDateToMillis(row['cancellation_requested_at']),
      'cancellationInitiatedBy': row['cancellation_initiated_by'],
      'cancellationReason': row['cancellation_reason'],
      'rejectionReason': row['rejection_reason'],
      'refundDenied': _safeBool(row['refund_denied']) ?? false,
      'refundDeniedReason': row['refund_denied_reason'],
      'refundDeniedAt': _parseSupabaseDateToMillis(row['refund_denied_at']),
      'refundDeniedBy': row['refund_denied_by'],
      'refundDeniedByName': row['refund_denied_by_name'],
      'riderId': row['rider_id'],
      'riderName': row['rider_name'],
      'riderPhone': row['rider_phone'],
      'assignedAt': _parseSupabaseDateToMillis(row['assigned_at']),
      'outForDeliveryAt': _parseSupabaseDateToMillis(row['out_for_delivery_at']),
      'readyForPickup': _safeBool(row['ready_for_pickup']),
      'readyForPickupAt': _parseSupabaseDateToMillis(row['ready_for_pickup_at']),
      'pickedUpAt': _parseSupabaseDateToMillis(row['picked_up_at']),
      'failedPickupAt': _parseSupabaseDateToMillis(row['failed_pickup_at']),
      'rescheduledNextWeek': _safeBool(row['rescheduled_next_week']),
      'isRated': _safeBool(row['is_rated']) ?? false,
      'orderRating': _safeInt(row['order_rating']),
      'orderComment': row['order_comment'],
      'orderMedia': row['order_media'],
      'orderRatedAt': _parseSupabaseDateToMillis(row['order_rated_at']),
      'riderRating': _safeInt(row['rider_rating']),
      'riderComment': row['rider_comment'],
      'riderRatedAt': _parseSupabaseDateToMillis(row['rider_rated_at']),
      'pickupExperienceComment': row['pickup_experience_comment'],
      'pickupExperienceRatedAt': _parseSupabaseDateToMillis(row['pickup_experience_rated_at']),
    };
  }

  List<Map<String, dynamic>> _normalizeSupabaseItems(dynamic itemsData) {
    try {
      if (itemsData == null) return [];
      if (itemsData is List) {
        return itemsData.map<Map<String, dynamic>>((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
          }
          return {};
        }).where((item) => item.isNotEmpty).toList();
      }
      if (itemsData is String && itemsData.isNotEmpty) {
        final decoded = jsonDecode(itemsData);
        if (decoded is List) {
          return decoded
              .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }
      if (itemsData is Map) {
        return itemsData.values
            .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (e) {
      debugPrint('❌ Failed to normalize Supabase items: $e');
    }
    return [];
  }

  bool? _safeBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return null;
  }

  Future<bool> _loadProductsFromSupabase() async {
    try {
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      final response = await supabase
          .from('products')
          .select('*')
          .order('category', ascending: true)
          .order('name', ascending: true);

      final List<Product> supabaseProducts = [];
      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            final product = _buildProductFromSupabaseRow(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
            );
            if (product != null) {
              supabaseProducts.add(product);
            }
          }
        }
      }

      _products = supabaseProducts;
      _products.sort((a, b) {
        final byCategory = a.category.compareTo(b.category);
        if (byCategory != 0) return byCategory;
        return a.name.compareTo(b.name);
      });
      
      // Set up real-time listener AFTER products are loaded
      // This ensures the listener is active and ready to receive updates
      _setupSupabaseProductsRealtimeListener();
      
      // Verify listener is set up
      debugPrint('📡 Products real-time listener setup initiated. Listener attached: $_productsRealtimeListenerAttached');

      if (_products.isNotEmpty) {
        debugPrint('Loaded ${_products.length} products from Supabase');
      } else {
        debugPrint('Supabase returned 0 products');
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('Error loading products from Supabase: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  Product? _buildProductFromSupabaseRow(Map<String, dynamic> row) {
    final productId = row['uid']?.toString() ?? row['id']?.toString() ?? '';
    if (productId.isEmpty) {
      return null;
    }

    final transformed = _transformSupabaseProduct(row);
    final baseProduct = Product.fromMap(transformed, productId);
    // Display availableQuantity directly (it's already decreased when orders are placed)
    // Don't subtract currentReserved as it's already accounted for in availableQuantity
    return baseProduct;
  }

  Product? _findProductLocally(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _transformSupabaseProduct(Map<String, dynamic> row) {
    // Determine availability: product is available only if both is_available is true AND status is 'active'
    // Handle null/undefined values: if is_available is null, check status; if status is null, default to 'active'
    final isAvailableFromDb = row['is_available'];
    final statusFromDb = (row['status']?.toString().toLowerCase() ?? 'active');
    final isAvailable = (isAvailableFromDb == true || isAvailableFromDb == 'true') && statusFromDb == 'active';
    
    final transformed = <String, dynamic>{
      'name': row['name'] ?? '',
      'description': row['description'] ?? '',
      'category': row['category'] ?? '',
      'price': _safeDouble(row['price']),
      'unit': row['unit'] ?? 'kg',
      'farmerId': row['farmer_id']?.toString() ?? '',
      'farmerName': row['farmer_name']?.toString() ?? '',
      'imageUrl': row['image_url'] ?? '',
      'imageUrls': _stringListFrom(row['image_urls']),
      'videoUrl': row['video_url'] ?? '',
      'videoUrls': _stringListFrom(row['video_urls']),
      'availableQuantity': _safeInt(row['available_quantity']) ?? _safeInt(row['quantity']) ?? 0,
      'quantity': _safeInt(row['quantity']),
      'currentReserved': _safeInt(row['current_reserved']) ?? 0,
      'soldQuantity': _safeInt(row['sold_quantity']),
      'harvestDate': _parseSupabaseDateToMillis(row['harvest_date']),
      'createdAt': _safeInt(row['created_at']) ?? DateTime.now().millisecondsSinceEpoch,
      'updatedAt': _safeInt(row['updated_at']) ?? DateTime.now().millisecondsSinceEpoch,
      'isAvailable': isAvailable,
      'status': row['status'] ?? 'active',
      'rating': _safeDouble(row['rating']),
      'reviewCount': _safeInt(row['review_count']) ?? 0,
      'tags': _stringListFrom(row['tags']),
      'location': row['location'] ?? '',
    };

    transformed.removeWhere((key, value) => value == null);
    return transformed;
  }

  List<String> _stringListFrom(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e == null ? null : e.toString())
          .whereType<String>()
          .where((element) => element.isNotEmpty)
          .toList();
    }
    return [];
  }

  int? _parseSupabaseDateToMillis(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return parsedInt;
      }
      final parsedDate = DateTime.tryParse(value);
      return parsedDate?.millisecondsSinceEpoch;
    }
    return null;
  }

  int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  // Set up Supabase real-time listener for products
  void _setupSupabaseProductsRealtimeListener() {
    // Always set up the listener, even if already attached (to handle reconnection)
    // But skip if we're already in the process of setting it up
    if (_productsRealtimeListenerAttached && _productsRealtimeChannel != null) {
      // Check if channel is still subscribed
      debugPrint('⚠️ Products real-time listener already attached, checking subscription status...');
      // Don't return - allow reconnection if needed
    }
    
    // Reset flag to allow reconnection
    _productsRealtimeListenerAttached = true;

    try {
      SupabaseService.initialize().then((_) async {
        final supabase = SupabaseService.client;
        
        // Unsubscribe from previous channel if exists
        if (_productsRealtimeChannel != null) {
          await _productsRealtimeChannel!.unsubscribe();
          _productsRealtimeChannel = null;
        }
        
        debugPrint('🔔 Setting up Supabase real-time listener for products...');
        
        _productsRealtimeChannel = supabase
            .channel('products_changes_${DateTime.now().millisecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'products',
              callback: (payload) {
                final productId = payload.newRecord['uid']?.toString() ?? payload.newRecord['id']?.toString() ?? 'unknown';
                final isAvailable = payload.newRecord['is_available'] ?? true;
                final status = payload.newRecord['status']?.toString() ?? 'active';
                final availableQuantity = payload.newRecord['available_quantity'] ?? payload.newRecord['quantity'] ?? 0;
                debugPrint('🔄 Product updated in real-time: $productId (is_available: $isAvailable, status: $status, qty: $availableQuantity)');
                _handleProductUpdate(payload.newRecord as Map<String, dynamic>);
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'products',
              callback: (payload) {
                debugPrint('➕ Product added in real-time: ${payload.newRecord['uid']}');
                _handleProductInsert(payload.newRecord as Map<String, dynamic>);
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: 'products',
              callback: (payload) {
                debugPrint('➖ Product deleted in real-time: ${payload.oldRecord['uid']}');
                _handleProductDelete(payload.oldRecord as Map<String, dynamic>);
              },
            )
            .subscribe(
              (status, [error]) {
                if (status == RealtimeSubscribeStatus.subscribed) {
                  debugPrint('✅ Products real-time subscription ACTIVE - listening for changes');
                } else if (status == RealtimeSubscribeStatus.timedOut) {
                  debugPrint('⏱️ Products real-time subscription TIMED OUT - will retry');
                  _productsRealtimeListenerAttached = false;
                  // Retry after 3 seconds
                  Future.delayed(const Duration(seconds: 3), () {
                    if (!_productsRealtimeListenerAttached) {
                      _setupSupabaseProductsRealtimeListener();
                    }
                  });
                } else if (status == RealtimeSubscribeStatus.channelError) {
                  debugPrint('❌ Products real-time subscription ERROR: $error - will retry');
                  _productsRealtimeListenerAttached = false;
                  // Retry after 3 seconds
                  Future.delayed(const Duration(seconds: 3), () {
                    if (!_productsRealtimeListenerAttached) {
                      _setupSupabaseProductsRealtimeListener();
                    }
                  });
                } else {
                  debugPrint('⚠️ Products real-time subscription status: $status');
                }
              },
            );
        
        debugPrint('✅ Supabase real-time listener for products subscription initiated');
      }).catchError((e, stackTrace) {
        debugPrint('❌ Error setting up Supabase real-time listener: $e');
        debugPrint('❌ Stack trace: $stackTrace');
        _productsRealtimeListenerAttached = false;
        // Retry after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (!_productsRealtimeListenerAttached) {
            _setupSupabaseProductsRealtimeListener();
          }
        });
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing Supabase real-time listener: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      _productsRealtimeListenerAttached = false;
    }
  }

  // Handle product update from real-time
  void _handleProductUpdate(Map<String, dynamic> row) {
    try {
      final productId = row['uid']?.toString() ?? row['id']?.toString() ?? '';
      if (productId.isEmpty) return;

      // Get the old product before updating to compare changes
      final oldProductIndex = _products.indexWhere((p) => p.id == productId);
      final oldProduct = oldProductIndex != -1 ? _products[oldProductIndex] : null;
      final oldIsAvailable = oldProduct?.isAvailable ?? true;
      final oldAvailableQuantity = oldProduct?.availableQuantity ?? 0;

      final transformed = _transformSupabaseProduct(row);
      final updatedProduct = Product.fromMap(transformed, productId);
      
      // Display availableQuantity directly (it's already decreased when orders are placed)
      // Don't subtract currentReserved as it's already accounted for in availableQuantity
      final product = updatedProduct;

      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        final newIsAvailable = product.isAvailable;
        final newAvailableQuantity = product.availableQuantity;
        
        // Log availability changes for debugging
        if (oldIsAvailable != newIsAvailable) {
          debugPrint('🔄 Product $productId availability changed: ${oldIsAvailable ? "Available" : "Unavailable"} → ${newIsAvailable ? "Available" : "Unavailable"}');
        }
        if (oldAvailableQuantity != newAvailableQuantity) {
          debugPrint('🔄 Product $productId quantity changed: $oldAvailableQuantity → $newAvailableQuantity');
        }
        
        _products[index] = product;
        _products.sort((a, b) {
          final byCategory = a.category.compareTo(b.category);
          if (byCategory != 0) return byCategory;
          return a.name.compareTo(b.name);
        });
        
        // CRITICAL: Notify listeners to update UI immediately
        notifyListeners();
        debugPrint('✅ Updated product $productId in local list (isAvailable: $newIsAvailable, available qty: $newAvailableQuantity)');
      } else {
        // Product not found in local list - might be a new product, add it
        _products.add(product);
        _products.sort((a, b) {
          final byCategory = a.category.compareTo(b.category);
          if (byCategory != 0) return byCategory;
          return a.name.compareTo(b.name);
        });
        notifyListeners();
        debugPrint('✅ Added product $productId to local list (was not found, treating as new)');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error handling product update: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
  }

  // Handle product insert from real-time
  void _handleProductInsert(Map<String, dynamic> row) {
    try {
      final product = _buildProductFromSupabaseRow(row);
      if (product != null && !_products.any((p) => p.id == product.id)) {
        _products.add(product);
        _products.sort((a, b) {
          final byCategory = a.category.compareTo(b.category);
          if (byCategory != 0) return byCategory;
          return a.name.compareTo(b.name);
        });
        notifyListeners();
        debugPrint('✅ Added new product ${product.id} to local list');
      }
    } catch (e) {
      debugPrint('Error handling product insert: $e');
    }
  }

  // Handle product delete from real-time
  void _handleProductDelete(Map<String, dynamic> row) {
    try {
      final productId = row['uid']?.toString() ?? row['id']?.toString() ?? '';
      if (productId.isEmpty) return;

      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        _products.removeAt(index);
        notifyListeners();
        debugPrint('✅ Removed product $productId from local list');
      }
    } catch (e) {
      debugPrint('Error handling product delete: $e');
    }
  }





  void _recomputeProductAvailability(String productId, Product baseProduct, {bool insertIfMissing = false}) async {
    try {
      // Display availableQuantity directly (it's already decreased when orders are placed)
      // Don't subtract currentReserved as it's already accounted for in availableQuantity
      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        _products[index] = baseProduct;
      } else if (insertIfMissing) {
        _products.add(baseProduct);
      }
      _products.sort((a, b) {
        final byCategory = a.category.compareTo(b.category);
        if (byCategory != 0) return byCategory;
        return a.name.compareTo(b.name);
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error recomputing reservations for $productId: $e');
    }
  }

  // Load all orders from Supabase to calculate weekly top products
  // This loads ALL orders (not just for current customer) to get global top products
  // Cumulative count (never resets) - matches web dashboard behavior
  Future<void> loadTopProducts() async {
    try {
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      // Fetch ALL orders from Supabase (cumulative, not just current week)
      final response = await supabase
          .from('orders')
          .select();
      
      _productSalesCount.clear();
      
      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            try {
              final orderMap = Map<String, dynamic>.from(item as Map);
              final status = (orderMap['status'] ?? '').toString().toLowerCase();
              final paymentMethod = (orderMap['payment_method'] ?? orderMap['paymentMethod'] ?? '').toString().toLowerCase();
              
              // Exclude ALL cancelled orders (GCash/Cash) - regardless of refund status
              if (status == 'cancelled') {
                continue;
              }
              
              // Exclude ALL rejected orders (GCash/Cash)
              if (status == 'rejected') {
                continue;
              }
              
              // Exclude orders with any cancellation flags
              final hasCancellationRequested = orderMap['cancellation_requested'] == true ||
                                               orderMap['cancellationRequested'] == true;
              final hasCancellationConfirmed = orderMap['cancellation_confirmed'] == true ||
                                               orderMap['cancellationConfirmed'] == true;
              final hasRefundConfirmed = orderMap['refund_confirmed_at'] != null ||
                                        orderMap['refundConfirmedAt'] != null;
              
              if (hasCancellationRequested || hasCancellationConfirmed || hasRefundConfirmed) {
                continue;
              }
              
              // Exclude failed cash orders (only failed GCash orders are included)
              if (status == 'failed' && paymentMethod != 'gcash') {
                continue;
              }
              
              // Count orders with these statuses:
              // - pending, confirmed, to_receive, out_for_delivery, pickup_ready
              // - delivered, picked_up
              // - failed (but only if it's a GCash order)
              final validStatuses = [
                'pending',
                'confirmed',
                'to_receive',
                'out_for_delivery',
                'pickup_ready',
                'ready_to_pickup',
                'delivered',
                'picked_up'
              ];
              
              final isFailedGcash = status == 'failed' && paymentMethod == 'gcash';
              final isValidStatus = validStatuses.contains(status);
              
              // Skip if not a valid status and not a failed GCash order
              if (!isValidStatus && !isFailedGcash) {
                continue;
              }
              
              // Parse items
              final items = orderMap['items'];
              if (items is List) {
                for (final it in items) {
                  if (it is Map) {
                    final itemMap = Map<String, dynamic>.from(it as Map);
                    final productId = (itemMap['productId'] ?? itemMap['product_id'] ?? '').toString();
                    if (productId.isEmpty) continue;
                    
                    final qty = (itemMap['quantity'] ?? 0);
                    final quantity = (qty is num) ? qty.toDouble() : 0.0;
                    final unit = (itemMap['unit'] ?? '').toString().toLowerCase();
                    
                    // Only count items with unit "kg" (matching web dashboard)
                    if (quantity > 0 && unit == 'kg') {
                      final q = quantity.toInt();
                      _productSalesCount.update(productId, (v) => v + q, ifAbsent: () => q);
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('Error processing order for top products: $e');
            }
          }
        }
      }
      
      debugPrint('✅ Loaded top products (cumulative): ${_productSalesCount.length} products');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading top products from Supabase: $e');
    }
  }

  void _ensureOrdersSalesRealtimeSubscribed() {
    if (_ordersSalesRealtimeChannel != null) return;
    try {
      SupabaseService.initialize();
      final supabase = SupabaseService.client;
      _ordersSalesRealtimeChannel = supabase.channel('orders-sales-realtime');
      _ordersSalesRealtimeChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) async {
              debugPrint('🔄 Orders change detected for sales sync: ${payload.eventType}');
              await loadTopProducts();
            },
          )
          .subscribe();
      debugPrint('✅ Subscribed to orders realtime for sales count');
    } catch (e) {
      debugPrint('⚠️ Failed to subscribe to orders realtime sales updates: $e');
    }
  }

  // Note: Real-time listener removed - top products now calculated from loaded orders
  // and refreshed when orders are loaded. This ensures weekly calculation is always current.

  // Refresh orders (for real-time updates)
  Future<void> refreshOrders(String customerId) async {
    try {
      debugPrint('🔄 Refreshing orders for customer: $customerId');
      
      // First, load fresh data
      await loadOrders(customerId);
      
      // Then, sync each order's status individually to ensure accuracy
      for (final order in _orders) {
        await syncOrderStatus(order.id);
      }
      
      debugPrint('✅ Orders refreshed successfully: ${_orders.length} orders');
    } catch (e) {
      debugPrint('Error refreshing orders: $e');
    }
  }
  
  // Simple refresh method
  Future<void> forceRefreshOrders(String customerId) async {
    await loadOrders(customerId);
  }

  // Refresh products (for real-time updates)
  Future<void> refreshProducts() async {
    try {
      await loadProducts();
    } catch (e) {
      debugPrint('Error refreshing products: $e');
    }
  }

  // Customer marks order as received (delivered)
  Future<bool> markOrderReceived(String orderId) async {
    try {
      await _database.child('orders/$orderId').update({
        'status': 'delivered',
        'deliveredAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

      // Update local list
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        _orders[idx] = _orders[idx].copyWith(status: 'delivered');
        notifyListeners();

        // Staff dashboard also sends an 'order_received' notification; avoid duplicate client-side notification
      }
      return true;
    } catch (e) {
      debugPrint('Error marking order received: $e');
      return false;
    }
  }

  // Load favorite products
  Future<void> loadFavoriteProducts(List<String> productIds) async {
    try {
      if (productIds.isEmpty) {
        _favoriteProducts = [];
        notifyListeners();
        return;
      }

      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      final response = await supabase
          .from('products')
          .select('*')
          .inFilter('uid', productIds);

      final favorites = <Product>[];
      if (response is List) {
        for (final item in response) {
          if (item is Map) {
            final product = _buildProductFromSupabaseRow(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
            );
            if (product != null && product.isAvailable) {
              favorites.add(product);
            }
          }
        }
      }

      final favoritesById = {
        for (final product in favorites) product.id: product,
      };

      final orderedFavorites = <Product>[];
      for (final id in productIds) {
        final supabaseProduct = favoritesById[id];
        if (supabaseProduct != null) {
          orderedFavorites.add(supabaseProduct);
          continue;
        }

        final localProduct = _findProductLocally(id);
        if (localProduct != null) {
          orderedFavorites.add(localProduct);
        }
      }

      _favoriteProducts = orderedFavorites.isEmpty ? favorites : orderedFavorites;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading favorite products: $e');
    }
  }

  // Add product to favorites
  Future<void> addToFavorites(String customerId, String productId) async {
    try {
      final customerRef = _database.child('customers/$customerId');
      final snapshot = await customerRef.child('favoriteProducts').get();
      
      List<String> favorites = [];
      if (snapshot.exists) {
        favorites = List<String>.from(snapshot.value as List);
      }
      
      if (!favorites.contains(productId)) {
        favorites.add(productId);
        await customerRef.child('favoriteProducts').set(favorites);
        
        // Reload favorite products
        await loadFavoriteProducts(favorites);
      }
    } catch (e) {
      debugPrint('Error adding to favorites: $e');
    }
  }

  // Remove product from favorites
  Future<void> removeFromFavorites(String customerId, String productId) async {
    try {
      final customerRef = _database.child('customers/$customerId');
      final snapshot = await customerRef.child('favoriteProducts').get();
      
      if (snapshot.exists) {
        List<String> favorites = List<String>.from(snapshot.value as List);
        favorites.remove(productId);
        await customerRef.child('favoriteProducts').set(favorites);
        
        // Reload favorite products
        await loadFavoriteProducts(favorites);
      }
    } catch (e) {
      debugPrint('Error removing from favorites: $e');
    }
  }

  // Place a new order
  Future<bool> placeOrder(Order order) async {
    try {
      debugPrint('🛒 Placing order for customer: ${order.customerId}');
      debugPrint('🛒 Order total: ${order.total}');
      debugPrint('🛒 Order items count: ${order.items.length}');
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Generate order ID (UUID format for Supabase)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (timestamp.hashCode % 1000000).abs().toString().padLeft(6, '0');
      final orderId = '$timestamp$random';

      // Build items payload
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      final itemsPayload = order.items.map((it) => {
            'productId': it.productId,
            'productName': it.productName,
            'farmerId': it.farmerId,
            'price': it.price,
            'quantity': it.quantity,
            'unit': it.unit,
          }).toList();

      // Save to Supabase (snake_case format)
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      // Convert to Supabase format (snake_case)
      final supabasePayload = <String, dynamic>{
        'uid': orderId, // Primary key - REQUIRED by Supabase orders table
        'id': orderId, // Also set id for compatibility
        'order_id': orderId, // Some tables use order_id as primary key
        'customer_id': order.customerId,
        'customer_name': order.customerName,
        'customer_phone': order.customerPhone,
        'customer_address': order.customerAddress,
        'subtotal': order.subtotal,
        'delivery_fee': order.deliveryFee,
        'total': order.total,
        'status': order.status,
        'payment_method': order.paymentMethod,
        'payment_status': order.paymentStatus,
        'delivery_option': order.deliveryOption,
        'order_date': order.orderDate.millisecondsSinceEpoch,
        'created_at': nowTs,
        'updated_at': nowTs,
        'items': itemsPayload,
        // Cancellation fields (defaults)
        'cancellation_requested': false,
      };
      
      // Conditionally add optional fields
      if (order.deliveryOption == 'delivery' && (order.deliveryAddress ?? order.customerAddress) != null) {
        supabasePayload['delivery_address'] = order.deliveryAddress ?? order.customerAddress;
      }
      
      // Add pickup fields only if it's a pickup order
      if (order.deliveryOption == 'pickup') {
        if (order.pickupAddress != null && order.pickupAddress!.isNotEmpty) {
          supabasePayload['pickup_address'] = order.pickupAddress;
        }
        if (order.pickupName != null && order.pickupName!.isNotEmpty) {
          supabasePayload['pickup_name'] = order.pickupName;
        }
        if (order.pickupStreet != null && order.pickupStreet!.isNotEmpty) {
          supabasePayload['pickup_street'] = order.pickupStreet;
        }
        if (order.pickupSitio != null && order.pickupSitio!.isNotEmpty) {
          supabasePayload['pickup_sitio'] = order.pickupSitio;
        }
        if (order.pickupBarangay != null && order.pickupBarangay!.isNotEmpty) {
          supabasePayload['pickup_barangay'] = order.pickupBarangay;
        }
        if (order.pickupCity != null && order.pickupCity!.isNotEmpty) {
          supabasePayload['pickup_city'] = order.pickupCity;
        }
        if (order.pickupProvince != null && order.pickupProvince!.isNotEmpty) {
          supabasePayload['pickup_province'] = order.pickupProvince;
        }
        if (order.pickupLandmark != null && order.pickupLandmark!.isNotEmpty) {
          supabasePayload['pickup_landmark'] = order.pickupLandmark;
        }
        if (order.pickupInstructions != null && order.pickupInstructions!.isNotEmpty) {
          supabasePayload['pickup_instructions'] = order.pickupInstructions;
        }
        if (order.pickupMapLink != null && order.pickupMapLink!.isNotEmpty) {
          supabasePayload['pickup_map_link'] = order.pickupMapLink;
        }
      }
      
      // Add GCash receipt URL if it exists
      if (order.gcashReceiptUrl != null && order.gcashReceiptUrl!.isNotEmpty) {
        supabasePayload['gcash_receipt_url'] = order.gcashReceiptUrl;
      }
      
      // Add farmer info if it exists
      if (order.farmerId.isNotEmpty) {
        supabasePayload['farmer_id'] = order.farmerId;
      }
      if (order.farmerName.isNotEmpty) {
        supabasePayload['farmer_name'] = order.farmerName;
      }
      
      // Add order notes if they exist
      if (order.deliveryNotes != null && order.deliveryNotes.isNotEmpty) {
        supabasePayload['order_notes'] = order.deliveryNotes;
      }
      
      debugPrint('📝 Inserting order to Supabase with ID: $orderId');
      final response = await supabase.from('orders').insert(supabasePayload).select();
      debugPrint('✅ Order saved to Supabase with ID: $orderId');
      debugPrint('📊 Insert response: $response');
      debugPrint('🔄 Moving to notification sending step...');

      // Stock adjustment on placement - always decrease base quantity
      // Update Supabase products only
      for (final it in order.items) {
        final productId = it.productId;
        final qty = it.quantity;
        
        try {
          await SupabaseService.initialize();
          final supabase = SupabaseService.client;
          
          // Get current product data from Supabase
          final supabaseResponse = await supabase
              .from('products')
              .select('*')
              .eq('uid', productId)
              .maybeSingle();
          
          if (supabaseResponse == null || supabaseResponse is! Map) {
            debugPrint('Product $productId not found in Supabase');
            continue;
          }
          
          final transformed = _transformSupabaseProduct(Map<String, dynamic>.from(supabaseResponse));
          final supabaseProduct = Product.fromMap(transformed, productId);
          
          final currentReserved = supabaseProduct.currentReserved ?? 0;
          final baseAvailable = supabaseProduct.availableQuantity;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          
          if (order.status.toLowerCase() == 'pending') {
            // For pending orders (GCash): decrease available_quantity AND increase current_reserved
            // This reserves the stock while deducting from available
            final newBase = (baseAvailable - qty) < 0 ? 0 : baseAvailable - qty;
            final newReserved = currentReserved + qty;
            await supabase
                .from('products')
                .update({
                  'available_quantity': newBase,
                  'current_reserved': newReserved,
                  'updated_at': nowMs,
                })
                .eq('uid', productId);
            debugPrint('✅ Updated Supabase product $productId (pending): available_quantity=$newBase (was $baseAvailable, -$qty), current_reserved=$newReserved (was $currentReserved, +$qty)');
          } else if (order.status.toLowerCase() == 'confirmed') {
            // For confirmed orders (Cash/COD): decrease base quantity directly
            // (For GCash that gets confirmed, available_quantity already decreased on placement, so only decrease reserved)
            final newBase = (baseAvailable - qty) < 0 ? 0 : baseAvailable - qty;
            await supabase
                .from('products')
                .update({
                  'available_quantity': newBase,
                  'updated_at': nowMs,
                })
                .eq('uid', productId);
            debugPrint('✅ Updated Supabase product $productId (confirmed): available_quantity=$newBase (was $baseAvailable, -$qty)');
          }
        } catch (e) {
          debugPrint('Error updating Supabase product $productId: $e');
        }
      }

      // Update customer's total orders and spent amount in Supabase only
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        
        // Get current customer data from Supabase
        final customerResponse = await supabase
            .from('customers')
            .select('total_orders, total_spent')
            .eq('uid', order.customerId)
            .maybeSingle();
        
        if (customerResponse != null) {
          final currentSupabaseTotalOrders = customerResponse['total_orders'] ?? 0;
          final currentSupabaseTotalSpent = (customerResponse['total_spent'] ?? 0.0).toDouble();
          
          // Update with cumulative values
          await SupabaseService.updateCustomer(order.customerId, {
            'totalOrders': currentSupabaseTotalOrders + 1,
            'totalSpent': currentSupabaseTotalSpent + order.total,
          });
          debugPrint('✅ Updated customer stats in Supabase: totalOrders=${currentSupabaseTotalOrders + 1}, totalSpent=${currentSupabaseTotalSpent + order.total}');
        }
      } catch (e) {
        debugPrint('⚠️ Error updating customer stats in Supabase: $e');
        // Don't fail the order placement if Supabase update fails
      }

      // Add order to local list with proper timestamps
      _orders.insert(0, order.copyWith(
        id: orderId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(nowTs),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(nowTs),
      ));
      debugPrint('✅ Order added to local list. Total orders now: ${_orders.length}');

      // Save orders to local storage immediately after placing order
      try {
        await saveOrdersToStorage(_currentCustomerId);
        debugPrint('✅ Orders saved to local storage');
      } catch (e) {
        debugPrint('⚠️ Error saving orders to storage: $e (continuing anyway)');
      }

      // Send notification to customer about successful order placement
      // IMPORTANT: Do this in a separate try-catch to ensure it doesn't block order completion
      debugPrint('🔔 ===== STARTING NOTIFICATION PROCESS =====');
      debugPrint('🔔 About to send order placed notification...');
      debugPrint('🔔 Order ID: $orderId');
      debugPrint('🔔 Order customerId: ${order.customerId}');
      debugPrint('🔔 Order customerId type: ${order.customerId.runtimeType}');
      debugPrint('🔔 Order customerId empty?: ${order.customerId.isEmpty}');
      debugPrint('🔔 Current customer ID: $_currentCustomerId');
      
      // Send notification regardless - let it fail gracefully if needed
      if (order.customerId.isEmpty || order.customerId.trim().isEmpty) {
        debugPrint('❌ ERROR: Order customerId is empty! Cannot send notification.');
        debugPrint('❌ Order object customerId value: "${order.customerId}"');
      } else {
        try {
          debugPrint('🔔 Calling _sendOrderPlacedNotification...');
          await _sendOrderPlacedNotification(orderId, order);
          debugPrint('✅ Order placed notification sent successfully');
        } catch (e, stackTrace) {
          debugPrint('❌ CRITICAL ERROR sending order placed notification: $e');
          debugPrint('❌ Error type: ${e.runtimeType}');
          debugPrint('❌ Error message: ${e.toString()}');
          debugPrint('❌ Stack trace: $stackTrace');
          // Log the full error details for debugging
          if (e.toString().contains('permission') || e.toString().contains('policy') || e.toString().contains('RLS')) {
            debugPrint('❌ RLS POLICY ERROR DETECTED!');
            debugPrint('❌ You need to run the SQL policy fix: FIX_NOTIFICATION_INSERT_POLICY.sql');
            debugPrint('❌ Error suggests Row Level Security policy is blocking the insert');
          }
          // Don't fail the order placement if notification fails
        }
      }
      debugPrint('🔔 ===== NOTIFICATION PROCESS COMPLETED =====');

      // Clear cart after successful order placement
      clearCart();

      return true;
    } catch (e) {
      _error = 'Failed to place order: $e';
      debugPrint('Error placing order: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Send notification when order is placed
  Future<void> _sendOrderPlacedNotification(String orderId, Order order) async {
    try {
      debugPrint('📧 Starting to send order placed notification...');
      debugPrint('📧 Order ID: $orderId');
      debugPrint('📧 Customer ID: ${order.customerId}');
      
      final now = DateTime.now();
      final hour = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
      final amPm = now.hour < 12 ? 'AM' : 'PM';
      final formattedDateTime = '${now.month}/${now.day}/${now.year} at $hour:${now.minute.toString().padLeft(2, '0')} $amPm';
      
      // Determine notification message based on payment method
      final paymentMethod = (order.paymentMethod ?? '').toString().toLowerCase();
      String notificationMessage;
      
      // Check for COD payment methods (cash, cod, cash_on_delivery, cash on delivery)
      final orderCode = _formatOrderCode(orderId);
      if (paymentMethod == 'cash' || 
          paymentMethod == 'cod' || 
          paymentMethod == 'cash_on_delivery' || 
          paymentMethod == 'cash on delivery') {
        // COD orders are automatically confirmed - include delivery schedule
        notificationMessage = 'Order placed successfully on $formattedDateTime. Order Code: #$orderCode. Your order has been confirmed. Please be patient with the delivery time, which is scheduled every Saturday or Sunday, and regularly check the status under the Orders section.';
      } else {
        // GCash orders - wait for confirmation
        notificationMessage = 'Order placed successfully on $formattedDateTime. Order Code: #$orderCode. Please wait for your order confirmation and check the status under the Orders section.';
      }
      
      // Create notification object with unique ID
      // Generate a proper UUID format that works with both TEXT and UUID columns
      final notificationId = _generateNotificationUuid();
      final notification = CustomerNotification(
        id: notificationId,
        title: 'Order Placed Successfully',
        message: notificationMessage,
        type: 'order_placed',
        timestamp: now,
        isRead: false,
        orderId: orderId,
      );

      debugPrint('📧 Notification object created:');
      debugPrint('  - ID: ${notification.id}');
      debugPrint('  - Title: ${notification.title}');
      debugPrint('  - Message: ${notification.message}');
      debugPrint('  - Type: ${notification.type}');
      debugPrint('  - Timestamp: ${notification.timestamp}');
      debugPrint('  - Timestamp (ms): ${notification.timestamp.millisecondsSinceEpoch}');
      debugPrint('  - Order ID: ${notification.orderId}');

      // Send notification to Supabase
      await NotificationService.sendNotification(order.customerId, notification);
      debugPrint('✅ Notification successfully sent to Supabase');
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending order placed notification: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      rethrow; // Re-throw to let caller handle
    }
  }

  // Client no longer sends generic phase notifications; staff dashboard handles these.

  // Generate UUID v4 for notification IDs
  String _generateNotificationUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    String _byteToHex(int byte) =>
        byte.toRadixString(16).padLeft(2, '0');
    return '${_byteToHex(bytes[0])}${_byteToHex(bytes[1])}${_byteToHex(bytes[2])}${_byteToHex(bytes[3])}-'
        '${_byteToHex(bytes[4])}${_byteToHex(bytes[5])}-'
        '${_byteToHex(bytes[6])}${_byteToHex(bytes[7])}-'
        '${_byteToHex(bytes[8])}${_byteToHex(bytes[9])}-'
        '${_byteToHex(bytes[10])}${_byteToHex(bytes[11])}${_byteToHex(bytes[12])}${_byteToHex(bytes[13])}${_byteToHex(bytes[14])}${_byteToHex(bytes[15])}';
  }

  // Cart operations
  void addToCart(Product product, {int quantity = 1}) {
    final existingIndex = _cartItems.indexWhere((i) => i.productId == product.id);
    final available = product.availableQuantity;

    if (existingIndex >= 0) {
      final existing = _cartItems[existingIndex];
      final desired = existing.quantity + quantity;
      final clamped = desired > available ? available : desired;
      _cartItems[existingIndex] = OrderItem(
        productId: existing.productId,
        productName: existing.productName,
        productImage: existing.productImage,
        price: existing.price,
        quantity: clamped,
        unit: existing.unit,
        total: clamped * existing.price,
        farmerId: existing.farmerId,
      );
    } else {
      final clamped = quantity > available ? available : quantity;
      if (clamped <= 0) return;
      _cartItems.add(OrderItem(
        productId: product.id,
        productName: product.name,
        productImage: product.imageUrl,
        price: product.price,
        quantity: clamped,
        unit: product.unit,
        total: product.price * clamped,
        farmerId: product.farmerId,
      ));
    }
    _saveCartToStorage(_currentCustomerId);
    notifyListeners();
  }

  // Start a one-off Buy Now flow (does not touch cart)
  void startBuyNow(Product product, {int quantity = 1}) {
    final clamped = quantity > product.availableQuantity ? product.availableQuantity : quantity;
    if (clamped <= 0) return;
    _buyNowItems = [
      OrderItem(
        productId: product.id,
        productName: product.name,
        productImage: product.imageUrl,
        price: product.price,
        quantity: clamped,
        unit: product.unit,
        total: product.price * clamped,
        farmerId: product.farmerId,
      ),
    ];
    _checkoutSource = 'buy_now';
    notifyListeners();
  }

  void clearBuyNow() {
    _buyNowItems = null;
    _checkoutSource = 'none';
    notifyListeners();
  }

  // Start checkout using a selection from the cart without altering the cart yet
  void startCheckoutWithSelected(List<OrderItem> selectedItems) {
    _buyNowItems = selectedItems.map((it) => OrderItem(
      productId: it.productId,
      productName: it.productName,
      productImage: it.productImage,
      price: it.price,
      quantity: it.quantity,
      unit: it.unit,
      total: it.total,
      farmerId: it.farmerId,
    )).toList();
    _checkoutSource = 'cart_selection';
    notifyListeners();
  }

  // Remove multiple items from cart by productId
  void removeItemsFromCartByProductIds(List<String> productIds) {
    _cartItems.removeWhere((item) => productIds.contains(item.productId));
    _saveCartToStorage(_currentCustomerId);
    notifyListeners();
  }

  void removeFromCart(String productId) {
    _cartItems.removeWhere((item) => item.productId == productId);
    _saveCartToStorage(_currentCustomerId);
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    _saveCartToStorage(_currentCustomerId);
    notifyListeners();
  }

  void updateCartItemQuantity(String productId, int newQuantity) {
    final index = _cartItems.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      if (newQuantity <= 0) {
        _cartItems.removeAt(index);
      } else {
        final item = _cartItems[index];
        // Clamp to available shown quantity
        final product = getProductById(productId);
        final available = product?.availableQuantity ?? newQuantity;
        final clamped = newQuantity > available ? available : newQuantity;
        _cartItems[index] = OrderItem(
          productId: item.productId,
          productName: item.productName,
          productImage: item.productImage,
          price: item.price,
          quantity: clamped,
          unit: item.unit,
          total: item.price * clamped,
          farmerId: item.farmerId,
        );
      }
      _saveCartToStorage();
      notifyListeners();
    }
  }

  // Save cart to local storage (customer-specific)
  Future<void> _saveCartToStorage([String? customerId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartData = _cartItems.map((item) => {
        'productId': item.productId,
        'productName': item.productName,
        'productImage': item.productImage,
        'price': item.price,
        'quantity': item.quantity,
        'unit': item.unit,
        'total': item.total,
        'farmerId': item.farmerId,
      }).toList();
      
      final storageKey = customerId != null ? 'cart_items_$customerId' : 'cart_items';
      await prefs.setString(storageKey, jsonEncode(cartData));
      debugPrint('💾 Saved ${_cartItems.length} cart items to local storage for customer: $customerId');
    } catch (e) {
      debugPrint('Error saving cart to storage: $e');
    }
  }

  // Load cart from local storage (customer-specific)
  Future<void> loadCartFromStorage([String? customerId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = customerId != null ? 'cart_items_$customerId' : 'cart_items';
      final cartJson = prefs.getString(storageKey);
      
      if (cartJson != null) {
        final cartData = jsonDecode(cartJson) as List;
        _cartItems.clear();
        _cartItems.addAll(cartData.map((item) => OrderItem(
          productId: item['productId'],
          productName: item['productName'],
          productImage: item['productImage'] ?? '',
          price: (item['price'] ?? 0.0).toDouble(),
          quantity: item['quantity'] ?? 1,
          unit: item['unit'] ?? 'kg',
          total: (item['total'] ?? 0.0).toDouble(),
          farmerId: item['farmerId'] ?? '',
        )));
        debugPrint('📦 Loaded ${_cartItems.length} cart items from local storage for customer: $customerId');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading cart from storage: $e');
    }
  }

  // Save orders to local storage for persistence (customer-specific)
  Future<void> saveOrdersToStorage([String? customerId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordersData = _orders.map((order) => order.toMap()).toList();
      final storageKey = customerId != null ? 'customer_orders_$customerId' : 'customer_orders';
      await prefs.setString(storageKey, jsonEncode(ordersData));
      debugPrint('💾 Saved ${_orders.length} orders to local storage for customer: $customerId');
    } catch (e) {
      debugPrint('Error saving orders to storage: $e');
    }
  }

  // Load orders from local storage (customer-specific)
  Future<void> loadOrdersFromStorage([String? customerId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storageKey = customerId != null ? 'customer_orders_$customerId' : 'customer_orders';
      final ordersJson = prefs.getString(storageKey);
      
      if (ordersJson != null) {
        final dynamic decodedData = jsonDecode(ordersJson);
        
        if (decodedData is List) {
          final ordersData = decodedData as List;
          _orders.clear();
          
          for (final orderData in ordersData) {
            try {
              if (orderData is Map) {
                final orderMap = Map<String, dynamic>.from(orderData as Map<dynamic, dynamic>);
                
                // Fix items field type casting if it exists
                if (orderMap['items'] != null && orderMap['items'] is List) {
                  final itemsList = orderMap['items'] as List;
                  final fixedItems = itemsList.map((item) {
                    if (item is Map) {
                      return Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
                    }
                    return item;
                  }).toList();
                  orderMap['items'] = fixedItems;
                }
                
                final order = Order.fromMap(orderMap, orderMap['id'] ?? '');
                _orders.add(order);
              }
            } catch (e) {
              debugPrint('❌ Error loading order from storage: $e');
              debugPrint('Order data: $orderData');
            }
          }
          
          // Sort orders by creation date (newest first)
          _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          debugPrint('📦 Loaded ${_orders.length} orders from local storage for customer: $customerId');
          notifyListeners();
        } else {
          debugPrint('❌ Local storage data is not a List: ${decodedData.runtimeType}');
        }
      } else {
        debugPrint('📭 No orders found in local storage for customer: $customerId');
      }
    } catch (e) {
      debugPrint('❌ Error loading orders from storage: $e');
    }
  }

  // Submit product ratings and comments for a delivered order
  Future<bool> submitRatings({
    required String orderId,
    required Map<String, int> ratings, // productId -> 1..5
    required Map<String, String> comments, // productId -> comment
  }) async {
    try {
      final updates = <String, dynamic>{};
      ratings.forEach((productId, rating) {
        final comment = comments[productId] ?? '';
        final reviewId = _database.child('reviews/$productId').push().key!;
        updates['reviews/$productId/$reviewId'] = {
          'rating': rating,
          'comment': comment,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };
      });
      // Mark order as rated
      updates['orders/$orderId/ratedAt'] = DateTime.now().millisecondsSinceEpoch;
      await _database.update(updates);
      return true;
    } catch (e) {
      debugPrint('Error submitting ratings: $e');
      return false;
    }
  }

  // Submit order and rider ratings with optional media
  Future<bool> submitOrderRating({
    required String orderId,
    required int orderRating,
    required String orderComment,
    int? riderRating,
    String? riderComment,
    String? pickupExperienceComment,
    List<XFile>? mediaFiles,
  }) async {
    try {
      debugPrint('📝 Submitting rating for order: $orderId');
      
      // Initialize Supabase
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      
      // Upload media files to Supabase storage if provided
      List<String> mediaUrls = [];
      if (mediaFiles != null && mediaFiles.isNotEmpty) {
        debugPrint('📤 Uploading ${mediaFiles.length} media files...');
        
        for (int i = 0; i < mediaFiles.length; i++) {
          final file = mediaFiles[i];
          final fileName = 'order_${orderId}_${nowMs}_$i.${file.path.split('.').last}';
          
          try {
            final bytes = await file.readAsBytes();
            
            // Upload to rated_media bucket
            final uploadResult = await supabase.storage
                .from('rated_media')
                .uploadBinary(
                  fileName,
                  bytes,
                  fileOptions: FileOptions(
                    upsert: true,
                  ),
                );
            
            // Get public URL
            final publicUrl = supabase.storage
                .from('rated_media')
                .getPublicUrl(fileName);
            
            mediaUrls.add(publicUrl);
            debugPrint('✅ Uploaded media file $i: $fileName');
          } catch (e) {
            debugPrint('⚠️ Failed to upload media file $i: $e');
            // Continue with other files even if one fails
          }
        }
      }
      
      // Update order in Supabase with rating data
      final updateData = {
        'order_rating': orderRating,
        'order_comment': orderComment.isNotEmpty ? orderComment : null,
        'order_media': mediaUrls.isNotEmpty ? jsonEncode(mediaUrls) : null,
        'order_rated_at': nowMs,
        'is_rated': true,
        'updated_at': nowMs,
      };
      
      // Add rider feedback for delivery orders
      if (riderRating != null) {
        updateData['rider_rating'] = riderRating;
        updateData['rider_comment'] = riderComment?.isNotEmpty == true ? riderComment : null;
        updateData['rider_rated_at'] = nowMs;
      }
      
      // Add pickup experience for pickup orders
      if (pickupExperienceComment != null && pickupExperienceComment.isNotEmpty) {
        updateData['pickup_experience_comment'] = pickupExperienceComment;
        updateData['pickup_experience_rated_at'] = nowMs;
      }
      
      await supabase
          .from('orders')
          .update(updateData)
          .eq('id', orderId);
      
      debugPrint('✅ Successfully submitted rating for order: $orderId');
      
      // CRITICAL: Update local order immediately so UI reflects the change right away
      // This prevents glitching where rating button disappears and reappears
      final orderIndex = _orders.indexWhere((o) => o.id == orderId);
      if (orderIndex != -1) {
        final existingOrder = _orders[orderIndex];
        _orders[orderIndex] = existingOrder.copyWith(
          isRated: true,
          orderRating: orderRating,
          orderComment: orderComment.isNotEmpty ? orderComment : existingOrder.orderComment,
          orderMedia: mediaUrls.isNotEmpty ? mediaUrls : existingOrder.orderMedia,
          orderRatedAt: DateTime.fromMillisecondsSinceEpoch(nowMs),
          riderRating: riderRating ?? existingOrder.riderRating,
          riderComment: riderComment?.isNotEmpty == true ? riderComment : existingOrder.riderComment,
          riderRatedAt: riderRating != null ? DateTime.fromMillisecondsSinceEpoch(nowMs) : existingOrder.riderRatedAt,
          pickupExperienceComment: pickupExperienceComment?.isNotEmpty == true ? pickupExperienceComment : existingOrder.pickupExperienceComment,
          pickupExperienceRatedAt: pickupExperienceComment?.isNotEmpty == true ? DateTime.fromMillisecondsSinceEpoch(nowMs) : existingOrder.pickupExperienceRatedAt,
        );
        notifyListeners(); // Notify immediately so UI updates
        debugPrint('✅ Updated local order with rating data immediately');
      }
      
      // Also refresh orders from Supabase to ensure we have the latest data
      // This happens in the background and won't cause glitching since we already updated locally
      if (_currentCustomerId != null) {
        loadOrders(_currentCustomerId!).catchError((e) {
          debugPrint('⚠️ Error refreshing orders after rating: $e');
        });
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ Error submitting order rating: $e');
      return false;
    }
  }

  // Cancel an order
  Future<bool> cancelOrder(String orderId, {String? reason}) async {
    try {
      // Load the order locally only (no Firebase read)
      Order? targetOrder = getOrderById(orderId);
      if (targetOrder == null) {
        debugPrint('cancelOrder: order $orderId not found locally');
        return false;
      }

      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final wasPending = targetOrder.status.toLowerCase() == 'pending';
      final wasConfirmed = targetOrder.status.toLowerCase() == 'confirmed';
      final paymentMethodLower = (targetOrder.paymentMethod).toString().toLowerCase();

      // Update local order first
      final orderIndex = _orders.indexWhere((order) => order.id == orderId);
      if (orderIndex == -1) {
        debugPrint('cancelOrder: order $orderId not found in local list');
        return false;
      }

      Order updatedOrder;
      Map<String, dynamic> supabaseUpdates = {
        'updated_at': nowMs,
      };

      if (wasPending || (wasConfirmed && paymentMethodLower == 'gcash')) {
        // For pending orders and GCash confirmed orders: record request and keep original status
        updatedOrder = _orders[orderIndex].copyWith(
          cancellationRequested: true,
          cancellationRequestedAt: now,
          cancellationReason: reason?.trim().isNotEmpty == true ? reason!.trim() : null,
          cancellationInitiatedBy: 'customer',
          updatedAt: now,
        );
        
        // Prepare Supabase update (snake_case)
        supabaseUpdates['cancellation_requested'] = true;
        supabaseUpdates['cancellation_requested_at'] = nowMs;
        supabaseUpdates['cancellation_initiated_by'] = 'customer';
        if (reason != null && reason.trim().isNotEmpty) {
          supabaseUpdates['cancellation_reason'] = reason.trim();
        }
      } else {
        // COD confirmed: cancel immediately
        updatedOrder = _orders[orderIndex].copyWith(
          status: 'cancelled',
          cancellationRequested: true,
          cancellationRequestedAt: now,
          cancellationReason: reason?.trim().isNotEmpty == true ? reason!.trim() : null,
          cancellationInitiatedBy: 'customer',
          updatedAt: now,
        );
        
        // Prepare Supabase update (snake_case)
        supabaseUpdates['status'] = 'cancelled';
        supabaseUpdates['cancellation_requested'] = true;
        supabaseUpdates['cancellation_requested_at'] = nowMs;
        supabaseUpdates['cancellation_initiated_by'] = 'customer';
        if (reason != null && reason.trim().isNotEmpty) {
          supabaseUpdates['cancellation_reason'] = reason.trim();
        }
        
        // Sync status to Firebase Realtime Database for push notifications
        try {
          final database = FirebaseDatabase.instance;
          // Get FCM token from Firebase Database (where it's stored)
          String? fcmToken;
          try {
            final customerRef = database.ref('customers/${targetOrder.customerId}/fcmToken');
            final tokenSnapshot = await customerRef.once();
            fcmToken = tokenSnapshot.snapshot.value?.toString();
          } catch (e) {
            debugPrint('⚠️ Could not fetch FCM token: $e');
          }
          
          // Write to order_status_updates table
          await database.ref('order_status_updates/$orderId').set({
            'fcmToken': fcmToken ?? '',
            'orderId': orderId,
            'customerId': targetOrder.customerId,
            'status': 'cancelled',
            'updatedAt': nowMs,
          });
          debugPrint('✅ Synced cancelled order status to Firebase Realtime Database');
        } catch (e) {
          debugPrint('⚠️ Failed to sync cancelled order status to Firebase: $e');
        }

        // Restore product quantities for Cash/COD cancelled orders
        // Since Cash/COD orders directly decrease available_quantity when placed,
        // we need to restore it when cancelled
        try {
          await SupabaseService.initialize();
          final supabase = SupabaseService.client;
          
          for (final item in targetOrder.items) {
            final productId = item.productId;
            final qty = item.quantity;
            
            try {
              // Get current product data from Supabase
              final supabaseResponse = await supabase
                  .from('products')
                  .select('*')
                  .eq('uid', productId)
                  .maybeSingle();
              
              if (supabaseResponse == null || supabaseResponse is! Map) {
                debugPrint('Product $productId not found in Supabase for cancellation');
                continue;
              }
              
              final transformed = _transformSupabaseProduct(Map<String, dynamic>.from(supabaseResponse));
              final supabaseProduct = Product.fromMap(transformed, productId);
              
              final currentAvailable = supabaseProduct.availableQuantity;
              final restoredAvailable = currentAvailable + qty;
              
              await supabase
                  .from('products')
                  .update({
                    'available_quantity': restoredAvailable,
                    'updated_at': nowMs,
                  })
                  .eq('uid', productId);
              
              debugPrint('✅ Restored product quantity for cancelled Cash/COD order: $productId available_quantity=$restoredAvailable (was $currentAvailable, +$qty)');
            } catch (e) {
              debugPrint('Error restoring product quantity for $productId: $e');
            }
          }
        } catch (e) {
          debugPrint('Error restoring product quantities for cancelled order: $e');
        }
      }

      // Write cancellation to Supabase
      try {
        await SupabaseService.initialize();
        final supabase = SupabaseService.client;
        
        // Update by matching either 'id' or 'order_id' column
        await supabase
            .from('orders')
            .update(supabaseUpdates)
            .or('id.eq.$orderId,order_id.eq.$orderId');
        
        debugPrint('✅ Cancellation written to Supabase for order: $orderId');
      } catch (e) {
        debugPrint('⚠️ Failed to write cancellation to Supabase: $e');
        // Continue even if Supabase write fails - local state is still updated
      }

      // Update local order
      _orders[orderIndex] = updatedOrder;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error cancelling order: $e');
      return false;
    }
  }

  // Search products
  List<Product> searchProducts(String query) {
    if (query.isEmpty) return _products;
    
    return _products.where((product) {
      return product.name.toLowerCase().contains(query.toLowerCase()) ||
             product.description.toLowerCase().contains(query.toLowerCase()) ||
             product.category.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }

  // Filter products by category
  List<Product> filterProductsByCategory(String category) {
    if (category.isEmpty) return _products;
    return _products.where((product) => product.category == category).toList();
  }

  // Get product categories
  List<String> getProductCategories() {
    final categories = _products.map((product) => product.category).toSet().toList();
    categories.sort();
    return categories;
  }

  // Get order by ID
  Order? getOrderById(String orderId) {
    try {
      return _orders.firstWhere((order) => order.id == orderId);
    } catch (e) {
      return null;
    }
  }

  // Get product by ID
  Product? getProductById(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  // Get sold quantity for a product from cumulative sales count (globally, in kg)
  int getSoldQuantity(String productId) {
    return _productSalesCount[productId] ?? 0;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Set current customer ID for persistence
  void setCurrentCustomerId(String customerId) {
    _currentCustomerId = customerId;
  }

  // Clear temporary data when user logs out (keep orders for persistence)
  void clearTemporaryData() {
    debugPrint('🧹 Clearing temporary data on logout (keeping orders)');
    _products.clear();
    _cartItems.clear();
    _favoriteProducts.clear();
    _productSalesCount.clear();
    _isLoading = false;
    _error = null;
    // DO NOT clear _orders - keep them for persistence
    notifyListeners();
  }

  // Clear all data when user logs out (including orders)
  void clearAllData() {
    debugPrint('🧹 Clearing all customer data on logout');
    _products.clear();
    _cartItems.clear();
    _orders.clear();
    _favoriteProducts.clear();
    _productSalesCount.clear();
    _isLoading = false;
    _error = null;
    _currentCustomerId = null;
    notifyListeners();
  }

  // Clear all local storage data for current customer
  Future<void> clearLocalStorageData([String? customerId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetCustomerId = customerId ?? _currentCustomerId;
      
      if (targetCustomerId != null) {
        // Clear customer-specific data
        await prefs.remove('customer_orders_$targetCustomerId');
        await prefs.remove('cart_items_$targetCustomerId');
        debugPrint('🧹 Cleared local storage for customer: $targetCustomerId');
      }
    } catch (e) {
      debugPrint('Error clearing local storage: $e');
    }
  }

  // Update orders from real-time listener
  void updateOrdersFromRealtime(List<Order> newOrders) {
    debugPrint('🔄 Updating orders from real-time listener: ${newOrders.length} orders');
    
    // Preserve local cancellation state when syncing from real-time
    final existingOrdersMap = {for (var order in _orders) order.id: order};
    final newOrderIds = newOrders.map((order) => order.id).toSet();
    final now = DateTime.now();
    
    // Merge: start with orders from real-time listener
    final List<Order> mergedOrders = newOrders.map<Order>((newOrder) {
      final existingOrder = existingOrdersMap[newOrder.id];
      
      if (existingOrder != null) {
        final existingStatus = existingOrder.status.toLowerCase();
        final newStatus = newOrder.status.toLowerCase();
        
        // CRITICAL: Preserve rating data if existing order has it and incoming order doesn't
        // This prevents rating data from being lost during real-time updates
        // Prefer incoming rating data (from Supabase) if it exists, otherwise preserve existing
        final existingHasRating = existingOrder.isRated == true || 
                                 existingOrder.orderRating != null || 
                                 existingOrder.orderRatedAt != null;
        final incomingHasRating = newOrder.isRated == true || 
                                newOrder.orderRating != null || 
                                newOrder.orderRatedAt != null;
        // Only preserve existing rating if incoming doesn't have it (incoming from Supabase is source of truth)
        final shouldPreserveRating = existingHasRating && !incomingHasRating;
        
        // CRITICAL: Prevent status regression (e.g., delivered → out_for_delivery)
        final isStatusRegression = !_canStatusProgress(existingStatus, newStatus);
        
        if (isStatusRegression) {
          debugPrint('⚠️ Preventing status regression in updateOrdersFromRealtime for order ${newOrder.id}: ${existingStatus} → ${newStatus}');
          // Keep existing status if it's more advanced, but update other fields
          return newOrder.copyWith(
            status: existingOrder.status, // Preserve the more advanced status
            // Preserve rating data if existing has it and incoming doesn't
            isRated: shouldPreserveRating ? existingOrder.isRated : newOrder.isRated,
            orderRating: shouldPreserveRating ? existingOrder.orderRating : newOrder.orderRating,
            orderComment: shouldPreserveRating ? existingOrder.orderComment : newOrder.orderComment,
            orderMedia: shouldPreserveRating ? existingOrder.orderMedia : newOrder.orderMedia,
            orderRatedAt: shouldPreserveRating ? existingOrder.orderRatedAt : newOrder.orderRatedAt,
            riderRating: shouldPreserveRating ? existingOrder.riderRating : newOrder.riderRating,
            riderComment: shouldPreserveRating ? existingOrder.riderComment : newOrder.riderComment,
            riderRatedAt: shouldPreserveRating ? existingOrder.riderRatedAt : newOrder.riderRatedAt,
            pickupExperienceComment: shouldPreserveRating ? existingOrder.pickupExperienceComment : newOrder.pickupExperienceComment,
            pickupExperienceRatedAt: shouldPreserveRating ? existingOrder.pickupExperienceRatedAt : newOrder.pickupExperienceRatedAt,
          );
        }
        
        // Preserve local cancellation state if it exists and database doesn't have it
        final shouldPreserveCancellation = existingOrder.cancellationRequested == true &&
            existingOrder.cancellationInitiatedBy == 'customer' &&
            (newOrder.cancellationRequested != true || 
             newOrder.cancellationInitiatedBy != 'customer');
        
        if (shouldPreserveCancellation || shouldPreserveRating) {
          // Merge: use database order but preserve local cancellation and/or rating fields
          return newOrder.copyWith(
            cancellationRequested: shouldPreserveCancellation ? existingOrder.cancellationRequested : newOrder.cancellationRequested,
            cancellationRequestedAt: shouldPreserveCancellation ? existingOrder.cancellationRequestedAt : newOrder.cancellationRequestedAt,
            cancellationReason: shouldPreserveCancellation ? existingOrder.cancellationReason : newOrder.cancellationReason,
            cancellationInitiatedBy: shouldPreserveCancellation ? existingOrder.cancellationInitiatedBy : newOrder.cancellationInitiatedBy,
            // Also preserve status if it was changed locally for cancellation
            status: existingOrder.status == 'cancelled' && newOrder.status != 'cancelled'
                ? existingOrder.status
                : newOrder.status,
            // Preserve rating data if existing has it and incoming doesn't
            isRated: shouldPreserveRating ? existingOrder.isRated : newOrder.isRated,
            orderRating: shouldPreserveRating ? existingOrder.orderRating : newOrder.orderRating,
            orderComment: shouldPreserveRating ? existingOrder.orderComment : newOrder.orderComment,
            orderMedia: shouldPreserveRating ? existingOrder.orderMedia : newOrder.orderMedia,
            orderRatedAt: shouldPreserveRating ? existingOrder.orderRatedAt : newOrder.orderRatedAt,
            riderRating: shouldPreserveRating ? existingOrder.riderRating : newOrder.riderRating,
            riderComment: shouldPreserveRating ? existingOrder.riderComment : newOrder.riderComment,
            riderRatedAt: shouldPreserveRating ? existingOrder.riderRatedAt : newOrder.riderRatedAt,
            pickupExperienceComment: shouldPreserveRating ? existingOrder.pickupExperienceComment : newOrder.pickupExperienceComment,
            pickupExperienceRatedAt: shouldPreserveRating ? existingOrder.pickupExperienceRatedAt : newOrder.pickupExperienceRatedAt,
          );
        }
      }
      
      return newOrder;
    }).toList();
    
    // Preserve local orders that aren't in real-time yet (newly placed orders)
    for (final existingOrder in _orders) {
      if (!newOrderIds.contains(existingOrder.id)) {
        // Check if it's a recent order (might not have synced yet)
        final orderAge = now.difference(existingOrder.createdAt);
        if (orderAge.inMinutes < 10) {
          debugPrint('💾 Preserving recent local order ${existingOrder.id} (not yet in Supabase, age: ${orderAge.inMinutes} minutes)');
          mergedOrders.add(existingOrder);
        } else {
          debugPrint('🗑️ Skipping stale local order ${existingOrder.id} (not in Supabase, older than 10 minutes)');
        }
      }
    }
    
    // Sort by creation date (newest first)
    mergedOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    _orders = mergedOrders;
    notifyListeners();
  }

  // Load delivery addresses for the current customer
  Future<void> loadDeliveryAddresses(String customerId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Load from Supabase
      final addressesData = await SupabaseService.loadDeliveryAddresses(customerId);
      
      if (addressesData.isNotEmpty) {
        // Use a Map to deduplicate addresses by ID to prevent duplicates
        final addressMap = <String, DeliveryAddress>{};
        
        for (final row in addressesData) {
          try {
            // Convert Supabase format (snake_case) to model format (camelCase)
            final map = {
              'customerId': row['customer_id'] ?? customerId,
              'address': row['address'] ?? '',
              'label': row['label'] ?? 'Address',
              'phoneNumber': row['phone_number'],
              'isDefault': row['is_default'] ?? false,
              'createdAt': row['created_at'],
              'updatedAt': row['updated_at'],
            };
            
            final addressId = row['id']?.toString() ?? '';
            if (addressId.isEmpty) continue;
            
            final address = DeliveryAddress.fromMap(map, addressId);
            // Only add if ID doesn't already exist (prevents duplicates)
            if (!addressMap.containsKey(address.id)) {
              addressMap[address.id] = address;
            } else {
              debugPrint('⚠️ Duplicate address ID found: ${address.id} - skipping');
            }
          } catch (e) {
            debugPrint('⚠️ Error parsing address: $e');
          }
        }
        
        _deliveryAddresses = addressMap.values.toList();
        
        // Sort by default first, then by creation date
        _deliveryAddresses.sort((a, b) {
          if (a.isDefault && !b.isDefault) return -1;
          if (!a.isDefault && b.isDefault) return 1;
          return b.createdAt.compareTo(a.createdAt);
        });
      } else {
        _deliveryAddresses = [];
      }

      debugPrint('📍 Loaded ${_deliveryAddresses.length} delivery addresses from Supabase');
    } catch (e) {
      debugPrint('❌ Error loading delivery addresses: $e');
      _error = 'Failed to load delivery addresses: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Save a new delivery address
  Future<bool> saveDeliveryAddress({
    required String customerId,
    required String address,
    required String label,
    String? phoneNumber,
    bool isDefault = false,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final now = DateTime.now();
      final addressData = {
        'customerId': customerId,
        'address': address,
        'label': label,
        'phoneNumber': phoneNumber,
        'isDefault': isDefault,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      };

      // Save to Supabase
      await SupabaseService.saveDeliveryAddress(addressData);

      // Reload addresses to get the updated list (including the new one)
      await loadDeliveryAddresses(customerId);

      debugPrint('✅ Saved delivery address to Supabase: $label');
      return true;
    } catch (e) {
      debugPrint('❌ Error saving delivery address: $e');
      _error = 'Failed to save delivery address: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update an existing delivery address
  Future<bool> updateDeliveryAddress({
    required String addressId,
    required String address,
    required String label,
    String? phoneNumber,
    bool isDefault = false,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final addressToUpdate = _deliveryAddresses.firstWhere((a) => a.id == addressId);
      final customerId = addressToUpdate.customerId;

      final now = DateTime.now();
      final updateData = {
        'customerId': customerId,
        'address': address,
        'label': label,
        'phoneNumber': phoneNumber,
        'isDefault': isDefault,
        'updatedAt': now.millisecondsSinceEpoch,
      };

      // Update in Supabase
      await SupabaseService.updateDeliveryAddress(
        addressId: addressId,
        addressData: updateData,
      );

      // Reload addresses to get the updated list
      await loadDeliveryAddresses(customerId);

      debugPrint('✅ Updated delivery address in Supabase: $label');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating delivery address: $e');
      _error = 'Failed to update delivery address: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a delivery address
  Future<bool> deleteDeliveryAddress(String addressId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final addressToDelete = _deliveryAddresses.firstWhere((a) => a.id == addressId);
      final customerId = addressToDelete.customerId;
      
      // Delete from Supabase
      await SupabaseService.deleteDeliveryAddress(addressId);

      // Reload addresses to get the updated list
      await loadDeliveryAddresses(customerId);

      debugPrint('✅ Deleted delivery address from Supabase: ${addressToDelete.label}');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting delivery address: $e');
      _error = 'Failed to delete delivery address: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get the default delivery address
  DeliveryAddress? get defaultDeliveryAddress {
    try {
      return _deliveryAddresses.firstWhere((address) => address.isDefault);
    } catch (e) {
      return _deliveryAddresses.isNotEmpty ? _deliveryAddresses.first : null;
    }
  }

  // Migration function to add existing customers' addresses to saved addresses
  Future<void> migrateExistingCustomerAddresses() async {
    try {
      debugPrint('🔄 Starting migration of existing customer addresses...');
      
      // Get all customers
      final customersSnapshot = await _database.child('customers').once();
      final customersData = customersSnapshot.snapshot.value as Map<dynamic, dynamic>?;
      
      if (customersData == null) {
        debugPrint('📭 No customers found to migrate');
        return;
      }

      // Get all existing delivery addresses
      final addressesSnapshot = await _database.child('deliveryAddresses').once();
      final addressesData = addressesSnapshot.snapshot.value as Map<dynamic, dynamic>?;
      
      // Create a set of customer IDs who already have delivery addresses
      final Set<String> customersWithAddresses = {};
      if (addressesData != null) {
        for (final entry in addressesData.entries) {
          final addressData = entry.value as Map<dynamic, dynamic>;
          final customerId = addressData['customerId'] as String?;
          if (customerId != null) {
            customersWithAddresses.add(customerId);
          }
        }
      }

      int migratedCount = 0;
      int skippedCount = 0;

      // Process each customer
      for (final entry in customersData.entries) {
        final customerId = entry.key;
        final customerData = entry.value as Map<dynamic, dynamic>;
        
        // Skip if customer already has delivery addresses
        if (customersWithAddresses.contains(customerId)) {
          skippedCount++;
          continue;
        }

        // Extract customer address information
        final address = customerData['address'] as String? ?? '';
        final city = customerData['city'] as String? ?? 'Ormoc';
        final state = customerData['state'] as String? ?? 'Leyte';
        final zipCode = customerData['zipCode'] as String? ?? '';
        
        if (address.isNotEmpty) {
          // Create full address
          final fullAddress = '$address, $city, $state $zipCode'.trim();
          
          // Create delivery address data
          final now = DateTime.now();
          final deliveryAddressData = {
            'customerId': customerId,
            'address': fullAddress,
            'label': 'Home',
            'isDefault': true,
            'createdAt': now.millisecondsSinceEpoch,
            'updatedAt': now.millisecondsSinceEpoch,
          };

          // Save to delivery addresses
          await _database
              .child('deliveryAddresses')
              .push()
              .set(deliveryAddressData);

          migratedCount++;
          debugPrint('✅ Migrated address for customer: $customerId');
        } else {
          debugPrint('⚠️ Skipped customer $customerId - no address found');
        }
      }

      debugPrint('🎉 Migration completed!');
      debugPrint('📊 Migrated: $migratedCount customers');
      debugPrint('⏭️ Skipped: $skippedCount customers (already had addresses)');
      
    } catch (e) {
      debugPrint('❌ Error during migration: $e');
    }
  }

  // Function to run migration for a specific customer (for testing)
  Future<void> migrateCustomerAddress(String customerId) async {
    try {
      debugPrint('🔄 Migrating address for customer: $customerId');
      
      // Check if customer already has delivery addresses
      final existingAddresses = await _database
          .child('deliveryAddresses')
          .orderByChild('customerId')
          .equalTo(customerId)
          .once();
      
      if (existingAddresses.snapshot.exists) {
        debugPrint('⏭️ Customer $customerId already has delivery addresses');
        return;
      }

      // Get customer data
      final customerSnapshot = await _database.child('customers').child(customerId).once();
      final customerData = customerSnapshot.snapshot.value as Map<dynamic, dynamic>?;
      
      if (customerData == null) {
        debugPrint('❌ Customer $customerId not found');
        return;
      }

      // Extract address information
      final address = customerData['address'] as String? ?? '';
      final city = customerData['city'] as String? ?? 'Ormoc';
      final state = customerData['state'] as String? ?? 'Leyte';
      final zipCode = customerData['zipCode'] as String? ?? '';
      
      if (address.isNotEmpty) {
        // Create full address
        final fullAddress = '$address, $city, $state $zipCode'.trim();
        
        // Create delivery address data
        final now = DateTime.now();
        final deliveryAddressData = {
          'customerId': customerId,
          'address': fullAddress,
          'label': 'Home',
          'isDefault': true,
          'createdAt': now.millisecondsSinceEpoch,
          'updatedAt': now.millisecondsSinceEpoch,
        };

        // Save to delivery addresses
        await _database
            .child('deliveryAddresses')
            .push()
            .set(deliveryAddressData);

        debugPrint('✅ Successfully migrated address for customer: $customerId');
        debugPrint('📍 Address: $fullAddress');
      } else {
        debugPrint('❌ Customer $customerId has no address to migrate');
      }
      
    } catch (e) {
      debugPrint('❌ Error migrating customer $customerId: $e');
    }
  }

  // Update order status
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _database.child('orders/$orderId').update({
        'status': newStatus,
        'updatedAt': ServerValue.timestamp,
      });

      // Update local order
      final orderIndex = _orders.indexWhere((order) => order.id == orderId);
      if (orderIndex != -1) {
        _orders[orderIndex] = _orders[orderIndex].copyWith(status: newStatus);
        notifyListeners();
      }
      
      debugPrint('✅ Order $orderId status updated to $newStatus');
      return true;
    } catch (e) {
      debugPrint('Error updating order status: $e');
      return false;
    }
  }

  // Check and update confirmed orders to "to_receive" status based on schedule
  /// DISABLED FOR DEVELOPMENT: No automatic status updates
  Future<void> checkAndUpdateOrderStatuses() async {
    // TODO: Re-enable automatic status updates when going to production
    debugPrint('🚧 DEVELOPMENT MODE: Automatic status updates disabled');
    return;
    
    // try {
    //   final now = DateTime.now();
    //   final weekday = now.weekday; // 1=Mon..7=Sun
    //   
    //   // Check if it's Thursday 1:00 PM or later
    //   bool shouldUpdateToReceive = false;
    //   if (weekday >= 4) { // Thursday (4) or later
    //     if (weekday == 4) { // Thursday
    //       final currentTime = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    //       final cutoffTime = DateTime(now.year, now.month, now.day, 13, 0); // 1:00 PM
    //       shouldUpdateToReceive = currentTime.isAfter(cutoffTime);
    //     } else {
    //       // Friday, Saturday, Sunday - definitely should be to_receive
    //       shouldUpdateToReceive = true;
    //     }
    //   }

    //   if (shouldUpdateToReceive) {
    //     // Find all confirmed orders that need to be updated
    //     final confirmedOrders = _orders.where((order) => 
    //       order.status.toLowerCase() == 'confirmed'
    //     ).toList();

    //     for (final order in confirmedOrders) {
    //       await updateOrderStatus(order.id, 'to_receive');
    //       debugPrint('🔄 Auto-updated order ${order.id} from confirmed to to_receive');
    //     }
    //   }
    // } catch (e) {
    //   debugPrint('Error checking order statuses: $e');
    // }
  }
}
