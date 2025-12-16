import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../../utils/responsive.dart';
import 'login_screen.dart';
import '../dashboard/dashboard_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _isEmailSent = false;
  bool _isLoading = false;
  bool _isVerifying = false;
  String? _errorMessage;
  String? _successMessage;
  String? _resetEmail;
  Timer? _resendTimer;
  int _resendCountdown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60; // 60 seconds countdown
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_resendCountdown > 0) {
            _resendCountdown--;
          } else {
            _resendTimer?.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOTP() async {
    if (!_emailFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final email = _emailController.text.trim().toLowerCase();
      
      // Check if email exists in customers table
      await SupabaseService.initialize();
      final existenceCheck = await SupabaseService.checkCustomerExists(email: email);
      
      if (!(existenceCheck['email'] ?? false)) {
        setState(() {
          _errorMessage = 'Email not found. Please check your email address.';
          _isLoading = false;
        });
        return;
      }

      // Send password reset email with OTP
      final supabaseClient = SupabaseService.client;
      await supabaseClient.auth.resetPasswordForEmail(email);

      // Store email for OTP verification
      _resetEmail = email;

      setState(() {
        _isEmailSent = true;
        _isLoading = false;
        _successMessage = 'OTP has been sent to your email. Please check your inbox.';
      });

      // Start the resend timer
      _startResendTimer();
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      setState(() {
        _errorMessage = e.toString().contains('rate limit') 
            ? 'Too many requests. Please wait a moment and try again.'
            : 'Failed to send OTP. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    if (!_otpFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final otp = _otpController.text.trim();
      
      if (_resetEmail == null) {
        throw Exception('Email not found. Please start over.');
      }

      final supabaseClient = SupabaseService.client;
      
      // Verify OTP with type "recovery"
      await supabaseClient.auth.verifyOTP(
        type: OtpType.recovery,
        token: otp,
        email: _resetEmail!,
      );

      // Wait a moment for session to be established
      await Future.delayed(const Duration(milliseconds: 300));

      // Check if session was established
      final session = supabaseClient.auth.currentSession;
      
      if (session == null) {
        throw Exception('OTP verified but no session found. Please try again.');
      }

      // OTP verified successfully - load customer data and navigate to dashboard
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });

        // Show loading message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('OTP verified successfully! Loading your account...'),
            backgroundColor: AppTheme.primaryColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );

        // Reload session and customer data in AuthProvider
        try {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          
          // Get the session to check user info
          final session = supabaseClient.auth.currentSession;
          if (session != null && session.user != null) {
            debugPrint('OTP verified - Auth User ID: ${session.user!.id}, Email: ${session.user!.email}');
          }
          
          // Reload session and customer data
          await authProvider.reloadSessionAndCustomerData();

          // Wait a bit for the data to be fully loaded
          await Future.delayed(const Duration(milliseconds: 800));

          // Check if customer data was loaded successfully
          if (mounted && authProvider.currentCustomer != null) {
            debugPrint('Customer data loaded successfully: ${authProvider.currentCustomer!.fullName}');
            // Navigate to dashboard
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
              (route) => false, // Remove all previous routes
            );
          } else if (mounted) {
            // Customer data not loaded - show detailed error
            final errorMsg = authProvider.error ?? 'Failed to load customer data.';
            debugPrint('Customer data not loaded. Error: $errorMsg');
            setState(() {
              _errorMessage = errorMsg.isNotEmpty 
                  ? errorMsg 
                  : 'Failed to load customer data. Please try logging in with your password.';
            });
          }
        } catch (e) {
          debugPrint('Error loading customer data after OTP verification: $e');
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to load customer data: ${e.toString()}. Please try logging in with your password.';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      setState(() {
        _errorMessage = e.toString().contains('Invalid') || e.toString().contains('expired')
            ? 'Invalid or expired OTP. Please check the code and try again.'
            : 'Failed to verify OTP. Please try again.';
        _isVerifying = false;
      });
    }
  }

  Future<void> _resendOTP() async {
    if (_resetEmail == null) {
      setState(() {
        _errorMessage = 'Please enter your email first.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final supabaseClient = SupabaseService.client;
      await supabaseClient.auth.resetPasswordForEmail(_resetEmail!);

      setState(() {
        _isLoading = false;
        _successMessage = 'OTP has been resent to your email.';
      });

      // Restart the resend timer
      _startResendTimer();
    } catch (e) {
      debugPrint('Error resending OTP: $e');
      String errorMsg = 'Failed to resend OTP. Please try again.';
      
      // Check if it's a rate limit error
      if (e.toString().contains('rate limit') || e.toString().contains('over_email_send_rate_limit')) {
        // Extract the wait time from error message if available
        final match = RegExp(r'after (\d+) seconds').firstMatch(e.toString());
        if (match != null) {
          final waitSeconds = int.tryParse(match.group(1) ?? '60');
          if (waitSeconds != null) {
            _resendCountdown = waitSeconds;
            _startResendTimer();
            errorMsg = 'Please wait before requesting another OTP.';
          }
        } else {
          // Default to 60 seconds if we can't parse the time
          _resendCountdown = 60;
          _startResendTimer();
          errorMsg = 'Please wait 60 seconds before requesting another OTP.';
        }
      }
      
      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
      });
    }
  }

  void _goBack() {
    if (_isEmailSent) {
      _resendTimer?.cancel();
      setState(() {
        _isEmailSent = false;
        _resetEmail = null;
        _otpController.clear();
        _errorMessage = null;
        _successMessage = null;
        _resendCountdown = 0;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                    // Back button
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: AppTheme.primaryColor,
                          size: Responsive.getIconSize(context, mobile: 28),
                        ),
                        onPressed: _goBack,
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    // Title
                    Text(
                      _isEmailSent ? 'Verify OTP' : 'Forgot Password',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                    Text(
                      _isEmailSent 
                          ? 'Enter the OTP code sent to your email'
                          : 'Enter your registered email to receive an OTP',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 32)),
                    
                    // Email Form
                    if (!_isEmailSent) ...[
                      Form(
                        key: _emailFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
                              decoration: InputDecoration(
                                labelText: 'Email',
                                labelStyle: TextStyle(color: Colors.grey[600]),
                                prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[600]),
                                filled: true,
                                fillColor: AppTheme.creamColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: BorderSide(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: BorderSide(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2.5),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: Responsive.getSpacing(context, mobile: 20),
                                  vertical: Responsive.getSpacing(context, mobile: 18),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!value.contains('@') || !value.contains('.')) {
                                  return 'Please enter a valid email address';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                            if (_errorMessage != null)
                              Container(
                                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                                margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor.withOpacity(0.1),
                                  border: Border.all(color: AppTheme.errorColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: AppTheme.errorColor,
                                      size: Responsive.getIconSize(context, mobile: 20),
                                    ),
                                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: AppTheme.errorColor,
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_successMessage != null)
                              Container(
                                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                                margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  border: Border.all(color: AppTheme.primaryColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: AppTheme.primaryColor,
                                      size: Responsive.getIconSize(context, mobile: 20),
                                    ),
                                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                    Expanded(
                                      child: Text(
                                        _successMessage!,
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              width: double.infinity,
                              height: Responsive.getHeight(context, mobile: 56),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                gradient: _isLoading
                                    ? LinearGradient(
                                        colors: [Colors.grey.shade400, Colors.grey.shade500],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : AppTheme.primaryGradient,
                                boxShadow: _isLoading
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: AppTheme.primaryColor.withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _sendOTP,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
                                ),
                                child: _isLoading
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            height: Responsive.getHeight(context, mobile: 20),
                                            width: Responsive.getWidth(context, mobile: 20),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Colors.white.withOpacity(0.8),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                          Text(
                                            'Sending...',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: Responsive.getFontSize(context, mobile: 16),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        'Send OTP',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: Responsive.getFontSize(context, mobile: 16),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // OTP Form
                      Form(
                        key: _otpFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: Responsive.getFontSize(context, mobile: 24),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                              decoration: InputDecoration(
                                labelText: 'OTP Code',
                                labelStyle: TextStyle(color: Colors.grey[600]),
                                hintText: 'Enter OTP',
                                hintStyle: TextStyle(
                                  fontSize: Responsive.getFontSize(context, mobile: 16),
                                  letterSpacing: 0,
                                ),
                                prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[600]),
                                filled: true,
                                fillColor: AppTheme.creamColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: BorderSide(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: BorderSide(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2.5),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: Responsive.getSpacing(context, mobile: 20),
                                  vertical: Responsive.getSpacing(context, mobile: 18),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the OTP code';
                                }
                                if (value.trim().length < 6) {
                                  return 'OTP code must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                            Text(
                              'Check your email for the OTP code sent to $_resetEmail',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: Responsive.getFontSize(context, mobile: 12),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                            if (_errorMessage != null)
                              Container(
                                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                                margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor.withOpacity(0.1),
                                  border: Border.all(color: AppTheme.errorColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: AppTheme.errorColor,
                                      size: Responsive.getIconSize(context, mobile: 20),
                                    ),
                                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: AppTheme.errorColor,
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_successMessage != null)
                              Container(
                                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                                margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  border: Border.all(color: AppTheme.primaryColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: AppTheme.primaryColor,
                                      size: Responsive.getIconSize(context, mobile: 20),
                                    ),
                                    SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                    Expanded(
                                      child: Text(
                                        _successMessage!,
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: Responsive.getFontSize(context, mobile: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              width: double.infinity,
                              height: Responsive.getHeight(context, mobile: 56),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                gradient: _isVerifying
                                    ? LinearGradient(
                                        colors: [Colors.grey.shade400, Colors.grey.shade500],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : AppTheme.primaryGradient,
                                boxShadow: _isVerifying
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: AppTheme.primaryColor.withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isVerifying ? null : _verifyOTP,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
                                ),
                                child: _isVerifying
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            height: Responsive.getHeight(context, mobile: 20),
                                            width: Responsive.getWidth(context, mobile: 20),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                Colors.white.withOpacity(0.8),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                          Text(
                                            'Verifying...',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: Responsive.getFontSize(context, mobile: 16),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        'Verify OTP',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: Responsive.getFontSize(context, mobile: 16),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                            TextButton(
                              onPressed: (_isLoading || _resendCountdown > 0) ? null : _resendOTP,
                              child: Text(
                                _resendCountdown > 0
                                    ? 'Resend OTP (${_resendCountdown}s)'
                                    : 'Resend OTP',
                                style: TextStyle(
                                  color: _resendCountdown > 0
                                      ? Colors.grey
                                      : AppTheme.primaryColor,
                                  fontSize: Responsive.getFontSize(context, mobile: 14),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

