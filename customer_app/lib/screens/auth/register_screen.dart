import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../../providers/auth_provider.dart';
import '../../utils/theme.dart';
import '../../utils/ormoc_barangays.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../services/email_validation_service.dart';
import 'login_screen.dart';
import '../../utils/responsive.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _suffixController = TextEditingController();
  final _ageController = TextEditingController();
  DateTime? _birthday;
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _sitioController = TextEditingController();
  String? _selectedBarangay;
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;
  String? _selectedGender;
  String? _selectedContactMethod;
  String? _selectedIdType;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  bool _isCheckingPhone = false;
  bool _isPhoneAvailable = true;
  bool _isCheckingEmail = false;
  bool _isEmailAvailable = true;
  EmailValidationResult? _emailValidationResult;
  String? _emailTypoSuggestion;
  final List<GlobalKey<FormState>> _stepFormKeys = List.generate(4, (_) => GlobalKey<FormState>());
  final ScrollController _stepScrollController = ScrollController();
  int _currentStep = 0;
  static const int _totalSteps = 4;
  
  // Debounce timer for username validation
  Timer? _usernameDebounceTimer;
  
  // Debounce timer for email validation
  Timer? _emailDebounceTimer;
  
  // Debounce timer for phone validation
  Timer? _phoneDebounceTimer;
  
  // ID Photo upload variables
  File? _idFrontPhoto;
  File? _idBackPhoto;
  bool _isUploadingFront = false;
  bool _isUploadingBack = false;

  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<String> _contactMethods = ['Phone Number', 'Gmail'];
  final List<String> _idTypes = [
    'Philippine National ID',
    'Driver\'s License',
    'Philippine Passport',
    'SSS',
    'GSIS',
    'Other'
  ];

  @override
  void dispose() {
    _usernameDebounceTimer?.cancel();
    _emailDebounceTimer?.cancel();
    _phoneDebounceTimer?.cancel();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _suffixController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _sitioController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _stepScrollController.dispose();
    super.dispose();
  }

  // Calculate age from birthday
  int? _calculateAge(DateTime? birthday) {
    if (birthday == null) return null;
    final now = DateTime.now();
    int age = now.year - birthday.year;
    if (now.month < birthday.month || 
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  // Show date picker for birthday
  Future<void> _selectBirthday(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)), // Must be at least 13 years old
      helpText: 'Select your birthday',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _birthday) {
      setState(() {
        _birthday = picked;
        final age = _calculateAge(picked);
        if (age != null) {
          _ageController.text = age.toString();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Set initial values for city and province
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cityController.text = 'Ormoc';
      _provinceController.text = 'Leyte';
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (username.isEmpty || username.length < 3 || !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      setState(() {
        _isUsernameAvailable = true;
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isAvailable = await authProvider.checkUsernameAvailability(username);
      
      if (mounted) {
        print('Before setState: _isUsernameAvailable = $_isUsernameAvailable');
        setState(() {
          _isUsernameAvailable = isAvailable;
          _isCheckingUsername = false;
        });
        print('After setState: _isUsernameAvailable = $_isUsernameAvailable');
        
        // Show immediate feedback if username is not available
        if (!isAvailable) {
          print('Username is NOT available - should show red border');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Username is already taken'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          print('Username IS available - should show green border');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUsernameAvailable = false;
          _isCheckingUsername = false;
        });
      }
    }
  }

  Future<void> _checkPhoneAvailability(String phone) async {
    if (phone.length < 10) {
      setState(() {
        _isPhoneAvailable = true;
        _isCheckingPhone = false;
      });
      return;
    }

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isAvailable = await authProvider.checkPhoneAvailability(phone);
      
      if (mounted) {
        print('=== PHONE STATE UPDATE ===');
        print('Setting _isPhoneAvailable to: $isAvailable');
        print('Current value: $_isPhoneAvailable');
        
        print('Before setState: _isPhoneAvailable = $_isPhoneAvailable');
        setState(() {
          _isPhoneAvailable = isAvailable;
          _isCheckingPhone = false;
        });
        
        print('After setState: _isPhoneAvailable = $_isPhoneAvailable');
        print('============================');
        
        // Show immediate feedback if phone is not available
        if (!isAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phone number is already registered'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPhoneAvailable = false;
          _isCheckingPhone = false;
        });
      }
    }
  }

  Future<void> _checkEmailAvailability(String email) async {
    if (email.isEmpty || !RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(email.trim())) {
      setState(() {
        _isEmailAvailable = true;
        _isCheckingEmail = false;
        _emailValidationResult = null;
        _emailTypoSuggestion = null;
      });
      return;
    }

    try {
      // Step 1: Comprehensive email validation (format, DNS, disposable, typos)
      final validationResult = await EmailValidationService.validateEmail(email);
      
      if (mounted) {
        setState(() {
          _emailValidationResult = validationResult;
          _emailTypoSuggestion = validationResult.suggestedCorrection;
        });

        // If validation failed, show error and stop
        if (!validationResult.isValid) {
          setState(() {
            _isEmailAvailable = false;
            _isCheckingEmail = false;
          });

          // Show appropriate error message
          if (validationResult.hasTypoSuggestion) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(validationResult.errorMessage ?? 'Email validation failed'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Use Suggested',
                  textColor: Colors.white,
                  onPressed: () {
                    _emailController.text = validationResult.suggestedCorrection!;
                  },
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(validationResult.errorMessage ?? 'Email validation failed'),
                backgroundColor: AppTheme.errorColor,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        // Show warning if it's a role-based email
        if (validationResult.hasWarning) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validationResult.warningMessage!),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Step 2: Check database availability (only if email passed validation)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isAvailable = await authProvider.checkEmailAvailability(email);
      
      if (mounted) {
        setState(() {
          _isEmailAvailable = isAvailable;
          _isCheckingEmail = false;
        });
        
        // Show immediate feedback if email is already registered
        if (!isAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email address is already registered'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmailAvailable = false;
          _isCheckingEmail = false;
          _emailValidationResult = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error validating email: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Builds the appropriate icon for email validation state
  Widget _buildEmailValidationIcon() {
    // If email validation failed (disposable, typo, invalid domain, etc.)
    if (_emailValidationResult != null && !_emailValidationResult!.isValid) {
      return Icon(
        _emailValidationResult!.hasTypoSuggestion 
            ? Icons.warning_amber_rounded 
            : Icons.error,
        color: _emailValidationResult!.hasTypoSuggestion 
            ? Colors.orange 
            : AppTheme.errorColor,
      );
    }
    
    // If email is already registered in database
    if (!_isEmailAvailable) {
      return const Icon(
        Icons.error,
        color: AppTheme.errorColor,
      );
    }
    
    // If email validation passed and available
    if (_emailValidationResult != null && _emailValidationResult!.isValid && _isEmailAvailable) {
      return Icon(
        _emailValidationResult!.hasWarning 
            ? Icons.check_circle_outline 
            : Icons.check_circle,
        color: Colors.green,
      );
    }
    
    // If only format is valid (still checking)
    return const Icon(
      Icons.check_circle,
      color: Colors.green,
    );
  }

  void _scrollToTop() {
    if (!_stepScrollController.hasClients) return;
    _stepScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  bool _validateStep(int stepIndex) {
    final formState = _stepFormKeys[stepIndex].currentState;
    final isValid = formState?.validate() ?? true;

    if (!isValid) {
      return false;
    }

    if (stepIndex == 1) {
      // Check email validation status
      final email = _emailController.text.trim();
      
      // If email is being checked, block proceeding
      if (_isCheckingEmail) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait while we validate your email address...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }
      
      // If email format is valid, check comprehensive validation
      if (email.isNotEmpty && RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
        // Check if validation failed (invalid domain, disposable, etc.)
        if (_emailValidationResult != null && !_emailValidationResult!.isValid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_emailValidationResult!.errorMessage ?? 'Invalid email address'),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 3),
            ),
          );
          return false;
        }
        
        // Check if email is already registered
        if (!_isEmailAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email address is already registered. Please use a different email.'),
              backgroundColor: AppTheme.errorColor,
              duration: Duration(seconds: 3),
            ),
          );
          return false;
        }
        
        // If validation hasn't run yet (user typed fast and clicked next), trigger it and block
        if (_emailValidationResult == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Validating email address... Please wait.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          // Trigger validation
          setState(() {
            _isCheckingEmail = true;
          });
          _checkEmailAvailability(email);
          return false;
        }
      }
      
      // Check ID photos
      if (_idFrontPhoto == null || _idBackPhoto == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload both front and back ID photos'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return false;
      }
    }

    return true;
  }

  bool _validateAllSteps() {
    for (var i = 0; i < _totalSteps; i++) {
      if (!_validateStep(i)) {
        setState(() {
          _currentStep = i;
        });
        _scrollToTop();
        return false;
      }
    }
    return true;
  }

  void _goToNextStep() {
    if (_currentStep >= _totalSteps - 1) return;
    if (_validateStep(_currentStep)) {
      setState(() {
        _currentStep++;
      });
      _scrollToTop();
    }
  }

  void _goToPreviousStep() {
    if (_currentStep == 0) return;
    setState(() {
      _currentStep--;
    });
    _scrollToTop();
  }

  Widget _buildStepProgress() {
    final progress = (_currentStep + 1) / _totalSteps;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Step ${_currentStep + 1} of $_totalSteps',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 8)),
          ClipRRect(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStepForms() {
    return [
      Form(
        key: _stepFormKeys[0],
        child: _buildPersonalDetailsStep(),
      ),
      Form(
        key: _stepFormKeys[1],
        child: _buildIdAndContactStep(),
      ),
      Form(
        key: _stepFormKeys[2],
        child: _buildAddressStep(),
      ),
      Form(
        key: _stepFormKeys[3],
        child: _buildAccountAndTermsStep(),
      ),
    ];
  }

  Widget _buildPersonalDetailsStep() {
    return _buildStepCard([
      _buildSectionHeader(
        icon: Icons.person_outline,
        title: 'Personal Details',
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      _buildModernTextField(
        controller: _firstNameController,
        label: 'First Name *',
        icon: Icons.person_outline,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter your first name';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      _buildModernTextField(
        controller: _lastNameController,
        label: 'Last Name *',
        icon: Icons.person_outline,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter your last name';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      _buildModernTextField(
        controller: _middleInitialController,
        label: 'Middle Initial (Optional)',
        icon: Icons.person_outline,
        textCapitalization: TextCapitalization.characters,
        maxLength: 3,
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      _buildModernTextField(
        controller: _suffixController,
        label: 'Suffix (Optional)',
        icon: Icons.person_outline,
        hint: 'e.g., Jr., Sr., III',
        textCapitalization: TextCapitalization.words,
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      InkWell(
        onTap: () => _selectBirthday(context),
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
        child: InputDecorator(
          decoration: _getInputDecoration(
            label: 'Birthday *',
            icon: Icons.calendar_today_outlined,
            suffixIcon: Icons.arrow_drop_down,
          ),
          child: Text(
            _birthday != null
                ? '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}'
                : 'Select your birthday',
            style: TextStyle(
              color: _birthday != null ? Colors.black87 : Colors.grey[600],
              fontSize: Responsive.getFontSize(context, mobile: 15),
            ),
          ),
        ),
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      TextFormField(
        controller: _ageController,
        readOnly: true,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Age (Auto-calculated)',
          icon: Icons.calendar_today_outlined,
        ).copyWith(
          filled: true,
          fillColor: Colors.grey[100],
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please select your birthday to calculate age';
          }
          final age = int.tryParse(value);
          if (age == null || age < 13 || age > 120) {
            return 'Age must be between 13 and 120';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      DropdownButtonFormField<String>(
        value: _selectedGender,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15), color: Colors.black87),
        decoration: _getInputDecoration(
          label: 'Gender *',
          icon: Icons.person_outline,
        ),
        items: _genders.map((gender) {
          return DropdownMenuItem<String>(
            value: gender,
            child: Text(gender),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedGender = value;
          });
        },
        validator: (value) {
          if (value == null) {
            return 'Please select your gender';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 14)),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: _goToNextStep,
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
            ),
          ),
          child: const Text('Next'),
        ),
      ),
    ]);
  }

  Widget _buildIdAndContactStep() {
    return _buildStepCard([
      _buildSectionHeader(
        icon: Icons.credit_card_outlined,
        title: 'Valid ID Information',
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      DropdownButtonFormField<String>(
        value: _selectedIdType,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15), color: Colors.black87),
        decoration: _getInputDecoration(
          label: 'ID Type *',
          icon: Icons.credit_card_outlined,
        ),
        items: _idTypes.map((idType) {
          return DropdownMenuItem<String>(
            value: idType,
            child: Text(idType),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedIdType = value;
          });
        },
        validator: (value) {
          if (value == null) {
            return 'Please select your ID type';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 14)),
      _buildIdPhotoSection(),
      SizedBox(height: Responsive.getHeight(context, mobile: 18)),
      _buildSectionHeader(
        icon: Icons.contact_mail_outlined,
        title: 'Contact Details',
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Phone Number *',
          icon: Icons.phone_outlined,
        ).copyWith(
          suffixIcon: _isCheckingPhone
              ? SizedBox(
                  width: Responsive.getWidth(context, mobile: 20),
                  height: Responsive.getHeight(context, mobile: 20),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                )
              : _phoneController.text.isNotEmpty && RegExp(r'^\+?[0-9]{10,13}$').hasMatch(_phoneController.text)
                  ? Icon(
                      _isPhoneAvailable ? Icons.check_circle : Icons.error,
                      color: _isPhoneAvailable ? Colors.green : AppTheme.errorColor,
                    )
                  : null,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter your phone number';
          }
          if (!RegExp(r'^\+?[0-9]{10,13}$').hasMatch(value)) {
            return 'Please enter a valid phone number';
          }
          if (!_isPhoneAvailable) {
            return 'Phone number is already registered';
          }
          return null;
        },
        onChanged: (value) {
          _phoneDebounceTimer?.cancel();

          if (value.length >= 10 && RegExp(r'^\+?[0-9]{10,13}$').hasMatch(value)) {
            setState(() {
              _isPhoneAvailable = true;
              _isCheckingPhone = false;
            });

            _phoneDebounceTimer = Timer(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _isCheckingPhone = true;
                });
                _checkPhoneAvailability(value);
              }
            });
          } else {
            if (!_isPhoneAvailable || _isCheckingPhone) {
              setState(() {
                _isPhoneAvailable = true;
                _isCheckingPhone = false;
              });
            }
          }
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Email Address *',
          icon: Icons.email_outlined,
        ).copyWith(
          // Show red border if validation failed
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            borderSide: const BorderSide(color: AppTheme.errorColor, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            borderSide: const BorderSide(color: AppTheme.errorColor, width: 2.5),
          ),
          suffixIcon: _isCheckingEmail
              ? SizedBox(
                  width: Responsive.getWidth(context, mobile: 20),
                  height: Responsive.getHeight(context, mobile: 20),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                )
              : _emailController.text.isNotEmpty && RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(_emailController.text.trim())
                  ? _buildEmailValidationIcon()
                  : null,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter your email address';
          }
          if (!RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(value.trim())) {
            return 'Please enter a valid email address';
          }
          
          // Check comprehensive validation result
          if (_emailValidationResult != null && !_emailValidationResult!.isValid) {
            return _emailValidationResult!.errorMessage ?? 'Invalid email';
          }
          
          // Check database availability
          if (!_isEmailAvailable && RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(value.trim())) {
            return 'Email address is already registered';
          }
          
          return null;
        },
        onChanged: (value) {
          _emailDebounceTimer?.cancel();

          if (RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(value.trim())) {
            _emailDebounceTimer = Timer(const Duration(milliseconds: 800), () {
              if (mounted) {
                setState(() {
                  _isCheckingEmail = true;
                  _emailValidationResult = null;
                  _emailTypoSuggestion = null;
                });
                _checkEmailAvailability(value.trim());
              }
            });
          } else {
            if (!_isEmailAvailable || _isCheckingEmail || _emailValidationResult != null) {
              setState(() {
                _isEmailAvailable = true;
                _isCheckingEmail = false;
                _emailValidationResult = null;
                _emailTypoSuggestion = null;
              });
            }
          }
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _goToPreviousStep,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                foregroundColor: AppTheme.primaryColor,
              ),
              child: const Text('Back'),
            ),
          ),
          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
          Expanded(
            child: TextButton(
              onPressed: _goToNextStep,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
              ),
              child: const Text('Next'),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildAddressStep() {
    return _buildStepCard([
      _buildSectionHeader(
        icon: Icons.location_on_outlined,
        title: 'Home Address Information',
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      Container(
        padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 14)),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.primaryColor, size: Responsive.getIconSize(context, mobile: 18)),
            SizedBox(width: Responsive.getWidth(context, mobile: 10)),
            Expanded(
              child: Text(
                'Only customers from Ormoc City, Leyte are allowed to register.',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w500,
                  fontSize: Responsive.getFontSize(context, mobile: 13),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 14)),
      _buildModernTextField(
        controller: _streetController,
        label: 'Street (Optional)',
        icon: Icons.streetview_outlined,
        hint: 'Enter your street name',
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      _buildModernTextField(
        controller: _sitioController,
        label: 'Sitio *',
        icon: Icons.location_on_outlined,
        hint: 'Enter your sitio',
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter your sitio';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      SearchableBarangayDropdown(
        value: _selectedBarangay,
        labelText: 'Barangay *',
        hintText: 'Select your barangay',
        prefixIcon: Icons.location_city_outlined,
        onChanged: (value) {
          setState(() {
            _selectedBarangay = value;
          });
        },
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please select your barangay';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _cityController,
        enabled: false,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'City',
          icon: Icons.location_city_outlined,
        ).copyWith(
          filled: true,
          fillColor: Colors.grey[100],
        ),
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _provinceController,
        enabled: false,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Province',
          icon: Icons.location_city_outlined,
        ).copyWith(
          filled: true,
          fillColor: Colors.grey[100],
        ),
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _goToPreviousStep,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                foregroundColor: AppTheme.primaryColor,
              ),
              child: const Text('Back'),
            ),
          ),
          SizedBox(width: Responsive.getWidth(context, mobile: 12)),
          Expanded(
            child: TextButton(
              onPressed: _goToNextStep,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                ),
              ),
              child: const Text('Next'),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildAccountAndTermsStep() {
    return _buildStepCard([
      _buildSectionHeader(
        icon: Icons.account_circle_outlined,
        title: 'Account and Password',
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _usernameController,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Username *',
          icon: Icons.person_outline,
        ).copyWith(
          hintText: 'Choose a unique username',
          suffixIcon: _isCheckingUsername
              ? SizedBox(
                  width: Responsive.getWidth(context, mobile: 20),
                  height: Responsive.getHeight(context, mobile: 20),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                )
              : _usernameController.text.isNotEmpty && RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_usernameController.text) && _usernameController.text.length >= 3
                  ? Icon(
                      _isUsernameAvailable ? Icons.check_circle : Icons.error,
                      color: _isUsernameAvailable ? Colors.green : AppTheme.errorColor,
                    )
                  : null,
        ),
        onChanged: (value) {
          _usernameDebounceTimer?.cancel();

          if (RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value) && value.length >= 3) {
            _usernameDebounceTimer = Timer(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _isCheckingUsername = true;
                });
                _checkUsernameAvailability(value);
              }
            });
          } else {
            if (!_isUsernameAvailable || _isCheckingUsername) {
              setState(() {
                _isUsernameAvailable = true;
                _isCheckingUsername = false;
              });
            }
          }
        },
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter a username';
          }
          if (value.length < 3) {
            return 'Username must be at least 3 characters';
          }
          if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
            return 'Username can only contain letters, numbers, and underscores';
          }
          if (!_isUsernameAvailable && value.length >= 3) {
            return 'Username is already taken';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Password *',
          icon: Icons.lock_outline,
        ).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Colors.grey[600],
              size: Responsive.getIconSize(context, mobile: 20),
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter a password';
          }
          if (value.length < 6) {
            return 'Password must be at least 6 characters';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 12)),
      TextFormField(
        controller: _confirmPasswordController,
        obscureText: _obscureConfirmPassword,
        style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
        decoration: _getInputDecoration(
          label: 'Confirm Password *',
          icon: Icons.lock_outline,
        ).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Colors.grey[600],
              size: Responsive.getIconSize(context, mobile: 20),
            ),
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please confirm your password';
          }
          if (value != _passwordController.text) {
            return 'Passwords do not match';
          }
          return null;
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 20)),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: _acceptTerms,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            onChanged: (value) {
              setState(() {
                _acceptTerms = value ?? false;
              });
            },
          ),
          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'I accept the Terms and Conditions',
                style: AppTheme.bodyTextStyle.copyWith(fontSize: Responsive.getFontSize(context, mobile: 14), height: 1.3),
              ),
            ),
          ),
        ],
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 6)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _goToPreviousStep,
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 0), vertical: Responsive.getSpacing(context, mobile: 8)),
            foregroundColor: AppTheme.primaryColor,
          ),
          child: const Text('Back to Step 3'),
        ),
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 10)),
      Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final isLoading = authProvider.isLoading || authProvider.isSigningIn;

          return Container(
            width: double.infinity,
            height: Responsive.getHeight(context, mobile: 48),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
              gradient: LinearGradient(
                colors: isLoading
                    ? [Colors.grey.shade400, Colors.grey.shade500]
                    : [
                        AppTheme.primaryColor,
                        AppTheme.primaryDarkColor,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      _register();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
                ),
                padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 12)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: Responsive.getHeight(context, mobile: 18),
                            width: Responsive.getWidth(context, mobile: 18),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withOpacity(0.85),
                              ),
                            ),
                          ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 10)),
                          Text(
                            'Creating Account...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: Responsive.getFontSize(context, mobile: 15),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Register',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Responsive.getFontSize(context, mobile: 15),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
      SizedBox(height: Responsive.getHeight(context, mobile: 14)),
      TextButton(
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        },
        child: const Text('Already have an account? Sign In'),
      ),
    ]);
  }

  Future<void> _pickImage(bool isFront) async {
    try {
      final ImagePicker picker = ImagePicker();
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Select Image Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.camera_alt),
                  title: Text('Camera'),
                  onTap: () {
                    Navigator.of(context).pop(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_library),
                  title: Text('Gallery'),
                  onTap: () {
                    Navigator.of(context).pop(ImageSource.gallery);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (source == null || !mounted) return;

      setState(() {
        if (isFront) {
          _isUploadingFront = true;
        } else {
          _isUploadingBack = true;
        }
      });

      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (!mounted) return;

      if (image != null) {
        setState(() {
          if (isFront) {
            _idFrontPhoto = File(image.path);
            _isUploadingFront = false;
          } else {
            _idBackPhoto = File(image.path);
            _isUploadingBack = false;
          }
        });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ID ${isFront ? 'Front' : 'Back'} photo selected successfully'),
              backgroundColor: AppTheme.successColor,
              duration: const Duration(seconds: 2),
            ),
          );
      } else {
        setState(() {
          if (isFront) {
            _isUploadingFront = false;
          } else {
            _isUploadingBack = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        if (isFront) {
          _isUploadingFront = false;
        } else {
          _isUploadingBack = false;
        }
      });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select image: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
    }
  }

  void _showPhotoReviewDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Review Your ID Photos'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Please review your uploaded ID photos before proceeding:',
                  style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                
                // Front ID Photo
                const Text(
                  'Front Side:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                if (_idFrontPhoto != null)
                  Container(
                    height: Responsive.getHeight(context, mobile: 150),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                      child: Image.file(
                        _idFrontPhoto!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  const Text('No front photo uploaded', style: TextStyle(color: Colors.red)),
                
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                
                // Back ID Photo
                const Text(
                  'Back Side:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                if (_idBackPhoto != null)
                  Container(
                    height: Responsive.getHeight(context, mobile: 150),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                      child: Image.file(
                        _idBackPhoto!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  const Text('No back photo uploaded', style: TextStyle(color: Colors.red)),
                
                SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: Responsive.getIconSize(context, mobile: 20)),
                      SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                      Expanded(
                        child: Text(
                          'Note: Are you sure all the information you have given are correct? This can affect your account\'s verification checking and approval.',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: Responsive.getFontSize(context, mobile: 13),
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _proceedWithRegistration();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm & Register'),
            ),
          ],
        );
      },
    );
  }

  void _register() {
    debugPrint('Register button clicked');
    
    // First validate the form
    if (!_validateAllSteps()) {
      debugPrint('Form validation failed');
      return;
    }

    debugPrint('Form validation passed, checking additional requirements...');

    // Create a function to show error snackbar
    void showError(String message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message,
              style: AppTheme.bodyTextStyle.copyWith(color: Colors.white)),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Check all required fields
    if (!_isUsernameAvailable && _usernameController.text.length >= 3) {
      showError('Username is already taken. Please choose a different username.');
      return;
    }

    if (!_isPhoneAvailable && _phoneController.text.length >= 10) {
      showError('Phone number is already registered. Please use a different phone number.');
      return;
    }

    // Check email validation result
    if (_emailValidationResult != null && !_emailValidationResult!.isValid) {
      showError(_emailValidationResult!.errorMessage ?? 'Invalid email address. Please check and try again.');
      return;
    }
    
    if (!_isEmailAvailable && RegExp(r'^[\w-\.]+@[\w-\.]+\.[a-zA-Z]{2,}$').hasMatch(_emailController.text.trim())) {
      showError('Email address is already registered. Please use a different email address.');
      return;
    }
    
    // If validation hasn't completed, block registration
    if (_isCheckingEmail) {
      showError('Please wait while we validate your email address...');
      return;
    }

    if (_birthday == null) {
      showError('Please select your birthday');
      return;
    }

    if (_selectedGender == null) {
      showError('Please select your gender');
      return;
    }

    if (_selectedIdType == null) {
      showError('Please select your ID type');
      return;
    }

    if (_selectedBarangay == null || _selectedBarangay!.trim().isEmpty) {
      showError('Please select your barangay');
      return;
    }

    if (!_acceptTerms) {
      showError('Please accept the Terms and Conditions');
      return;
    }

    // Check ID photos
    if (_idFrontPhoto == null) {
      showError('Please upload the front side of your valid ID');
      return;
    }

    if (_idBackPhoto == null) {
      showError('Please upload the back side of your valid ID');
      return;
    }

    debugPrint('All validations passed, showing photo review dialog');

    // Show photo review dialog before proceeding
    _showPhotoReviewDialog();
  }

  void _proceedWithRegistration() async {
    debugPrint('Starting registration process...');
    
    // Get AuthProvider without listening to changes
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      // Construct complete address
      final streetPart = _streetController.text.trim().isNotEmpty ? '${_streetController.text.trim()}, ' : '';
      final sitioPart = _sitioController.text.trim().isNotEmpty ? '${_sitioController.text.trim()}, ' : '';
      final completeAddress = '${streetPart}${sitioPart}${_selectedBarangay ?? ''}, Ormoc, Leyte';
      debugPrint('Address: $completeAddress');

      // Double check photos are available
      if (_idFrontPhoto == null || _idBackPhoto == null) {
        debugPrint('Error: ID photos missing');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload both front and back ID photos'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Construct full name from separate fields
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final middleInitial = _middleInitialController.text.trim();
      final suffix = _suffixController.text.trim();
      
      String fullName = '$firstName $lastName';
      if (middleInitial.isNotEmpty) {
        fullName = '$firstName $middleInitial $lastName';
      }
      if (suffix.isNotEmpty) {
        fullName = '$fullName $suffix';
      }
      
      debugPrint('Calling authProvider.register...');
      final success = await authProvider.register(
        username: _usernameController.text.trim(),
        fullName: fullName.trim(),
        firstName: firstName,
        lastName: lastName,
        middleInitial: middleInitial.isNotEmpty ? middleInitial : null,
        suffix: suffix.isNotEmpty ? suffix : null,
        age: int.parse(_ageController.text.trim()),
        gender: _selectedGender!,
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: completeAddress,
        street: _streetController.text.trim().isNotEmpty ? _streetController.text.trim() : null,
        sitio: _sitioController.text.trim().isNotEmpty ? _sitioController.text.trim() : null,
        barangay: _selectedBarangay,
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
        idFrontPhoto: _idFrontPhoto!,  // Non-null assertion is safe here
        idBackPhoto: _idBackPhoto!,    // Non-null assertion is safe here
        idType: _selectedIdType!,
        birthday: _birthday,
      );

      debugPrint('Registration result: $success');

      if (!mounted) return;

      if (success) {
        debugPrint('Registration successful!');
        
        // Show success message
        // Show verification pending message
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Registration Successful'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your account has been created successfully!'),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  Text('Next steps:'),
                  SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                  Text('1. Your ID will be verified by our admin team'),
                  Text('2. This usually takes 24-48 hours'),
                  Text('3. You\'ll be able to login once verified'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Navigate to login screen after dialog is closed
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  child: const Text('OK, I Understand'),
                ),
              ],
            );
          },
        );
      } else {
        debugPrint('Registration failed with error: ${authProvider.error}');
        
        // Show error from AuthProvider
        final error = authProvider.error ?? 'Registration failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Exception during registration: $e');
      if (!mounted) return;

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: Responsive.getIconSize(context, mobile: 18)),
        SizedBox(width: Responsive.getWidth(context, mobile: 10)),
        Text(
          title,
          style: TextStyle(
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.w600,
            fontSize: Responsive.getFontSize(context, mobile: 16),
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStepCard(List<Widget> children) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  InputDecoration _getInputDecoration({
    required String label,
    required IconData icon,
    IconData? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[700], fontSize: Responsive.getFontSize(context, mobile: 13), fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, color: Colors.grey[600], size: Responsive.getIconSize(context, mobile: 20)),
      suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: Colors.grey[600], size: Responsive.getIconSize(context, mobile: 18)) : null,
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
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextCapitalization? textCapitalization,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 15)),
      textCapitalization: textCapitalization ?? TextCapitalization.none,
      maxLength: maxLength,
      decoration: _getInputDecoration(label: label, icon: icon).copyWith(
        hintText: hint,
      ),
      validator: validator,
    );
  }

  Widget _buildIdPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valid ID Photos (Required)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        SizedBox(height: Responsive.getHeight(context, mobile: 8)),
        Text(
          'Please upload clear photos of your valid government-issued ID',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
        
        // ID Front Photo
        Row(
          children: [
            Expanded(
              child: _buildIdPhotoCard(
                title: 'Front Side',
                isUploaded: _idFrontPhoto != null,
                isLoading: _isUploadingFront,
                onTap: () => _pickImage(true),
              ),
            ),
            SizedBox(width: Responsive.getWidth(context, mobile: 16)),
            Expanded(
              child: _buildIdPhotoCard(
                title: 'Back Side',
                isUploaded: _idBackPhoto != null,
                isLoading: _isUploadingBack,
                onTap: () => _pickImage(false),
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.getHeight(context, mobile: 16)),
        Container(
          padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: Responsive.getIconSize(context, mobile: 18)),
              SizedBox(width: Responsive.getWidth(context, mobile: 8)),
              Expanded(
                child: Text(
                  'Uploading a valid ID is required for user verification. This measure ensures the authenticity of users and promotes accountability in placing and managing orders.',
                  style: TextStyle(
                    color: Colors.blue[800],
                    fontSize: Responsive.getFontSize(context, mobile: 12),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdPhotoCard({
    required String title,
    required bool isUploaded,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: Responsive.getHeight(context, mobile: 120),
        decoration: BoxDecoration(
          border: Border.all(
            color: isUploaded ? AppTheme.successColor : Colors.grey[300]!,
            width: Responsive.getWidth(context, mobile: 2),
          ),
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
          color: isUploaded ? AppTheme.successColor.withOpacity(0.1) : Colors.grey[50],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              )
            else if (isUploaded)
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    color: Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    child: Image.file(
                      title == 'Front Side' ? _idFrontPhoto! : _idBackPhoto!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              )
            else
              Icon(
                Icons.add_a_photo,
                color: Colors.grey[400],
                size: Responsive.getIconSize(context, mobile: 32),
              ),
            if (!isUploaded) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 8)),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                'Tap to upload',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepForms = _buildStepForms();
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.primaryColor.withOpacity(0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
            ),
            padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 10)),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboardInset),
              child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                child: Column(
                  children: [
                  Text(
                    'AgriCart',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: Responsive.getFontSize(context, mobile: 30),
                      color: AppTheme.primaryColor,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                  Text(
                    'Create your account',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                            fontSize: Responsive.getFontSize(context, mobile: 15),
                      fontWeight: FontWeight.w400,
                            letterSpacing: 0.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  ],
                ),
              ),
              _buildStepProgress(),
                  SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                        Expanded(
                child: SingleChildScrollView(
                  controller: _stepScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                  child: IndexedStack(
                    index: _currentStep,
                    children: stepForms,
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
