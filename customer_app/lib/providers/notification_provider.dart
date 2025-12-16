import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

class NotificationProvider with ChangeNotifier {
  List<CustomerNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;
  // Track active listeners to avoid duplicate streams/popups
  DatabaseReference? _notificationsRef;
  StreamSubscription<DatabaseEvent>? _notificationsSubscription;
  RealtimeChannel? _supabaseChannel; // Supabase realtime channel
  // Session-level dedupe for pop-up notifications
  final Set<String> _seenPopupIds = <String>{};
  DateTime? _listenerStartTime; // Track when listener was started to prevent showing old notifications
  // CRITICAL: Track notifications deleted by user to prevent recreation
  // Key format: '${orderId}_${notificationType}' or just notificationId for non-order notifications
  // This is persisted to SharedPreferences to survive app restarts
  Set<String> _userDeletedNotifications = <String>{};
  static const String _deletedNotificationsKey = 'user_deleted_notifications';
  
  // Load deleted notifications from SharedPreferences
  Future<void> _loadDeletedNotifications(String customerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deletedKey = '${_deletedNotificationsKey}_$customerId';
      final deletedJson = prefs.getString(deletedKey);
      if (deletedJson != null) {
        final deletedList = (jsonDecode(deletedJson) as List).map((e) => e.toString()).toList();
        _userDeletedNotifications = deletedList.toSet();
        debugPrint('📂 Loaded ${_userDeletedNotifications.length} deleted notification keys from storage');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading deleted notifications: $e');
    }
  }
  
  // Save deleted notifications to SharedPreferences
  Future<void> _saveDeletedNotifications(String customerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deletedKey = '${_deletedNotificationsKey}_$customerId';
      final deletedList = _userDeletedNotifications.toList();
      await prefs.setString(deletedKey, jsonEncode(deletedList));
      debugPrint('💾 Saved ${deletedList.length} deleted notification keys to storage');
    } catch (e) {
      debugPrint('⚠️ Error saving deleted notifications: $e');
    }
  }

  List<CustomerNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load notifications for a customer from Supabase
  Future<void> loadNotifications(String customerId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      
      // CRITICAL: Load deleted notification keys from storage
      await _loadDeletedNotifications(customerId);

      final response = await SupabaseService.client
          .from('customer_notifications')
          .select()
          .eq('customer_id', customerId)
          .order('timestamp', ascending: false);

      if (response != null && response is List) {
        final allNotifications = response.map((data) {
          final timestampValue = data['timestamp'];
          final timestampInt = timestampValue is int 
              ? timestampValue 
              : (timestampValue is String ? int.tryParse(timestampValue) ?? 0 : 0);
          
          return CustomerNotification.fromMap({
            'title': data['title'] ?? '',
            'message': data['message'] ?? '',
            'type': data['type'] ?? '',
            'timestamp': timestampInt,
            'isRead': data['is_read'] ?? false,
            'orderId': data['order_id']?.toString(),
            'productId': data['product_id']?.toString(),
          }, data['id']?.toString() ?? '');
        }).toList();

        // Filter out duplicates based on orderId + type (keep the newest one)
        // This prevents duplicate "Order Out for Delivery" notifications from appearing
        final seenNotifications = <String, CustomerNotification>{};
        for (final notification in allNotifications) {
          if (notification.orderId != null && notification.type.isNotEmpty) {
            final key = '${notification.orderId}_${notification.type}';
            final existing = seenNotifications[key];
            if (existing == null || notification.timestamp.isAfter(existing.timestamp)) {
              // Keep the newest notification for this orderId + type
              seenNotifications[key] = notification;
            }
          } else {
            // For notifications without orderId, keep all (use id as key)
            final key = notification.id;
            if (!seenNotifications.containsKey(key)) {
              seenNotifications[key] = notification;
            }
          }
        }
        
        _notifications = seenNotifications.values.toList();

        // Sort by timestamp (newest first)
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // Calculate unread count
        _unreadCount = _notifications.where((notification) => !notification.isRead).length;
      } else {
        _notifications = [];
        _unreadCount = 0;
      }
    } catch (e) {
      _error = 'Failed to load notifications: $e';
      debugPrint('Error loading notifications from Supabase: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Mark notification as read
  Future<void> markAsRead(String customerId, String notificationId) async {
    try {
      // Update in Supabase
      await SupabaseService.client
          .from('customer_notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('customer_id', customerId);

      // Update local notification
      final notificationIndex = _notifications.indexWhere(
        (notification) => notification.id == notificationId,
      );
      
      if (notificationIndex != -1) {
        _notifications[notificationIndex] = _notifications[notificationIndex]
            .copyWith(isRead: true);
        
        // Recalculate unread count
        _unreadCount = _notifications.where((notification) => !notification.isRead).length;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  // Mark all notifications as read in Supabase
  Future<void> markAllAsRead(String customerId) async {
    try {
      await SupabaseService.client
          .from('customer_notifications')
          .update({'is_read': true})
          .eq('customer_id', customerId)
          .eq('is_read', false);
      
      // Update local notifications
      _notifications = _notifications.map((notification) {
        return notification.copyWith(isRead: true);
      }).toList();
      
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  // Delete a notification
  Future<void> deleteNotification(String customerId, String notificationId) async {
    try {
      debugPrint('🗑️ Deleting notification: $notificationId for customer: $customerId');
      
      // CRITICAL: Get notification details before deleting so we can track it
      final notificationBeforeDelete = _notifications.firstWhere(
        (notification) => notification.id == notificationId,
        orElse: () => CustomerNotification(
          id: notificationId,
          title: '',
          message: '',
          type: '',
          timestamp: DateTime.now(),
        ),
      );
      
      // Delete from Supabase - use .delete() and verify it was deleted
      try {
        final deleteResponse = await SupabaseService.client
            .from('customer_notifications')
            .delete()
            .eq('id', notificationId)
            .eq('customer_id', customerId);
        
        debugPrint('🗑️ Supabase delete response: $deleteResponse');
      } catch (deleteError) {
        debugPrint('❌ Error in Supabase delete: $deleteError');
        // Continue to verification
      }
      
      // Verify deletion by checking if notification still exists
      final verifyResponse = await SupabaseService.client
          .from('customer_notifications')
          .select('id')
          .eq('id', notificationId)
          .eq('customer_id', customerId)
          .maybeSingle();
      
      if (verifyResponse != null) {
        debugPrint('⚠️ WARNING: Notification still exists in Supabase after delete attempt: $notificationId');
        debugPrint('⚠️ This may be due to RLS policies. Attempting force delete...');
        // Try force delete with different approach
        try {
          await SupabaseService.client
              .from('customer_notifications')
              .delete()
              .eq('id', notificationId);
          
          // Verify again
          final verifyAgain = await SupabaseService.client
              .from('customer_notifications')
              .select('id')
              .eq('id', notificationId)
              .maybeSingle();
          
          if (verifyAgain != null) {
            debugPrint('❌ Force delete also failed - notification still exists: $notificationId');
            debugPrint('❌ This suggests an RLS policy or permissions issue');
            // Don't throw - we'll still mark it as deleted in tracking
          } else {
            debugPrint('✅ Force deleted notification from Supabase: $notificationId');
          }
        } catch (forceDeleteError) {
          debugPrint('❌ Force delete also failed: $forceDeleteError');
          // Don't throw - we'll still mark it as deleted in tracking
        }
      } else {
        debugPrint('✅ Notification successfully deleted from Supabase: $notificationId');
      }

      // Delete from Firebase Database (if applicable)
      try {
        final database = FirebaseDatabase.instance;
        final notificationRef = database.ref('notifications/customers/$customerId/$notificationId');
        await notificationRef.remove();
        
        // Verify Firebase deletion
        final firebaseSnapshot = await notificationRef.get();
        if (firebaseSnapshot.exists) {
          debugPrint('⚠️ WARNING: Notification still exists in Firebase after delete attempt: $notificationId');
          // Try to remove again
          await notificationRef.remove();
        } else {
          debugPrint('✅ Notification successfully deleted from Firebase Database: $notificationId');
        }
      } catch (firebaseError) {
        debugPrint('⚠️ Error deleting from Firebase Database (non-critical): $firebaseError');
        // Continue even if Firebase delete fails - Supabase is the source of truth
      }

      // Remove from local list
      final removedCount = _notifications.length;
      final notificationToDelete = _notifications.firstWhere(
        (notification) => notification.id == notificationId,
        orElse: () => CustomerNotification(
          id: notificationId,
          title: '',
          message: '',
          type: '',
          timestamp: DateTime.now(),
        ),
      );
      
      _notifications.removeWhere(
        (notification) => notification.id == notificationId,
      );
      final afterRemovalCount = _notifications.length;
      debugPrint('🗑️ Removed from local list: ${removedCount - afterRemovalCount} notification(s)');
      
      // CRITICAL: Track this notification as deleted by user to prevent recreation
      if (notificationToDelete.orderId != null && notificationToDelete.orderId!.isNotEmpty && notificationToDelete.type.isNotEmpty) {
        final deletedKey = '${notificationToDelete.orderId}_${notificationToDelete.type}';
        _userDeletedNotifications.add(deletedKey);
        // Persist to storage so it survives app restarts
        await _saveDeletedNotifications(customerId);
        debugPrint('🔒 Marked notification as user-deleted (key: $deletedKey) - will not be recreated');
      } else {
        // For notifications without orderId, track by ID
        _userDeletedNotifications.add(notificationId);
        // Persist to storage so it survives app restarts
        await _saveDeletedNotifications(customerId);
        debugPrint('🔒 Marked notification as user-deleted (ID: $notificationId) - will not be recreated');
      }
      
      // Recalculate unread count
      _unreadCount = _notifications.where((notification) => !notification.isRead).length;
      notifyListeners();
      
      debugPrint('✅ Notification deletion completed: $notificationId');
    } catch (e, stackTrace) {
      debugPrint('❌ Error deleting notification: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Clear all notifications from Supabase and Firebase
  Future<void> clearAllNotifications(String customerId) async {
    try {
      debugPrint('🗑️ Clearing all notifications for customer: $customerId');
      
      // CRITICAL: Get all notification IDs first before deleting
      // This ensures we can track them as deleted even if delete fails
      final allNotificationsBeforeDelete = await SupabaseService.client
          .from('customer_notifications')
          .select('id, order_id, type')
          .eq('customer_id', customerId);
      
      // Mark all as deleted in our tracking before attempting delete
      if (allNotificationsBeforeDelete is List) {
        for (final notificationData in allNotificationsBeforeDelete) {
          final notificationId = notificationData['id']?.toString() ?? '';
          final orderId = notificationData['order_id']?.toString();
          final notificationType = notificationData['type']?.toString() ?? '';
          
          if (orderId != null && orderId.isNotEmpty && notificationType.isNotEmpty) {
            final deletedKey = '${orderId}_$notificationType';
            _userDeletedNotifications.add(deletedKey);
          } else {
            _userDeletedNotifications.add(notificationId);
          }
        }
        await _saveDeletedNotifications(customerId);
        debugPrint('🔒 Marked ${allNotificationsBeforeDelete.length} notifications as user-deleted before deletion');
      }
      
      // Delete all from Supabase - use .delete() with proper error handling
      try {
        final deleteResponse = await SupabaseService.client
            .from('customer_notifications')
            .delete()
            .eq('customer_id', customerId);
        debugPrint('🗑️ Supabase delete all response: $deleteResponse');
      } catch (deleteError) {
        debugPrint('❌ Error in Supabase delete all: $deleteError');
        // Continue to verification even if delete throws error
      }
      
      // Verify deletion by checking count
      final verifyResponse = await SupabaseService.client
          .from('customer_notifications')
          .select('id')
          .eq('customer_id', customerId);
      
      final remainingCount = verifyResponse is List ? verifyResponse.length : 0;
      if (remainingCount > 0) {
        debugPrint('⚠️ WARNING: $remainingCount notifications still exist in Supabase after delete all attempt');
        debugPrint('⚠️ This may be due to RLS policies or permissions. Attempting individual deletes...');
        // Try to delete again with different approach - delete individually
        try {
          // Get all notification IDs and delete them individually
          if (verifyResponse is List) {
            int deletedCount = 0;
            for (final notificationData in verifyResponse) {
              final notificationId = notificationData['id']?.toString();
              if (notificationId != null) {
                try {
                  await SupabaseService.client
                      .from('customer_notifications')
                      .delete()
                      .eq('id', notificationId)
                      .eq('customer_id', customerId);
                  deletedCount++;
                } catch (individualDeleteError) {
                  debugPrint('❌ Failed to delete individual notification $notificationId: $individualDeleteError');
                }
              }
            }
            debugPrint('✅ Force deleted $deletedCount notifications individually from Supabase');
            
            // Verify again
            final finalVerify = await SupabaseService.client
                .from('customer_notifications')
                .select('id')
                .eq('customer_id', customerId);
            final finalCount = finalVerify is List ? finalVerify.length : 0;
            if (finalCount > 0) {
              debugPrint('⚠️ WARNING: $finalCount notifications STILL exist after individual deletes');
              debugPrint('⚠️ This suggests an RLS policy or permissions issue');
            } else {
              debugPrint('✅ All notifications successfully deleted from Supabase (after individual deletes)');
            }
          }
        } catch (forceDeleteError) {
          debugPrint('❌ Force delete all also failed: $forceDeleteError');
          // Don't throw - we've already marked them as deleted in tracking
        }
      } else {
        debugPrint('✅ All notifications successfully deleted from Supabase for customer: $customerId');
      }

      // Delete all from Firebase Database (if applicable)
      try {
        final database = FirebaseDatabase.instance;
        final notificationsRef = database.ref('notifications/customers/$customerId');
        await notificationsRef.remove();
        
        // Verify Firebase deletion
        final firebaseSnapshot = await notificationsRef.get();
        if (firebaseSnapshot.exists) {
          debugPrint('⚠️ WARNING: Notifications still exist in Firebase after delete all attempt');
          // Try to remove again
          await notificationsRef.remove();
        } else {
          debugPrint('✅ All notifications successfully deleted from Firebase Database for customer: $customerId');
        }
      } catch (firebaseError) {
        debugPrint('⚠️ Error deleting from Firebase Database (non-critical): $firebaseError');
        // Continue even if Firebase delete fails - Supabase is the source of truth
      }

      // CRITICAL: Mark all current notifications as user-deleted to prevent recreation
      for (final notification in _notifications) {
        if (notification.orderId != null && notification.orderId!.isNotEmpty && notification.type.isNotEmpty) {
          final deletedKey = '${notification.orderId}_${notification.type}';
          _userDeletedNotifications.add(deletedKey);
        } else {
          _userDeletedNotifications.add(notification.id);
        }
      }
      // Persist to storage so it survives app restarts
      await _saveDeletedNotifications(customerId);
      debugPrint('🔒 Marked ${_notifications.length} notifications as user-deleted - will not be recreated');
      
      _notifications.clear();
      _unreadCount = 0;
      notifyListeners();
      
      debugPrint('✅ Clear all notifications completed for customer: $customerId');
    } catch (e, stackTrace) {
      debugPrint('❌ Error clearing all notifications: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Get notifications by type
  List<CustomerNotification> getNotificationsByType(String type) {
    return _notifications.where((notification) => notification.type == type).toList();
  }

  // Get unread notifications
  List<CustomerNotification> getUnreadNotifications() {
    return _notifications.where((notification) => !notification.isRead).toList();
  }

  // Add a new notification (for testing or local notifications)
  void addNotification(CustomerNotification notification) {
    _notifications.add(notification);
    // Sort by timestamp (newest first) after adding
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (!notification.isRead) {
      _unreadCount++;
    }
    notifyListeners();
  }

  // Listen for real-time notification updates from Supabase
  void listenToNotifications(String customerId) {
    // Cancel previous listeners to prevent duplicate popups
    _notificationsSubscription?.cancel();
    _supabaseChannel?.unsubscribe();
    
    // Record the exact time when we start listening
    _listenerStartTime = DateTime.now();
    debugPrint('🔔 Started listening to notifications at: $_listenerStartTime');

    try {
      // Subscribe to Supabase realtime changes
      _supabaseChannel = SupabaseService.client
          .channel('customer_notifications_$customerId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'customer_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: customerId,
            ),
            callback: (payload) {
              _handleNewNotification(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'customer_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: customerId,
            ),
            callback: (payload) {
              _handleUpdatedNotification(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'customer_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: customerId,
            ),
            callback: (payload) {
              _handleDeletedNotification(payload.oldRecord['id']?.toString() ?? '');
            },
          )
          .subscribe(
            (status, [error]) {
              if (status == RealtimeSubscribeStatus.subscribed) {
                debugPrint('✅ Notification realtime subscription ACTIVE - listening for changes');
              } else if (status == RealtimeSubscribeStatus.timedOut) {
                debugPrint('⏱️ Notification realtime subscription TIMED OUT - will retry');
                // Retry after 3 seconds
                Future.delayed(const Duration(seconds: 3), () {
                  listenToNotifications(customerId);
                });
              } else if (status == RealtimeSubscribeStatus.channelError) {
                debugPrint('❌ Notification realtime subscription ERROR: $error - will retry');
                // Retry after 3 seconds
                Future.delayed(const Duration(seconds: 3), () {
                  listenToNotifications(customerId);
                });
              } else {
                debugPrint('⚠️ Notification realtime subscription status: $status');
              }
            },
          );
        
      debugPrint('✅ Supabase realtime listener for notifications subscription initiated');
    } catch (e) {
      debugPrint('❌ Error setting up Supabase realtime listener: $e');
      // Retry after 5 seconds on error
      Future.delayed(const Duration(seconds: 5), () {
        listenToNotifications(customerId);
      });
    }
  }

  // Handle new notification from Supabase
  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final timestampValue = data['timestamp'];
      final timestampInt = timestampValue is int 
          ? timestampValue 
          : (timestampValue is String ? int.tryParse(timestampValue) ?? 0 : 0);
      
      debugPrint('🔔 Real-time notification received: ${data['title']} (ID: ${data['id']}, Type: ${data['type']}, OrderId: ${data['order_id']})');
      
      final notification = CustomerNotification.fromMap({
        'title': data['title'] ?? '',
        'message': data['message'] ?? '',
        'type': data['type'] ?? '',
        'timestamp': timestampInt,
        'isRead': data['is_read'] ?? false,
        'orderId': data['order_id']?.toString(),
      }, data['id']?.toString() ?? '');
      
      // CRITICAL: Only show notification if fcm_sent is FALSE
      // If fcm_sent is true, it means FCM already delivered it when app was closed
      final fcmSent = data['fcm_sent'] ?? false;
      
      // Check if notification already exists by ID
      final existingByIdIndex = _notifications.indexWhere((n) => n.id == notification.id);
      final existsById = existingByIdIndex != -1;
      
      // CRITICAL: Also check for duplicates based on orderId + type
      // This prevents showing the same notification multiple times for the same order status change
      final orderId = notification.orderId;
      final notificationType = notification.type;
      final existingByOrderAndTypeIndex = orderId != null && notificationType.isNotEmpty
          ? _notifications.indexWhere((n) => 
              n.orderId == orderId && 
              n.type == notificationType &&
              n.id != notification.id // Don't match itself
            )
          : -1;
      final existsByOrderAndType = existingByOrderAndTypeIndex != -1;
      
      // If notification exists by ID, skip it (exact duplicate)
      if (existsById) {
        debugPrint('🔕 Skipping duplicate notification: ${notification.title} (ID: ${notification.id} already exists)');
        return;
      }
      
      // If notification exists by orderId+type, replace it with the newer one
      bool shouldAdd = true;
      if (existsByOrderAndType) {
        final existingNotification = _notifications[existingByOrderAndTypeIndex];
        // Compare timestamps - if new notification is newer or equal, replace the old one
        if (notification.timestamp.isAfter(existingNotification.timestamp) || 
            notification.timestamp.isAtSameMomentAs(existingNotification.timestamp)) {
          // Remove old notification
          final wasRead = existingNotification.isRead;
          if (!wasRead) {
            _unreadCount--; // Decrement since we're removing an unread notification
          }
          _notifications.removeAt(existingByOrderAndTypeIndex);
          debugPrint('🔄 Replacing existing notification: ${existingNotification.title} with newer one: ${notification.title}');
        } else {
          // Old notification is newer, skip adding this one
          debugPrint('🔕 Skipping older notification: ${notification.title} (Order: $orderId, Type: $notificationType - existing one is newer)');
          shouldAdd = false;
        }
      }
      
      if (shouldAdd) {
        _notifications.add(notification);
        // Sort by timestamp (newest first) after adding
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (!notification.isRead) {
          _unreadCount++;
        }
        
        // CRITICAL: Check if notification was already shown by FCM foreground handler
        // This prevents duplicates when app is open - FCM handler shows notification immediately,
        // and we don't want to show it again via Supabase listener
        final wasShownByFCM = NotificationService.isNotificationAlreadyShown(
          orderId,
          notificationType,
          notification.id,
        );
        
        // CRITICAL: Only show in-app notification if:
        // 1. FCM was NOT sent (fcm_sent = false) - means notification was created while app was open
        // 2. AND it wasn't already shown by FCM foreground handler
        // 3. AND it hasn't been seen before in this session
        if (!fcmSent && !wasShownByFCM) {
          // Show notification if it hasn't been shown before
          // Use orderId + type as key to prevent duplicates
          final notificationKey = orderId != null && notificationType.isNotEmpty
              ? '${orderId}_$notificationType'
              : notification.id;
          final shouldShowNotification = !_seenPopupIds.contains(notificationKey);
          
          if (shouldShowNotification) {
            _seenPopupIds.add(notificationKey);
            debugPrint('🔔 Showing in-app notification: ${notification.title} (ID: ${notification.id}, Key: $notificationKey) - FCM not sent and not shown by FCM handler');
            NotificationService.showCustomNotification(
              title: notification.title,
              body: notification.message,
              data: {
                'type': notification.type,
                if (notification.orderId != null) 'orderId': notification.orderId!,
              },
            );
          } else {
            debugPrint('🔕 Skipping notification: ${notification.title} (already seen: $notificationKey)');
          }
        } else {
          if (fcmSent) {
            // FCM was already sent - notification was shown on phone when app was closed
            // Don't show again when app is reopened to prevent duplicates
            debugPrint('🔕 Skipping in-app notification: ${notification.title} (ID: ${notification.id}) - FCM already sent (notification was shown on phone)');
          } else if (wasShownByFCM) {
            // FCM handler already showed this notification when app was open
            // Don't show again to prevent duplicates
            debugPrint('🔕 Skipping in-app notification: ${notification.title} (ID: ${notification.id}) - Already shown by FCM foreground handler');
          }
        }
        
        // CRITICAL: Always call notifyListeners() to update the UI immediately
        // This ensures notifications appear in the history right away
        debugPrint('✅ Notification added to list: ${notification.title} (ID: ${notification.id}, Type: $notificationType) - Calling notifyListeners()');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error handling new notification: $e');
    }
  }

  // Handle updated notification from Supabase
  void _handleUpdatedNotification(Map<String, dynamic> data) {
    try {
      final timestampValue = data['timestamp'];
      final timestampInt = timestampValue is int 
          ? timestampValue 
          : (timestampValue is String ? int.tryParse(timestampValue) ?? 0 : 0);
      
      final updatedNotification = CustomerNotification.fromMap({
        'title': data['title'] ?? '',
        'message': data['message'] ?? '',
        'type': data['type'] ?? '',
        'timestamp': timestampInt,
        'isRead': data['is_read'] ?? false,
        'orderId': data['order_id']?.toString(),
      }, data['id']?.toString() ?? '');
      
      final index = _notifications.indexWhere((n) => n.id == updatedNotification.id);
      if (index != -1) {
        final wasUnread = !_notifications[index].isRead;
        final isNowRead = updatedNotification.isRead;
        
        _notifications[index] = updatedNotification;
        
        if (wasUnread && isNowRead) {
          _unreadCount--;
        } else if (!wasUnread && !isNowRead) {
          _unreadCount++;
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error handling updated notification: $e');
    }
  }

  // Handle deleted notification from Supabase
  void _handleDeletedNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    // Recalculate unread count
    _unreadCount = _notifications.where((notification) => !notification.isRead).length;
    notifyListeners();
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    _supabaseChannel?.unsubscribe();
    _notificationsRef = null;
    _supabaseChannel = null;
    super.dispose();
  }

  // Stop listening to notifications
  void stopListeningToNotifications(String customerId) {
    _notificationsSubscription?.cancel();
    _supabaseChannel?.unsubscribe();
    _notificationsSubscription = null;
    _notificationsRef = null;
    _supabaseChannel = null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Clear all notifications from memory (for switching users)
  void clearAllNotificationsFromMemory() {
    debugPrint('🧹 Clearing all notifications from memory');
    _notifications.clear();
    _unreadCount = 0;
    _isLoading = false;
    _error = null;
    _seenPopupIds.clear(); // Clear the seen notifications tracking
    _listenerStartTime = null; // Reset listener start time
    // NOTE: Don't clear _userDeletedNotifications - keep track of deleted notifications across sessions
    // This prevents recreating notifications that were explicitly deleted by the user
    notifyListeners();
  }

  // Clear notifications before loading new user's notifications
  void clearNotificationsBeforeLoading() {
    debugPrint('🧹 Clearing notifications before loading new user data');
    _notifications.clear();
    _unreadCount = 0;
    _seenPopupIds.clear(); // Clear the seen notifications tracking
    _listenerStartTime = null; // Reset listener start time
    // NOTE: Don't clear _userDeletedNotifications - keep track of deleted notifications
    // This prevents recreating notifications that were explicitly deleted by the user
    notifyListeners();
  }
  
  // Check if a notification was deleted by user (prevents recreation)
  bool isNotificationDeletedByUser(String? orderId, String notificationType) {
    if (orderId != null && orderId.isNotEmpty && notificationType.isNotEmpty) {
      final key = '${orderId}_$notificationType';
      final isDeleted = _userDeletedNotifications.contains(key);
      if (isDeleted) {
        debugPrint('🔒 Notification marked as deleted by user: $key');
      }
      return isDeleted;
    }
    return false;
  }
  
  // Check if a notification ID was deleted by user
  bool isNotificationIdDeletedByUser(String notificationId) {
    return _userDeletedNotifications.contains(notificationId);
  }
  
  // Get all deleted notification keys (for debugging)
  Set<String> get deletedNotificationKeys => Set.from(_userDeletedNotifications);
}
