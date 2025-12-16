import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/featured_media_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'services/notification_service.dart';
import 'utils/theme.dart';
import 'utils/order_schedule.dart';
import 'utils/responsive.dart';

// Top-level message handler for background notifications
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('📱 Handling a background message: ${message.messageId}');
  print('📱 Message title: ${message.notification?.title}');
  print('📱 Message body: ${message.notification?.body}');
  print('📱 Message data: ${message.data}');
  
  // FCM automatically displays notifications when app is closed if notification field is present
  // We just need to save it to the database
  await _saveBackgroundNotificationToDatabase(message);
}

// Save notification to Firebase Database when app is closed
Future<void> _saveBackgroundNotificationToDatabase(RemoteMessage message) async {
  try {
    final database = FirebaseDatabase.instance;
    final data = message.data;
    
    // Extract customer ID from data or notification
    final customerId = data['customerId']?.toString() ?? 
                       data['customer_id']?.toString();
    
    if (customerId == null || customerId.isEmpty) {
      print('⚠️ No customerId in background message, skipping database save');
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
    print('✅ Background notification saved to Firebase Database');
  } catch (e) {
    print('❌ Error saving background notification to database: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
    
    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Configure Firebase Messaging with error handling
    try {
      final messaging = FirebaseMessaging.instance;
      
      // Request permission with error handling
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      print('User granted permission: ${settings.authorizationStatus}');
      
      // Get FCM token with error handling
      String? token = await messaging.getToken();
      if (token != null) {
        print('FCM Token: ${token.substring(0, 20)}...');
      }
      
    } catch (e) {
      print('Firebase Messaging setup failed: $e');
    }
    
  } catch (e) {
    print('Firebase initialization failed: $e');
    // Continue without Firebase for now
  }

  // Initialize notifications BEFORE starting the app (CRITICAL for Android 11+)
  // This ensures the notification channel is created before the app can be closed
  try {
    await NotificationService.initialize();
    print('✅ Notification service initialized - channel should be created');
  } catch (e) {
    print('❌ Notification initialization failed: $e');
  }

  // Start the app
  runApp(const MyApp());

  // Initialize OrderSchedule AFTER first frame to avoid blocking splash
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      // Start listening to cooperative desktop time for order window enforcement
      await OrderSchedule.initialize();
      print('OrderSchedule (coop time) initialized');
    } catch (e) {
      print('OrderSchedule init failed: $e');
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => FeaturedMediaProvider()),
      ],
      child: Consumer2<ThemeProvider, SettingsProvider>(
        builder: (context, themeProvider, settingsProvider, child) {
          // Sync dark mode on app start
          if (!settingsProvider.isLoading && settingsProvider.darkModeEnabled && themeProvider.themeMode != ThemeMode.dark) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              themeProvider.setDarkMode();
            });
          } else if (!settingsProvider.isLoading && !settingsProvider.darkModeEnabled && themeProvider.themeMode != ThemeMode.light) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              themeProvider.setLightMode();
            });
          }
          
          return MaterialApp(
            title: 'AgriCart',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
            navigatorKey: NotificationService.navigatorKey,
            // Add performance optimizations and responsive text scaling
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaleFactor: Responsive.getTextScaleFactor(context),
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  Timer? _periodicCheckTimer;

  @override
  void initState() {
    super.initState();
    // Start periodic account status checks when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPeriodicAccountChecks();
    });
  }

  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicAccountChecks() {
    // Cancel any existing timer
    _periodicCheckTimer?.cancel();
    
    // Check account status every 3 seconds when user is authenticated
    _periodicCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Only check if user is authenticated
      if (authProvider.isAuthenticated && authProvider.userId != null) {
        // Force immediate account status check
        authProvider.forceAccountStatusCheck();
      } else {
        // User is not authenticated, stop checking
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Restart periodic checks when authentication state changes
        if (authProvider.isAuthenticated && (_periodicCheckTimer == null || !_periodicCheckTimer!.isActive)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startPeriodicAccountChecks();
          });
        } else if (!authProvider.isAuthenticated) {
          _periodicCheckTimer?.cancel();
        }
        print('=== AUTHWRAPPER DEBUG ===');
        print('isLoading: ${authProvider.isLoading}');
        print('isAuthenticated: ${authProvider.isAuthenticated}');
        print('currentCustomer: ${authProvider.currentCustomer?.fullName}');
        print('error: ${authProvider.error}');
        print('userId: ${authProvider.userId}');
        
        // Show network error dialog with retry button (not deactivation)
        // Use global navigator key so it works from any screen
        if (authProvider.error != null && authProvider.isNetworkError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Use global navigator key to show dialog from any screen
            final navigatorContext = NotificationService.navigatorKey.currentContext;
            if (navigatorContext == null) {
              debugPrint('Navigator context not available - cannot show network error dialog');
              return;
            }
            
            showDialog(
              context: navigatorContext,
              barrierDismissible: false,
              useRootNavigator: true,
              builder: (BuildContext context) {
                return PopScope(
                  canPop: false, // Prevent back button from dismissing
                  child: AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text(
                      'Connection Issue',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          color: Colors.orange[600],
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          authProvider.error ?? 'Slow internet connection detected. Please check your network.',
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    actions: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                authProvider.clearError();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Dismiss',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await authProvider.retryAccountStatusCheck();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          });
        }
        
        // Show account deactivation dialog only for actual deactivation (not network errors)
        // and only if it hasn't been shown/acknowledged before
        // Use global navigator key so it works from any screen
        if (authProvider.error != null && 
            authProvider.error!.contains('deactivated') && 
            !authProvider.isNetworkError) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // Check if dialog has been shown before
            final hasBeenShown = await authProvider.hasDeactivationDialogBeenShown();
            if (hasBeenShown) {
              // Dialog already shown, don't show it again
              debugPrint('Deactivation dialog already shown - skipping');
              return;
            }
            
            // Use global navigator key to show dialog from any screen
            final navigatorContext = NotificationService.navigatorKey.currentContext;
            if (navigatorContext == null) {
              debugPrint('Navigator context not available - cannot show deactivation dialog');
              return;
            }
            
            showDialog(
              context: navigatorContext,
              barrierDismissible: false,
              useRootNavigator: true,
              builder: (BuildContext context) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    'Account Deactivated',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_circle_outlined,
                        color: Colors.red[600],
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your account has been deactivated. Please contact our AgriCart staff for more information.',
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: const Text(
                          'You will be redirected to the login screen.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    Center(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            // Close dialog
                            Navigator.of(context, rootNavigator: true).pop();
                            
                            // Mark dialog as shown
                            await authProvider.markDeactivationDialogAsShown();
                            authProvider.clearError();
                            
                            // Pop all routes to get back to root (AuthWrapper will show login screen)
                            final navigatorContext = NotificationService.navigatorKey.currentContext;
                            if (navigatorContext != null) {
                              Navigator.of(navigatorContext, rootNavigator: true).popUntil((route) => route.isFirst);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Understood',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          });
        }

        if (authProvider.isLoading) {
          print('AuthWrapper: Showing loading screen');
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading AgriCart...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (authProvider.isAuthenticated) {
          print('AuthWrapper: User is authenticated');
          // Check if the customer profile is complete
          final customer = authProvider.currentCustomer;
          if (customer != null && 
              (customer.fullName.isEmpty || 
               customer.fullName == 'Unknown Customer' || 
               customer.email.isEmpty)) {
            print('AuthWrapper: Profile incomplete - showing profile screen');
            // Profile is incomplete, show profile completion screen
            return const ProfileScreen();
          }
          print('AuthWrapper: Showing dashboard screen');
          return const DashboardScreen();
        }

        print('AuthWrapper: Showing login screen');
        print('=== END AUTHWRAPPER DEBUG ===');
        return const LoginScreen();
      },
    );
  }
}
