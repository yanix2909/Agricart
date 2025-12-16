import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

class AuthProvider with ChangeNotifier {

  String? _userId;
  Customer? _currentCustomer;
  bool _isLoading = true;  // Start with true to prevent login screen flash
  bool _isSigningIn = false;
  String? _error;
  Timer? _accountStatusListener;
  RealtimeChannel? _accountStatusRealtimeChannel;
  bool _isMonitoringDisabled = false;
  Timer? _timeoutTimer;
  int _consecutiveNetworkErrors = 0;
  bool _isNetworkError = false;

  String? get userId => _userId;
  Customer? get currentCustomer => _currentCustomer;
  bool get isLoading => _isLoading;
  bool get isSigningIn => _isSigningIn;
  String? get error => _error;
  bool get isAuthenticated => _userId != null && _currentCustomer != null;

  /// Hash password using SHA-256 with salt
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate a random salt for password hashing
  String _generateSalt() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = utf8.encode(random);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  AuthProvider() {
    _init();
  }

  void _init() {
    // Set timeout to prevent infinite loading
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (_isLoading) {
        debugPrint('Auth initialization timeout - setting isLoading to false');
        _isLoading = false;
        notifyListeners();
      }
    });

    try {
      // Check for existing Supabase session
      _checkSupabaseSession();
    } catch (e) {
      debugPrint('Auth initialization error: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _checkSupabaseSession() async {
    try {
      await SupabaseService.initialize();
      final session = SupabaseService.client.auth.currentSession;
      
      if (session != null && session.user != null) {
        final authUserId = session.user!.id;
        final authUserEmail = session.user!.email;
        
        debugPrint('Session found - Auth User ID: $authUserId, Email: $authUserEmail');
        
        // Try to load customer data by UID first
        Map<String, dynamic>? customerData;
        try {
          customerData = await SupabaseService.loadCustomer(authUserId);
        } on TimeoutException {
          debugPrint('⏱️ Network timeout loading customer during session check - skipping');
          return; // Don't proceed if network error
        } on SocketException {
          debugPrint('🌐 No internet during session check - skipping');
          return; // Don't proceed if no internet
        } catch (e) {
          // Check if this is a network-related error
          final errorString = e.toString().toLowerCase();
          final isNetworkError = 
              errorString.contains('network') ||
              errorString.contains('connection') ||
              errorString.contains('timeout') ||
              errorString.contains('502') ||
              errorString.contains('bad gateway') ||
              errorString.contains('ssl') ||
              errorString.contains('tls') ||
              errorString.contains('clientexception') ||
              errorString.contains('postgresterror') ||
              errorString.contains('gateway error');
          
          if (isNetworkError) {
            debugPrint('🔌 Network error during session check - skipping: $e');
            return; // Don't proceed if network error
          }
          // For other errors, continue (might be account not found, which is handled below)
          debugPrint('⚠️ Error loading customer during session check: $e');
        }
        
        // If customer not found by UID, try to find by email and update UID
        if (customerData == null && authUserEmail != null) {
          debugPrint('Customer not found by UID, searching by email: $authUserEmail');
          try {
            final customerByEmail = await SupabaseService.client
                .from('customers')
                .select('uid, email')
                .eq('email', authUserEmail.toLowerCase())
                .maybeSingle() as Map<String, dynamic>?;
            
            if (customerByEmail != null) {
              final existingUid = customerByEmail['uid'] as String?;
              debugPrint('Found customer by email with UID: $existingUid');
              
              // If UID doesn't match, update it
              if (existingUid != authUserId) {
                debugPrint('UID mismatch detected. Updating customer UID from $existingUid to $authUserId');
                await SupabaseService.client
                    .from('customers')
                    .update({'uid': authUserId})
                    .eq('email', authUserEmail.toLowerCase());
              }
              
              // Now try loading again with the auth user ID
              customerData = await SupabaseService.loadCustomer(authUserId);
            }
          } catch (e) {
            debugPrint('Error finding customer by email: $e');
          }
        }
        
        _userId = authUserId;
        await _loadCustomerData(_userId!);
        _startAccountStatusMonitoring(_userId!);
        // Save/update FCM token for this user so backend can send push notifications
        // This will work properly if notification permission was granted
        try {
          debugPrint('🔑 Attempting to save FCM token for logged-in user...');
          await NotificationService.saveFCMToken(_userId!);
          debugPrint('✅ FCM token save process completed');
        } catch (e) {
          debugPrint('❌ Failed to save FCM token: $e');
          debugPrint('ℹ️ This may be because notification permission is not granted');
          debugPrint('ℹ️ Token will be saved automatically when permission is granted');
        }
        // Request battery optimization exemption after login to ensure notifications work
        // This is done after login so user is engaged and more likely to grant permission
        try {
          debugPrint('🔋 Requesting battery optimization exemption after login...');
          await NotificationService.requestBatteryOptimizationExemption();
          debugPrint('✅ Battery optimization request completed');
        } catch (e) {
          debugPrint('❌ Failed to request battery optimization exemption: $e');
          debugPrint('ℹ️ This is non-critical - notifications may still work');
        }
      } else {
        _userId = null;
        _currentCustomer = null;
        _stopAccountStatusMonitoring();
      }
      
      if (_isLoading) {
        _isLoading = false;
        _timeoutTimer?.cancel();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking Supabase session: $e');
      _userId = null;
      _currentCustomer = null;
      notifyListeners();
    }
  }

  void _startAccountStatusMonitoring(String uid) {
    _stopAccountStatusMonitoring();
    
    try {
      debugPrint('🔍 Starting account status monitoring for user: $uid (using Supabase realtime + polling fallback)');
      
      // First, set up Supabase realtime subscription for immediate detection
      _setupRealtimeAccountStatusMonitoring(uid);
      
      // Also set up periodic polling as a fallback (reduced to 2 seconds for immediate detection if realtime fails)
      _accountStatusListener = Timer.periodic(const Duration(seconds: 2), (timer) async {
        // Skip processing if monitoring is temporarily disabled
        if (_isMonitoringDisabled) {
          debugPrint('🔒 Account status monitoring is disabled - skipping check');
          return;
        }
        
        try {
          await SupabaseService.initialize();
          
          // Add timeout for the network request
          final customerData = await SupabaseService.loadCustomer(uid)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  debugPrint('⏱️ Account status check timed out (slow internet)');
                  throw TimeoutException('Network request timed out', const Duration(seconds: 10));
                },
              );
          
          // If we successfully connected and got a response, reset network error counters
          // This means the connection is working, so any deactivation is real
          _consecutiveNetworkErrors = 0;
          _isNetworkError = false;
          _error = null;
          notifyListeners();
          
          // If we got null, treat as transient fetch issue unless we can confirm deactivation
          if (customerData == null) {
            _consecutiveNetworkErrors++;
            _isNetworkError = true;
            debugPrint('⚠️ Supabase returned null customer data (possible transient issue) - NOT treating as deactivation. Count=$_consecutiveNetworkErrors');
            if (_consecutiveNetworkErrors == 1) {
              _error = 'Connection issue detected. Please check your internet connection.';
              notifyListeners();
            }
            return; // skip deactivation on null response
          }
          
          // Check account status from successful response
          final accountStatus = customerData['accountStatus'] as String?;
          debugPrint('📊 Account status check: $accountStatus');
          
          // If we successfully connected and account is not active, it's actually deactivated
          if (accountStatus != 'active') {
            debugPrint('⚠️ Account deactivated (status: $accountStatus) - handling deactivation');
            _handleAccountDeactivation();
            timer.cancel();
          } else {
            debugPrint('✅ Account status is active - no action needed');
          }
        } on TimeoutException catch (e) {
          // Network timeout - this is a connection issue, NOT account deactivation
          _consecutiveNetworkErrors++;
          _isNetworkError = true;
          debugPrint('⏱️ Network timeout error ($_consecutiveNetworkErrors): $e - This is a connection issue, NOT account deactivation');
          
          // Show network error message but don't logout
          if (_consecutiveNetworkErrors == 1) {
            _error = 'Slow internet connection detected. Please check your network and try again.';
            notifyListeners();
          }
        } on SocketException catch (e) {
          // No internet connection - this is a connection issue, NOT account deactivation
          _consecutiveNetworkErrors++;
          _isNetworkError = true;
          debugPrint('🌐 Network connection error ($_consecutiveNetworkErrors): $e - This is a connection issue, NOT account deactivation');
          
          if (_consecutiveNetworkErrors == 1) {
            _error = 'No internet connection. Please check your network settings.';
            notifyListeners();
          }
        } on PostgrestException catch (e) {
          // Supabase-specific errors - check if it's a network issue
          if (e.code == 'PGRST116' || e.message.contains('timeout') || e.message.contains('network')) {
            // Network-related Supabase error - this is a connection issue, NOT account deactivation
            _consecutiveNetworkErrors++;
            _isNetworkError = true;
            debugPrint('🔌 Supabase network error ($_consecutiveNetworkErrors): $e - This is a connection issue, NOT account deactivation');
            
            if (_consecutiveNetworkErrors == 1) {
              _error = 'Connection issue detected. Please check your internet connection.';
              notifyListeners();
            }
          } else {
            // Other Supabase errors (like 404, 403, etc.) - might indicate account issue
            // But we need to be careful - only treat as deactivation if we're sure
            debugPrint('❌ Supabase error checking account status: $e (code: ${e.code})');
            // Don't treat as deactivation unless we're certain - could be temporary server issue
          }
        } catch (e) {
          // Unknown error - treat as network issue to be safe
          _consecutiveNetworkErrors++;
          _isNetworkError = true;
          debugPrint('❌ Unexpected error checking account status ($_consecutiveNetworkErrors): $e - Treating as connection issue');
          
          if (_consecutiveNetworkErrors == 1) {
            _error = 'Unable to verify account status. Please check your connection.';
            notifyListeners();
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Failed to start account monitoring: $e');
    }
  }

  void _stopAccountStatusMonitoring() {
    // Stop realtime subscription
    if (_accountStatusRealtimeChannel != null) {
      try {
        _accountStatusRealtimeChannel!.unsubscribe();
        debugPrint('✅ Stopped account status realtime subscription');
      } catch (e) {
        debugPrint('⚠️ Error unsubscribing from realtime channel: $e');
      }
      _accountStatusRealtimeChannel = null;
    }
    
    // Stop polling timer
    if (_accountStatusListener != null) {
      _accountStatusListener!.cancel();
      _accountStatusListener = null;
    }
  }

  /// Set up Supabase realtime subscription for immediate account status detection
  void _setupRealtimeAccountStatusMonitoring(String uid) {
    // Initialize Supabase asynchronously without blocking
    SupabaseService.initialize().then((_) {
      try {
        final supabase = SupabaseService.client;
        
        debugPrint('🔔 Setting up Supabase realtime subscription for customer account status: $uid');
        
        _accountStatusRealtimeChannel = supabase
          .channel('customer_account_status_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'customers',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'uid',
              value: uid,
            ),
            callback: (payload) {
              debugPrint('🔄 Customer account update detected in realtime');
              _handleRealtimeAccountUpdate(payload.newRecord as Map<String, dynamic>);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'customers',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'uid',
              value: uid,
            ),
            callback: (payload) {
              debugPrint('🗑️ Customer account deletion detected in realtime');
              _handleRealtimeAccountDeletion();
            },
          )
          .subscribe(
            (status, [error]) {
              if (status == RealtimeSubscribeStatus.subscribed) {
                debugPrint('✅ Account status realtime subscription active');
                // Reset network error state on successful subscription
                _consecutiveNetworkErrors = 0;
                _isNetworkError = false;
                // Immediately check account status after successful subscription
                _performImmediateAccountStatusCheck(uid);
              } else if (status == RealtimeSubscribeStatus.timedOut) {
                debugPrint('⏱️ Account status realtime subscription timed out - will use polling fallback');
                // Try to resubscribe after a shorter delay
                Future.delayed(const Duration(seconds: 2), () {
                  if (_userId != null && _accountStatusRealtimeChannel != null) {
                    debugPrint('🔄 Attempting to resubscribe to realtime channel...');
                    _setupRealtimeAccountStatusMonitoring(_userId!);
                  }
                });
              } else if (status == RealtimeSubscribeStatus.channelError) {
                debugPrint('❌ Account status realtime subscription error: $error - will use polling fallback');
                // Try to resubscribe after a shorter delay
                Future.delayed(const Duration(seconds: 2), () {
                  if (_userId != null && _accountStatusRealtimeChannel != null) {
                    debugPrint('🔄 Attempting to resubscribe to realtime channel after error...');
                    _setupRealtimeAccountStatusMonitoring(_userId!);
                  }
                });
              }
            },
          );
      
        debugPrint('✅ Supabase realtime subscription for account status set up');
      } catch (e) {
        debugPrint('❌ Failed to set up realtime account status monitoring: $e - will use polling fallback');
        // Continue with polling as fallback
      }
    }).catchError((e) {
      debugPrint('❌ Failed to initialize Supabase for realtime monitoring: $e - will use polling fallback');
    });
  }

  /// Perform an immediate account status check (used after realtime subscription and on demand)
  Future<void> _performImmediateAccountStatusCheck(String uid) async {
    if (_isMonitoringDisabled) {
      return;
    }

    try {
      await SupabaseService.initialize();
      
      final customerData = await SupabaseService.loadCustomer(uid)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⏱️ Immediate account check timed out - treating as network error, not deactivation');
              throw TimeoutException('Network request timed out', const Duration(seconds: 5));
            },
          );
      
      // Only treat null as deactivation if we successfully connected (no timeout/network error)
      if (customerData == null) {
        debugPrint('⚠️ Account not found during immediate check - account removed/deactivated');
        _handleAccountDeactivation();
        return;
      }
      
      final accountStatus = customerData['accountStatus'] as String?;
      debugPrint('📊 Immediate account status check: $accountStatus');
      
      if (accountStatus != 'active') {
        debugPrint('⚠️ Account deactivated during immediate check (status: $accountStatus)');
        _handleAccountDeactivation();
      }
    } on TimeoutException {
      // Network timeout - don't treat as deactivation, just log it
      debugPrint('⏱️ Network timeout during immediate check - not treating as deactivation');
      // Don't set error flags here - let the polling timer handle network error states
    } on SocketException {
      // No internet - don't treat as deactivation
      debugPrint('🌐 No internet during immediate check - not treating as deactivation');
      // Don't set error flags here - let the polling timer handle network error states
    } catch (e) {
      // Check if this is a network-related error (not actual account deactivation)
      final errorString = e.toString().toLowerCase();
      final isNetworkError = 
          errorString.contains('network') ||
          errorString.contains('connection') ||
          errorString.contains('timeout') ||
          errorString.contains('502') ||
          errorString.contains('bad gateway') ||
          errorString.contains('ssl') ||
          errorString.contains('tls') ||
          errorString.contains('clientexception') ||
          errorString.contains('postgresterror') ||
          (e is Exception && e.toString().contains('502')) ||
          (e is Exception && e.toString().contains('Bad Gateway'));
      
      if (isNetworkError) {
        debugPrint('🔌 Network error during immediate check - NOT treating as deactivation: $e');
        // Don't treat network errors as deactivation - let polling handle it
        return;
      }
      
      // For other errors, log but don't treat as deactivation unless we're certain
      debugPrint('❌ Error during immediate account check: $e - NOT treating as deactivation (could be temporary)');
      // Don't treat errors as deactivation - let polling handle it
    }
  }

  /// Force an immediate account status check (can be called from UI)
  Future<void> forceAccountStatusCheck() async {
    if (_userId != null) {
      await _performImmediateAccountStatusCheck(_userId!);
    }
  }

  /// Handle realtime account update event
  void _handleRealtimeAccountUpdate(Map<String, dynamic> newRecord) {
    try {
      // Skip if monitoring is temporarily disabled
      if (_isMonitoringDisabled) {
        debugPrint('🔒 Account status monitoring is disabled - skipping realtime update');
        return;
      }
      
      final accountStatus = newRecord['account_status'] as String?;
      debugPrint('📊 Realtime account status update: $accountStatus');
      
      // Check if account status changed to non-active
      if (accountStatus != null && accountStatus != 'active') {
        debugPrint('⚠️ Account deactivated in realtime (status: $accountStatus) - handling deactivation');
        _handleAccountDeactivation();
      } else if (accountStatus == 'active') {
        debugPrint('✅ Account status is active - no action needed');
        // Reset any error states if account is active
        if (_error != null && _error!.contains('deactivated')) {
          _error = null;
          _isNetworkError = false;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling realtime account update: $e');
    }
  }

  /// Handle realtime account deletion event
  void _handleRealtimeAccountDeletion() {
    try {
      // Skip if monitoring is temporarily disabled
      if (_isMonitoringDisabled) {
        debugPrint('🔒 Account status monitoring is disabled - skipping realtime deletion');
        return;
      }
      
      debugPrint('⚠️ Account deleted in realtime - handling deactivation');
      _handleAccountDeactivation();
    } catch (e) {
      debugPrint('❌ Error handling realtime account deletion: $e');
    }
  }

  // Temporarily disable account status monitoring during critical operations
  void temporarilyDisableMonitoring() {
    debugPrint('🔒 Temporarily disabling account status monitoring');
    _isMonitoringDisabled = true;
  }

  // Re-enable account status monitoring
  void reEnableMonitoring() {
    debugPrint('🔓 Re-enabling account status monitoring');
    _isMonitoringDisabled = false;
  }

  // Clear error and reset network error state
  void clearError() {
    _error = null;
    _isNetworkError = false;
    _consecutiveNetworkErrors = 0;
    notifyListeners();
  }

  // Retry account status check manually
  Future<void> retryAccountStatusCheck() async {
    if (_userId == null) return;
    
    clearError();
    _isMonitoringDisabled = true; // Temporarily disable to prevent conflicts
    
    try {
      await SupabaseService.initialize();
      final customerData = await SupabaseService.loadCustomer(_userId!)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Network request timed out', const Duration(seconds: 10));
            },
          );
      
      if (customerData == null) {
        // If we successfully connected but got null, account doesn't exist (removed/deactivated)
        debugPrint('⚠️ Account not found during retry - account removed/deactivated');
        _handleAccountDeactivation();
        return;
      }
      
      final accountStatus = customerData['accountStatus'] as String?;
      
      if (accountStatus != 'active') {
        // Account is deactivated - handle it properly
        debugPrint('⚠️ Account deactivated during retry (status: $accountStatus)');
        _handleAccountDeactivation();
        return;
      }
      
      // Success - reset everything
      _consecutiveNetworkErrors = 0;
      _isNetworkError = false;
      _error = null;
      notifyListeners();
    } on TimeoutException {
      _error = 'Connection timed out. Please check your internet connection and try again.';
      _isNetworkError = true;
      notifyListeners();
    } on SocketException {
      _error = 'No internet connection. Please check your network settings.';
      _isNetworkError = true;
      notifyListeners();
    } catch (e) {
      // Check if this is a network-related error
      final errorString = e.toString().toLowerCase();
      final isNetworkError = 
          errorString.contains('network') ||
          errorString.contains('connection') ||
          errorString.contains('timeout') ||
          errorString.contains('502') ||
          errorString.contains('bad gateway') ||
          errorString.contains('ssl') ||
          errorString.contains('tls') ||
          errorString.contains('clientexception') ||
          errorString.contains('postgresterror') ||
          errorString.contains('gateway error');
      
      if (isNetworkError) {
        _error = 'Connection issue detected. Please check your internet connection and try again.';
        _isNetworkError = true;
        debugPrint('🔌 Network error retrying account status check - NOT treating as deactivation: $e');
      } else {
        _error = 'Unable to verify account status. Please try again.';
        _isNetworkError = true;
        debugPrint('❌ Error retrying account status check: $e');
      }
      notifyListeners();
    } finally {
      _isMonitoringDisabled = false;
    }
  }

  bool get isNetworkError => _isNetworkError;

  /// Immediately check account status before critical operations
  /// Returns true if account is active, false if deactivated/removed
  /// Throws exception if there's a network error (should not block operation)
  Future<bool> checkAccountStatusImmediately() async {
    if (_userId == null) {
      debugPrint('⚠️ No user ID - cannot check account status');
      return false;
    }

    try {
      await SupabaseService.initialize();
      
      // Quick check with shorter timeout for immediate operations
      final customerData = await SupabaseService.loadCustomer(_userId!)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⏱️ Immediate account check timed out - treating as network error, not deactivation');
              throw TimeoutException('Network request timed out', const Duration(seconds: 5));
            },
          );
      
      // Only treat null as deactivation if we successfully connected (no timeout/network error)
      if (customerData == null) {
        debugPrint('⚠️ Account not found during immediate check - account removed');
        _handleAccountDeactivation();
        return false;
      }
      
      // Check account status
      final accountStatus = customerData['accountStatus'] as String?;
      debugPrint('📊 Immediate account status check: $accountStatus');
      
      if (accountStatus != 'active') {
        debugPrint('⚠️ Account deactivated during immediate check (status: $accountStatus)');
        _handleAccountDeactivation();
        return false;
      }
      
      // Account is active
      return true;
    } on TimeoutException {
      // Timeout - don't block operation, but log it
      debugPrint('⏱️ Immediate account check timed out - allowing operation (background monitoring will catch deactivation)');
      return true; // Allow operation to proceed
    } on SocketException {
      // No internet - don't block operation
      debugPrint('🌐 No internet during immediate check - allowing operation');
      return true; // Allow operation to proceed
    } catch (e) {
      // Check if this is a network-related error (not actual account deactivation)
      final errorString = e.toString().toLowerCase();
      final isNetworkError = 
          errorString.contains('network') ||
          errorString.contains('connection') ||
          errorString.contains('timeout') ||
          errorString.contains('502') ||
          errorString.contains('bad gateway') ||
          errorString.contains('ssl') ||
          errorString.contains('tls') ||
          errorString.contains('clientexception') ||
          errorString.contains('postgresterror') ||
          (e is Exception && e.toString().contains('502')) ||
          (e is Exception && e.toString().contains('Bad Gateway'));
      
      if (isNetworkError) {
        debugPrint('🔌 Network error during immediate check - allowing operation (NOT deactivation): $e');
        return true; // Allow operation to proceed, background monitoring will catch issues
      }
      
      // Other errors - log but don't block
      debugPrint('❌ Error during immediate account check: $e - allowing operation');
      return true; // Allow operation to proceed, background monitoring will catch issues
    }
  }

  void _handleAccountDeactivation() {
    debugPrint('🚫 Handling account deactivation...');
    debugPrint('🚫 Stack trace: ${StackTrace.current}');
    _error = 'Your account has been deactivated. Please contact our AgriCart staff for more information.';
    
    // Save userId before clearing it (needed for FCM token removal)
    final customerIdToRemoveToken = _userId;
    
    // Clear customer data immediately to ensure isAuthenticated becomes false
    _currentCustomer = null;
    _userId = null; // Set immediately so isAuthenticated is false right away
    
    // Explicitly mark this as NOT a network error (it's actual deactivation)
    _isNetworkError = false;
    _consecutiveNetworkErrors = 0;
    
    // Stop monitoring before signing out
    _stopAccountStatusMonitoring();
    
    // Remove FCM token so deactivated customer doesn't receive notifications
    if (customerIdToRemoveToken != null) {
      NotificationService.removeFCMToken(customerIdToRemoveToken).then((_) {
        debugPrint('✅ FCM token removed due to account deactivation');
      }).catchError((error) {
        debugPrint('⚠️ Error removing FCM token on deactivation: $error');
        // Non-critical - continue with sign out
      });
    }
    
    // Sign out the user (async, but we've already cleared local state)
    SupabaseService.client.auth.signOut().then((_) {
      debugPrint('✅ User signed out due to account deactivation');
      // _userId is already null, but ensure it stays null
      _userId = null;
    }).catchError((error) {
      debugPrint('❌ Error signing out user: $error');
      // Even if signOut fails, user is already logged out locally
      _userId = null;
    });
    
    notifyListeners();
  }

  /// Check if deactivation dialog has been shown/acknowledged
  Future<bool> hasDeactivationDialogBeenShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('deactivation_dialog_shown') ?? false;
    } catch (e) {
      debugPrint('Error checking deactivation dialog flag: $e');
      return false;
    }
  }

  /// Mark deactivation dialog as shown/acknowledged
  Future<void> markDeactivationDialogAsShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('deactivation_dialog_shown', true);
      debugPrint('✅ Deactivation dialog marked as shown');
    } catch (e) {
      debugPrint('Error marking deactivation dialog as shown: $e');
    }
  }

  /// Clear deactivation dialog flag (when account is reactivated or user logs in successfully)
  Future<void> clearDeactivationDialogFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('deactivation_dialog_shown');
      debugPrint('✅ Deactivation dialog flag cleared');
    } catch (e) {
      debugPrint('Error clearing deactivation dialog flag: $e');
    }
  }

  String getWelcomeMessage() {
    if (_currentCustomer == null) return '';
    
    // Use hasLoggedInBefore flag to determine if this is a first-time login
    // This flag is set to false for new users and becomes true after they interact with the app
    debugPrint('=== WELCOME MESSAGE DEBUG ===');
    debugPrint('hasLoggedInBefore: ${_currentCustomer!.hasLoggedInBefore}');
    debugPrint('Customer: ${_currentCustomer!.fullName}');
    debugPrint('Returning: ${_currentCustomer!.hasLoggedInBefore ? "Welcome back" : "Welcome"}');
    debugPrint('===============================');
    
    return _currentCustomer!.hasLoggedInBefore ? 'Welcome back!' : 'Welcome!';
  }

  Future<void> markUserAsLoggedInBefore() async {
    if (_currentCustomer == null || _currentCustomer!.hasLoggedInBefore) return;
    
    debugPrint('Marking user as having logged in before');
    final now = DateTime.now();
    await SupabaseService.updateCustomer(_currentCustomer!.uid, {
      'hasLoggedInBefore': true,
      'updatedAt': now.millisecondsSinceEpoch,
    });
    
    _currentCustomer = _currentCustomer!.copyWith(
      hasLoggedInBefore: true,
      updatedAt: now,
    );
    notifyListeners();
  }


  Future<bool> checkUsernameAvailability(String username) async {
    try {
      debugPrint('=== CHECKING USERNAME AVAILABILITY ===');
      debugPrint('Username to check: $username');
      
      await SupabaseService.initialize();
      final existenceCheck = await SupabaseService.checkCustomerExists(username: username);
      
      final isAvailable = !(existenceCheck['username'] ?? false);
      
      debugPrint('Username ${isAvailable ? 'is' : 'is not'} available');
      debugPrint('Returning: $isAvailable');
      debugPrint('=====================================');
      return isAvailable;
    } catch (e) {
      debugPrint('Error checking username availability: $e');
      return false;
    }
  }

  Future<bool> checkPhoneAvailability(String phone, {String? excludeCustomerId}) async {
    try {
      debugPrint('=== CHECKING PHONE AVAILABILITY ===');
      debugPrint('Phone to check: $phone');
      if (excludeCustomerId != null) {
        debugPrint('Excluding customer ID: $excludeCustomerId');
      }
      
      await SupabaseService.initialize();
      final isAvailable = await SupabaseService.checkPhoneAvailabilityComprehensive(
        phone,
        excludeCustomerId: excludeCustomerId,
      );
      
      debugPrint('Phone ${isAvailable ? 'is' : 'is not'} available');
      debugPrint('Returning: $isAvailable');
      debugPrint('===================================');
      return isAvailable;
    } catch (e) {
      debugPrint('Error checking phone availability: $e');
      return false;
    }
  }

  Future<bool> checkEmailAvailability(String email) async {
    try {
      debugPrint('=== CHECKING EMAIL AVAILABILITY ===');
      debugPrint('Email to check: $email');
      
      await SupabaseService.initialize();
      final existenceCheck = await SupabaseService.checkCustomerExists(email: email);
      
      final isAvailable = !(existenceCheck['email'] ?? false);
      
      debugPrint('Email ${isAvailable ? 'is' : 'is not'} available');
      debugPrint('Returning: $isAvailable');
      debugPrint('==================================');
      return isAvailable;
    } catch (e) {
      debugPrint('Error checking email availability: $e');
      return false;
    }
  }

  Future<void> _loadCustomerData(String uid) async {
    try {
      debugPrint('Loading customer data for uid: $uid');
      await SupabaseService.initialize();
      final customerData = await SupabaseService.loadCustomer(uid);
      
      if (customerData != null) {
        _currentCustomer = Customer.fromMap(customerData, uid);

        // Check verification status
        final verificationStatus = _currentCustomer!.verificationStatus;
        final accountStatus = _currentCustomer!.accountStatus;
        
        debugPrint('Customer verification status: $verificationStatus');
        debugPrint('Customer account status: $accountStatus');

        if (verificationStatus == 'rejected') {
          _error = 'Your account registration has been rejected. Please contact support or try registering again.';
          _currentCustomer = null;
          await SupabaseService.client.auth.signOut();
          _userId = null;
          notifyListeners();
          return;
        } else if (accountStatus == 'inactive') {
          _error = 'Your account has been deactivated. Please contact our AgriCart staff for more information.';
          _currentCustomer = null;
          await SupabaseService.client.auth.signOut();
          _userId = null;
          notifyListeners();
          return;
        } else if (verificationStatus != 'approved' || accountStatus != 'active') {
          _error = 'Your account is pending verification. Please wait for admin approval.';
          _currentCustomer = null;
          await SupabaseService.client.auth.signOut();
          _userId = null;
          notifyListeners();
          return;
        }

        // Check if this is a first-time login
        if (!_currentCustomer!.hasLoggedInBefore) {
          debugPrint('First time login detected');
          // Mark user as having logged in before
          final now = DateTime.now();
          await SupabaseService.updateCustomer(uid, {
            'hasLoggedInBefore': true,
            'updatedAt': now.millisecondsSinceEpoch,
          });
          
          _currentCustomer = _currentCustomer!.copyWith(
            hasLoggedInBefore: true,
            updatedAt: now,
          );
        } else {
          debugPrint('Returning user');
        }
        
        _error = null;
        debugPrint('Customer data loaded successfully from Supabase');
        } else {
          debugPrint('Customer profile not found in Supabase');
          // Customer not found in Supabase - account may have been removed or rejected
          _error = 'Your account has been removed. Please contact our AgriCart staff for more information.';
          
        _currentCustomer = null;
        await SupabaseService.client.auth.signOut();
        _userId = null;
        }
    } on TimeoutException {
      // Network timeout - don't sign out, just log it
      debugPrint('⏱️ Network timeout loading customer data - NOT signing out');
      _error = 'Connection timeout. Please check your internet connection.';
      // Don't sign out on network errors
    } on SocketException {
      // No internet - don't sign out
      debugPrint('🌐 No internet loading customer data - NOT signing out');
      _error = 'No internet connection. Please check your network settings.';
      // Don't sign out on network errors
    } catch (e) {
      // Check if this is a network-related error
      final errorString = e.toString().toLowerCase();
      final isNetworkError = 
          errorString.contains('network') ||
          errorString.contains('connection') ||
          errorString.contains('timeout') ||
          errorString.contains('502') ||
          errorString.contains('bad gateway') ||
          errorString.contains('ssl') ||
          errorString.contains('tls') ||
          errorString.contains('clientexception') ||
          errorString.contains('postgresterror') ||
          errorString.contains('gateway error');
      
      if (isNetworkError) {
        debugPrint('🔌 Network error loading customer data - NOT signing out: $e');
        _error = 'Connection issue. Please check your internet connection.';
        // Don't sign out on network errors
      } else {
        // Other errors - might be actual account issue, but be cautious
        debugPrint('❌ Error loading customer data: $e');
        _error = 'Failed to load customer data. Please try again.';
        // Don't automatically sign out - let user retry
      }
    }
    notifyListeners();
  }

  /// Public method to refresh current customer data from Supabase
  /// This is useful when customer data changes (e.g., after placing an order)
  Future<void> refreshCustomerData() async {
    if (_userId == null) {
      debugPrint('Cannot refresh customer data: no user logged in');
      return;
    }
    
    try {
      debugPrint('Refreshing customer data for uid: $_userId');
      await SupabaseService.initialize();
      final customerData = await SupabaseService.loadCustomer(_userId!);
      
      if (customerData != null) {
        _currentCustomer = Customer.fromMap(customerData, _userId!);
        _error = null;
        debugPrint('✅ Customer data refreshed successfully');
        debugPrint('   Total Orders: ${_currentCustomer!.totalOrders}');
        debugPrint('   Total Spent: ${_currentCustomer!.totalSpent}');
        notifyListeners();
      } else {
        debugPrint('⚠️ Customer data not found during refresh');
      }
    } catch (e) {
      debugPrint('❌ Error refreshing customer data: $e');
      // Don't sign out the user if refresh fails, just log the error
    }
  }

  /// Public method to reload session and customer data
  /// Useful after OTP verification or when session is established externally
  Future<void> reloadSessionAndCustomerData() async {
    debugPrint('Reloading session and customer data...');
    await _checkSupabaseSession();
  }

  Future<bool> register({
    required String username,
    required String fullName,
    String? firstName,
    String? lastName,
    String? middleInitial,
    String? suffix,
    required int age,
    required String gender,
    required String email,
    required String phone,
    required String address,
    String? street,
    String? sitio,
    String? barangay,
    required String password,
    required String confirmPassword,
    File? idFrontPhoto,
    File? idBackPhoto,
    required String idType,
    DateTime? birthday,
  }) async {
    try {
      debugPrint('=== STARTING REGISTRATION ===');
      debugPrint('Email: $email');
      debugPrint('Username: $username');

      // Validate required fields
      if (username.isEmpty || email.isEmpty || password.isEmpty || 
          fullName.isEmpty || phone.isEmpty || address.isEmpty) {
        _error = 'Please fill in all required fields';
        notifyListeners();
        return false;
      }

      // Validate ID photos for new registration
      if (idFrontPhoto == null || idBackPhoto == null) {
        _error = 'Please upload both front and back ID photos';
        notifyListeners();
        return false;
      }

      // Reset state and set loading
      _error = null;
      _isLoading = true;
      _isSigningIn = true;
      notifyListeners();
      
      debugPrint('=== Starting registration process ===');
      debugPrint('Username: $username');
      debugPrint('Email: $email');

      // Step 1: Check if username/email/phone already exists in Supabase
      debugPrint('Checking username, email, and phone availability in Supabase...');
      await SupabaseService.initialize();
      final existenceCheck = await SupabaseService.checkCustomerExists(
        username: username,
        email: email,
        phone: phone,
      );

      // Check if username is already taken
      if (existenceCheck['username'] == true) {
        _error = 'Username is already taken';
        notifyListeners();
        return false;
      }
      
      // Check if email is already taken
      if (existenceCheck['email'] == true) {
        _error = 'An account already exists with this email';
        notifyListeners();
        return false;
      }
      
      // Check if phone number is already taken
      if (existenceCheck['phone'] == true) {
        _error = 'Phone number is already registered';
        notifyListeners();
        return false;
      }

      // Step 2: Create Supabase Auth account and hash password
      debugPrint('Creating Supabase Auth account...');
      final salt = _generateSalt();
      final passwordHash = _hashPassword(password, salt);
      
      final supabaseClient = SupabaseService.client;
      final authResponse = await supabaseClient.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'full_name': fullName,
        },
      );

      if (authResponse.user == null) {
        _error = 'Failed to create account';
        notifyListeners();
        return false;
      }

      final userId = authResponse.user!.id;
      debugPrint('Supabase Auth account created: $userId');

      // Step 3: Upload ID photos to Supabase
      debugPrint('Uploading ID photos to Supabase...');
      String? idFrontPhotoUrl;
      String? idBackPhotoUrl;

      try {
        if (idFrontPhoto != null && idBackPhoto != null) {
          // Initialize Supabase if not already initialized
          await SupabaseService.initialize();

          // Generate unique file names using customer UID
          final customerId = userId;
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final frontFileName = '$customerId/front_$timestamp${path.extension(idFrontPhoto.path)}';
          final backFileName = '$customerId/back_$timestamp${path.extension(idBackPhoto.path)}';

          // Upload images to Supabase
          debugPrint('Uploading front ID photo to Supabase...');
          idFrontPhotoUrl = await SupabaseService.uploadImage(idFrontPhoto, frontFileName);
          debugPrint('Front ID photo uploaded: $idFrontPhotoUrl');

          debugPrint('Uploading back ID photo to Supabase...');
          idBackPhotoUrl = await SupabaseService.uploadImage(idBackPhoto, backFileName);
          debugPrint('Back ID photo uploaded: $idBackPhotoUrl');

          debugPrint('ID photos uploaded to Supabase successfully');
        } else {
          debugPrint('No ID photos provided');
          _error = 'Please provide both front and back ID photos';
          notifyListeners();
          return false;
        }
      } catch (e, stackTrace) {
        debugPrint('=== Registration Error: ID Photo Upload ===');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $stackTrace');
        debugPrint('===========================================');
        
        // Extract detailed error message
        String errorMessage = 'Failed to upload ID photos. Please try again.';
        if (e.toString().contains('Supabase credentials not configured')) {
          errorMessage = 'Supabase is not configured. Please contact support.';
        } else if (e.toString().contains('bucket')) {
          errorMessage = 'Storage bucket error. Please contact support.';
        } else if (e.toString().contains('permission') || e.toString().contains('policy')) {
          errorMessage = 'Storage permission error. Please contact support.';
        } else if (e.toString().contains('network') || e.toString().contains('connection')) {
          errorMessage = 'Network error. Please check your internet connection and try again.';
        } else {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }
        
        _error = errorMessage;
        notifyListeners();
        return false;
      }

      // Step 4: Create customer profile with pending status
      debugPrint('Creating customer profile with pending verification...');
      final now = DateTime.now();
      final customer = Customer(
        uid: userId,
        email: email,
        fullName: fullName,
        firstName: firstName ?? '',
        lastName: lastName ?? '',
        middleInitial: middleInitial ?? '',
        suffix: suffix ?? '',
        username: username,
        age: age,
        gender: gender,
        phoneNumber: phone,
        address: address,
        street: street ?? '',
        sitio: sitio ?? '',
        barangay: barangay ?? '',
        city: 'Ormoc',
        state: 'Leyte',
        zipCode: '',
        createdAt: now,
        updatedAt: now,
        accountStatus: 'pending',  // Set account status to pending
        verificationStatus: 'pending',  // Set verification status to pending
        hasLoggedInBefore: false,
        idType: idType,
        status: 'pending',  // Set overall status to pending
        isOnline: false,
      );

      // Step 5: Save to Supabase with ID info and password hash
      debugPrint('Saving customer data to Supabase...');
      final customerData = customer.toMap();
      customerData['idFrontPhoto'] = idFrontPhotoUrl;
      customerData['idBackPhoto'] = idBackPhotoUrl;
      customerData['idType'] = idType;
      customerData['registrationDate'] = now.millisecondsSinceEpoch;
      customerData['password'] = passwordHash; // Store hashed password
      if (birthday != null) {
        customerData['birthday'] = birthday.toIso8601String().split('T')[0]; // Store as YYYY-MM-DD format
      }

      await SupabaseService.saveCustomer(customerData);

      // Step 6: Create default delivery address from registration address in Supabase
      debugPrint('Creating default delivery address in Supabase...');
      final fullAddress = '$address, Ormoc, Leyte';
      final deliveryAddressData = {
        'customerId': userId,
        'address': fullAddress,
        'label': 'Home',
        'isDefault': true,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      };

      try {
        await SupabaseService.saveDeliveryAddress(deliveryAddressData);
        debugPrint('Default delivery address created successfully in Supabase');
      } catch (e) {
        debugPrint('Warning: Failed to create default delivery address: $e');
        // Don't fail registration if delivery address creation fails
        // The address can be added later by the user
      }

      debugPrint('Registration successful!');
      _userId = userId;
      _currentCustomer = customer;
      _error = null;
      return true;

    } catch (e) {
      debugPrint('Supabase Auth error: $e');
      if (e.toString().contains('User already registered')) {
        _error = 'An account already exists with this email';
      } else if (e.toString().contains('Invalid email')) {
        _error = 'Invalid email address';
      } else if (e.toString().contains('Password')) {
        _error = 'Password is too weak. Please use a stronger password.';
      } else {
        _error = 'Registration failed: ${e.toString()}';
      }
      return false;

    } catch (e) {
      debugPrint('Registration error: $e');
      _error = 'Registration failed. Please try again.';
      return false;

    } finally {
      _isLoading = false;
      _isSigningIn = false;
      notifyListeners();
      debugPrint('=== REGISTRATION COMPLETE ===');
    }
  }

  /// Resend email confirmation to the user
  Future<bool> resendConfirmationEmail(String email) async {
    try {
      debugPrint('=== RESENDING CONFIRMATION EMAIL ===');
      debugPrint('Email: $email');
      
      final supabaseClient = SupabaseService.client;
      
      // Resend confirmation email
      await supabaseClient.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      
      debugPrint('Confirmation email resent successfully');
      return true;
    } catch (e) {
      debugPrint('Error resending confirmation email: $e');
      _error = 'Failed to resend confirmation email. Please try again later.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithUsername(String username, String password) async {
    String? userEmail;
    try {
      debugPrint('=== SIGNIN WITH USERNAME DEBUG START ===');
      debugPrint('Username: $username');
      _error = null;
      _isSigningIn = true;
      notifyListeners();

      // Find user by username in Supabase customers table
      debugPrint('Searching for username in Supabase customers table...');
      try {
        await SupabaseService.initialize();
        final existenceCheck = await SupabaseService.checkCustomerExists(username: username);
        
        if (!(existenceCheck['username'] ?? false)) {
          debugPrint('Username not found in Supabase customers');
          // Username not found - from the customer's perspective this usually means
          // the account was removed or never created. Show a clear support message.
          _error = 'Your account has either been removed/rejected. Please contact AgriCart support for this problem.';
          debugPrint('User not found - treating as removed/rejected account');
          debugPrint('=== SIGNIN WITH USERNAME DEBUG END (early return) ===');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        // Get customer data to find email for Firebase Auth
        final customerData = await SupabaseService.client
            .from('customers')
            .select('uid, email, account_status, verification_status')
            .eq('username', username)
            .maybeSingle() as Map<String, dynamic>?;

        if (customerData == null) {
          // Safety fallback – existence check said it exists but row not returned.
          _error = 'Your account has either been removed/rejected. Please contact AgriCart support for this problem.';
          _isSigningIn = false;
          notifyListeners();
          return false;
        }
        final userEmail = customerData['email'] as String?;
        final accountStatus = customerData['account_status'] as String?;
        final verificationStatus = customerData['verification_status'] as String?;

        if (userEmail == null || userEmail.isEmpty) {
          _error = 'Account email not found. Please contact support.';
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        // Check account status (case-insensitive)
        final normalizedVerificationStatus = (verificationStatus ?? '').toLowerCase();
        final normalizedAccountStatus = (accountStatus ?? '').toLowerCase();
        
        debugPrint('Account status check - verificationStatus: $verificationStatus ($normalizedVerificationStatus), accountStatus: $accountStatus ($normalizedAccountStatus)');
        
        if (normalizedVerificationStatus == 'pending') {
          _error = 'Your account is pending verification. Please wait for approval from our AgriCart staff.';
          debugPrint('Account is pending verification - setting pending error');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        // Explicit handling for rejected, deactivated, and removed accounts
        if (normalizedVerificationStatus == 'rejected' ||
            normalizedAccountStatus == 'rejected') {
          _error = 'Your account has either been removed/rejected. Please contact AgriCart support for this problem.';
          debugPrint('Account is rejected - blocking login with removed/rejected message');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        if (normalizedAccountStatus == 'inactive') {
          _error = 'Your account has been deactivated. Please contact AgriCart support for this problem.';
          debugPrint('Account is deactivated - blocking login');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        if (normalizedAccountStatus == 'removed' ||
            normalizedAccountStatus == 'deleted') {
          _error = 'Your account has been removed. Please contact AgriCart support for this problem.';
          debugPrint('Account is removed - blocking login');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        // Ensure account is approved and active before allowing login
        if (normalizedVerificationStatus != 'approved') {
          _error = 'Your account verification is not complete. Current status: ${verificationStatus ?? 'unknown'}. Please contact support.';
          debugPrint('Account verification status is not approved: $verificationStatus');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        // Clear deactivation dialog flag if account is active (user successfully logging in)
        if (normalizedAccountStatus == 'active' && normalizedVerificationStatus == 'approved') {
          await clearDeactivationDialogFlag();
        }

        if (normalizedAccountStatus != 'active') {
          _error = 'Your account is not active. Current status: ${accountStatus ?? 'unknown'}. Please contact the AgriCart staff for more information.';
          debugPrint('Account status is not active: $accountStatus');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }

        // Clear deactivation dialog flag if account is active (user successfully logging in)
        await clearDeactivationDialogFlag();

        // Sign in with Supabase Auth
        debugPrint('About to attempt Supabase Auth with email: $userEmail');
        debugPrint('Customer UID from Supabase: ${customerData['uid']}');
        final supabaseClient = SupabaseService.client;
        
        var authResponse = await supabaseClient.auth.signInWithPassword(
          email: userEmail,
          password: password,
        );
        
        // Handle case where auth user was deleted but customer record exists
        if (authResponse.user == null) {
          debugPrint('⚠️ Auth user not found - attempting to recreate auth user');
          
          try {
            // Try to recreate the auth user with the same password
            debugPrint('Recreating Supabase Auth user for: $userEmail');
            final recreateResponse = await supabaseClient.auth.signUp(
              email: userEmail,
              password: password,
              data: {
                'username': username,
                'full_name': customerData['full_name'] ?? '',
              },
            );
            
            if (recreateResponse.user != null) {
              debugPrint('✅ Auth user successfully recreated');
              
              // Update the customer record with the new UID if different
              if (recreateResponse.user!.id != customerData['uid']) {
                debugPrint('Updating customer UID from ${customerData['uid']} to ${recreateResponse.user!.id}');
                await SupabaseService.client
                    .from('customers')
                    .update({'uid': recreateResponse.user!.id})
                    .eq('username', username);
              }
              
              // Now try to sign in again with the recreated user
              authResponse = await supabaseClient.auth.signInWithPassword(
                email: userEmail,
                password: password,
              );
            }
          } catch (recreateError) {
            debugPrint('❌ Failed to recreate auth user: $recreateError');
            
            // If recreation fails, show helpful error message
            _error = 'Account authentication error. Please contact support with your username: $username';
            _isSigningIn = false;
            notifyListeners();
            return false;
          }
        }
        
        if (authResponse.user == null) {
          _error = 'Wrong username or password. Please check and try again.';
          _isSigningIn = false;
          notifyListeners();
          return false;
        }
        
        // Check if email is confirmed
        if (authResponse.user!.emailConfirmedAt == null) {
          _error = 'Please verify your email address before signing in. Check your inbox for the confirmation link.';
          debugPrint('Email not confirmed for user: $userEmail');
          _isSigningIn = false;
          notifyListeners();
          return false;
        }
        
        debugPrint('Supabase Auth successful');
        _userId = authResponse.user!.id;
        await _loadCustomerData(_userId!);

        // Clear deactivation dialog flag on successful login
        if (_currentCustomer != null && _error == null) {
          await clearDeactivationDialogFlag();
        }

        // After successful login + customer load, save FCM token for this device/customer
        if (_currentCustomer != null && _error == null) {
          try {
            debugPrint('🔑 Attempting to save FCM token after username login...');
            await NotificationService.saveFCMToken(_userId!);
            debugPrint('✅ FCM token save process completed (username login)');
          } catch (e) {
            debugPrint('❌ Failed to save FCM token after username login: $e');
            debugPrint('ℹ️ This may be because notification permission is not granted');
          }

          // Request battery optimization exemption after login
          try {
            debugPrint('🔋 Requesting battery optimization exemption after username login...');
            await NotificationService.requestBatteryOptimizationExemption();
            debugPrint('✅ Battery optimization request completed (username login)');
          } catch (e) {
            debugPrint('❌ Failed to request battery optimization exemption after username login: $e');
          }
        }

        return _currentCustomer != null && _error == null;
      } catch (e) {
        debugPrint('Database query error: $e');
        final msg = e.toString().toLowerCase();
        if (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception')) {
          _error = 'Network problem. Please check your internet connection and try again.';
        } else {
          _error = 'Wrong username or password. Please check and try again.';
        }
        debugPrint('=== SIGNIN WITH USERNAME DEBUG END (database error) ===');
        _isSigningIn = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      // Debug logging
      debugPrint('=== SUPABASE AUTH EXCEPTION DEBUG ===');
      debugPrint('Error: $e');
      debugPrint('User email: $userEmail');
      
      final msg = e.toString().toLowerCase();
      if (msg.contains('invalid login credentials') || msg.contains('invalid email or password')) {
        _error = 'Wrong username or password. Please check and try again.';
      } else if (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception')) {
        _error = 'Network problem. Please check your internet connection and try again.';
      } else {
        _error = 'Login failed. Please try again later.';
      }
      debugPrint('=== END SUPABASE AUTH EXCEPTION DEBUG ===');
      return false;
    } catch (e) {
      _error = 'Login failed. Please try again later.';
      return false;
    } finally {
      _isLoading = false;
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      _error = null;
      _isSigningIn = true;
      notifyListeners();

      // First check if user exists in Supabase customers table
      await SupabaseService.initialize();
      final existenceCheck = await SupabaseService.checkCustomerExists(email: email);
      
      if (!(existenceCheck['email'] ?? false)) {
        // User not found in Supabase - from the customer's perspective this usually
        // means the account was removed or never existed. Show a clear support message.
        _error = 'Your account has either been removed/rejected. Please contact AgriCart support for this problem.';
        _isSigningIn = false;
        notifyListeners();
        return false;
      }

      // Get customer data to check account status
      final customerData = await SupabaseService.client
          .from('customers')
          .select('uid, account_status, verification_status')
          .eq('email', email.toLowerCase())
          .maybeSingle() as Map<String, dynamic>?;

      if (customerData == null) {
        // Safety fallback – existence check said it exists but row not returned.
        _error = 'Your account has either been removed/rejected. Please contact AgriCart support for this problem.';
        _isSigningIn = false;
        notifyListeners();
        return false;
      }
      final accountStatus = customerData['account_status'] as String?;
      final verificationStatus = customerData['verification_status'] as String?;
      
      // Check account status (case-insensitive)
      final normalizedVerificationStatus = (verificationStatus ?? '').toLowerCase();
      final normalizedAccountStatus = (accountStatus ?? '').toLowerCase();
      
      debugPrint('Account status check - verificationStatus: $verificationStatus ($normalizedVerificationStatus), accountStatus: $accountStatus ($normalizedAccountStatus)');
      
      // Check if account verification is pending
      if (normalizedVerificationStatus == 'pending') {
        _error = 'Your account is pending verification. Please wait for approval from our AgriCart staff.';
        _isSigningIn = false;
        notifyListeners();
        return false;
      }
      
      if (normalizedVerificationStatus == 'rejected' ||
          normalizedAccountStatus == 'rejected') {
        _error = 'Your account has either been removed/rejected. Please contact AgriCart support for this problem.';
        _isSigningIn = false;
        notifyListeners();
        return false;
      }

      if (normalizedAccountStatus == 'inactive') {
        _error = 'Your account has been deactivated. Please contact AgriCart support for this problem.';
        _isSigningIn = false;
        notifyListeners();
        return false;
      }

      if (normalizedAccountStatus == 'removed' ||
          normalizedAccountStatus == 'deleted') {
        _error = 'Your account has been removed. Please contact AgriCart support for this problem.';
        _isSigningIn = false;
        notifyListeners();
        return false;
      }

      // Ensure account is approved and active before allowing login
      if (normalizedVerificationStatus != 'approved') {
        _error = 'Your account verification is not complete. Current status: ${verificationStatus ?? 'unknown'}. Please contact support.';
        debugPrint('Account verification status is not approved: $verificationStatus');
        _isSigningIn = false;
        notifyListeners();
        return false;
      }

      if (normalizedAccountStatus != 'active') {
        _error = 'Your account is not active. Current status: ${accountStatus ?? 'unknown'}. Please contact the AgriCart staff for more information.';
        debugPrint('Account status is not active: $accountStatus');
        _isSigningIn = false;
        notifyListeners();
        return false;
      }

      debugPrint('About to attempt Supabase Auth with email: $email');
      debugPrint('Customer UID from Supabase: ${customerData['uid']}');
      final supabaseClient = SupabaseService.client;
      
      var authResponse = await supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      // Handle case where auth user was deleted but customer record exists
      if (authResponse.user == null) {
        debugPrint('⚠️ Auth user not found - attempting to recreate auth user');
        
        try {
          // Try to recreate the auth user with the same password
          debugPrint('Recreating Supabase Auth user for: $email');
          final recreateResponse = await supabaseClient.auth.signUp(
            email: email,
            password: password,
            data: {
              'email': email,
              'full_name': customerData['full_name'] ?? '',
            },
          );
          
          if (recreateResponse.user != null) {
            debugPrint('✅ Auth user successfully recreated');
            
            // Update the customer record with the new UID if different
            if (recreateResponse.user!.id != customerData['uid']) {
              debugPrint('Updating customer UID from ${customerData['uid']} to ${recreateResponse.user!.id}');
              await SupabaseService.client
                  .from('customers')
                  .update({'uid': recreateResponse.user!.id})
                  .eq('email', email.toLowerCase());
            }
            
            // Now try to sign in again with the recreated user
            authResponse = await supabaseClient.auth.signInWithPassword(
              email: email,
              password: password,
            );
          }
        } catch (recreateError) {
          debugPrint('❌ Failed to recreate auth user: $recreateError');
          
          // If recreation fails, show helpful error message
          _error = 'Account authentication error. Please contact support with your email: $email';
          _isSigningIn = false;
          notifyListeners();
          return false;
        }
      }
      
      if (authResponse.user == null) {
        _error = 'Wrong username or password. Please check and try again.';
        return false;
      }
      
      // Check if email is confirmed
      if (authResponse.user!.emailConfirmedAt == null) {
        _error = 'Please verify your email address before signing in. Check your inbox for the confirmation link.';
        debugPrint('Email not confirmed for user: $email');
        _isSigningIn = false;
        notifyListeners();
        return false;
      }
      
      debugPrint('Supabase Auth successful');
      _userId = authResponse.user!.id;
      await _loadCustomerData(_userId!);

      // After successful email login + customer load, save FCM token for this device/customer
      if (_currentCustomer != null && _error == null) {
        try {
          debugPrint('🔑 Attempting to save FCM token after email login...');
          await NotificationService.saveFCMToken(_userId!);
          debugPrint('✅ FCM token save process completed (email login)');
        } catch (e) {
          debugPrint('❌ Failed to save FCM token after email login: $e');
          debugPrint('ℹ️ This may be because notification permission is not granted');
        }

        // Request battery optimization exemption after login
        try {
          debugPrint('🔋 Requesting battery optimization exemption after email login...');
          await NotificationService.requestBatteryOptimizationExemption();
          debugPrint('✅ Battery optimization request completed (email login)');
        } catch (e) {
          debugPrint('❌ Failed to request battery optimization exemption after email login: $e');
        }
      }

      return _currentCustomer != null && _error == null;
    } catch (e) {
      // Debug logging
      debugPrint('=== EMAIL LOGIN SUPABASE AUTH EXCEPTION DEBUG ===');
      debugPrint('Error: $e');
      debugPrint('Email: $email');
      
      final msg = e.toString().toLowerCase();
      if (msg.contains('invalid login credentials') || msg.contains('invalid email or password')) {
        _error = 'Wrong username or password. Please check and try again.';
      } else if (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception')) {
        _error = 'Network problem. Please check your internet connection and try again.';
      } else {
        _error = 'Login failed. Please try again later.';
      }
      debugPrint('=== END EMAIL LOGIN SUPABASE AUTH EXCEPTION DEBUG ===');
      return false;
    } catch (e) {
      _error = 'Login failed. Please try again later.';
      return false;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      debugPrint('🚪 User signing out...');
      _stopAccountStatusMonitoring();
      
      // Remove FCM token so user doesn't receive notifications when logged out
      final customerId = _userId;
      if (customerId != null) {
        try {
          await NotificationService.removeFCMToken(customerId);
        } catch (e) {
          debugPrint('⚠️ Error removing FCM token on logout: $e');
        }
      }
      
      await SupabaseService.client.auth.signOut();
      _userId = null;
      _currentCustomer = null;
      _error = null;
      notifyListeners();
      debugPrint('✅ User signed out successfully');
    } catch (e) {
      debugPrint('❌ Error signing out: $e');
    }
  }

  Future<void> updateCustomerProfile(Customer updatedCustomer) async {
    try {
      if (_userId != null) {
        // Check account status before updating profile
        final isAccountActive = await checkAccountStatusImmediately();
        if (!isAccountActive) {
          // Account was deactivated - stop here, user will be redirected
          debugPrint('⚠️ Cannot update profile - account is deactivated');
          return;
        }
        
        await SupabaseService.updateCustomer(_userId!, updatedCustomer.toMap());
        _currentCustomer = updatedCustomer;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
    }
  }

  /// Customer-initiated account deletion
  /// - Calls the same remove_customer_account RPC used by staff/admin
  /// - Then signs the user out locally
  Future<bool> deleteOwnAccount({String? reason}) async {
    try {
      if (_userId == null) {
        _error = 'You must be logged in to delete your account.';
        notifyListeners();
        return false;
      }

      await SupabaseService.initialize();

      // Call remove_customer_account RPC with customer as the actor
      final supabase = SupabaseService.client;
      final rpcReason = reason ?? 'Account deletion requested by customer';

      final rpcResponse = await supabase.rpc('remove_customer_account', params: {
        'p_customer_uid': _userId,
        'p_removal_reason': rpcReason,
        'p_removed_by': _userId, // self-initiated
        'p_removed_by_name': _currentCustomer?.fullName ?? 'Customer',
        'p_removed_by_role': 'Customer',
      });

      if (rpcResponse == null) {
        debugPrint('remove_customer_account RPC returned null response');
      }

      // After successful RPC, sign out and clear local state
      await signOut();
      return true;
    } catch (e) {
      debugPrint('Error deleting own account: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception')) {
        _error = 'Network problem. Please check your internet connection and try again.';
      } else {
        _error = 'Failed to delete account. Please try again later or contact support.';
      }
      notifyListeners();
      return false;
    }
  }

  // Method for testing account deactivation (remove in production)
  void testAccountDeactivation() {
    debugPrint('🧪 Testing account deactivation...');
    _handleAccountDeactivation();
  }

  @override
  void dispose() {
    _stopAccountStatusMonitoring();
    _timeoutTimer?.cancel();
    super.dispose();
  }
}