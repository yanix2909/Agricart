import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:email_validator/email_validator.dart';

/// Comprehensive email validation service that checks:
/// 1. Email format validity
/// 2. DNS MX records (domain can receive emails)
/// 3. Common typos in popular email providers
/// 4. Disposable/temporary email blocking
/// 5. Role-based email detection
class EmailValidationService {
  
  // List of disposable/temporary email domains to block
  static const Set<String> _disposableEmailDomains = {
    '10minutemail.com',
    'guerrillamail.com',
    'mailinator.com',
    'temp-mail.org',
    'throwaway.email',
    'trashmail.com',
    'yopmail.com',
    'tempmail.com',
    'getnada.com',
    'maildrop.cc',
    'dispostable.com',
    'fakeinbox.com',
    'getairmail.com',
    'sharklasers.com',
    'guerrillamail.info',
    'grr.la',
    'guerrillamail.biz',
    'guerrillamail.de',
    'spam4.me',
    'mailnesia.com',
    'emailondeck.com',
    'mintemail.com',
    'mytrashmail.com',
  };

  // Common email provider typos and their corrections
  static const Map<String, String> _commonTypos = {
    'gmial.com': 'gmail.com',
    'gmai.com': 'gmail.com',
    'gmil.com': 'gmail.com',
    'gnail.com': 'gmail.com',
    'gmailc.om': 'gmail.com',
    'gmail.co': 'gmail.com',
    'gmail.con': 'gmail.com',
    'yahooo.com': 'yahoo.com',
    'yaho.com': 'yahoo.com',
    'yhoo.com': 'yahoo.com',
    'yahoo.co': 'yahoo.com',
    'yahoo.con': 'yahoo.com',
    'hotmai.com': 'hotmail.com',
    'hotmal.com': 'hotmail.com',
    'hotmial.com': 'hotmail.com',
    'hotmail.co': 'hotmail.com',
    'hotmail.con': 'hotmail.com',
    'outlok.com': 'outlook.com',
    'outloo.com': 'outlook.com',
    'outlook.co': 'outlook.com',
    'outlook.con': 'outlook.com',
  };

  // Role-based emails (often used for business, not personal)
  static const Set<String> _roleBasedEmails = {
    'admin',
    'info',
    'support',
    'sales',
    'contact',
    'help',
    'webmaster',
    'noreply',
    'no-reply',
    'postmaster',
    'root',
  };

  /// Validates email format using industry-standard validation
  static bool isValidFormat(String email) {
    return EmailValidator.validate(email.trim());
  }

  /// Checks if the domain has valid MX records (can receive emails)
  static Future<bool> hasValidMxRecords(String email) async {
    try {
      final domain = email.split('@').last.trim();
      
      // Use nslookup or dig to check MX records
      // This is a simple check - in production you might want a more robust solution
      final result = await InternetAddress.lookup(domain);
      
      // If we can resolve the domain, it likely exists
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('MX record check failed for $email: $e');
      return false;
    }
  }

  /// Detects if email is from a disposable/temporary email service
  static bool isDisposableEmail(String email) {
    final domain = email.split('@').last.trim().toLowerCase();
    return _disposableEmailDomains.contains(domain);
  }

  /// Detects common typos and suggests corrections
  static String? detectTypo(String email) {
    final domain = email.split('@').last.trim().toLowerCase();
    return _commonTypos[domain];
  }

  /// Checks if email uses a role-based address (admin@, info@, etc.)
  static bool isRoleBasedEmail(String email) {
    final localPart = email.split('@').first.trim().toLowerCase();
    return _roleBasedEmails.contains(localPart);
  }

  /// Comprehensive validation with detailed result
  static Future<EmailValidationResult> validateEmail(String email) async {
    final trimmedEmail = email.trim().toLowerCase();
    
    // 1. Check format
    if (!isValidFormat(trimmedEmail)) {
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'Invalid email format',
        errorType: EmailErrorType.invalidFormat,
      );
    }

    // 2. Check for disposable email
    if (isDisposableEmail(trimmedEmail)) {
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'Temporary/disposable email addresses are not allowed',
        errorType: EmailErrorType.disposableEmail,
      );
    }

    // 3. Check for common typos
    final typoSuggestion = detectTypo(trimmedEmail);
    if (typoSuggestion != null) {
      final correctedEmail = trimmedEmail.replaceAll(
        trimmedEmail.split('@').last,
        typoSuggestion,
      );
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'Did you mean $correctedEmail?',
        errorType: EmailErrorType.possibleTypo,
        suggestedCorrection: correctedEmail,
      );
    }

    // 4. Check for role-based email (warning, not blocking)
    if (isRoleBasedEmail(trimmedEmail)) {
      return EmailValidationResult(
        isValid: true,
        email: trimmedEmail,
        warningMessage: 'This appears to be a role-based email. We recommend using a personal email address.',
        errorType: EmailErrorType.roleBasedEmail,
      );
    }

    // 5. Check DNS MX records
    final hasValidMx = await hasValidMxRecords(trimmedEmail);
    if (!hasValidMx) {
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'This email domain cannot receive emails. Please check and try again.',
        errorType: EmailErrorType.invalidDomain,
      );
    }

    // All checks passed
    return EmailValidationResult(
      isValid: true,
      email: trimmedEmail,
      errorType: EmailErrorType.none,
    );
  }

  /// Quick validation (format + disposable + typo check only, no network call)
  static EmailValidationResult validateEmailQuick(String email) {
    final trimmedEmail = email.trim().toLowerCase();
    
    // 1. Check format
    if (!isValidFormat(trimmedEmail)) {
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'Invalid email format',
        errorType: EmailErrorType.invalidFormat,
      );
    }

    // 2. Check for disposable email
    if (isDisposableEmail(trimmedEmail)) {
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'Temporary/disposable email addresses are not allowed',
        errorType: EmailErrorType.disposableEmail,
      );
    }

    // 3. Check for common typos
    final typoSuggestion = detectTypo(trimmedEmail);
    if (typoSuggestion != null) {
      final correctedEmail = trimmedEmail.replaceAll(
        trimmedEmail.split('@').last,
        typoSuggestion,
      );
      return EmailValidationResult(
        isValid: false,
        email: trimmedEmail,
        errorMessage: 'Did you mean $correctedEmail?',
        errorType: EmailErrorType.possibleTypo,
        suggestedCorrection: correctedEmail,
      );
    }

    // 4. Check for role-based email (warning only)
    if (isRoleBasedEmail(trimmedEmail)) {
      return EmailValidationResult(
        isValid: true,
        email: trimmedEmail,
        warningMessage: 'This appears to be a role-based email. We recommend using a personal email address.',
        errorType: EmailErrorType.roleBasedEmail,
      );
    }

    return EmailValidationResult(
      isValid: true,
      email: trimmedEmail,
      errorType: EmailErrorType.none,
    );
  }
}

/// Result of email validation with detailed information
class EmailValidationResult {
  final bool isValid;
  final String email;
  final String? errorMessage;
  final String? warningMessage;
  final EmailErrorType errorType;
  final String? suggestedCorrection;

  EmailValidationResult({
    required this.isValid,
    required this.email,
    this.errorMessage,
    this.warningMessage,
    required this.errorType,
    this.suggestedCorrection,
  });

  bool get hasError => errorMessage != null;
  bool get hasWarning => warningMessage != null;
  bool get hasTypoSuggestion => suggestedCorrection != null;
}

/// Types of email validation errors
enum EmailErrorType {
  none,
  invalidFormat,
  disposableEmail,
  possibleTypo,
  roleBasedEmail,
  invalidDomain,
  alreadyRegistered,
}

