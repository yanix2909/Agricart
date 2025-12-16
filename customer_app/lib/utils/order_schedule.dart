import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderSchedule {
  static DateTime? _coopNow;
  static int? _lastHeartbeatMs;
  static int? _deviceReceivedMs; // Device time when heartbeat was received
  static String? _heartbeatSource; // Track the source of the heartbeat
  static RealtimeChannel? _channel;
  static Timer? _periodicRefreshTimer; // Periodic refresh as backup
  static bool _isOrderingOpen = true;
  static final List<VoidCallback> _listeners = [];
  
  // Authoritative source identifier - web dashboard heartbeat
  static const String _authoritativeSource = 'staff-admin-desktop';
  
  // Stale thresholds: longer for authoritative web dashboard heartbeat
  static const int _authoritativeStaleThresholdMs = 10 * 60 * 1000; // 10 minutes for web dashboard
  static const int _nonAuthoritativeStaleThresholdMs = 2 * 60 * 1000; // 2 minutes for others

  /// Initialize listening to cooperative desktop time from Supabase
  static Future<void> initialize() async {
    try {
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Starting initialization...');
      }
      
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Supabase client initialized, fetching system_data...');
      }
      
      // Load initial value
      await _loadCoopTime(supabase);
      
      // Set up real-time subscription for system_data table
      _channel = supabase
          .channel('system_data_coopTime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'system_data',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: 'coopTime',
            ),
            callback: (payload) {
              if (kDebugMode) {
                debugPrint('[OrderSchedule] Real-time update received: ${payload.eventType}');
                debugPrint('[OrderSchedule] Payload: ${payload.newRecord}');
              }
              _loadCoopTime(supabase);
            },
          )
          .subscribe();
      
      // Set up periodic refresh as backup (every 20 seconds)
      // This ensures we get updates even if real-time fails
      // Web dashboard sends heartbeats every 15s, so 20s polling ensures we catch updates
      _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
        if (kDebugMode) {
          debugPrint('[OrderSchedule] Periodic refresh triggered - fetching latest heartbeat');
        }
        await _loadCoopTime(supabase);
      });
      
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Initialized Supabase real-time listener for cooperative time');
        debugPrint('[OrderSchedule] Set up periodic refresh (30s) as backup');
        debugPrint('[OrderSchedule] Current coop time: $_coopNow, last heartbeat: $_lastHeartbeatMs, source: $_heartbeatSource');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Error initializing: $e');
        debugPrint('[OrderSchedule] Stack trace: $stackTrace');
      }
      // Fallback to device time if Supabase fails
      final now = DateTime.now();
      _coopNow = now;
      _lastHeartbeatMs = now.millisecondsSinceEpoch;
      _deviceReceivedMs = now.millisecondsSinceEpoch;
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Falling back to device time: $_coopNow');
      }
    }
  }

  /// Load cooperative time from Supabase
  /// PRIORITIZES web dashboard heartbeat (staff-admin-desktop) as authoritative source
  static Future<void> _loadCoopTime(dynamic supabase) async {
    try {
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Fetching system_data from Supabase...');
      }
      
      final response = await supabase
          .from('system_data')
          .select()
          .eq('id', 'coopTime')
          .maybeSingle();

      if (kDebugMode) {
        debugPrint('[OrderSchedule] Response from Supabase: $response');
      }

      if (response != null && response is Map) {
        final epochMs = response['epoch_ms'];
        final source = response['source'] as String?;
        
        if (kDebugMode) {
          debugPrint('[OrderSchedule] Parsed epoch_ms: $epochMs, source: $source');
        }
        
        if (epochMs != null) {
          final epoch = epochMs is int ? epochMs : (epochMs is num ? epochMs.toInt() : null);
          if (epoch != null) {
            // CRITICAL: Prioritize web dashboard heartbeat (authoritative source)
            final isAuthoritative = source == _authoritativeSource;
            
            // Check if this heartbeat is newer than what we have
            final isNewer = _lastHeartbeatMs == null || epoch > _lastHeartbeatMs!;
            
            // Only update if:
            // 1. This is an authoritative heartbeat (web dashboard), OR
            // 2. We don't have a heartbeat yet, OR
            // 3. Current heartbeat is not authoritative and this one is, OR
            // 4. This heartbeat is newer than what we have (for same source updates)
            final shouldUpdate = isAuthoritative || 
                                 _lastHeartbeatMs == null || 
                                 _heartbeatSource != _authoritativeSource ||
                                 (isNewer && isAuthoritative && _heartbeatSource == _authoritativeSource);
            
            if (shouldUpdate) {
              final previousTime = _coopNow;
              final previousEpoch = _lastHeartbeatMs;
              
              _coopNow = DateTime.fromMillisecondsSinceEpoch(epoch);
              _lastHeartbeatMs = epoch;
              _deviceReceivedMs = DateTime.now().millisecondsSinceEpoch; // Track when we received it on device
              _heartbeatSource = source;
              
              if (kDebugMode) {
                debugPrint('[OrderSchedule] Heartbeat received (${isAuthoritative ? "AUTHORITATIVE" : "non-authoritative"}): epochMs=$epoch, source=$source, coopNow=$_coopNow, deviceReceived=${_deviceReceivedMs}');
                if (previousEpoch != null && previousTime != null) {
                  debugPrint('[OrderSchedule] Previous heartbeat: epoch=$previousEpoch, time=$previousTime');
                  debugPrint('[OrderSchedule] Time difference: ${epoch - previousEpoch}ms');
                }
              }
              
              // Always refresh ordering status after receiving a heartbeat
              final wasOrderingOpen = _isOrderingOpen;
              // Force recalculation with fresh time
              _isOrderingOpen = canPlaceOrder();
              
              if (kDebugMode) {
                final currentTime = _now();
                debugPrint('[OrderSchedule] Heartbeat processed - Ordering status: $_isOrderingOpen (was: $wasOrderingOpen)');
                debugPrint('[OrderSchedule] Current calculated time: $currentTime (weekday: ${currentTime.weekday})');
              }
              
              // Always notify listeners when we receive a heartbeat
              // This ensures UI updates when time changes (even if status didn't change)
              _notifyListeners();
            } else {
              if (kDebugMode) {
                debugPrint('[OrderSchedule] Ignoring non-authoritative heartbeat (source=$source). Using existing authoritative web dashboard heartbeat.');
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint('[OrderSchedule] Invalid epoch value: $epochMs');
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('[OrderSchedule] No epoch_ms found in response');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[OrderSchedule] No system_data found in Supabase (response is null or not a Map)');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Error loading coop time: $e');
        debugPrint('[OrderSchedule] Stack trace: $stackTrace');
      }
    }
  }

  /// Resolve cooperative time.
  /// PRIORITIZES web dashboard heartbeat (authoritative source) with extended stale threshold.
  /// Only falls back to device time if no authoritative heartbeat is available.
  static DateTime _now() {
    final coop = _coopNow;
    final lastMs = _lastHeartbeatMs;
    final deviceReceivedMs = _deviceReceivedMs;
    final source = _heartbeatSource;
    
    if (coop != null && lastMs != null && deviceReceivedMs != null) {
      final deviceNowMs = DateTime.now().millisecondsSinceEpoch;
      // Calculate elapsed time on device since we received the heartbeat
      final deviceElapsedMs = deviceNowMs - deviceReceivedMs;
      final isAuthoritative = source == _authoritativeSource;
      
      // Use extended stale threshold for authoritative web dashboard heartbeat
      final staleThreshold = isAuthoritative 
          ? _authoritativeStaleThresholdMs  // 10 minutes for web dashboard
          : _nonAuthoritativeStaleThresholdMs; // 2 minutes for others
      
      // Check if heartbeat is still fresh based on device elapsed time
      if (deviceElapsedMs <= staleThreshold) {
        // Calculate current server time: server_time_when_received + elapsed_device_time
        // This ensures we use the authoritative server time while accounting for time elapsed on device
        final currentServerTimeMs = lastMs + deviceElapsedMs;
        final currentTime = DateTime.fromMillisecondsSinceEpoch(currentServerTimeMs);
        
        if (kDebugMode && isAuthoritative) {
          debugPrint('[OrderSchedule] Using AUTHORITATIVE web dashboard heartbeat (server: ${lastMs}, elapsed: ${deviceElapsedMs ~/ 1000}s, current: $currentTime)');
        }
        return currentTime; // Use authoritative web dashboard time + elapsed device time
      } else {
        if (kDebugMode) {
          debugPrint('[OrderSchedule] Heartbeat stale (elapsed: ${deviceElapsedMs ~/ 1000}s, threshold: ${staleThreshold ~/ 1000}s, authoritative: $isAuthoritative)');
        }
      }
    }
    
    // Fallback to device time only if no heartbeat available
    // This ensures web dashboard time is always preferred when available
    if (kDebugMode) {
      if (coop == null) {
        debugPrint('[OrderSchedule] No heartbeat available, using device time');
      } else {
        debugPrint('[OrderSchedule] Heartbeat data incomplete (coop: $coop, lastMs: $lastMs, deviceReceivedMs: $deviceReceivedMs), using device time');
      }
    }
    return DateTime.now();
  }
  /// Check if ordering is currently allowed
  /// Ordering time: Monday 12:00 AM - Thursday 8:00 PM
  /// Cut-off: Thursday 8:01 PM - Sunday 11:59 PM
  static bool canPlaceOrder() {
    final now = _now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    bool allowed;
    
    // Allowed: Monday 12:00 AM (00:00) to Thursday 8:00 PM (20:00)
    if (weekday >= 1 && weekday <= 4) {
      // Monday-Wednesday: fully open all day (00:00 - 23:59)
      if (weekday >= 1 && weekday <= 3) {
        allowed = true;
      } 
      // Thursday: open until 8:00 PM (20:00), cut-off starts at 8:01 PM (20:01)
      else if (weekday == 4) {
        final hour = now.hour;
        final minute = now.minute;
        // Allow ordering up to and including Thursday 8:00 PM (20:00:00)
        // Cut-off starts at Thursday 8:01 PM (20:01:00)
        if (hour < 20) {
          // Before 8:00 PM - ordering allowed
          allowed = true;
        } else if (hour == 20 && minute == 0) {
          // Exactly 8:00 PM (20:00) - ordering allowed
          allowed = true;
        } else {
          // After 8:00 PM (8:01 PM onwards) - cut-off period, ordering not allowed
          allowed = false;
        }
      } else {
        allowed = false;
      }
    } 
    // Cut-off period: Friday-Sunday (Thursday 8:01 PM - Sunday 11:59 PM)
    else {
      allowed = false;
    }
    
    if (kDebugMode) {
      debugPrint('[OrderSchedule] canPlaceOrder? $allowed | now=$now (weekday=$weekday, ${now.hour}:${now.minute}:${now.second}) | coopNow=${_coopNow} lastHbMs=${_lastHeartbeatMs}');
    }
    return allowed;
  }
  
  /// Check if order cancellation is currently allowed
  /// Returns true if orders can be cancelled (Monday-Thursday before 1:00 PM)
  /// DISABLED FOR DEVELOPMENT: Always returns true
  static bool canCancelOrder() {
    // TODO: Re-enable time restrictions when going to production
    // return canPlaceOrder(); // Same logic as placing orders
    return true; // Always allow cancellation during development
  }
  
  /// Get the next ordering period start date
  /// Returns the next Monday at 12:00 AM
  static DateTime getNextOrderingPeriodStart() {
    final now = _now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    
    // Calculate days until next Monday
    int daysUntilMonday;
    if (weekday == 1) {
      // If it's Monday, get next Monday
      daysUntilMonday = 7;
    } else {
      daysUntilMonday = 8 - weekday;
    }
    
    final nextMonday = DateTime(now.year, now.month, now.day + daysUntilMonday, 0, 0);
    return nextMonday;
  }
  
  /// Get the current week's ordering period end date
  /// Returns Thursday at 8:00 PM (20:00) of current week
  static DateTime getCurrentOrderingPeriodEnd() {
    final now = _now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    
    // Calculate days until Thursday
    int daysUntilThursday;
    if (weekday <= 4) {
      // Monday-Thursday: days until Thursday
      daysUntilThursday = 4 - weekday;
    } else {
      // Friday-Sunday: days until next Thursday
      daysUntilThursday = 4 + (7 - weekday);
    }
    
    final thursday8PM = DateTime(now.year, now.month, now.day + daysUntilThursday, 20, 0);
    return thursday8PM;
  }
  
  /// Get the delivery date for orders placed in the current week
  /// Returns Saturday of the current week
  static DateTime getCurrentWeekDeliveryDate() {
    final now = _now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    
    // Calculate days until Saturday
    int daysUntilSaturday;
    if (weekday <= 6) {
      // Monday-Saturday: days until Saturday
      daysUntilSaturday = 6 - weekday;
    } else {
      // Sunday: days until next Saturday
      daysUntilSaturday = 6;
    }
    
    final saturday = DateTime(now.year, now.month, now.day + daysUntilSaturday, 0, 0);
    return saturday;
  }
  
  /// Get the alternative delivery date (Sunday) for orders placed in the current week
  /// Returns Sunday of the current week
  static DateTime getCurrentWeekAlternativeDeliveryDate() {
    final now = _now();
    final weekday = now.weekday; // 1=Mon..7=Sun
    
    // Calculate days until Sunday
    int daysUntilSunday;
    if (weekday == 7) {
      // If it's Sunday, get next Sunday
      daysUntilSunday = 7;
    } else {
      // Monday-Saturday: days until Sunday
      daysUntilSunday = 7 - weekday;
    }
    
    final sunday = DateTime(now.year, now.month, now.day + daysUntilSunday, 0, 0);
    return sunday;
  }
  
  /// Get a user-friendly message about the ordering schedule
  static String getOrderingScheduleMessage() {
    if (canPlaceOrder()) {
      final endTime = getCurrentOrderingPeriodEnd();
      return 'You can place orders until ${formatDateTime(endTime)}';
    } else {
      final nextStart = getNextOrderingPeriodStart();
      return 'Ordering is closed. Next ordering period starts ${formatDateTime(nextStart)}';
    }
  }
  
  /// Get a user-friendly message about the delivery schedule
  static String getDeliveryScheduleMessage() {
    final saturday = getCurrentWeekDeliveryDate();
    final sunday = getCurrentWeekAlternativeDeliveryDate();
    return 'Orders placed this week will be delivered on ${formatDate(saturday)} or ${formatDate(sunday)}';
  }
  
  /// Format DateTime for display
  static String formatDateTime(DateTime dateTime) {
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final weekday = weekdays[dateTime.weekday - 1];
    final time = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$weekday at $time';
  }
  
  /// Format Date for display
  static String formatDate(DateTime date) {
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    return '$weekday, $month ${date.day}';
  }
  
  /// Add a listener for order schedule changes
  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }
  
  /// Remove a listener for order schedule changes
  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
  
  /// Notify all listeners of schedule changes
  static void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[OrderSchedule] Error notifying listener: $e');
        }
      }
    }
  }
  
  /// Get current ordering status
  static bool get isOrderingOpen => _isOrderingOpen;

  /// Force refresh of ordering status based on current time
  /// Call this if you need to refresh the status after time sync
  static void refreshOrderingStatus() {
    final wasOrderingOpen = _isOrderingOpen;
    _isOrderingOpen = canPlaceOrder();
    
    if (wasOrderingOpen != _isOrderingOpen) {
      if (kDebugMode) {
        debugPrint('[OrderSchedule] Ordering status refreshed: $wasOrderingOpen -> $_isOrderingOpen');
      }
      _notifyListeners();
    }
  }

  /// Get current server time (for debugging)
  static DateTime? get currentServerTime => _coopNow != null && _lastHeartbeatMs != null && _deviceReceivedMs != null
      ? DateTime.fromMillisecondsSinceEpoch(_lastHeartbeatMs! + (DateTime.now().millisecondsSinceEpoch - _deviceReceivedMs!))
      : null;

  /// Dispose resources (unsubscribe from real-time and cancel timer)
  static void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
  }
}
