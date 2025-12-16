import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/notification.dart';
import '../services/supabase_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  // Track foreground notifications already shown to prevent duplicates
  // Use orderId_type format for order notifications, or notificationId for others
  static final Set<String> _shownForegroundNotificationKeys = <String>{};
  
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> initialize() async {
    try {
      // Request permission for notifications
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // Check permission status and ensure everything works if granted
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ User granted permission for notifications');
        debugPrint('✅ Notification permission: AUTHORIZED');
        debugPrint('✅ All notification features will work properly');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('⚠️ User granted provisional permission for notifications');
        debugPrint('⚠️ Notifications may be limited');
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('❌ User denied permission for notifications');
        debugPrint('⚠️ Notifications will not work until permission is granted');
      } else {
        debugPrint('⚠️ Notification permission status: ${settings.authorizationStatus}');
      }

      // Initialize local notifications (always initialize, even if permission not granted yet)
      // This ensures the notification channel is created for Android
      await _initializeLocalNotifications();

      // Request battery optimization exemption (Android only)
      // This ensures notifications work even when app is closed/force-stopped
      // Note: We also request this after login when user is more engaged
      if (Platform.isAndroid) {
        await requestBatteryOptimizationExemption();
      }

      // Get FCM token - try to get it even if permission was just granted
      // On Android, FCM token can be obtained even without notification permission
      // On iOS, token is only available after permission is granted
      try {
        final token = await _firebaseMessaging.getToken();
        if (token != null) {
          debugPrint('✅ FCM Token obtained: ${token.substring(0, 20)}...');
          debugPrint('✅ FCM Token length: ${token.length}');
          // Token will be saved when user logs in (via auth_provider)
        } else {
          debugPrint('⚠️ FCM Token is null - may need notification permission');
        }
      } catch (tokenError) {
        debugPrint('⚠️ Error getting FCM token: $tokenError');
        debugPrint('ℹ️ Token may be available after permission is granted');
      }

      // Set up message handlers - these will work once permission is granted
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 Received foreground FCM message');
        _handleForegroundMessage(message);
      });

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('📨 Notification tapped (app was in background)');
        _handleNotificationTap(message);
      });

      // Handle notification tap when app is terminated
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('📨 Notification tapped (app was terminated)');
        _handleNotificationTap(initialMessage);
      }

      // Handle token refresh - this will trigger when permission is granted
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 FCM Token refreshed: ${newToken.substring(0, 20)}...');
        debugPrint('✅ New token available - will be saved when user logs in');
        // Token will be saved via auth_provider when user logs in
      });

      debugPrint('✅ Notification service initialized successfully');
      debugPrint('✅ All handlers are set up and ready');
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permission is GRANTED - everything will work');
      } else {
        debugPrint('ℹ️ Notification permission not yet granted - will work once granted');
      }

    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing notification service: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      // Continue anyway - app should still work
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android (CRITICAL for Android 11+ background notifications)
    // Optimized for Android 11+ (API 30+) and all screen sizes
    // Using MAX importance to ensure notifications always appear, even when app is closed/force-stopped
    const androidChannel = AndroidNotificationChannel(
      'agricart_customer_channel',
      'AgriCart Customer Notifications',
      description: 'Notifications for order updates and important messages',
      importance: Importance.max, // MAX importance - ensures notifications always appear (Android 11+)
      playSound: true, // Enable sound for all Android versions
      enableVibration: true, // Enable vibration for all Android versions
      showBadge: true, // Show badge count (Android 11+)
      // Additional settings for Android 11+ compatibility
      enableLights: true, // Enable LED light (if device supports it)
      ledColor: const Color.fromARGB(255, 76, 175, 80), // Green LED color
    );

    // Create the channel - MUST be done before app closes for Android 11+
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
      // Delete existing channel first (if any) to ensure clean creation
      try {
        await androidImplementation.deleteNotificationChannel('agricart_customer_channel');
        debugPrint('🗑️ Deleted existing notification channel (if any)');
      } catch (e) {
        // Channel might not exist, that's okay
        debugPrint('ℹ️ No existing channel to delete');
      }
      
      // Create the channel
      await androidImplementation.createNotificationChannel(androidChannel);
      debugPrint('✅ Notification channel created: agricart_customer_channel');
      debugPrint('✅ Channel importance: ${androidChannel.importance}');
      debugPrint('✅ Channel sound: ${androidChannel.playSound}');
      debugPrint('✅ Channel vibration: ${androidChannel.enableVibration}');
      debugPrint('✅ Channel badge: ${androidChannel.showBadge}');
      
      // Note: Channel is now created and will persist even when app is closed
      // Android will use this channel for FCM notifications when app is closed
      debugPrint('✅ Channel creation complete - ready for background notifications');
    } else {
      debugPrint('⚠️ Android notification implementation not available');
    }
  }

  // Request battery optimization exemption to ensure notifications work when app is closed
  // This is public so it can be called after login when user is engaged
  static Future<void> requestBatteryOptimizationExemption({bool showDialog = false}) async {
    if (!Platform.isAndroid) {
      debugPrint('ℹ️ Battery optimization request skipped (not Android)');
      return;
    }

    try {
      debugPrint('🔋 Checking battery optimization status...');
      
      // Check if battery optimization is already disabled
      final isIgnoringBatteryOptimizations = await Permission.ignoreBatteryOptimizations.isGranted;
      
      if (isIgnoringBatteryOptimizations) {
        debugPrint('✅ Battery optimization already disabled for AgriCart - notifications will work when app is closed');
        return;
      }

      debugPrint('⚠️ Battery optimization is ENABLED - requesting exemption...');
      
      // If showDialog is true, we can show a custom dialog first
      // For now, we'll directly request (system will show its own dialog)
      // Request battery optimization exemption
      // This will open system settings if permission is not granted
      final status = await Permission.ignoreBatteryOptimizations.request();
      
      debugPrint('🔋 Battery optimization request result: $status');
      
      if (status.isGranted) {
        debugPrint('✅ Battery optimization exemption GRANTED - notifications will work when app is closed/force-stopped');
      } else if (status.isPermanentlyDenied) {
        debugPrint('❌ Battery optimization exemption PERMANENTLY DENIED');
        debugPrint('⚠️ Notifications may NOT work when app is force-stopped');
        debugPrint('ℹ️ User needs to manually disable: Settings → Apps → AgriCart → Battery → Unrestricted');
        // Could show a dialog here guiding user to settings
      } else if (status.isDenied) {
        debugPrint('⚠️ Battery optimization exemption DENIED (not permanent)');
        debugPrint('⚠️ Notifications may NOT work when app is force-stopped');
        debugPrint('ℹ️ Will request again after login');
      } else {
        debugPrint('⚠️ Battery optimization request status: $status');
        debugPrint('⚠️ Notifications may NOT work when app is force-stopped');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error requesting battery optimization exemption: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      // Non-critical - continue anyway
    }
  }

  // Check if battery optimization is disabled (for troubleshooting)
  static Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) {
      return true; // Not applicable on non-Android
    }
    
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (e) {
      debugPrint('❌ Error checking battery optimization status: $e');
      return false;
    }
  }

  // Open battery optimization settings manually
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    
    try {
      // Open battery optimization settings for this app
      await Permission.ignoreBatteryOptimizations.request();
    } catch (e) {
      debugPrint('❌ Error opening battery optimization settings: $e');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📨 Received foreground FCM message: ${message.messageId}');
    debugPrint('📨 Notification title: ${message.notification?.title}');
    debugPrint('📨 Notification body: ${message.notification?.body}');
    
    // Show local notification immediately so user sees it even when app is open
    final title = message.notification?.title ?? 'AgriCart';
    final body = message.notification?.body ?? '';
    final notificationId =
        message.data['id']?.toString() ?? message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // CRITICAL: Use orderId + type as key for order notifications to match notification_provider deduplication
    // This prevents duplicates when both FCM handler and Supabase listener try to show the same notification
    final orderId = message.data['orderId']?.toString() ?? message.data['order_id']?.toString();
    final notificationType = message.data['type']?.toString() ?? '';
    final notificationKey = (orderId != null && orderId.isNotEmpty && notificationType.isNotEmpty)
        ? '${orderId}_$notificationType'
        : notificationId;

    // Prevent duplicates: if we've already shown this foreground notification, skip
    if (_shownForegroundNotificationKeys.contains(notificationKey)) {
      debugPrint('🔕 Skipping duplicate foreground notification: $notificationKey');
      return; // Don't show and don't save to database
    } else {
      _shownForegroundNotificationKeys.add(notificationKey);
      // Keep the set from growing unbounded
      if (_shownForegroundNotificationKeys.length > 100) {
        _shownForegroundNotificationKeys.clear();
      }
      _showLocalNotification(title: title, body: body, payload: notificationId);
      debugPrint('✅ Shown foreground notification with key: $notificationKey');
    }

    // Also persist for history/backward compatibility
    _saveNotificationToDatabase(message);
    
    debugPrint('📨 Foreground message handled - local notification shown immediately');
  }
  
  // Check if a notification was already shown by FCM handler (for notification_provider to check)
  static bool isNotificationAlreadyShown(String? orderId, String notificationType, String notificationId) {
    if (orderId != null && orderId.isNotEmpty && notificationType.isNotEmpty) {
      final key = '${orderId}_$notificationType';
      return _shownForegroundNotificationKeys.contains(key);
    }
    return _shownForegroundNotificationKeys.contains(notificationId);
  }

  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.messageId}');
    
    // Navigate based on notification data
    final data = message.data;
    if (data.containsKey('type')) {
      switch (data['type']) {
        case 'order_update':
        case 'order_confirmed':
        case 'order_placed':
        case 'order_packed':
        case 'order_out_for_delivery':
          // Navigate to orders screen
          navigatorKey.currentState?.pushNamed('/orders');
          break;
        case 'product_available':
          if (data.containsKey('productId')) {
            navigatorKey.currentState?.pushNamed(
              '/product-detail',
              arguments: data['productId'],
            );
          }
          break;
        case 'product_restocked':
        case 'product_added':
          // Navigate to products screen
          navigatorKey.currentState?.pushNamed('/products');
          break;
        default:
          // Navigate to orders screen for any order-related notification
          navigatorKey.currentState?.pushNamed('/orders');
          break;
      }
    } else {
      // Default to orders screen if no type specified
      navigatorKey.currentState?.pushNamed('/orders');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
    // Handle local notification tap
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'agricart_customer_channel',
      'AgriCart Customer Notifications',
      channelDescription: 'Notifications for customer app',
      importance: Importance.max, // MAX importance - ensures notifications always appear
      priority: Priority.max, // MAX priority - ensures notifications always appear
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> _saveNotificationToDatabase(RemoteMessage message) async {
    try {
      final database = FirebaseDatabase.instance;
      final data = message.data;
      
      // Extract customer ID from data
      final customerId = data['customerId']?.toString() ?? 
                         data['customer_id']?.toString();
      
      if (customerId == null || customerId.isEmpty) {
        debugPrint('⚠️ No customerId in foreground message, skipping database save');
        return;
      }
      
      // Create notification ID
      final notificationId = DateTime.now().millisecondsSinceEpoch.toString();
      final notificationRef = database.ref('notifications/customers/$customerId/$notificationId');
      
      // Prepare notification data
      final notificationData = {
        'id': notificationId,
        'title': message.notification?.title ?? 'AgriCart',
        'message': message.notification?.body ?? '',
        'type': data['type']?.toString() ?? 'notification',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
      };
      
      // Add orderId if present
      if (data['orderId'] != null) {
        notificationData['orderId'] = data['orderId'].toString();
      }
      
      // Save to Firebase Database
      await notificationRef.set(notificationData);
      debugPrint('✅ Foreground notification saved to Firebase Database');
    } catch (e) {
      debugPrint('Error saving foreground notification to database: $e');
    }
  }

  // Subscribe to topics
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('Error subscribing to topic: $e');
    }
  }

  // Unsubscribe from topics
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('Error unsubscribing from topic: $e');
    }
  }

  // Save FCM token to Supabase and Firebase Database for a specific customer
  // Re-check notification permission and get FCM token if permission was just granted
  // This is useful when permission is granted after initial app launch
  static Future<bool> ensureNotificationPermissionAndToken() async {
    try {
      // Check current permission status
      final settings = await _firebaseMessaging.getNotificationSettings();
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permission is GRANTED');
        
        // Try to get FCM token now that permission is granted
        try {
          final token = await _firebaseMessaging.getToken();
          if (token != null) {
            debugPrint('✅ FCM Token obtained after permission grant: ${token.substring(0, 20)}...');
            return true;
          } else {
            debugPrint('⚠️ FCM Token is still null even after permission granted');
            return false;
          }
        } catch (tokenError) {
          debugPrint('⚠️ Error getting FCM token after permission grant: $tokenError');
          return false;
        }
      } else {
        debugPrint('⚠️ Notification permission is NOT granted (status: ${settings.authorizationStatus})');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error checking notification permission: $e');
      return false;
    }
  }

  static Future<void> saveFCMToken(String customerId) async {
    debugPrint('🔑 Starting FCM token save process for customer: $customerId');
    
    // First, check notification permission status
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permission is GRANTED - FCM token should be available');
      } else {
        debugPrint('⚠️ Notification permission is NOT granted (status: ${settings.authorizationStatus})');
        debugPrint('ℹ️ On Android, FCM token may still be available');
        debugPrint('ℹ️ On iOS, FCM token requires notification permission');
      }
    } catch (e) {
      debugPrint('⚠️ Error checking notification permission: $e');
      // Continue anyway - try to get token
    }
    
    // Get token - try to get it even if permission status is unclear
    // On Android, FCM token can sometimes be obtained even without notification permission
    // On iOS, token is only available after permission is granted
    String? token;
    try {
      token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint('✅ FCM Token obtained successfully: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
      } else {
        debugPrint('⚠️ FCM Token is null');
        debugPrint('ℹ️ This may be because notification permission is not granted');
        debugPrint('ℹ️ On iOS, FCM token requires notification permission');
        debugPrint('ℹ️ On Android, token may be available even without permission');
        return;
      }
    } catch (tokenError) {
      debugPrint('❌ Error getting FCM token: $tokenError');
      debugPrint('ℹ️ Token may be available after notification permission is granted');
      return;
    }

    debugPrint('🔑 Saving FCM token for customer: $customerId');
    debugPrint('🔑 Token (first 20 chars): ${token.substring(0, token.length > 20 ? 20 : token.length)}...');

    try {
      // Ensure Supabase is initialized
      await SupabaseService.initialize();
      
      debugPrint('🔍 Supabase initialized, attempting to save FCM token...');
      debugPrint('🔍 Customer ID: $customerId');
      debugPrint('🔍 Token length: ${token.length}');
      
      // Check current auth user
      final currentUser = SupabaseService.client.auth.currentUser;
      debugPrint('🔍 Current auth user ID: ${currentUser?.id}');
      debugPrint('🔍 Auth user matches customer ID: ${currentUser?.id == customerId}');
      
      // Save FCM token to Supabase (primary storage)
      // IMPORTANT: We upsert on customer_id since the schema has UNIQUE constraint on customer_id
      // This ensures one token per customer and handles token updates correctly (e.g., after reactivation)
      try {
        // First, try to delete any existing token for this customer to avoid conflicts
        // This handles cases where token changed (new device, token refresh, etc.)
        try {
          await SupabaseService.client
              .from('customer_fcm_tokens')
              .delete()
              .eq('customer_id', customerId);
          debugPrint('🧹 Cleaned up any existing FCM token for customer: $customerId');
        } catch (deleteError) {
          debugPrint('⚠️ Error deleting old FCM token (non-critical): $deleteError');
          // Continue - upsert will handle it
        }
        
        // Now insert the new token
        final response = await SupabaseService.client
            .from('customer_fcm_tokens')
            .insert({
              'customer_id': customerId,
              'fcm_token': token,
              'device_type': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown'),
              'last_used_at': DateTime.now().toIso8601String(),
            });
        
        debugPrint('✅ FCM token saved for customer: $customerId');
        debugPrint('✅ Insert response: $response');
      } catch (insertError) {
        // If insert fails (e.g., token already exists), try upsert on customer_id
        debugPrint('⚠️ Insert failed, trying upsert on customer_id: $insertError');
        try {
          final response = await SupabaseService.client
              .from('customer_fcm_tokens')
              .upsert({
                'customer_id': customerId,
                'fcm_token': token,
                'device_type': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown'),
                'last_used_at': DateTime.now().toIso8601String(),
              }, onConflict: 'customer_id');
          
          debugPrint('✅ FCM token upsert (by customer_id) completed for customer: $customerId');
          debugPrint('✅ Upsert response: $response');
        } catch (upsertError) {
          debugPrint('❌ Upsert error when saving FCM token: $upsertError');
          debugPrint('❌ Error type: ${upsertError.runtimeType}');
          // If this fails, it's usually a duplicate token edge case; we log and continue.
        }
      }
      
      // Wait a bit for the database to update
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verify it was saved
      debugPrint('🔍 Verifying FCM token was saved...');
      final verify = await SupabaseService.client
          .from('customer_fcm_tokens')
          .select('fcm_token, customer_id, device_type')
          .eq('customer_id', customerId)
          .maybeSingle();
      
      if (verify != null) {
        debugPrint('✅ FCM token found in database!');
        debugPrint('✅ Saved token (first 20): ${verify['fcm_token'].toString().substring(0, verify['fcm_token'].toString().length > 20 ? 20 : verify['fcm_token'].toString().length)}...');
        debugPrint('✅ Device type: ${verify['device_type']}');
        
        if (verify['fcm_token'] == token) {
          debugPrint('✅ FCM token verified - matches saved token');
        } else {
          debugPrint('⚠️ FCM token mismatch - saved token differs from current token');
        }
      } else {
        debugPrint('❌ FCM token NOT found in database after save!');
        debugPrint('❌ This might be an RLS policy issue');
      }
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌ ============================================');
      debugPrint('❌ ERROR saving FCM token to Supabase!');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      debugPrint('❌ Error toString: ${e.toString()}');
      debugPrint('❌ Stack trace: $stackTrace');
      debugPrint('❌ ============================================');
      debugPrint('');
      // Don't return - still try to save to Firebase
    }

    // Also save to Firebase Database for backward compatibility (optional)
    try {
      final database = FirebaseDatabase.instance;
      final customerRef = database.ref('customers/$customerId');
      
      await customerRef.update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      
      debugPrint('✅ FCM token saved to Firebase Database for customer: $customerId');
    } catch (e) {
      debugPrint('⚠️ Error saving FCM token to Firebase (non-critical): $e');
    }
  }

  // Remove FCM token from Supabase and Firebase Database
  static Future<void> removeFCMToken(String customerId) async {
    // Remove from Supabase (primary)
    try {
      await SupabaseService.client
          .from('customer_fcm_tokens')
          .delete()
          .eq('customer_id', customerId);
      debugPrint('✅ FCM token removed from Supabase for customer: $customerId');
    } catch (e) {
      debugPrint('❌ Error removing FCM token from Supabase: $e');
    }

    // Also remove from Firebase Database for backward compatibility
    try {
      final database = FirebaseDatabase.instance;
      final customerRef = database.ref('customers/$customerId');
      await customerRef.update({
        'fcmToken': null,
      });
      debugPrint('✅ FCM token removed from Firebase Database for customer: $customerId');
    } catch (e) {
      debugPrint('⚠️ Error removing FCM token from Firebase (non-critical): $e');
    }
  }

  // Show a custom local notification
  static Future<void> showCustomNotification({
    required String title,
    required String body,
    String? payload,
    Map<String, dynamic>? data,
  }) async {
    await _showLocalNotification(
      title: title,
      body: body,
      payload: payload,
    );

    // Save to database if data is provided
    if (data != null) {
      // This would typically be done on the server side
      debugPrint('Custom notification data: $data');
    }
  }

  // Listen for verification status changes
  static Stream<CustomerNotification?> listenToVerificationStatus(String customerId) {
    // DISABLED: Verification notifications are now handled in dashboard_screen.dart
    // to prevent duplicate notifications and ensure proper timing
    return Stream.value(null);
  }

  // Send notification to customer (saves to Supabase, which triggers Edge Function to send FCM)
  // CRITICAL: When app is open, we show local notification immediately AND send FCM
  // This ensures notification appears on phone even when app is in use
  static Future<void> sendNotification(String customerId, CustomerNotification notification) async {
    debugPrint('=== SENDING NOTIFICATION TO SUPABASE ===');
    debugPrint('Customer ID: $customerId');
    debugPrint('Notification ID: ${notification.id}');
    debugPrint('Notification timestamp: ${notification.timestamp}');
    debugPrint('Timestamp in milliseconds: ${notification.timestamp.millisecondsSinceEpoch}');
    debugPrint('Notification data: ${notification.toMap()}');
    
    try {
      // Prepare notification data for Supabase
      final notificationData = <String, dynamic>{
        'id': notification.id,
        'customer_id': customerId,
        'title': notification.title,
        'message': notification.message,
        'type': notification.type,
        'timestamp': notification.timestamp.millisecondsSinceEpoch,
        'is_read': notification.isRead,
        'fcm_sent': false, // Will be set to true by Edge Function after sending FCM
      };
      
      // Add order_id only if it's not null
      if (notification.orderId != null && notification.orderId!.isNotEmpty) {
        notificationData['order_id'] = notification.orderId;
      }
      
      // Save notification to Supabase (Edge Function will send FCM; foreground handler shows local)
      // This will trigger the database trigger which calls the Edge Function to send FCM
      await SupabaseService.client
          .from('customer_notifications')
          .insert(notificationData);
      
      debugPrint('✅ Notification saved to Supabase');
      debugPrint('✅ FCM push notification will be sent via Edge Function trigger');
      debugPrint('ℹ️ FCM will also appear on phone (may be duplicate, but that\'s OK - user sees it once)');
      
      // Also save to Firebase Database for backward compatibility (optional)
      try {
        final database = FirebaseDatabase.instance;
        final notificationRef = database.ref('notifications/customers/$customerId/${notification.id}');
        await notificationRef.set({
          'id': notification.id,
          'title': notification.title,
          'message': notification.message,
          'type': notification.type,
          'timestamp': notification.timestamp.millisecondsSinceEpoch,
          'isRead': notification.isRead,
          if (notification.orderId != null) 'orderId': notification.orderId,
        });
        debugPrint('✅ Notification also saved to Firebase Database (backward compatibility)');
      } catch (firebaseError) {
        debugPrint('⚠️ Error saving to Firebase Database (non-critical): $firebaseError');
      }
      
      // Note: We show local notification immediately AND send FCM
      // The notification provider will check fcm_sent flag to prevent duplicates
      // When app is reopened, notifications with fcm_sent=true won't be shown again
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌ ============================================');
      debugPrint('❌ ERROR saving notification to Supabase!');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      debugPrint('❌ Error toString: ${e.toString()}');
      debugPrint('❌ Stack trace: $stackTrace');
      debugPrint('❌ ============================================');
      debugPrint('');
      rethrow;
    }
  }

  // Get customer notifications (not used anymore - using provider instead)
  static Stream<List<CustomerNotification>> getCustomerNotifications(String customerId) {
    // This method is deprecated - use NotificationProvider instead
    return Stream.value(<CustomerNotification>[]);
  }

  // Mark notification as read in Supabase
  static Future<void> markAsRead(String customerId, String notificationId) async {
    try {
      await SupabaseService.client
          .from('customer_notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('customer_id', customerId);
      debugPrint('✅ Notification marked as read in Supabase');
    } catch (e) {
      debugPrint('❌ Error marking notification as read: $e');
      rethrow;
    }
  }

  // Delete notification from Supabase
  static Future<void> deleteNotification(String customerId, String notificationId) async {
    try {
      await SupabaseService.client
          .from('customer_notifications')
          .delete()
          .eq('id', notificationId)
          .eq('customer_id', customerId);
      debugPrint('✅ Notification deleted from Supabase');
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
      rethrow;
    }
  }

  // Handle notification tap from database notifications
  static void handleDatabaseNotificationTap(CustomerNotification notification) {
    debugPrint('Database notification tapped: ${notification.id}');
    
    // Navigate based on notification type
    switch (notification.type) {
      case 'order_update':
      case 'order_confirmed':
      case 'order_placed':
      case 'order_packed':
      case 'order_out_for_delivery':
        // Navigate to orders screen
        navigatorKey.currentState?.pushNamed('/orders');
        break;
      case 'product_available':
      case 'product_restocked':
      case 'product_added':
        // Navigate to products screen
        navigatorKey.currentState?.pushNamed('/products');
        break;
      default:
        // Default to orders screen for any order-related notification
        navigatorKey.currentState?.pushNamed('/orders');
        break;
    }
  }
}
