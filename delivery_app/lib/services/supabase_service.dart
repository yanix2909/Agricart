import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Supabase credentials - same as customer_app
  static const String _supabaseUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFma3dleHZ2dXh3YnBpb3FuZWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5MzA3MjcsImV4cCI6MjA3ODUwNjcyN30.7r5j1xfWdJwiRZZm8AcOIaBp9VaXoD2QWE3WrGYZNyM';

  static bool _initialized = false;

  /// Check if Supabase is initialized
  static bool get isInitialized => _initialized;

  /// Initialize Supabase client
  /// Call this once at app startup (in main.dart)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );
      _initialized = true;
      debugPrint('✅ Supabase initialized successfully');
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

  static Future<String> uploadRiderProfilePicture(File imageFile, String fileName) async {
    return _uploadFileToBucket(
      imageFile: imageFile,
      fileName: fileName,
      bucketName: 'rider_profile',
    );
  }

  /// Upload delivery proof image to Supabase Storage
  /// Returns the public URL of the uploaded image
  static Future<String> uploadDeliveryProofImage(File imageFile, String fileName) async {
    return _uploadFileToBucket(
      imageFile: imageFile,
      fileName: fileName,
      bucketName: 'delivery_proof',
    );
  }

  /// Upload payment proof image to Supabase Storage
  /// Returns the public URL of the uploaded image
  static Future<String> uploadPaymentProofImage(File imageFile, String fileName) async {
    return _uploadFileToBucket(
      imageFile: imageFile,
      fileName: fileName,
      bucketName: 'delivery_proof_payment',
    );
  }

  static Future<void> deleteRiderProfilePicture(String storagePath) async {
    try {
      if (!_initialized) {
        await initialize();
      }
      await client.storage.from('rider_profile').remove([storagePath]);
    } catch (e) {
      debugPrint('Failed to delete rider profile picture: $e');
    }
  }

  static Future<String> _uploadFileToBucket({
    required File imageFile,
    required String fileName,
    required String bucketName,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      if (!await imageFile.exists()) {
        throw Exception('File does not exist: ${imageFile.path}');
      }

      final fileBytes = await imageFile.readAsBytes();
      if (fileBytes.isEmpty) {
        throw Exception('File is empty: ${imageFile.path}');
      }

      final contentType = _contentTypeForExtension(fileName.split('.').last);

      try {
        await client.storage
            .from(bucketName)
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true,
              ),
            );
      } catch (e) {
        if (!e.toString().contains('duplicate')) {
          rethrow;
        }
      }

      // Use fileName directly - uploadBinary returns full path but getPublicUrl adds bucket path again
      return client.storage.from(bucketName).getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Failed to upload file to $bucketName: $e');
      rethrow;
    }
  }

  static String _contentTypeForExtension(String extension) {
    final ext = extension.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

