import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // TODO: Replace these with your actual Supabase credentials
  // Get these from your Supabase project settings: Settings > API
  static const String _supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co'; // Replace with your Supabase URL
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM'; // Replace with your Supabase Anon Key
  static const String _bucketName = 'customerid_image';

  static bool _initialized = false;

  /// Initialize Supabase client
  /// Call this once at app startup (in main.dart) or it will be called automatically when needed
  static Future<void> initialize() async {
    // Check if credentials are configured
    if (_supabaseUrl == 'YOUR_SUPABASE_URL' || _supabaseAnonKey == 'YOUR_SUPABASE_ANON_KEY') {
      throw Exception(
        'Supabase credentials not configured. Please set _supabaseUrl and _supabaseAnonKey in lib/services/supabase_service.dart'
      );
    }

    // Check if already initialized
    try {
      if (Supabase.instance.isInitialized) {
        debugPrint('🔍 Supabase already initialized');
        debugPrint('🔍 Expected URL: $_supabaseUrl');
        if (_initialized) {
          debugPrint('✅ Supabase already initialized');
          return;
        }
      }
    } catch (e) {
      debugPrint('🔍 Supabase instance check failed: $e (this is ok if not initialized yet)');
    }

    if (_initialized) {
      debugPrint('✅ Supabase already marked as initialized');
      return;
    }

    debugPrint('🔍 Initializing Supabase with URL: $_supabaseUrl');
    debugPrint('🔍 Anon key (first 20 chars): ${_supabaseAnonKey.substring(0, 20)}...');
    
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );
      _initialized = true;
      debugPrint('✅ Supabase initialized successfully');
      debugPrint('✅ Supabase URL: $_supabaseUrl');
    } catch (e) {
      debugPrint('❌ Failed to initialize Supabase: $e');
      throw Exception('Failed to initialize Supabase: $e');
    }
  }

  /// Get Supabase client instance
  static SupabaseClient get client {
    if (!_initialized) {
      throw Exception('Supabase not initialized. Call SupabaseService.initialize() first.');
    }
    return Supabase.instance.client;
  }

  /// Upload image file to Supabase bucket
  /// Returns the public URL of the uploaded image
  static Future<String> uploadImage(File imageFile, String fileName) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      debugPrint('=== Supabase Upload Debug ===');
      debugPrint('File path: ${imageFile.path}');
      debugPrint('File exists: ${await imageFile.exists()}');
      debugPrint('File name: $fileName');
      debugPrint('Bucket name: $_bucketName');

      // Check if file exists
      if (!await imageFile.exists()) {
        throw Exception('File does not exist: ${imageFile.path}');
      }

      // Read file bytes
      final fileBytes = await imageFile.readAsBytes();
      debugPrint('File size: ${fileBytes.length} bytes');

      if (fileBytes.isEmpty) {
        throw Exception('File is empty: ${imageFile.path}');
      }

      // Detect content type from file extension
      String contentType = 'image/jpeg';
      final extension = fileName.toLowerCase().split('.').last;
      if (extension == 'png') {
        contentType = 'image/png';
      } else if (extension == 'jpg' || extension == 'jpeg') {
        contentType = 'image/jpeg';
      } else if (extension == 'webp') {
        contentType = 'image/webp';
      }

      debugPrint('Content type: $contentType');

      // Upload to Supabase Storage using uploadBinary
      debugPrint('Starting upload to Supabase...');
      String uploadedPath;
      
      try {
        uploadedPath = await client.storage
            .from(_bucketName)
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true, // Replace if exists
              ),
            );
        
        debugPrint('Upload successful! Uploaded path: $uploadedPath');
      } catch (uploadError) {
        debugPrint('Upload failed with error: $uploadError');
        // Check if it's a duplicate file error (which is ok with upsert: true)
        if (uploadError.toString().contains('duplicate') || 
            uploadError.toString().contains('already exists')) {
          debugPrint('File already exists, continuing...');
          uploadedPath = fileName;
        } else {
          rethrow;
        }
      }

      // Get public URL
      final publicUrl = client.storage
          .from(_bucketName)
          .getPublicUrl(uploadedPath);

      debugPrint('Public URL: $publicUrl');
      debugPrint('=== Upload Complete ===');

      return publicUrl;
    } catch (e, stackTrace) {
      debugPrint('=== Supabase Upload Error ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('============================');
      
      // Provide more detailed error message
      String errorMessage = 'Failed to upload image to Supabase';
      if (e.toString().contains('bucket')) {
        errorMessage = 'Supabase bucket "$_bucketName" not found or not accessible. Please check your Supabase configuration.';
      } else if (e.toString().contains('permission') || e.toString().contains('policy')) {
        errorMessage = 'Permission denied. Please check Supabase storage policies for bucket "$_bucketName".';
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and Supabase URL.';
      } else {
        errorMessage = 'Failed to upload image: ${e.toString()}';
      }
      
      throw Exception(errorMessage);
    }
  }

  /// Delete image from Supabase bucket
  static Future<void> deleteImage(String fileName) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      await client.storage
          .from(_bucketName)
          .remove([fileName]);
    } catch (e) {
      throw Exception('Failed to delete image from Supabase: $e');
    }
  }

  /// Upload GCash receipt image to Supabase gcash_receipt bucket
  /// Returns the public URL of the uploaded image
  static Future<String> uploadGcashReceipt(File imageFile, String fileName) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      const bucketName = 'gcash_receipt';

      debugPrint('=== Supabase GCash Receipt Upload Debug ===');
      debugPrint('File path: ${imageFile.path}');
      debugPrint('File exists: ${await imageFile.exists()}');
      debugPrint('File name: $fileName');
      debugPrint('Bucket name: $bucketName');

      // Check if file exists
      if (!await imageFile.exists()) {
        throw Exception('File does not exist: ${imageFile.path}');
      }

      // Read file bytes
      final fileBytes = await imageFile.readAsBytes();
      debugPrint('File size: ${fileBytes.length} bytes');

      if (fileBytes.isEmpty) {
        throw Exception('File is empty: ${imageFile.path}');
      }

      // Detect content type from file extension
      String contentType = 'image/jpeg';
      final extension = fileName.toLowerCase().split('.').last;
      if (extension == 'png') {
        contentType = 'image/png';
      } else if (extension == 'jpg' || extension == 'jpeg') {
        contentType = 'image/jpeg';
      } else if (extension == 'webp') {
        contentType = 'image/webp';
      }

      debugPrint('Content type: $contentType');

      // Upload to Supabase Storage using uploadBinary
      debugPrint('Starting upload to Supabase...');
      String uploadedPath;
      
      try {
        uploadedPath = await client.storage
            .from(bucketName)
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true, // Replace if exists
              ),
            );
        
        debugPrint('Upload successful! Uploaded path: $uploadedPath');
      } catch (uploadError) {
        debugPrint('Upload failed with error: $uploadError');
        // Check if it's a duplicate file error (which is ok with upsert: true)
        if (uploadError.toString().contains('duplicate') || 
            uploadError.toString().contains('already exists')) {
          debugPrint('File already exists, continuing...');
          uploadedPath = fileName;
        } else {
          rethrow;
        }
      }

      // Get public URL
      final publicUrl = client.storage
          .from(bucketName)
          .getPublicUrl(uploadedPath);

      debugPrint('Public URL: $publicUrl');
      debugPrint('=== Upload Complete ===');

      return publicUrl;
    } catch (e, stackTrace) {
      debugPrint('=== Supabase GCash Receipt Upload Error ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('===========================================');
      
      // Provide more detailed error message
      String errorMessage = 'Failed to upload GCash receipt to Supabase';
      if (e.toString().contains('bucket')) {
        errorMessage = 'Supabase bucket "gcash_receipt" not found or not accessible. Please check your Supabase configuration.';
      } else if (e.toString().contains('permission') || e.toString().contains('policy')) {
        errorMessage = 'Permission denied. Please check Supabase storage policies for bucket "gcash_receipt".';
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and Supabase URL.';
      } else {
        errorMessage = 'Failed to upload GCash receipt: ${e.toString()}';
      }
      
      throw Exception(errorMessage);
    }
  }

  /// Upload chat media (image or video) to Supabase customerconvo_uploads bucket
  /// Returns the public URL of the uploaded file
  static Future<String> uploadChatMedia(File mediaFile, String fileName) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      const bucketName = 'customerconvo_uploads';

      debugPrint('=== Supabase Chat Media Upload Debug ===');
      debugPrint('File path: ${mediaFile.path}');
      debugPrint('File exists: ${await mediaFile.exists()}');
      debugPrint('File name: $fileName');
      debugPrint('Bucket name: $bucketName');

      // Check if file exists
      if (!await mediaFile.exists()) {
        throw Exception('File does not exist: ${mediaFile.path}');
      }

      // Read file bytes
      final fileBytes = await mediaFile.readAsBytes();
      debugPrint('File size: ${fileBytes.length} bytes');

      if (fileBytes.isEmpty) {
        throw Exception('File is empty: ${mediaFile.path}');
      }

      // Detect content type from file extension
      String contentType = 'image/jpeg';
      final extension = fileName.toLowerCase().split('.').last;
      if (extension == 'png') {
        contentType = 'image/png';
      } else if (extension == 'jpg' || extension == 'jpeg') {
        contentType = 'image/jpeg';
      } else if (extension == 'webp') {
        contentType = 'image/webp';
      } else if (extension == 'mp4') {
        contentType = 'video/mp4';
      } else if (extension == 'mov') {
        contentType = 'video/quicktime';
      } else if (extension == 'avi') {
        contentType = 'video/x-msvideo';
      } else if (extension == 'webm') {
        contentType = 'video/webm';
      }

      debugPrint('Content type: $contentType');

      // Upload to Supabase Storage using uploadBinary
      debugPrint('Starting upload to Supabase...');
      String uploadedPath;
      
      try {
        uploadedPath = await client.storage
            .from(bucketName)
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true, // Replace if exists
              ),
            );
        
        debugPrint('Upload successful! Uploaded path: $uploadedPath');
      } catch (uploadError) {
        debugPrint('Upload failed with error: $uploadError');
        // Check if it's a duplicate file error (which is ok with upsert: true)
        if (uploadError.toString().contains('duplicate') || 
            uploadError.toString().contains('already exists')) {
          debugPrint('File already exists, continuing...');
          uploadedPath = fileName;
        } else {
          rethrow;
        }
      }

      // Get public URL
      final publicUrl = client.storage
          .from(bucketName)
          .getPublicUrl(uploadedPath);

      debugPrint('Public URL: $publicUrl');
      debugPrint('=== Chat Media Upload Complete ===');

      return publicUrl;
    } catch (e, stackTrace) {
      debugPrint('=== Supabase Chat Media Upload Error ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('========================================');
      
      // Provide more detailed error message
      String errorMessage = 'Failed to upload chat media to Supabase';
      if (e.toString().contains('bucket')) {
        errorMessage = 'Supabase bucket "customerconvo_uploads" not found or not accessible. Please check your Supabase configuration.';
      } else if (e.toString().contains('permission') || e.toString().contains('policy')) {
        errorMessage = 'Permission denied. Please check Supabase storage policies for bucket "customerconvo_uploads".';
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and Supabase URL.';
      } else {
        errorMessage = 'Failed to upload chat media: ${e.toString()}';
      }
      
      throw Exception(errorMessage);
    }
  }

  /// Upload customer profile picture to Supabase customer_profile bucket
  /// Returns the public URL of the uploaded image
  static Future<String> uploadProfilePicture(File imageFile, String fileName) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      const bucketName = 'customer_profile';

      debugPrint('=== Supabase Profile Picture Upload Debug ===');
      debugPrint('File path: ${imageFile.path}');
      debugPrint('File exists: ${await imageFile.exists()}');
      debugPrint('File name: $fileName');
      debugPrint('Bucket name: $bucketName');

      // Check if file exists
      if (!await imageFile.exists()) {
        throw Exception('File does not exist: ${imageFile.path}');
      }

      // Read file bytes
      final fileBytes = await imageFile.readAsBytes();
      debugPrint('File size: ${fileBytes.length} bytes');

      if (fileBytes.isEmpty) {
        throw Exception('File is empty: ${imageFile.path}');
      }

      // Detect content type from file extension
      String contentType = 'image/jpeg';
      final extension = fileName.toLowerCase().split('.').last;
      if (extension == 'png') {
        contentType = 'image/png';
      } else if (extension == 'jpg' || extension == 'jpeg') {
        contentType = 'image/jpeg';
      } else if (extension == 'webp') {
        contentType = 'image/webp';
      }

      debugPrint('Content type: $contentType');

      // Upload to Supabase Storage using uploadBinary
      debugPrint('Starting upload to Supabase...');
      String uploadedPath;
      
      try {
        uploadedPath = await client.storage
            .from(bucketName)
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true, // Replace if exists
              ),
            );
        
        debugPrint('Upload successful! Uploaded path: $uploadedPath');
      } catch (uploadError) {
        debugPrint('Upload failed with error: $uploadError');
        // Check if it's a duplicate file error (which is ok with upsert: true)
        if (uploadError.toString().contains('duplicate') || 
            uploadError.toString().contains('already exists')) {
          debugPrint('File already exists, continuing...');
          uploadedPath = fileName;
        } else {
          rethrow;
        }
      }

      // Get public URL
      final publicUrl = client.storage
          .from(bucketName)
          .getPublicUrl(uploadedPath);

      debugPrint('Uploaded path: $uploadedPath');
      debugPrint('Public URL: $publicUrl');
      debugPrint('=== Profile Picture Upload Complete ===');

      return publicUrl;
    } catch (e, stackTrace) {
      debugPrint('=== Supabase Profile Picture Upload Error ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('============================================');
      
      // Provide more detailed error message
      String errorMessage = 'Failed to upload profile picture to Supabase';
      if (e.toString().contains('bucket')) {
        errorMessage = 'Supabase bucket "customer_profile" not found or not accessible. Please check your Supabase configuration.';
      } else if (e.toString().contains('permission') || e.toString().contains('policy')) {
        errorMessage = 'Permission denied. Please check Supabase storage policies for bucket "customer_profile".';
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and Supabase URL.';
      } else {
        errorMessage = 'Failed to upload profile picture: ${e.toString()}';
      }
      
      throw Exception(errorMessage);
    }
  }

  /// Delete customer profile picture from Supabase customer_profile bucket
  static Future<void> deleteProfilePicture(String fileName) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      const bucketName = 'customer_profile';

      debugPrint('=== Deleting Profile Picture ===');
      debugPrint('Bucket: $bucketName');
      debugPrint('File name: $fileName');
      
      // Remove the file
      final result = await client.storage
          .from(bucketName)
          .remove([fileName]);
      
      debugPrint('Delete result: $result');
      debugPrint('✅ Profile picture deleted successfully: $fileName');
    } catch (e, stackTrace) {
      debugPrint('❌ Error deleting profile picture: $e');
      debugPrint('Stack trace: $stackTrace');
      // Re-throw so the caller knows deletion failed
      // The caller will handle it gracefully
      rethrow;
    }
  }

  /// Check if customer exists by username, email, or phone in Supabase
  static Future<Map<String, bool>> checkCustomerExists({
    String? username,
    String? email,
    String? phone,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      final results = <String, bool>{
        'username': false,
        'email': false,
        'phone': false,
      };

      // Check username
      if (username != null && username.isNotEmpty) {
        try {
          final data = await client
              .from('customers')
              .select('uid')
              .eq('username', username)
              .maybeSingle() as Map<String, dynamic>?;
          results['username'] = data != null;
        } catch (e) {
          debugPrint('Error checking username: $e');
        }
      }

      // Check email
      if (email != null && email.isNotEmpty) {
        try {
          final data = await client
              .from('customers')
              .select('uid')
              .eq('email', email.toLowerCase())
              .maybeSingle() as Map<String, dynamic>?;
          results['email'] = data != null;
        } catch (e) {
          debugPrint('Error checking email: $e');
        }
      }

      // Check phone
      if (phone != null && phone.isNotEmpty) {
        try {
          final data = await client
              .from('customers')
              .select('uid')
              .eq('phone_number', phone)
              .maybeSingle() as Map<String, dynamic>?;
          results['phone'] = data != null;
        } catch (e) {
          debugPrint('Error checking phone: $e');
        }
      }

      return results;
    } catch (e) {
      debugPrint('Error checking customer existence: $e');
      return {
        'username': false,
        'email': false,
        'phone': false,
      };
    }
  }

  /// Check if phone number is available across all tables (customers, staff, admins, riders)
  /// Returns true if available, false if taken
  /// Excludes the current customer's phone number if excludeCustomerId is provided
  static Future<bool> checkPhoneAvailabilityComprehensive(
    String phone, {
    String? excludeCustomerId,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      if (phone.isEmpty) {
        return false;
      }

      // Check customers (column: phone_number)
      try {
        var query = client
            .from('customers')
            .select('uid')
            .eq('phone_number', phone);
        
        // Exclude current customer if provided
        if (excludeCustomerId != null && excludeCustomerId.isNotEmpty) {
          query = query.not('uid', 'eq', excludeCustomerId);
        }
        
        final data = await query.limit(1).maybeSingle() as Map<String, dynamic>?;
        if (data != null) {
          debugPrint('Phone number found in customers table');
          return false;
        }
      } catch (e) {
        debugPrint('Error checking phone in customers: $e');
      }

      // Check staff (column: phone)
      try {
        final data = await client
            .from('staff')
            .select('uuid')
            .eq('phone', phone)
            .limit(1)
            .maybeSingle() as Map<String, dynamic>?;
        if (data != null) {
          debugPrint('Phone number found in staff table');
          return false;
        }
      } catch (e) {
        debugPrint('Error checking phone in staff: $e');
      }

      // Check admins (column: phone)
      try {
        final data = await client
            .from('admins')
            .select('uuid')
            .eq('phone', phone)
            .limit(1)
            .maybeSingle() as Map<String, dynamic>?;
        if (data != null) {
          debugPrint('Phone number found in admins table');
          return false;
        }
      } catch (e) {
        debugPrint('Error checking phone in admins: $e');
      }

      // Check riders (column: phone_number)
      try {
        final data = await client
            .from('riders')
            .select('uid')
            .eq('phone_number', phone)
            .limit(1)
            .maybeSingle() as Map<String, dynamic>?;
        if (data != null) {
          debugPrint('Phone number found in riders table');
          return false;
        }
      } catch (e) {
        debugPrint('Error checking phone in riders: $e');
      }

      debugPrint('Phone number is available');
      return true;
    } catch (e) {
      debugPrint('❌ Error checking phone availability comprehensively: $e');
      return false;
    }
  }

  /// Save customer data to Supabase customers table
  /// Converts Firebase format (camelCase) to Supabase format (snake_case)
  static Future<void> saveCustomer(Map<String, dynamic> customerData) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Convert camelCase to snake_case for Supabase
      final supabaseData = <String, dynamic>{
        'uid': customerData['uid'],
        'email': customerData['email'] ?? '',
        'full_name': customerData['fullName'] ?? '',
        'first_name': customerData['firstName'] ?? '',
        'last_name': customerData['lastName'] ?? '',
        'middle_initial': customerData['middleInitial'] ?? '',
        'suffix': customerData['suffix'] ?? '',
        'username': customerData['username'] ?? '',
        'age': customerData['age'] ?? 0,
        'birthday': customerData['birthday'],
        'gender': customerData['gender'] ?? '',
        'phone_number': customerData['phoneNumber'] ?? '',
        'address': customerData['address'] ?? '',
        'street': customerData['street'] ?? '',
        'sitio': customerData['sitio'] ?? '',
        'barangay': customerData['barangay'] ?? '',
        'city': customerData['city'] ?? 'Ormoc',
        'state': customerData['state'] ?? 'Leyte',
        'zip_code': customerData['zipCode'] ?? '',
        'profile_image_url': customerData['profileImageUrl'] ?? '',
        'created_at': customerData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'updated_at': customerData['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'is_online': customerData['isOnline'] ?? false,
        'last_seen': customerData['lastSeen'],
        'status': customerData['status'] ?? 'active',
        'account_status': customerData['accountStatus'] ?? 'pending',
        'verification_status': customerData['verificationStatus'] ?? 'pending',
        'rejection_reason': customerData['rejectionReason'],
        'id_type': customerData['idType'] ?? 'Not specified',
        'verification_date': customerData['verificationDate'],
        'verified_by': customerData['verifiedBy'],
        'verified_by_name': customerData['verifiedByName'],
        'verified_by_role': customerData['verifiedByRole'],
        'rejected_at': customerData['rejectedAt'],
        'rejected_by': customerData['rejectedBy'],
        'rejected_by_name': customerData['rejectedByName'],
        'rejected_by_role': customerData['rejectedByRole'],
        'fcm_token': customerData['fcmToken'],
        'password': customerData['password'], // Hashed password
        'favorite_products': customerData['favoriteProducts'] ?? [],
        'total_orders': customerData['totalOrders'] ?? 0,
        'total_spent': customerData['totalSpent'] ?? 0.0,
        'has_logged_in_before': customerData['hasLoggedInBefore'] ?? false,
        'id_front_photo': customerData['idFrontPhoto'],
        'id_back_photo': customerData['idBackPhoto'],
        'registration_date': customerData['registrationDate'] ?? customerData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      };

      // Remove null values
      supabaseData.removeWhere((key, value) => value == null);

      try {
        await client
            .from('customers')
            .upsert([supabaseData], onConflict: 'uid');
        debugPrint('✅ Customer saved to Supabase successfully');
      } catch (e) {
        // If upsert throws an error, it means the operation failed
        throw Exception('Failed to save customer to Supabase: $e');
      }
    } catch (e) {
      debugPrint('❌ Error saving customer to Supabase: $e');
      rethrow;
    }
  }

  /// Load customer data from Supabase by UID
  /// Converts Supabase format (snake_case) to Firebase format (camelCase)
  static Future<Map<String, dynamic>?> loadCustomer(String uid) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      final data = await client
          .from('customers')
          .select('*')
          .eq('uid', uid)
          .single() as Map<String, dynamic>;
      
      // Convert snake_case to camelCase for compatibility
      return {
        'uid': data['uid'],
        'email': data['email'] ?? '',
        'fullName': data['full_name'] ?? '',
        'firstName': data['first_name'] ?? '',
        'lastName': data['last_name'] ?? '',
        'middleInitial': data['middle_initial'] ?? '',
        'suffix': data['suffix'] ?? '',
        'username': data['username'] ?? '',
        'age': data['age'] ?? 0,
        'birthday': data['birthday'] != null 
            ? (data['birthday'] is String 
                ? data['birthday']  // Keep as YYYY-MM-DD string format for Supabase DATE type
                : (data['birthday'] is int 
                    ? DateTime.fromMillisecondsSinceEpoch(data['birthday']).toIso8601String().split('T')[0]
                    : data['birthday']))
            : null,
        'gender': data['gender'] ?? '',
        'phoneNumber': data['phone_number'] ?? '',
        'address': data['address'] ?? '',
        'street': data['street'] ?? '',
        'sitio': data['sitio'] ?? '',
        'barangay': data['barangay'] ?? '',
        'city': data['city'] ?? 'Ormoc',
        'state': data['state'] ?? 'Leyte',
        'zipCode': data['zip_code'] ?? '',
        'profileImageUrl': data['profile_image_url'] ?? '',
        'createdAt': data['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
        'updatedAt': data['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
        'isOnline': data['is_online'] ?? false,
        'lastSeen': data['last_seen'],
        'status': data['status'] ?? 'active',
        'accountStatus': data['account_status'] ?? 'pending',
        'verificationStatus': data['verification_status'] ?? 'pending',
        'rejectionReason': data['rejection_reason'],
        'idType': data['id_type'] ?? 'Not specified',
        'verificationDate': data['verification_date'],
        'verifiedBy': data['verified_by'],
        'favoriteProducts': data['favorite_products'] ?? [],
        'totalOrders': data['total_orders'] ?? 0,
        'totalSpent': (data['total_spent'] ?? 0.0).toDouble(),
        'hasLoggedInBefore': data['has_logged_in_before'] ?? false,
        'idFrontPhoto': data['id_front_photo'],
        'idBackPhoto': data['id_back_photo'],
        'registrationDate': data['registration_date'] ?? data['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      // Check if it's a "no rows" error (account doesn't exist)
      if (e.toString().contains('PGRST116') || e.toString().contains('No rows')) {
        return null;
      }
      
      // Check if it's a network-related error - rethrow it instead of returning null
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
        debugPrint('🔌 Network error loading customer from Supabase - rethrowing: $e');
        rethrow; // Rethrow network errors so they can be handled properly
      }
      
      // For other errors, log and return null (might be account not found or other issues)
      debugPrint('❌ Error loading customer from Supabase: $e');
      return null;
    }
  }

  /// Update customer data in Supabase
  static Future<void> updateCustomer(String uid, Map<String, dynamic> updates) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Convert camelCase to snake_case
      final supabaseUpdates = <String, dynamic>{};
      final fieldMapping = {
        'accountStatus': 'account_status',
        'verificationStatus': 'verification_status',
        'rejectionReason': 'rejection_reason',
        'idType': 'id_type',
        'verificationDate': 'verification_date',
        'verifiedBy': 'verified_by',
        'favoriteProducts': 'favorite_products',
        'totalOrders': 'total_orders',
        'totalSpent': 'total_spent',
        'hasLoggedInBefore': 'has_logged_in_before',
        'idFrontPhoto': 'id_front_photo',
        'idBackPhoto': 'id_back_photo',
        'registrationDate': 'registration_date',
        'fullName': 'full_name',
        'firstName': 'first_name',
        'lastName': 'last_name',
        'middleInitial': 'middle_initial',
        'phoneNumber': 'phone_number',
        'zipCode': 'zip_code',
        'profileImageUrl': 'profile_image_url',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'customerLastUpdatedAt': 'customer_last_updated_at',
        'isOnline': 'is_online',
        'lastSeen': 'last_seen',
      };

      updates.forEach((key, value) {
        final snakeKey = fieldMapping[key] ?? key.replaceAllMapped(
          RegExp(r'([A-Z])'),
          (match) => '_${match.group(1)!.toLowerCase()}',
        );
        supabaseUpdates[snakeKey] = value;
      });

      // Always update updated_at
      supabaseUpdates['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      
      // Check if this is a customer-initiated profile update (not admin/staff update)
      // Customer-initiated updates include: phone_number, address, street, sitio, barangay, city, state, zip_code, profile_image_url
      final customerProfileFields = ['phone_number', 'address', 'street', 'sitio', 'barangay', 'city', 'state', 'zip_code', 'profile_image_url'];
      final isCustomerProfileUpdate = supabaseUpdates.keys.any((key) => customerProfileFields.contains(key));
      
      if (isCustomerProfileUpdate) {
        // Set customer_last_updated_at when customer updates their own profile
        supabaseUpdates['customer_last_updated_at'] = DateTime.now().millisecondsSinceEpoch;
      }

      try {
        await client
            .from('customers')
            .update(supabaseUpdates)
            .eq('uid', uid);
        debugPrint('✅ Customer updated in Supabase successfully');
      } catch (e) {
        // If update throws an error, it means the operation failed
        throw Exception('Failed to update customer in Supabase: $e');
      }
    } catch (e) {
      debugPrint('❌ Error updating customer in Supabase: $e');
      rethrow;
    }
  }

  /// Load delivery addresses from Supabase for a customer
  static Future<List<Map<String, dynamic>>> loadDeliveryAddresses(String customerId) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      final response = await client
          .from('delivery_addresses')
          .select('*')
          .eq('customer_id', customerId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      if (response is List) {
        return response.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      }
      
      return [];
    } catch (e) {
      debugPrint('❌ Error loading delivery addresses from Supabase: $e');
      return [];
    }
  }

  /// Save delivery address to Supabase delivery_addresses table
  static Future<void> saveDeliveryAddress(Map<String, dynamic> addressData) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Convert camelCase to snake_case for Supabase
      final supabaseData = <String, dynamic>{
        'customer_id': addressData['customerId'],
        'address': addressData['address'] ?? '',
        'label': addressData['label'] ?? 'Address',
        'phone_number': addressData['phoneNumber'],
        'is_default': addressData['isDefault'] ?? false,
        'created_at': addressData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'updated_at': addressData['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      };

      // Remove null phone_number if it's null
      if (supabaseData['phone_number'] == null) {
        supabaseData.remove('phone_number');
      }

      // If this is set as default, unset other defaults for this customer
      if (supabaseData['is_default'] == true) {
        try {
          await client
              .from('delivery_addresses')
              .update({'is_default': false})
              .eq('customer_id', supabaseData['customer_id'])
              .eq('is_default', true);
        } catch (e) {
          debugPrint('Warning: Failed to unset other defaults: $e');
          // Continue anyway
        }
      }

      // Insert the new delivery address
      await client
          .from('delivery_addresses')
          .insert([supabaseData]);
      
      debugPrint('✅ Delivery address saved to Supabase successfully');
    } catch (e) {
      debugPrint('❌ Error saving delivery address to Supabase: $e');
      rethrow;
    }
  }

  /// Update delivery address in Supabase
  static Future<void> updateDeliveryAddress({
    required String addressId,
    required Map<String, dynamic> addressData,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      // Convert camelCase to snake_case for Supabase
      final supabaseData = <String, dynamic>{
        'address': addressData['address'] ?? '',
        'label': addressData['label'] ?? 'Address',
        'phone_number': addressData['phoneNumber'],
        'is_default': addressData['isDefault'] ?? false,
        'updated_at': addressData['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      };

      // Remove null phone_number if it's null
      if (supabaseData['phone_number'] == null) {
        supabaseData.remove('phone_number');
      }

      // If this is set as default, unset other defaults for this customer
      if (supabaseData['is_default'] == true) {
        try {
          final customerId = addressData['customerId'];
          await client
              .from('delivery_addresses')
              .update({'is_default': false})
              .eq('customer_id', customerId)
              .eq('is_default', true)
              .neq('id', addressId); // Don't unset the one we're updating
        } catch (e) {
          debugPrint('Warning: Failed to unset other defaults: $e');
          // Continue anyway
        }
      }

      // Update the delivery address
      await client
          .from('delivery_addresses')
          .update(supabaseData)
          .eq('id', addressId);
      
      debugPrint('✅ Delivery address updated in Supabase successfully');
    } catch (e) {
      debugPrint('❌ Error updating delivery address in Supabase: $e');
      rethrow;
    }
  }

  /// Delete delivery address from Supabase
  static Future<void> deleteDeliveryAddress(String addressId) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      await client
          .from('delivery_addresses')
          .delete()
          .eq('id', addressId);
      
      debugPrint('✅ Delivery address deleted from Supabase successfully');
    } catch (e) {
      debugPrint('❌ Error deleting delivery address from Supabase: $e');
      rethrow;
    }
  }
}

