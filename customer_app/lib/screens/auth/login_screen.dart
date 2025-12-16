import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../dashboard/dashboard_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'package:flutter/foundation.dart';
import '../../utils/responsive.dart';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _showError = false;
  String _errorMessage = '';
  bool _showResendConfirmation = false;
  String? _pendingEmail;

  // Helper widget for icon circles in header
  Widget _buildIconCircle(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: Responsive.getWidth(context, mobile: 2),
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: Responsive.getIconSize(context, mobile: 32),
          ),
        ),
        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: Responsive.getFontSize(context, mobile: 12),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    // Clear errors but don't show loading yet for wrong credentials
    setState(() {
      _showError = false;
      _errorMessage = '';
    });

    if (_formKey.currentState!.validate()) {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      
      // Basic validation without loading state
      if (username.isEmpty || password.isEmpty) {
        setState(() {
          _showError = true;
          _errorMessage = 'Please enter both username and password';
        });
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      print('=== LOGIN SCREEN DEBUG ===');
      print('Attempting login for username: $username');
      print('Before login - isAuthenticated: ${authProvider.isAuthenticated}');
      print('Before login - currentCustomer: ${authProvider.currentCustomer?.fullName}');
      print('Before login - isLoading: ${authProvider.isLoading}');
      
      final success = await authProvider.signInWithUsername(username, password);
      
      print('Login result: $success');
      print('After login - isAuthenticated: ${authProvider.isAuthenticated}');
      print('After login - currentCustomer: ${authProvider.currentCustomer?.fullName}');
      print('After login - isLoading: ${authProvider.isLoading}');
      print('After login - error: ${authProvider.error}');
      
      print('=== END LOGIN SCREEN DEBUG ===');

      if (!success && mounted) {
        final errorMessage = authProvider.error ?? 'Authentication failed';
        
        // Check if it's an email confirmation error
        final isEmailConfirmationError = errorMessage.contains('verify your email') || 
                                         errorMessage.contains('confirmation link');
        
        // Get email for resending confirmation
        String? userEmail;
        if (isEmailConfirmationError) {
          try {
            final customerData = await SupabaseService.client
                .from('customers')
                .select('email')
                .eq('username', username)
                .maybeSingle() as Map<String, dynamic>?;
            userEmail = customerData?['email'] as String?;
          } catch (e) {
            debugPrint('Error fetching email for resend: $e');
          }
        }
        
        // Show error immediately above sign-in button
        setState(() {
          _showError = true;
          _errorMessage = errorMessage;
          _showResendConfirmation = isEmailConfirmationError && userEmail != null;
          _pendingEmail = userEmail;
        });
      } else if (success && mounted) {
        print('Login successful - clearing errors and waiting for redirect');
        // Clear any errors on success
        setState(() {
          _showError = false;
          _errorMessage = '';
        });
        
        // Manually navigate to dashboard since AuthWrapper isn't rebuilding
        print('Manually navigating to dashboard...');
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalHeight = constraints.maxHeight;
            final imageHeight = totalHeight * 0.37;
            final formMinHeight = math.max(totalHeight - imageHeight, 0.0);

            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: imageHeight,
                    child: Container(
                      width: double.infinity,
                      color: AppTheme.creamLight,
                      child: Center(
                        child: Image.asset(
                          'assets/images/agricart_logo.png',
                          width: imageHeight * 0.6,
                          height: imageHeight * 0.6,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.creamLight,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      minHeight: formMinHeight,
                    ),
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                          Text(
                            'AgriCart',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                          Text(
                            'Sign in to continue',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 32)),
                          TextFormField(
                            controller: _usernameController,
                            style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
                            decoration: InputDecoration(
                              labelText: 'Username',
                              labelStyle: TextStyle(color: Colors.grey[600]),
                              prefixIcon: Icon(Icons.person_outline, color: Colors.grey[600]),
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
                              contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 20), vertical: Responsive.getSpacing(context, mobile: 18)),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your username';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                              prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[600]),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
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
                              contentPadding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 20), vertical: Responsive.getSpacing(context, mobile: 18)),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                          // Forgot Password Button
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontSize: Responsive.getFontSize(context, mobile: 14),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                          if (_showError)
                            Container(
                              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                              margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
                              decoration: BoxDecoration(
                                color: AppTheme.errorColor.withOpacity(0.1),
                                border: Border.all(color: AppTheme.errorColor, width: 1.5),
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.errorColor.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                                    decoration: BoxDecoration(
                                      color: AppTheme.errorColor.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.error_outline,
                                      color: AppTheme.errorColor,
                                      size: Responsive.getIconSize(context, mobile: 20),
                                    ),
                                  ),
                                  SizedBox(width: Responsive.getWidth(context, mobile: 12)),
                                  Expanded(
                                    child: Text(
                                      _errorMessage,
                                      style: TextStyle(
                                        color: AppTheme.errorColor,
                                        fontSize: Responsive.getFontSize(context, mobile: 14),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_showResendConfirmation && _pendingEmail != null)
                            Container(
                              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
                              margin: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                border: Border.all(color: AppTheme.primaryColor, width: 1.5),
                                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.email_outlined,
                                        color: AppTheme.primaryColor,
                                        size: Responsive.getIconSize(context, mobile: 20),
                                      ),
                                      SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                                      Expanded(
                                        child: Text(
                                          'Didn\'t receive the email?',
                                          style: TextStyle(
                                            color: AppTheme.primaryColor,
                                            fontSize: Responsive.getFontSize(context, mobile: 14),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                      final success = await authProvider.resendConfirmationEmail(_pendingEmail!);
                                      
                                      if (mounted) {
                                        if (success) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Confirmation email sent to $_pendingEmail'),
                                              backgroundColor: AppTheme.primaryColor,
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Failed to send confirmation email. Please try again.'),
                                              backgroundColor: AppTheme.errorColor,
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: Icon(Icons.send, size: Responsive.getIconSize(context, mobile: 18)),
                                    label: const Text('Resend Confirmation Email'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Consumer<AuthProvider>(
                            builder: (context, authProvider, child) {
                              final isLoading = authProvider.isSigningIn;

                              return Container(
                                width: double.infinity,
                                height: Responsive.getHeight(context, mobile: 56),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                  gradient: isLoading
                                      ? LinearGradient(
                                          colors: [Colors.grey.shade400, Colors.grey.shade500],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : AppTheme.primaryGradient,
                                  boxShadow: isLoading
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
                                  onPressed: isLoading ? null : _submitForm,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
                                    ),
                                    padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 16)),
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: isLoading
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
                                                'Signing in...',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: Responsive.getFontSize(context, mobile: 16),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            'Sign In',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: Responsive.getFontSize(context, mobile: 16),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Don\'t have an account? ',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: Responsive.getFontSize(context, mobile: 14),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (context) => const RegisterScreen()),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontSize: Responsive.getFontSize(context, mobile: 14),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                          // Contact Support Footer
                          _buildContactSupportFooter(),
                          SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContactSupportFooter() {
    return FutureBuilder<Map<String, String>>(
      future: _loadContactSupportInfo(),
      builder: (context, snapshot) {
        final email = snapshot.data?['email'] ?? 'calcoacoop@gmail.com';
        final phone = snapshot.data?['phone'] ?? '+63 123 456 7890';

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 16)),
            border: Border.all(
              color: AppTheme.primaryColor.withOpacity(0.1),
              width: Responsive.getWidth(context, mobile: 1),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    color: AppTheme.primaryColor,
                    size: Responsive.getIconSize(context, mobile: 20),
                  ),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  Expanded(
                    child: Text(
                      'For concerns and inquiries',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: Responsive.getFontSize(context, mobile: 13),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Row(
                children: [
                  Icon(
                    Icons.email_outlined,
                    color: AppTheme.primaryColor,
                    size: Responsive.getIconSize(context, mobile: 16),
                  ),
                  SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                  Expanded(
                    child: Text(
                      email,
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: Responsive.getFontSize(context, mobile: 13),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              GestureDetector(
                onTap: () async {
                  try {
                    // Clean phone number: remove all characters except digits and +
                    String cleanedPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
                    
                    // Ensure proper format for tel: URI
                    if (!cleanedPhone.startsWith('+')) {
                      if (cleanedPhone.startsWith('0')) {
                        cleanedPhone = '+63${cleanedPhone.substring(1)}';
                      } else if (cleanedPhone.startsWith('63')) {
                        cleanedPhone = '+$cleanedPhone';
                      } else {
                        cleanedPhone = '+63$cleanedPhone';
                      }
                    }
                    
                    final uri = Uri.parse('tel:$cleanedPhone');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    print('Error launching phone dialer: $e');
                  }
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      color: AppTheme.primaryColor,
                      size: Responsive.getIconSize(context, mobile: 16),
                    ),
                    SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                    Expanded(
                      child: Text(
                        phone,
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: Responsive.getFontSize(context, mobile: 13),
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.call,
                      color: AppTheme.primaryColor,
                      size: Responsive.getIconSize(context, mobile: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, String>> _loadContactSupportInfo() async {
    try {
      // Import SupabaseService to access client
      final supabase = SupabaseService.client;

      final response = await supabase
          .from('system_data')
          .select('support_email, support_phone')
          .eq('id', 'contactSupport')
          .maybeSingle();

      if (response != null && response['support_email'] != null) {
        return {
          'email': response['support_email'] as String? ?? 'calcoacoop@gmail.com',
          'phone': response['support_phone'] as String? ?? '+63 123 456 7890',
        };
      }

      return {
        'email': 'calcoacoop@gmail.com',
        'phone': '+63 123 456 7890',
      };
    } catch (e) {
      print('Error loading contact support info: $e');
      return {
        'email': 'calcoacoop@gmail.com',
        'phone': '+63 123 456 7890',
      };
    }
  }
}

// Custom painter for vector cartoon grocery illustration
class GroceryCartoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withOpacity(0.4);

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Left grocery bag (brown paper bag style)
    paint.color = const Color(0xFF8B6F47); // Brown paper bag
    final leftBagPath = Path()
      ..moveTo(centerX - 100, centerY - 20)
      ..lineTo(centerX - 40, centerY - 20)
      ..lineTo(centerX - 35, centerY + 40)
      ..lineTo(centerX - 105, centerY + 40)
      ..close();
    canvas.drawPath(leftBagPath, paint);

    // Bag outline
    strokePaint.color = const Color(0xFF6B5638);
    strokePaint.strokeWidth = 2;
    canvas.drawPath(leftBagPath, strokePaint);

    // Bag handles (left)
    strokePaint.color = Colors.white;
    strokePaint.strokeWidth = 4;
    canvas.drawLine(
      Offset(centerX - 95, centerY - 20),
      Offset(centerX - 85, centerY - 30),
      strokePaint,
    );
    canvas.drawLine(
      Offset(centerX - 45, centerY - 20),
      Offset(centerX - 55, centerY - 30),
      strokePaint,
    );

    // Vegetables in left bag
    // Carrots
    paint.color = const Color(0xFFFF9800);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 80, centerY + 5),
        width: 10,
        height: 25,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 65, centerY + 10),
        width: 10,
        height: 25,
      ),
      paint,
    );
    // Carrot leaves
    paint.color = const Color(0xFF4CAF50);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 80, centerY - 8),
        width: 8,
        height: 10,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 65, centerY - 3),
        width: 8,
        height: 10,
      ),
      paint,
    );

    // Tomatoes
    paint.color = const Color(0xFFE53935);
    canvas.drawCircle(Offset(centerX - 55, centerY + 15), 8, paint);
    canvas.drawCircle(Offset(centerX - 75, centerY + 20), 7, paint);
    // Tomato stems
    paint.color = const Color(0xFF4CAF50);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 55, centerY + 5),
        width: 5,
        height: 8,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 75, centerY + 10),
        width: 5,
        height: 8,
      ),
      paint,
    );

    // Lettuce/Leafy greens
    paint.color = const Color(0xFF66BB6A);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 70, centerY + 30),
        width: 25,
        height: 12,
      ),
      paint,
    );

    // Right grocery bag (mesh/tote style)
    paint.color = const Color(0xFF2196F3); // Blue bag
    final rightBagPath = Path()
      ..moveTo(centerX + 40, centerY - 20)
      ..lineTo(centerX + 100, centerY - 20)
      ..lineTo(centerX + 105, centerY + 40)
      ..lineTo(centerX + 35, centerY + 40)
      ..close();
    canvas.drawPath(rightBagPath, paint);

    // Bag outline
    strokePaint.color = const Color(0xFF1976D2);
    strokePaint.strokeWidth = 2;
    canvas.drawPath(rightBagPath, strokePaint);

    // Bag handles (right)
    strokePaint.color = Colors.white;
    strokePaint.strokeWidth = 4;
    canvas.drawLine(
      Offset(centerX + 45, centerY - 20),
      Offset(centerX + 55, centerY - 30),
      strokePaint,
    );
    canvas.drawLine(
      Offset(centerX + 95, centerY - 20),
      Offset(centerX + 85, centerY - 30),
      strokePaint,
    );

    // Vegetables in right bag
    // Broccoli
    paint.color = const Color(0xFF4CAF50);
    canvas.drawCircle(Offset(centerX + 60, centerY + 5), 10, paint);
    // Broccoli florets
    paint.color = const Color(0xFF66BB6A);
    canvas.drawCircle(Offset(centerX + 56, centerY + 0), 5, paint);
    canvas.drawCircle(Offset(centerX + 64, centerY + 0), 5, paint);
    canvas.drawCircle(Offset(centerX + 60, centerY - 5), 5, paint);
    canvas.drawCircle(Offset(centerX + 58, centerY + 3), 4, paint);
    canvas.drawCircle(Offset(centerX + 62, centerY + 3), 4, paint);

    // Bell pepper
    paint.color = const Color(0xFF4CAF50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX + 80, centerY + 10),
          width: 12,
          height: 15,
        ),
        const Radius.circular(6),
      ),
      paint,
    );
    // Bell pepper stem
    paint.color = const Color(0xFF2E7D32);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 80, centerY + 2),
        width: 6,
        height: 5,
      ),
      paint,
    );

    // Cucumber
    paint.color = const Color(0xFF66BB6A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX + 70, centerY + 25),
          width: 8,
          height: 20,
        ),
        const Radius.circular(4),
      ),
      paint,
    );

    // Eggplant
    paint.color = const Color(0xFF7B1FA2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX + 85, centerY + 28),
          width: 10,
          height: 18,
        ),
        const Radius.circular(5),
      ),
      paint,
    );
    // Eggplant stem
    paint.color = const Color(0xFF2E7D32);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 85, centerY + 18),
        width: 6,
        height: 4,
      ),
      paint,
    );

    // Floating vegetables around the bags
    // Left side
    paint.color = const Color(0xFF4CAF50);
    canvas.drawCircle(Offset(centerX - 140, centerY - 10), 14, paint);
    paint.color = const Color(0xFFFF9800);
    canvas.drawCircle(Offset(centerX - 130, centerY + 15), 12, paint);
    paint.color = const Color(0xFFE53935);
    canvas.drawCircle(Offset(centerX - 120, centerY - 5), 10, paint);

    // Right side
    paint.color = const Color(0xFF4CAF50);
    canvas.drawCircle(Offset(centerX + 130, centerY - 5), 13, paint);
    paint.color = const Color(0xFFFF9800);
    canvas.drawCircle(Offset(centerX + 120, centerY + 20), 11, paint);
    paint.color = const Color(0xFF66BB6A);
    canvas.drawCircle(Offset(centerX + 140, centerY + 10), 12, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
