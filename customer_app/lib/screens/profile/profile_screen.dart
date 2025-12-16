import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/settings_provider.dart';
import '../auth/login_screen.dart';
import '../../utils/theme.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../services/supabase_service.dart';
import '../../models/customer.dart';
import '../../utils/responsive.dart';

class ProfileScreen extends StatefulWidget {
  final bool showAppBar;
  const ProfileScreen({super.key, this.showAppBar = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingProfilePicture = false;

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Fix profile image URL to ensure it's properly formatted for Supabase
  String _fixProfileImageUrl(String url) {
    String fixedUrl = url.trim();
    
    // Remove duplicate bucket names
    fixedUrl = fixedUrl.replaceAll('/customer_profile/customer_profile/', '/customer_profile/');
    
    // If URL doesn't start with http, it might be a path - construct full URL
    if (!fixedUrl.startsWith('http://') && !fixedUrl.startsWith('https://')) {
      // It's a file path, construct Supabase URL
      String cleanPath = fixedUrl.replaceFirst(RegExp(r'^/+'), '');
      // Remove bucket name if present (handle multiple occurrences)
      while (cleanPath.startsWith('customer_profile/')) {
        cleanPath = cleanPath.substring('customer_profile/'.length).replaceFirst(RegExp(r'^/+'), '');
      }
      fixedUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co/storage/v1/object/public/customer_profile/$cleanPath';
    }
    
    return fixedUrl;
  }

  /// Extract filename from Supabase storage URL
  /// Example: https://...supabase.co/storage/v1/object/public/customer_profile/profile_123.jpg
  /// Returns: profile_123.jpg (without bucket name prefix)
  String _extractFileNameFromUrl(String url) {
    try {
      if (url.isEmpty) {
        debugPrint('URL is empty');
        return '';
      }
      
      debugPrint('Extracting filename from URL: $url');
      
      String extractedPath = '';
      
      // Method 1: Use regex to extract everything after /customer_profile/
      // This handles URLs like: https://...supabase.co/storage/v1/object/public/customer_profile/profile_123.jpg
      final regexPattern = RegExp(r'/customer_profile/(.+?)(?:\?|$)');
      final regexMatch = regexPattern.firstMatch(url);
      if (regexMatch != null) {
        extractedPath = regexMatch.group(1) ?? '';
        if (extractedPath.isNotEmpty) {
          debugPrint('Extracted path (regex method): $extractedPath');
        }
      }
      
      // Method 2: Parse URI and find customer_profile in path segments
      if (extractedPath.isEmpty) {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        debugPrint('Path segments: $pathSegments');
        
        final bucketIndex = pathSegments.indexOf('customer_profile');
        debugPrint('Bucket index: $bucketIndex');
        
        if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
          // Get the filename after the bucket name
          extractedPath = pathSegments.sublist(bucketIndex + 1).join('/');
          debugPrint('Extracted path (path segments method): $extractedPath');
        }
      }
      
      // Method 3: Simple string extraction
      if (extractedPath.isEmpty) {
        final customerProfileIndex = url.indexOf('/customer_profile/');
        if (customerProfileIndex != -1) {
          final afterBucket = url.substring(customerProfileIndex + '/customer_profile/'.length);
          // Remove query parameters if any
          final queryIndex = afterBucket.indexOf('?');
          extractedPath = queryIndex != -1 ? afterBucket.substring(0, queryIndex) : afterBucket;
          if (extractedPath.isNotEmpty) {
            debugPrint('Extracted path (string method): $extractedPath');
          }
        }
      }
      
      // Fallback: try to extract from the end of the path
      if (extractedPath.isEmpty) {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          extractedPath = pathSegments.last;
          debugPrint('Extracted path (fallback): $extractedPath');
        }
      }
      
      if (extractedPath.isEmpty) {
        debugPrint('❌ Could not extract filename from URL');
        return '';
      }
      
      // IMPORTANT: Remove bucket name prefix if it exists
      // The remove() method expects only the file path relative to the bucket
      // So if we have "customer_profile/profile_123.jpg", we need just "profile_123.jpg"
      String cleanFileName = extractedPath;
      if (cleanFileName.startsWith('customer_profile/')) {
        cleanFileName = cleanFileName.substring('customer_profile/'.length);
        debugPrint('Removed bucket prefix, clean filename: $cleanFileName');
      }
      
      // Also remove any leading slashes
      cleanFileName = cleanFileName.replaceFirst(RegExp(r'^/+'), '');
      
      debugPrint('✅ Final extracted filename: $cleanFileName');
      return cleanFileName;
    } catch (e, stackTrace) {
      debugPrint('❌ Error extracting filename from URL: $e');
      debugPrint('Stack trace: $stackTrace');
      return '';
    }
  }

  /// Show image cropper with square crop (will be displayed as circle in UI)
  Future<File?> _showImageCropper(File imageFile) async {
    try {
      // Verify file exists and is readable
      if (!await imageFile.exists()) {
        debugPrint('Image file does not exist: ${imageFile.path}');
        return null;
      }
      
      debugPrint('Starting image crop for: ${imageFile.path}');
      
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1), // Square crop for circular profile
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust Profile Picture',
            toolbarColor: AppTheme.primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
            showCropGrid: true,
            cropFrameColor: AppTheme.primaryColor,
            cropFrameStrokeWidth: 2,
            activeControlsWidgetColor: AppTheme.primaryColor,
          ),
          IOSUiSettings(
            title: 'Adjust Profile Picture',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            hidesNavigationBar: false,
          ),
        ],
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
      );

      if (croppedFile != null) {
        final file = File(croppedFile.path);
        debugPrint('Image cropped successfully: ${file.path}');
        
        // Verify cropped file exists
        if (await file.exists()) {
          return file;
        } else {
          debugPrint('Cropped file does not exist: ${file.path}');
          return null;
        }
      }
      debugPrint('User cancelled image cropping');
      return null;
    } catch (e, stackTrace) {
      debugPrint('Error cropping image: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cropping image. Please try again.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  /// Show preview dialog with the cropped image before uploading
  Future<bool> _showImagePreviewDialog(File croppedFile) async {
    try {
      // Verify file exists before showing preview
      if (!await croppedFile.exists()) {
        debugPrint('Cropped file does not exist for preview: ${croppedFile.path}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preview image not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
      
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
          ),
          child: Container(
            padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preview Profile Picture',
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                ClipOval(
                  child: Image.file(
                    croppedFile,
                    width: Responsive.getWidth(context, mobile: 200),
                    height: Responsive.getHeight(context, mobile: 200),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Error loading preview image: $error');
                      return Container(
                        width: Responsive.getWidth(context, mobile: 200),
                        height: Responsive.getHeight(context, mobile: 200),
                        color: Colors.grey[300],
                        child: Icon(Icons.error, size: Responsive.getIconSize(context, mobile: 50)),
                      );
                    },
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                Text(
                  'Does this look good?',
                  style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 20)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Upload'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ?? false;
    } catch (e, stackTrace) {
      debugPrint('Error showing preview dialog: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }
  
  Future<void> _changeProfilePicture() async {
    try {
      // Show options: Camera or Gallery
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change Profile Picture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      
      if (source == null) return;
      
      XFile? image;
      try {
        image = await _imagePicker.pickImage(
          source: source,
          imageQuality: 100, // Use high quality for cropping
        );
      } catch (e) {
        debugPrint('Error picking image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error accessing image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      if (image != null) {
        // Verify file exists before cropping
        final imageFile = File(image.path);
        if (!await imageFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image file not found'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        // Show image cropping screen
        File? croppedFile;
        try {
          croppedFile = await _showImageCropper(imageFile);
        } catch (e) {
          debugPrint('Error in image cropper: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error cropping image: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        if (croppedFile == null) {
          // User cancelled cropping
          return;
        }
        
        // Verify cropped file exists
        if (!await croppedFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cropped image file not found'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        // Show preview and upload confirmation dialog
        bool? shouldUpload;
        try {
          shouldUpload = await _showImagePreviewDialog(croppedFile);
        } catch (e) {
          debugPrint('Error showing preview dialog: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error showing preview: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        if (shouldUpload != true) {
          // User cancelled upload
          return;
        }
        
        setState(() {
          _isUploadingProfilePicture = true;
        });
        
        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading profile picture...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        // Upload to Supabase
        try {
          await SupabaseService.initialize();
          
          // Get the old profile image URL before uploading new one
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final customer = authProvider.currentCustomer;
          final oldProfileImageUrl = customer?.profileImageUrl ?? '';
          
          // Generate unique filename with customer UID to ensure uniqueness across all customers
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final random = DateTime.now().microsecondsSinceEpoch % 10000;
          final extension = path.extension(croppedFile.path);
          final customerId = customer?.uid ?? 'unknown';
          // Include customer UID in filename to ensure uniqueness across all customers
          final fileName = 'profile_${customerId}_${timestamp}_$random$extension';
          
          // Upload to Supabase customer_profile bucket
          final url = await SupabaseService.uploadProfilePicture(croppedFile, fileName);
          
          // Update customer profile in Firebase
          if (customer != null) {
            final updatedCustomer = customer.copyWith(
              profileImageUrl: url,
              updatedAt: DateTime.now(),
            );
            
            await authProvider.updateCustomerProfile(updatedCustomer);
            
            // Delete old profile picture from Supabase if it exists and is different
            if (oldProfileImageUrl.isNotEmpty && oldProfileImageUrl != url) {
              try {
                debugPrint('=== Attempting to delete old profile picture ===');
                debugPrint('Old URL: $oldProfileImageUrl');
                debugPrint('New URL: $url');
                
                // Extract filename from the old URL
                final oldFileName = _extractFileNameFromUrl(oldProfileImageUrl);
                debugPrint('Extracted filename: $oldFileName');
                
                if (oldFileName.isNotEmpty) {
                  debugPrint('Calling deleteProfilePicture with: $oldFileName');
                  await SupabaseService.deleteProfilePicture(oldFileName);
                  debugPrint('✅ Old profile picture deleted successfully: $oldFileName');
                } else {
                  debugPrint('⚠️ Could not extract filename from URL: $oldProfileImageUrl');
                }
              } catch (e, stackTrace) {
                // Don't fail the upload if deletion fails, but log the error
                debugPrint('❌ Error deleting old profile picture: $e');
                debugPrint('Stack trace: $stackTrace');
              }
            } else {
              debugPrint('Skipping deletion - old URL: ${oldProfileImageUrl.isEmpty ? "empty" : oldProfileImageUrl}, new URL: $url');
            }
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Profile picture updated successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Error uploading profile picture: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error uploading profile picture: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _isUploadingProfilePicture = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isUploadingProfilePicture = false;
        });
      }
    }
  }

  void _showEditDialog(BuildContext context, String field, String currentValue, Function(String) onSave) {
    final controller = TextEditingController(text: currentValue);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $field'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: field,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newValue = controller.text.trim();
              if (newValue.isNotEmpty) {
                onSave(newValue);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showNameEditDialog(BuildContext context, customer) {
    final firstNameController = TextEditingController(text: customer.firstName);
    final lastNameController = TextEditingController(text: customer.lastName);
    final middleInitialController = TextEditingController(text: customer.middleInitial);
    final suffixController = TextEditingController(text: customer.suffix);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              TextField(
                controller: lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              TextField(
                controller: middleInitialController,
                decoration: const InputDecoration(
                  labelText: 'Middle Initial',
                  border: OutlineInputBorder(),
                  hintText: 'Optional',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              TextField(
                controller: suffixController,
                decoration: const InputDecoration(
                  labelText: 'Suffix (Optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Jr., Sr., III',
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final firstName = firstNameController.text.trim();
              final lastName = lastNameController.text.trim();
              final middleInitial = middleInitialController.text.trim();
              final suffix = suffixController.text.trim();
              
              if (firstName.isNotEmpty && lastName.isNotEmpty) {
                try {
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  
                  // Construct full name
                  String fullName = '$firstName $lastName';
                  if (middleInitial.isNotEmpty) {
                    fullName = '$firstName $middleInitial $lastName';
                  }
                  if (suffix.isNotEmpty) {
                    fullName = '$fullName $suffix';
                  }
                  
                  final updatedCustomer = customer.copyWith(
                    fullName: fullName.trim(),
                    firstName: firstName,
                    lastName: lastName,
                    middleInitial: middleInitial,
                    suffix: suffix,
                  );
                  await authProvider.updateCustomerProfile(updatedCustomer);
                  
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name updated successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update name: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill in at least First Name and Last Name'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddressEditDialog(BuildContext context, customer) {
    final streetController = TextEditingController(text: customer.street);
    final sitioController = TextEditingController(text: customer.sitio);
    final cityController = TextEditingController(text: customer.city);
    final stateController = TextEditingController(text: customer.state);
    final zipCodeController = TextEditingController(text: customer.zipCode);
    String selectedBarangay = customer.barangay;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: streetController,
                  decoration: const InputDecoration(
                    labelText: 'Street (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Enter your street name',
                  ),
                  autofocus: true,
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextField(
                  controller: sitioController,
                  decoration: const InputDecoration(
                    labelText: 'Sitio (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Enter your sitio',
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                SearchableBarangayDropdown(
                  value: selectedBarangay.isNotEmpty ? selectedBarangay : null,
                  labelText: 'Barangay *',
                  hintText: 'Select your barangay',
                  onChanged: (value) {
                    setState(() {
                      selectedBarangay = value ?? '';
                    });
                  },
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextField(
                  controller: stateController,
                  decoration: const InputDecoration(
                    labelText: 'State',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                TextField(
                  controller: zipCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Zip Code',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newStreet = streetController.text.trim();
              final newSitio = sitioController.text.trim();
              final newCity = cityController.text.trim();
              final newState = stateController.text.trim();
              final newZipCode = zipCodeController.text.trim();
              
              if (selectedBarangay.isNotEmpty && newCity.isNotEmpty && newState.isNotEmpty && newZipCode.isNotEmpty) {
                try {
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
                  
                  // Construct complete address (sitio and street are optional)
                  final streetPart = newStreet.isNotEmpty ? '$newStreet, ' : '';
                  final sitioPart = newSitio.isNotEmpty ? '$newSitio, ' : '';
                  final completeAddress = '${streetPart}${sitioPart}$selectedBarangay, $newCity, $newState $newZipCode';
                  
                  final updatedCustomer = customer.copyWith(
                    address: completeAddress,
                    street: newStreet,
                    sitio: newSitio,
                    barangay: selectedBarangay,
                    city: newCity,
                    state: newState,
                    zipCode: newZipCode,
                  );
                  await authProvider.updateCustomerProfile(updatedCustomer);
                  
                  // Also update the Home delivery address if it exists (sync with customer profile)
                  final fullAddress = completeAddress;
                  try {
                    final homeAddress = customerProvider.deliveryAddresses.firstWhere(
                      (addr) => addr.label == 'Home',
                    );
                    if (homeAddress.label == 'Home') {
                    await customerProvider.updateDeliveryAddress(
                        addressId: homeAddress.id,
                      address: fullAddress,
                      label: 'Home',
                        phoneNumber: customer.phoneNumber.isNotEmpty ? customer.phoneNumber : null,
                      isDefault: true,
                    );
                    }
                  } catch (e) {
                    // Home address might not exist yet, that's okay
                    print('Home address not found for address sync: $e');
                  }
                  
                  // Reload delivery addresses to ensure the order review screen reflects changes
                  await customerProvider.loadDeliveryAddresses(authProvider.currentCustomer!.uid);
                  
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Address updated successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update address: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please fill in all required fields: Barangay, City, State, and Zip Code'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
    );
  }

  void _showPhoneNumberEditDialog(BuildContext context, Customer customer) {
    final phoneController = TextEditingController(text: customer.phoneNumber);
    bool isValidating = false;
    String? validationError;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Phone Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: const OutlineInputBorder(),
                  hintText: 'Enter 11-digit phone number',
                  prefixIcon: const Icon(Icons.phone),
                  errorText: validationError,
                  counterText: '',
                ),
                autofocus: true,
                onChanged: (value) {
                  // Clear error when user types
                  if (validationError != null) {
                    setState(() {
                      validationError = null;
                    });
                  }
                },
              ),
              if (isValidating)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Checking availability...',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isValidating ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isValidating ? null : () async {
                final newPhoneNumber = phoneController.text.trim();
                
                // Validate 11 digits
                if (newPhoneNumber.isEmpty) {
                  setState(() {
                    validationError = 'Phone number is required';
                  });
                  return;
                }
                
                // Remove any non-digit characters for validation
                final digitsOnly = newPhoneNumber.replaceAll(RegExp(r'[^\d]'), '');
                
                if (digitsOnly.length != 11) {
                  setState(() {
                    validationError = 'Phone number must be exactly 11 digits';
                  });
                  return;
                }
                
                // Check if phone number is the same as current (no need to check availability)
                if (digitsOnly == customer.phoneNumber.replaceAll(RegExp(r'[^\d]'), '')) {
                  // Same number, just close dialog
                  Navigator.of(context).pop();
                  return;
                }
                
                // Check availability
                setState(() {
                  isValidating = true;
                  validationError = null;
                });
                
                try {
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  final isAvailable = await authProvider.checkPhoneAvailability(
                    digitsOnly,
                    excludeCustomerId: customer.uid,
                  );
                  
                  if (!isAvailable) {
                    setState(() {
                      isValidating = false;
                      validationError = 'This phone number is already in use by another account';
                    });
                    return;
                  }
                  
                  // Phone is available, proceed with update
                  final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
                  
                  // Update customer profile phone number
                  final updatedCustomer = customer.copyWith(
                    phoneNumber: digitsOnly,
                  );
                  await authProvider.updateCustomerProfile(updatedCustomer);
                  
                  // Also update the Home delivery address phone number if it exists (sync with customer profile)
                  try {
                    final homeAddress = customerProvider.deliveryAddresses.firstWhere(
                      (addr) => addr.label == 'Home',
                    );
                    if (homeAddress != null) {
                      await customerProvider.updateDeliveryAddress(
                        addressId: homeAddress.id,
                        address: homeAddress.address,
                        label: 'Home',
                        phoneNumber: digitsOnly,
                        isDefault: homeAddress.isDefault,
                      );
                    }
                  } catch (e) {
                    // Home address might not exist yet, that's okay
                    print('Home address not found for phone sync: $e');
                  }
                  
                  // Reload delivery addresses to ensure the order review screen reflects changes
                  await customerProvider.loadDeliveryAddresses(authProvider.currentCustomer!.uid);
                  
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phone number updated successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() {
                      isValidating = false;
                      validationError = 'Failed to check availability. Please try again.';
                    });
                  }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          return AlertDialog(
            title: const Text('Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('App Settings:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                
                // Notifications Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Notifications'),
                    Switch(
                      value: settingsProvider.notificationsEnabled,
                      onChanged: (value) {
                        settingsProvider.setNotificationsEnabled(value);
                      },
                    ),
                  ],
                ),
                
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                
                // Dark Mode Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dark Mode'),
                    Switch(
                      value: settingsProvider.darkModeEnabled,
                      onChanged: (value) {
                        settingsProvider.setDarkModeEnabled(value, context: context);
                      },
                    ),
                  ],
                ),
                
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                
                // Language Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Language'),
                    Switch(
                      value: settingsProvider.languageEnglish,
                      onChanged: (value) {
                        settingsProvider.setLanguageEnglish(value);
                      },
                    ),
                  ],
                ),
                
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                Text(
                  settingsProvider.getLanguageDisplayName(),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: Responsive.getFontSize(context, mobile: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, String>>(
        future: _loadContactSupportInfo(),
        builder: (context, snapshot) {
          final email = snapshot.data?['email'] ?? 'calcoacoop@gmail.com';
          final phone = snapshot.data?['phone'] ?? '+63 123 456 7890';

          return AlertDialog(
            title: const Text('Help & Support'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need help? Contact us:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 12)),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.email_outlined,
                            size: Responsive.getIconSize(context, mobile: 18),
                            color: AppTheme.primaryColor,
                          ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: Responsive.getIconSize(context, mobile: 18),
                            color: AppTheme.primaryColor,
                          ),
                          SizedBox(width: Responsive.getWidth(context, mobile: 8)),
                          Expanded(
                            child: Text(
                              phone,
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                const Text(
                  'Common Topics:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                const Text('• How to place an order'),
                const Text('• Track your delivery'),
                const Text('• Return policy'),
                const Text('• Payment options'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Call the phone number
                  try {
                    // Clean phone number: remove all characters except digits and +
                    String cleanedPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
                    
                    // Ensure proper format for tel: URI
                    if (!cleanedPhone.startsWith('+')) {
                      // If it starts with 0, replace with +63
                      if (cleanedPhone.startsWith('0')) {
                        cleanedPhone = '+63${cleanedPhone.substring(1)}';
                      } else if (cleanedPhone.startsWith('63')) {
                        cleanedPhone = '+$cleanedPhone';
                      } else {
                        cleanedPhone = '+63$cleanedPhone';
                      }
                    }
                    
                    final uri = Uri.parse('tel:$cleanedPhone');
                    
                    // Use external application mode to force phone dialer
                    final launched = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    
                    if (!launched) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not open phone dialer for $cleanedPhone'),
                            backgroundColor: Colors.red,
                            action: SnackBarAction(
                              label: 'Copy',
                              textColor: Colors.white,
                              onPressed: () {
                                // TODO: Copy phone number to clipboard
                              },
                            ),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    print('Error launching phone dialer: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Phone: $phone\nTap to copy'),
                          backgroundColor: AppTheme.primaryColor,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone, size: Responsive.getIconSize(context, mobile: 18)),
                    SizedBox(width: Responsive.getWidth(context, mobile: 6)),
                    Text('Call Now'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, String>> _loadContactSupportInfo() async {
    try {
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About AgriCart'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AgriCart Customer App'),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Text('Version: 1.0.0'),
            Text('Build: 2024.01.01'),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Text('AgriCart connects customers with local farmers to provide fresh, quality products directly from the source.'),
            SizedBox(height: Responsive.getHeight(context, mobile: 8)),
            Text('© 2024 AgriCart. All rights reserved.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEmailEditDialog(BuildContext context, Customer customer) {
    final newEmailController = TextEditingController();
    final otpController = TextEditingController();
    final oldEmail = customer.email;
    bool _isOTPSent = false; // OTP sent to current email
    bool _isCurrentOTPVerified = false; // Current email OTP verified
    bool _isLoading = false;
    bool _isVerifying = false;
    bool _isChanging = false;
    String? _errorMessage;
    String? _successMessage;
    Timer? _resendTimer;
    int _resendCountdown = 0;

    void startResendTimer() {
      _resendCountdown = 60;
      _resendTimer?.cancel();
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_resendCountdown > 0) {
            _resendCountdown--;
          } else {
            _resendTimer?.cancel();
            timer.cancel();
          }
        });
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Change Email'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show current email
                  Text(
                    'Current Email: ${customer.email}',
                    style: TextStyle(
                      fontSize: Responsive.getFontSize(context, mobile: 14),
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  // Step 1: Send OTP to current email
                  if (!_isOTPSent && !_isCurrentOTPVerified) ...[
                    Text(
                      'For your security, we will first verify your current email address.',
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 12),
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(
                              color: Colors.green, fontSize: 12),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              setState(() {
                                _isLoading = true;
                                _errorMessage = null;
                                _successMessage = null;
                              });

                              try {
                                final supabaseClient = SupabaseService.client;

                                // Send OTP to CURRENT email for verification
                                await supabaseClient.auth
                                    .resetPasswordForEmail(oldEmail);

                                setState(() {
                                  _isOTPSent = true;
                                  _isLoading = false;
                                  _successMessage =
                                      'OTP has been sent to your current email ($oldEmail). Please check your inbox.';
                                });

                                startResendTimer();
                              } catch (e) {
                                debugPrint(
                                    'Error sending email change OTP: $e');
                                setState(() {
                                  final msg = e.toString().toLowerCase();
                                  _errorMessage = (msg.contains('network') ||
                                          msg.contains('connection') ||
                                          msg.contains('socketexception'))
                                      ? 'Network problem. Please check your internet connection and try again.'
                                      : 'Failed to send OTP. Please try again.';
                                  _isLoading = false;
                                });
                              }
                            },
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send OTP'),
                    ),
                  ],
                  // Step 2: Verify OTP from current email
                  if (_isOTPSent && !_isCurrentOTPVerified) ...[
                    Text(
                      'Enter the OTP code sent to your current email: $oldEmail',
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 12),
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    TextField(
                      controller: otpController,
                      decoration: const InputDecoration(
                        labelText: 'OTP Code',
                        border: OutlineInputBorder(),
                        hintText: 'Enter OTP from email',
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _isVerifying
                          ? null
                          : () async {
                              final otp = otpController.text.trim();

                              if (otp.isEmpty) {
                                setState(() {
                                  _errorMessage = 'Please enter the OTP code';
                                });
                                return;
                              }

                              setState(() {
                                _isVerifying = true;
                                _errorMessage = null;
                                _successMessage = null;
                              });

                              try {
                                final supabaseClient = SupabaseService.client;

                                // Verify OTP from current email (recovery type since we used resetPasswordForEmail)
                                await supabaseClient.auth.verifyOTP(
                                  type: OtpType.recovery,
                                  token: otp,
                                  email: oldEmail,
                                );

                                // Wait a moment for session to be established
                                await Future.delayed(
                                    const Duration(milliseconds: 300));

                                setState(() {
                                  _isCurrentOTPVerified = true;
                                  _isVerifying = false;
                                  _successMessage =
                                      'Current email verified. You can now enter your new email.';
                                  _errorMessage = null;
                                });

                                otpController.clear();
                              } catch (e) {
                                debugPrint(
                                    'Error verifying current email OTP: $e');
                                setState(() {
                                  final msg = e.toString().toLowerCase();
                                  _errorMessage = msg.contains('token')
                                      ? 'Invalid or expired OTP. Please try again.'
                                      : 'Failed to verify OTP. Please try again.';
                                  _isVerifying = false;
                                });
                              }
                            },
                      child: _isVerifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify OTP'),
                    ),
                    if (_resendCountdown > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Resend OTP (${_resendCountdown}s)',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () async {
                          try {
                            final supabaseClient = SupabaseService.client;
                            await supabaseClient.auth
                                .resetPasswordForEmail(oldEmail);
                            setState(() {
                              _successMessage =
                                  'OTP has been resent to your current email ($oldEmail).';
                            });
                            startResendTimer();
                          } catch (e) {
                            setState(() {
                              final msg = e.toString().toLowerCase();
                              _errorMessage =
                                  (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception'))
                                      ? 'Network problem. Please check your internet connection and try again.'
                                      : 'Failed to resend OTP. Please try again.';
                            });
                          }
                        },
                        child: const Text('Resend OTP'),
                      ),
                  ],
                  // Step 3: Enter new email and perform change via Edge Function
                  if (_isCurrentOTPVerified) ...[
                    SizedBox(height: Responsive.getHeight(context, mobile: 24)),
                    const Divider(),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    Text(
                      'Enter your new email address',
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 14),
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 12)),
                    TextField(
                      controller: newEmailController,
                      decoration: const InputDecoration(
                        labelText: 'New Email',
                        border: OutlineInputBorder(),
                        hintText: 'Enter your new email address',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(
                              color: Colors.green, fontSize: 12),
                        ),
                      ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    ElevatedButton(
                      onPressed: _isChanging
                          ? null
                          : () async {
                              final newEmail =
                                  newEmailController.text.trim().toLowerCase();

                              if (newEmail.isEmpty ||
                                  !newEmail.contains('@')) {
                                setState(() {
                                  _errorMessage =
                                      'Please enter a valid email address';
                                });
                                return;
                              }

                              if (newEmail == oldEmail.toLowerCase()) {
                                setState(() {
                                  _errorMessage =
                                      'New email must be different from current email';
                                });
                                return;
                              }

                              // Check if new email is already in use
                              try {
                                await SupabaseService.initialize();
                                final existenceCheck =
                                    await SupabaseService.checkCustomerExists(
                                        email: newEmail);

                                if (existenceCheck['email'] ?? false) {
                                  setState(() {
                                    _errorMessage =
                                        'This email is already registered. Please use a different email.';
                                  });
                                  return;
                                }
                              } catch (e) {
                                debugPrint(
                                    'Error checking email existence: $e');
                              }

                              setState(() {
                                _isChanging = true;
                                _errorMessage = null;
                                _successMessage = null;
                              });

                              try {
                                final supabaseClient = SupabaseService.client;
                                final authProvider =
                                    Provider.of<AuthProvider>(context,
                                        listen: false);

                                // Call Edge Function to update Auth email and free old email
                                final response = await supabaseClient
                                    .functions
                                    .invoke('update-auth-email', body: {
                                  'uid': customer.uid,
                                  'newEmail': newEmail,
                                });

                                // In this version of the client, errors are thrown as exceptions.
                                // We can optionally inspect response.data for success if needed.
                                final data = response.data;
                                if (data is Map &&
                                    (data['success'] == false ||
                                        data['error'] != null)) {
                                  debugPrint(
                                      'update-auth-email error payload: $data');
                                  throw Exception(
                                      data['message'] ?? data['error'] ?? 'Email update failed');
                                }

                                // Update customers table with new email
                                await supabaseClient
                                    .from('customers')
                                    .update({'email': newEmail}).eq(
                                        'uid', customer.uid);

                                // Refresh local customer data
                                await authProvider.refreshCustomerData();

                                setState(() {
                                  _isChanging = false;
                                });

                                if (context.mounted) {
                                  _resendTimer?.cancel();
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Email changed successfully. A notification has been sent to your old and new email addresses.'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 4),
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint(
                                    'Error changing email via edge function: $e');
                                if (context.mounted) {
                                  final msg = e.toString().toLowerCase();
                                  final friendly = (msg.contains('network') ||
                                          msg.contains('connection') ||
                                          msg.contains('socketexception'))
                                      ? 'Network problem. Please check your internet connection and try again.'
                                      : 'Failed to change email. Please try again later.';
                                  setState(() {
                                    _isChanging = false;
                                    _errorMessage = friendly;
                                  });
                                }
                              }
                            },
                      child: _isChanging
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save New Email'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _resendTimer?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      _resendTimer?.cancel();
    });
  }

  void _showUsernameEditDialog(BuildContext context, Customer customer) {
    final passwordController = TextEditingController();
    final usernameController = TextEditingController(text: customer.username);
    bool _obscurePassword = true;
    bool _isVerifying = false;
    bool _isVerified = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Username'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isVerified) ...[
                  Text(
                    'Please enter your password to continue',
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14), color: Colors.grey),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    enabled: !_isVerifying,
                    autofocus: true,
                  ),
                ] else ...[
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      hintText: 'Enter your username',
                    ),
                    autofocus: true,
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                  Text(
                    'Note: This username will be used for login after saving.',
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 12), color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isVerifying ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (!_isVerified)
              ElevatedButton(
                onPressed: _isVerifying ? null : () async {
                  final password = passwordController.text.trim();
                  if (password.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter your password'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  
                  setState(() {
                    _isVerifying = true;
                  });
                  
                  try {
                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                    final supabaseClient = SupabaseService.client;
                    
                    // Verify password by attempting to sign in
                    await supabaseClient.auth.signInWithPassword(
                      email: customer.email,
                      password: password,
                    );
                    
                    setState(() {
                      _isVerified = true;
                      _isVerifying = false;
                    });
                  } catch (e) {
                    setState(() {
                      _isVerifying = false;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Incorrect password. Please try again.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: _isVerifying
                    ? SizedBox(
                        width: Responsive.getWidth(context, mobile: 20),
                        height: Responsive.getHeight(context, mobile: 20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              )
            else
              ElevatedButton(
                onPressed: () async {
                  final newUsername = usernameController.text.trim();
                  if (newUsername.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a username'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  
                  try {
                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                    
                    // Check if username is available
                    final isAvailable = await authProvider.checkUsernameAvailability(newUsername);
                    if (!isAvailable) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Username is already taken. Please choose another.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    
                    // Update customer profile
                    final updatedCustomer = customer.copyWith(username: newUsername);
                    await authProvider.updateCustomerProfile(updatedCustomer);
                    
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Username updated successfully! You can now use this username to login.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      final msg = e.toString().toLowerCase();
                      final friendly = (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception'))
                          ? 'Network problem. Please check your internet connection and try again.'
                          : 'Failed to update username. Please try again later.';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(friendly),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final otpController = TextEditingController();
    bool _obscureCurrentPassword = true;
    bool _obscureNewPassword = true;
    bool _obscureConfirmPassword = true;
    bool _isForgotPasswordMode = false; // Toggle between normal and forgot password mode
    bool _isOTPSent = false;
    bool _isOTPVerified = false;
    bool _isLoading = false;
    bool _isVerifying = false;
    bool _isChanging = false;
    String? _errorMessage;
    String? _successMessage;
    Timer? _resendTimer;
    int _resendCountdown = 0;
    
    // Pre-fill email from current customer
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final customer = authProvider.currentCustomer;
    final emailController = TextEditingController(text: customer?.email ?? '');
    
    void startResendTimer() {
      _resendCountdown = 60;
      _resendTimer?.cancel();
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_resendCountdown > 0) {
            _resendCountdown--;
          } else {
            _resendTimer?.cancel();
            timer.cancel();
          }
        });
      });
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Change Password'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isOTPVerified) ...[
                    // Show current password field only in normal mode
                    if (!_isForgotPasswordMode) ...[
                      TextField(
                        controller: currentPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureCurrentPassword ? Icons.visibility : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _obscureCurrentPassword = !_obscureCurrentPassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscureCurrentPassword,
                        enabled: !_isOTPSent,
                        autofocus: !_isOTPSent,
                      ),
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    ] else ...[
                      // Show email field in forgot password mode
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        enabled: false, // Pre-filled and disabled
                      ),
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    ],
                    // New Password Field (shown before OTP in normal mode)
                    if (!_isForgotPasswordMode && !_isOTPSent)
                      TextField(
                        controller: newPasswordController,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNewPassword ? Icons.visibility : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _obscureNewPassword = !_obscureNewPassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscureNewPassword,
                      ),
                    if (!_isForgotPasswordMode && !_isOTPSent)
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    // Confirm Password Field (shown before OTP in normal mode)
                    if (!_isForgotPasswordMode && !_isOTPSent)
                      TextField(
                        controller: confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword = !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
                      ),
                    // Forgot Password link (only shown in normal mode before OTP is sent)
                    if (!_isForgotPasswordMode && !_isOTPSent) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _isForgotPasswordMode = true;
                              _errorMessage = null;
                              _successMessage = null;
                            });
                          },
                          child: const Text('Forgot Password?'),
                        ),
                      ),
                    ],
                    // Send OTP button
                    if (!_isOTPSent) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                      ElevatedButton(
                        onPressed: _isLoading ? null : () async {
                          if (_isForgotPasswordMode) {
                            // Forgot password mode - just send OTP
                            final email = emailController.text.trim();
                            
                            if (email.isEmpty) {
                              setState(() {
                                _errorMessage = 'Please enter your email';
                              });
                              return;
                            }
                            
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            
                            try {
                              final supabaseClient = SupabaseService.client;
                              await supabaseClient.auth.resetPasswordForEmail(email);
                              
                              setState(() {
                                _isOTPSent = true;
                                _isLoading = false;
                                _successMessage = 'OTP has been sent to your email. Please check your inbox.';
                              });
                              
                              startResendTimer();
                            } catch (e) {
                              debugPrint('Error sending OTP: $e');
                              setState(() {
                                _errorMessage = 'Failed to send OTP. Please try again.';
                                _isLoading = false;
                              });
                            }
                          } else {
                            // Normal mode - verify current password then send OTP
                            final currentPassword = currentPasswordController.text.trim();
                            final newPassword = newPasswordController.text.trim();
                            final confirmPassword = confirmPasswordController.text.trim();
                            
                            if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                              setState(() {
                                _errorMessage = 'Please fill in all fields';
                              });
                              return;
                            }
                            
                            if (newPassword.length < 6) {
                              setState(() {
                                _errorMessage = 'New password must be at least 6 characters long';
                              });
                              return;
                            }
                            
                            if (newPassword != confirmPassword) {
                              setState(() {
                                _errorMessage = 'New passwords do not match';
                              });
                              return;
                            }
                            
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            
                            try {
                              final customer = authProvider.currentCustomer;
                              
                              if (customer == null) {
                                setState(() {
                                  _errorMessage = 'User not found';
                                  _isLoading = false;
                                });
                                return;
                              }
                              
                              // Verify current password by attempting to sign in
                              final supabaseClient = SupabaseService.client;
                              try {
                                await supabaseClient.auth.signInWithPassword(
                                  email: customer.email,
                                  password: currentPassword,
                                );
                              } catch (e) {
                                setState(() {
                                  _errorMessage = 'Current password is incorrect';
                                  _isLoading = false;
                                });
                                return;
                              }
                              
                              // Send OTP for password change
                              await supabaseClient.auth.resetPasswordForEmail(customer.email);
                              
                              setState(() {
                                _isOTPSent = true;
                                _isLoading = false;
                                _successMessage = 'OTP has been sent to your email. Please check your inbox.';
                              });
                              
                              startResendTimer();
                            } catch (e) {
                              debugPrint('Error sending OTP: $e');
                              setState(() {
                                _errorMessage = 'Failed to send OTP. Please try again.';
                                _isLoading = false;
                              });
                            }
                          }
                        },
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send OTP'),
                      ),
                    ],
                    // OTP verification section
                    if (_isOTPSent && !_isOTPVerified) ...[
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                      TextField(
                        controller: otpController,
                        decoration: const InputDecoration(
                          labelText: 'OTP Code',
                          border: OutlineInputBorder(),
                          hintText: 'Enter OTP from email',
                        ),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                        ),
                      ),
                      SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      if (_successMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _successMessage!,
                            style: const TextStyle(color: Colors.green, fontSize: 12),
                          ),
                        ),
                      ElevatedButton(
                        onPressed: _isVerifying ? null : () async {
                          final otp = otpController.text.trim();
                          final email = _isForgotPasswordMode 
                              ? emailController.text.trim() 
                              : customer?.email ?? '';
                          
                          if (otp.isEmpty) {
                            setState(() {
                              _errorMessage = 'Please enter the OTP code';
                            });
                            return;
                          }
                          
                          setState(() {
                            _isVerifying = true;
                            _errorMessage = null;
                          });
                          
                          try {
                            final supabaseClient = SupabaseService.client;
                            
                            // Verify OTP
                            await supabaseClient.auth.verifyOTP(
                              type: OtpType.recovery,
                              token: otp,
                              email: email,
                            );
                            
                            // Wait for session
                            await Future.delayed(const Duration(milliseconds: 300));
                            
                            setState(() {
                              _isOTPVerified = true;
                              _isVerifying = false;
                              _successMessage = 'OTP verified successfully!';
                            });
                            
                            _resendTimer?.cancel();
                          } catch (e) {
                            debugPrint('Error verifying OTP: $e');
                            setState(() {
                              _errorMessage = 'Invalid or expired OTP. Please try again.';
                              _isVerifying = false;
                            });
                          }
                        },
                        child: _isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Verify OTP'),
                      ),
                      if (_resendCountdown > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Resend OTP (${_resendCountdown}s)',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: () async {
                            try {
                              final email = _isForgotPasswordMode 
                                  ? emailController.text.trim() 
                                  : customer?.email ?? '';
                              final supabaseClient = SupabaseService.client;
                              await supabaseClient.auth.resetPasswordForEmail(email);
                              setState(() {
                                _successMessage = 'OTP has been resent to your email.';
                              });
                              startResendTimer();
                            } catch (e) {
                              setState(() {
                                _errorMessage = 'Failed to resend OTP. Please try again.';
                              });
                            }
                          },
                          child: const Text('Resend OTP'),
                        ),
                    ],
                  ],
                  // After OTP verification - show new password fields
                  if (_isOTPVerified) ...[
                    const Text(
                      'OTP verified! Now enter your new password.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    TextField(
                      controller: newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNewPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscureNewPassword = !_obscureNewPassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureNewPassword,
                      autofocus: true,
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    TextField(
                      controller: confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureConfirmPassword,
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _resendTimer?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              if (_isOTPVerified)
                ElevatedButton(
                  onPressed: _isChanging ? null : () async {
                    final newPassword = newPasswordController.text.trim();
                    final confirmPassword = confirmPasswordController.text.trim();
                    
                    if (newPassword.isEmpty || confirmPassword.isEmpty) {
                      setState(() {
                        _errorMessage = 'Please fill in all fields';
                      });
                      return;
                    }
                    
                    if (newPassword.length < 6) {
                      setState(() {
                        _errorMessage = 'New password must be at least 6 characters long';
                      });
                      return;
                    }
                    
                    if (newPassword != confirmPassword) {
                      setState(() {
                        _errorMessage = 'New passwords do not match';
                      });
                      return;
                    }
                    
                    setState(() {
                      _isChanging = true;
                      _errorMessage = null;
                    });
                    
                    try {
                      final supabaseClient = SupabaseService.client;
                      
                      // Update password (previous password is not logged for security)
                      await supabaseClient.auth.updateUser(
                        UserAttributes(password: newPassword),
                      );
                      
                      if (context.mounted) {
                        _resendTimer?.cancel();
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Error updating password: $e');
                      if (context.mounted) {
                        final msg = e.toString().toLowerCase();
                        final friendly = (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception'))
                            ? 'Network problem. Please check your internet connection and try again.'
                            : 'Failed to update password. Please try again later.';
                        setState(() {
                          _errorMessage = friendly;
                          _isChanging = false;
                        });
                      }
                    }
                  },
                  child: _isChanging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
                ),
            ],
          );
        },
      ),
    ).then((_) {
      _resendTimer?.cancel();
    });
  }

  // Removed _showForgotPasswordDialog - functionality merged into _showChangePasswordDialog
  // Old method kept for reference but not used
  void _showForgotPasswordDialog_OLD_UNUSED(BuildContext context) {
    final emailController = TextEditingController();
    final otpController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool _obscureNewPassword = true;
    bool _obscureConfirmPassword = true;
    bool _isOTPSent = false;
    bool _isOTPVerified = false;
    bool _isLoading = false;
    bool _isVerifying = false;
    bool _isChanging = false;
    String? _errorMessage;
    String? _successMessage;
    Timer? _resendTimer;
    int _resendCountdown = 0;
    
    // Pre-fill email from current customer
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final customer = authProvider.currentCustomer;
    if (customer != null) {
      emailController.text = customer.email;
    }
    
    void startResendTimer() {
      _resendCountdown = 60;
      _resendTimer?.cancel();
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_resendCountdown > 0) {
            _resendCountdown--;
          } else {
            _resendTimer?.cancel();
            timer.cancel();
          }
        });
      });
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Forgot Password'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isOTPSent) ...[
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      enabled: false, // Pre-filled and disabled
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    ElevatedButton(
                      onPressed: _isLoading ? null : () async {
                        final email = emailController.text.trim();
                        
                        if (email.isEmpty) {
                          setState(() {
                            _errorMessage = 'Please enter your email';
                          });
                          return;
                        }
                        
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        
                        try {
                          final supabaseClient = SupabaseService.client;
                          await supabaseClient.auth.resetPasswordForEmail(email);
                          
                          setState(() {
                            _isOTPSent = true;
                            _isLoading = false;
                            _successMessage = 'OTP has been sent to your email. Please check your inbox.';
                          });
                          
                          startResendTimer();
                        } catch (e) {
                          debugPrint('Error sending OTP: $e');
                          setState(() {
                            _errorMessage = 'Failed to send OTP. Please try again.';
                            _isLoading = false;
                          });
                        }
                      },
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send OTP'),
                    ),
                  ],
                  if (_isOTPSent && !_isOTPVerified) ...[
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    TextField(
                      controller: otpController,
                      decoration: const InputDecoration(
                        labelText: 'OTP Code',
                        border: OutlineInputBorder(),
                        hintText: 'Enter OTP from email',
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _isVerifying ? null : () async {
                        final otp = otpController.text.trim();
                        final email = emailController.text.trim();
                        
                        if (otp.isEmpty) {
                          setState(() {
                            _errorMessage = 'Please enter the OTP code';
                          });
                          return;
                        }
                        
                        setState(() {
                          _isVerifying = true;
                          _errorMessage = null;
                        });
                        
                        try {
                          final supabaseClient = SupabaseService.client;
                          
                          // Verify OTP
                          await supabaseClient.auth.verifyOTP(
                            type: OtpType.recovery,
                            token: otp,
                            email: email,
                          );
                          
                          // Wait for session
                          await Future.delayed(const Duration(milliseconds: 300));
                          
                          setState(() {
                            _isOTPVerified = true;
                            _isVerifying = false;
                            _successMessage = 'OTP verified successfully!';
                          });
                          
                          _resendTimer?.cancel();
                        } catch (e) {
                          debugPrint('Error verifying OTP: $e');
                          setState(() {
                            _errorMessage = 'Invalid or expired OTP. Please try again.';
                            _isVerifying = false;
                          });
                        }
                      },
                      child: _isVerifying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify OTP'),
                    ),
                    if (_resendCountdown > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Resend OTP (${_resendCountdown}s)',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () async {
                          try {
                            final email = emailController.text.trim();
                            final supabaseClient = SupabaseService.client;
                            await supabaseClient.auth.resetPasswordForEmail(email);
                            setState(() {
                              _successMessage = 'OTP has been resent to your email.';
                            });
                            startResendTimer();
                          } catch (e) {
                            setState(() {
                              _errorMessage = 'Failed to resend OTP. Please try again.';
                            });
                          }
                        },
                        child: const Text('Resend OTP'),
                      ),
                  ],
                  if (_isOTPVerified) ...[
                    const Text(
                      'OTP verified! Now enter your new password.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    TextField(
                      controller: newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNewPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscureNewPassword = !_obscureNewPassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureNewPassword,
                      autofocus: true,
                    ),
                    SizedBox(height: Responsive.getHeight(context, mobile: 16)),
                    TextField(
                      controller: confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureConfirmPassword,
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _resendTimer?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              if (_isOTPVerified)
                ElevatedButton(
                  onPressed: _isChanging ? null : () async {
                    final newPassword = newPasswordController.text.trim();
                    final confirmPassword = confirmPasswordController.text.trim();
                    
                    if (newPassword.isEmpty || confirmPassword.isEmpty) {
                      setState(() {
                        _errorMessage = 'Please fill in all fields';
                      });
                      return;
                    }
                    
                    if (newPassword.length < 6) {
                      setState(() {
                        _errorMessage = 'New password must be at least 6 characters long';
                      });
                      return;
                    }
                    
                    if (newPassword != confirmPassword) {
                      setState(() {
                        _errorMessage = 'New passwords do not match';
                      });
                      return;
                    }
                    
                    setState(() {
                      _isChanging = true;
                      _errorMessage = null;
                    });
                    
                    try {
                      final supabaseClient = SupabaseService.client;
                      
                      // Update password (previous password is not logged for security)
                      await supabaseClient.auth.updateUser(
                        UserAttributes(password: newPassword),
                      );
                      
                      if (context.mounted) {
                        _resendTimer?.cancel();
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Error updating password: $e');
                      if (context.mounted) {
                        final msg = e.toString().toLowerCase();
                        final friendly = (msg.contains('network') || msg.contains('connection') || msg.contains('socketexception'))
                            ? 'Network problem. Please check your internet connection and try again.'
                            : 'Failed to update password. Please try again later.';
                        setState(() {
                          _errorMessage = friendly;
                          _isChanging = false;
                        });
                      }
                    }
                  },
                  child: _isChanging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
                ),
            ],
          );
        },
      ),
    ).then((_) {
      _resendTimer?.cancel();
    });
  }

  void _showRegisteredAccountDetailsDialog(BuildContext context, Customer customer) {
    // Get cumulative totals from CustomerProvider
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => _RegisteredAccountDetailsDialog(
        customer: customer,
        cumulativeTotalOrders: customerProvider.cumulativeTotalOrders,
        cumulativeTotalSpent: customerProvider.cumulativeTotalSpent,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: Responsive.getWidth(context, mobile: 140),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                fontSize: Responsive.getFontSize(context, mobile: 14),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 14),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final heroTopPadding = widget.showAppBar 
        ? Responsive.getSpacing(context, mobile: 20) 
        : mediaQuery.padding.top + Responsive.getSpacing(context, mobile: 16);

    return Scaffold(
      appBar: widget.showAppBar 
          ? AppBar(
              title: Text(
                'Profile',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 20)),
              ),
              toolbarHeight: Responsive.getAppBarHeight(context),
            )
          : null,
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final customer = authProvider.currentCustomer;
          
          if (customer == null) {
            return Center(
              child: Text(
                'No customer data available',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
              ),
            );
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppTheme.subtleGradient,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: Responsive.getSpacing(context, mobile: 32)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroStack(context, customer),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 100)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: Responsive.getHorizontalPadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Personal Information'),
                            SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                          ],
                        ),
                      ),
                      _buildInfoCard(
                    children: [
                      _buildProfileTile(
                        icon: Icons.alternate_email,
                        label: 'Username',
                        value: customer.username.isNotEmpty ? customer.username : 'Not provided',
                        onTap: () => _showUsernameEditDialog(context, customer),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.person,
                        label: 'Name',
                        value: customer.fullName.isNotEmpty ? customer.fullName : 'Not provided',
                        onTap: null, // Name cannot be edited
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.location_on,
                        label: 'Home Address',
                        value: customer.address.isNotEmpty ? customer.address : 'Not provided',
                        onTap: () => _showAddressEditDialog(context, customer),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.phone,
                        label: 'Phone Number',
                        value: customer.phoneNumber.isNotEmpty ? customer.phoneNumber : 'Not provided',
                        onTap: () => _showPhoneNumberEditDialog(context, customer),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.verified_user,
                        label: 'Verification',
                        value: customer.verificationDate != null
                            ? 'Approved on ${_formatDate(customer.verificationDate!)}'
                            : 'Pending approval',
                        badgeColor: customer.verificationDate != null ? Colors.green : Colors.orange,
                        badgeLabel: customer.verificationDate != null ? 'Approved' : 'Pending',
                      ),
                    ],
                  ),
                      SizedBox(height: Responsive.getSpacing(context, mobile: 28)),
                      Padding(
                        padding: Responsive.getHorizontalPadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('App'),
                            SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                          ],
                        ),
                      ),
                      _buildInfoCard(
                    children: [
                      _buildProfileTile(
                        icon: Icons.settings,
                        label: 'Settings',
                        value: 'Notifications, language',
                        onTap: () => _showSettingsDialog(context),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.help_outline,
                        label: 'Help & Support',
                        value: 'FAQs and contact',
                        onTap: () => _showHelpDialog(context),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.info_outline,
                        label: 'About AgriCart',
                        value: 'Version 1.0.0',
                        onTap: () => _showAboutDialog(context),
                      ),
                    ],
                  ),
                      SizedBox(height: Responsive.getSpacing(context, mobile: 28)),
                      Padding(
                        padding: Responsive.getHorizontalPadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Account'),
                            SizedBox(height: Responsive.getSpacing(context, mobile: 12)),
                          ],
                        ),
                      ),
                      _buildInfoCard(
                    children: [
                      _buildProfileTile(
                        icon: Icons.email,
                        label: 'Email',
                        value: customer.email.isNotEmpty ? customer.email : 'Not provided',
                        onTap: () => _showEmailEditDialog(context, customer),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.lock_outline,
                        label: 'Change Password',
                        value: 'Update your password',
                        onTap: () => _showChangePasswordDialog(context),
                      ),
                      _buildDivider(),
                      _buildProfileTile(
                        icon: Icons.account_circle,
                        label: 'Registered Account Details',
                        value: 'View account information',
                        onTap: () => _showRegisteredAccountDetailsDialog(context, customer),
                      ),
                    ],
                  ),
                      SizedBox(height: Responsive.getSpacing(context, mobile: 20)),
                      _buildDeleteAccountButton(context, authProvider),
                      SizedBox(height: Responsive.getSpacing(context, mobile: 20)),
                      _buildSignOutButton(context, authProvider),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeleteAccountButton(BuildContext context, AuthProvider authProvider) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        icon: Icon(Icons.delete_forever, color: Colors.white, size: Responsive.getIconSize(context, mobile: 18)),
        label: const Text('Delete Account'),
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            vertical: Responsive.getSpacing(context, mobile: 12),
            horizontal: Responsive.getSpacing(context, mobile: 16),
          ),
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 10)),
          ),
        ),
        onPressed: () => _confirmDeleteAccount(context, authProvider),
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to permanently delete your AgriCart account? '
          'This will remove your profile and login access. Your past orders and sales records will be kept for reporting, '
          'but you will no longer be able to use this account.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop(); // close dialog
              final success = await authProvider.deleteOwnAccount(
                reason: 'Account deletion requested by customer from profile screen',
              );
              if (!context.mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Your account has been deleted successfully.'),
                    backgroundColor: Colors.green,
                  ),
                );
                // After signOut inside deleteOwnAccount, navigate to login screen
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } else {
                final error = authProvider.error ??
                    'Failed to delete your account. Please try again later or contact support.';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Yes, Delete My Account'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStack(BuildContext context, Customer customer) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildProfileHero(context, customer),
        Positioned(
          bottom: -Responsive.getSpacing(context, mobile: 50),
          left: 0,
          right: 0,
          child: _buildSummaryCard(customer),
        ),
      ],
    );
  }

  Widget _buildProfileHero(BuildContext context, Customer customer) {
    final tagline = customer.address.isNotEmpty
        ? customer.address
        : 'Enjoying fresh harvests from Cabintan farmers';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        Responsive.getHorizontalPadding(context).left,
        widget.showAppBar 
            ? Responsive.getSpacing(context, mobile: 28) 
            : MediaQuery.of(context).padding.top + Responsive.getSpacing(context, mobile: 20),
        Responsive.getHorizontalPadding(context).right,
        Responsive.getSpacing(context, mobile: 90),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: Responsive.getImageSize(context, mobile: 110),
            height: Responsive.getImageSize(context, mobile: 110),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.primaryDarkColor,
                width: Responsive.isTabletOrLarger(context) ? 4 : 3,
              ),
            ),
            child: ClipOval(
              child: Container(
                color: Colors.white.withOpacity(0.2),
                child: _buildProfileImage(customer),
              ),
            ),
          ),
          SizedBox(height: Responsive.getSpacing(context, mobile: 16)),
          Text(
            customer.fullName.isNotEmpty ? customer.fullName : 'Unknown Customer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: Responsive.getFontSize(context, mobile: 22),
                ),
          ),
          SizedBox(height: Responsive.getSpacing(context, mobile: 8)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8)),
            child: Text(
              customer.email,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: Responsive.getFontSize(context, mobile: 14),
                  ),
            ),
          ),
          SizedBox(height: Responsive.getSpacing(context, mobile: 6)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 8)),
            child: Text(
              tagline,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.8),
                    height: 1.4,
                    fontSize: Responsive.getFontSize(context, mobile: 12),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileImage(Customer customer) {
    if (_isUploadingProfilePicture) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (customer.profileImageUrl.isEmpty) {
      final initial = customer.fullName.isNotEmpty ? customer.fullName[0].toUpperCase() : 'C';
      return Builder(
        builder: (context) => Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: Responsive.getFontSize(context, mobile: 36),
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Image.network(
      _fixProfileImageUrl(customer.profileImageUrl),
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      },
      errorBuilder: (context, error, stack) {
        return Builder(
          builder: (context) => Center(
            child: Text(
              customer.fullName.isNotEmpty ? customer.fullName[0].toUpperCase() : 'C',
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 36),
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(Customer customer) {
    // Get cumulative totals from CustomerProvider
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    
    final stats = [
      _ProfileStat(
        label: 'Total Orders',
        value: '${customerProvider.cumulativeTotalOrders}',
        icon: Icons.receipt_long,
      ),
      _ProfileStat(
        label: 'Total Spent',
        value: '\u20B1${customerProvider.cumulativeTotalSpent.toStringAsFixed(2)}',
        icon: Icons.payments_outlined,
      ),
    ];

    return Builder(
      builder: (context) {
        final rowChildren = <Widget>[];
        for (var i = 0; i < stats.length; i++) {
          final stat = stats[i];
          rowChildren.add(
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                    ),
                    child: Icon(
                      stat.icon,
                      color: AppTheme.primaryColor,
                      size: Responsive.getIconSize(context, mobile: 20),
                    ),
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 6)),
                  Text(
                    stat.value,
                    style: TextStyle(
                      fontSize: Responsive.getFontSize(context, mobile: 18),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  SizedBox(height: Responsive.getSpacing(context, mobile: 3)),
                  Text(
                    stat.label,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: Responsive.getFontSize(context, mobile: 12),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );

          if (i < stats.length - 1) {
            rowChildren.add(
              Container(
                width: Responsive.getWidth(context, mobile: 1),
                height: Responsive.getSpacing(context, mobile: 45),
                margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12)),
                color: Colors.grey.withOpacity(0.2),
              ),
            );
          }
        }

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.getHorizontalPadding(context).left,
            vertical: Responsive.getSpacing(context, mobile: 12),
          ),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
          child: Row(children: rowChildren),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Builder(
      builder: (context) => Text(
        title,
        style: TextStyle(
          fontSize: Responsive.getFontSize(context, mobile: 18),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInfoCard({required List<Widget> children}) {
    return Builder(
      builder: (context) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.getHorizontalPadding(context).left,
          vertical: Responsive.getSpacing(context, mobile: 4),
        ),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildProfileTile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    String? badgeLabel,
    Color? badgeColor,
  }) {
    final showChevron = onTap != null;
    return Builder(
      builder: (context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 10)),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 14)),
                ),
                child: Icon(
                  icon,
                  color: AppTheme.primaryColor,
                  size: Responsive.getIconSize(context, mobile: 24),
                ),
              ),
              SizedBox(width: Responsive.getSpacing(context, mobile: 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: Responsive.getFontSize(context, mobile: 13),
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (badgeLabel != null && badgeColor != null)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: Responsive.getSpacing(context, mobile: 10),
                              vertical: Responsive.getSpacing(context, mobile: 4),
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 30)),
                            ),
                            child: Text(
                              badgeLabel,
                              style: TextStyle(
                                fontSize: Responsive.getFontSize(context, mobile: 11),
                                color: badgeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: Responsive.getSpacing(context, mobile: 4)),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: Responsive.getFontSize(context, mobile: 15),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChevron)
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: Responsive.getIconSize(context, mobile: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: Responsive.getHeight(context, mobile: 0),
      thickness: 1,
      color: Colors.grey[200],
    );
  }

  Widget _buildActionGrid(BuildContext context, Customer customer) {
    final actions = [
      _QuickAction(
        label: 'Change Photo',
        icon: Icons.camera_alt,
        onTap: _isUploadingProfilePicture ? null : _changeProfilePicture,
      ),
      _QuickAction(
        label: 'Edit Address',
        icon: Icons.home_outlined,
        onTap: () => _showAddressEditDialog(context, customer),
      ),
      // Phone number removed - now managed in saved addresses
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: actions.map((action) {
        final enabled = action.onTap != null;
        return InkWell(
          onTap: enabled ? action.onTap : null,
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
          child: Ink(
            width: Responsive.getWidth(context, mobile: 110),
            padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12), vertical: Responsive.getSpacing(context, mobile: 14)),
            decoration: BoxDecoration(
              gradient: enabled ? AppTheme.cardGradient : LinearGradient(
                colors: [AppTheme.creamColor, AppTheme.creamColor],
              ),
              borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 18)),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
              boxShadow: enabled ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ] : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 12)),
                  ),
                  child: Icon(action.icon, color: AppTheme.primaryColor, size: Responsive.getIconSize(context, mobile: 18)),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 10)),
                Text(
                  action.label,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: Responsive.getFontSize(context, mobile: 12)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHorizontalActionRow(BuildContext context, Customer customer) {
    final actions = [
      _QuickAction(
        label: 'Change Photo',
        icon: Icons.camera_alt,
        onTap: _isUploadingProfilePicture ? null : _changeProfilePicture,
      ),
      _QuickAction(
        label: 'Edit Address',
        icon: Icons.home_outlined,
        onTap: () => _showAddressEditDialog(context, customer),
      ),
      // Phone number removed - now managed in saved addresses
    ];

    return SizedBox(
      height: Responsive.getHeight(context, mobile: 112),
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 16)),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final action = actions[index];
          final enabled = action.onTap != null;
          return InkWell(
            onTap: enabled ? action.onTap : null,
            borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
            child: Ink(
              width: Responsive.getWidth(context, mobile: 140),
              decoration: BoxDecoration(
                gradient: enabled ? AppTheme.cardGradient : LinearGradient(
                  colors: [AppTheme.creamColor, AppTheme.creamColor],
                ),
                borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
                boxShadow: enabled ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ] : null,
              ),
              padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 8)),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 14)),
                    ),
                    child: Icon(action.icon, color: AppTheme.primaryColor, size: Responsive.getIconSize(context, mobile: 18)),
                  ),
                  SizedBox(height: Responsive.getHeight(context, mobile: 10)),
                  Text(
                    action.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: Responsive.getFontSize(context, mobile: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => SizedBox(width: Responsive.getWidth(context, mobile: 14)),
        itemCount: actions.length,
      ),
    );
  }

  Widget _buildActivityCard() {
    final points = [
      const _ActivityPoint(label: 'Mon', value: 0.4),
      const _ActivityPoint(label: 'Tue', value: 0.6),
      const _ActivityPoint(label: 'Wed', value: 0.3),
      const _ActivityPoint(label: 'Thu', value: 0.75),
      const _ActivityPoint(label: 'Fri', value: 0.5),
      const _ActivityPoint(label: 'Sat', value: 0.9),
      const _ActivityPoint(label: 'Sun', value: 0.65),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Responsive.getSpacing(context, mobile: 20)),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 24)),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ordering Activity',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 16),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 12), vertical: Responsive.getSpacing(context, mobile: 6)),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 30)),
                ),
                child: const Text(
                  'Week',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: Responsive.getHeight(context, mobile: 18)),
          SizedBox(
            height: Responsive.getHeight(context, mobile: 100),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((point) {
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 70 * point.value + 20,
                        margin: EdgeInsets.symmetric(horizontal: Responsive.getSpacing(context, mobile: 6)),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withOpacity(0.25),
                              AppTheme.primaryColor,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                            bottom: Radius.circular(6),
                          ),
                        ),
                      ),
                      SizedBox(height: Responsive.getHeight(context, mobile: 6)),
                      Text(
                        point.label,
                        style: TextStyle(
                          fontSize: Responsive.getFontSize(context, mobile: 11),
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context, AuthProvider authProvider) {
    return Builder(
      builder: (context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 20)),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
            padding: EdgeInsets.symmetric(
              vertical: Responsive.getSpacing(context, mobile: 16),
              horizontal: Responsive.getHorizontalPadding(context).left,
            ),
            alignment: Alignment.centerLeft,
            minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 48)),
          ),
          icon: Icon(
            Icons.logout,
            size: Responsive.getIconSize(context, mobile: 20),
          ),
          label: Text(
            'Sign Out',
            style: TextStyle(
              fontSize: Responsive.getFontSize(context, mobile: 15),
              fontWeight: FontWeight.w600,
            ),
          ),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                'Sign Out',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 20)),
              ),
              content: Text(
                'Are you sure you want to sign out?',
                style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 16)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                    minimumSize: Size(0, Responsive.getButtonHeight(context, mobile: 40)),
                  ),
                  child: Text(
                    'Sign Out',
                    style: TextStyle(fontSize: Responsive.getFontSize(context, mobile: 14)),
                  ),
                ),
              ],
            ),
          );

          if (confirmed == true && context.mounted) {
            final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
            customerProvider.clearAllData();
            await customerProvider.clearLocalStorageData();

            await authProvider.signOut();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        },
        ),
      ),
    );
  }
}

class _ProfileStat {
  final String label;
  final String value;
  final IconData icon;

  const _ProfileStat({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _ActivityPoint {
  final String label;
  final double value;

  const _ActivityPoint({
    required this.label,
    required this.value,
  });
}

// Separate StatefulWidget for Registered Account Details Dialog
class _RegisteredAccountDetailsDialog extends StatefulWidget {
  final Customer customer;
  final int cumulativeTotalOrders;
  final double cumulativeTotalSpent;

  const _RegisteredAccountDetailsDialog({
    required this.customer,
    required this.cumulativeTotalOrders,
    required this.cumulativeTotalSpent,
  });

  @override
  State<_RegisteredAccountDetailsDialog> createState() => _RegisteredAccountDetailsDialogState();
}

class _RegisteredAccountDetailsDialogState extends State<_RegisteredAccountDetailsDialog> {
  String? idFrontPhotoUrl;
  String? idBackPhotoUrl;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIdPhotos();
  }

  Future<void> _loadIdPhotos() async {
    try {
      await SupabaseService.initialize();
      final customerData = await SupabaseService.loadCustomer(widget.customer.uid);
      if (mounted) {
        setState(() {
          if (customerData != null) {
            idFrontPhotoUrl = customerData['idFrontPhoto'];
            idBackPhotoUrl = customerData['idBackPhoto'];
          }
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ID photos: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Format dates with time
  String formatDateTimeWithTime(DateTime? date) {
    if (date == null) return 'Not set';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour < 12 ? 'AM' : 'PM';
    return '${months[date.month - 1]} ${date.day}, ${date.year} • $hour:$minute $ampm';
  }

  String _fixIdImageUrl(String url) {
    // Fix duplicate bucket names in URL
    String fixedUrl = url.trim();
    
    // Remove duplicate bucket names
    fixedUrl = fixedUrl.replaceAll('/customerid_image/customerid_image/', '/customerid_image/');
    
    // If URL doesn't start with http, it might be a path - construct full URL
    if (!fixedUrl.startsWith('http://') && !fixedUrl.startsWith('https://')) {
      // It's a file path, construct Supabase URL
      String cleanPath = fixedUrl.replaceFirst(RegExp(r'^/+'), '');
      // Remove bucket name if present (handle multiple occurrences)
      while (cleanPath.startsWith('customerid_image/')) {
        cleanPath = cleanPath.substring('customerid_image/'.length).replaceFirst(RegExp(r'^/+'), '');
      }
      fixedUrl = 'https://afkwexvvuxwbpioqnelp.supabase.co/storage/v1/object/public/customerid_image/$cleanPath';
    }
    
    return fixedUrl;
  }

  void _showImageFullScreen(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  _fixIdImageUrl(imageUrl),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(Icons.broken_image, color: Colors.white, size: Responsive.getIconSize(context, mobile: 64)),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: Responsive.getIconSize(context, mobile: 30)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Responsive.getSpacing(context, mobile: 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: Responsive.getWidth(context, mobile: 140),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                fontSize: Responsive.getFontSize(context, mobile: 14),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: Responsive.getFontSize(context, mobile: 14),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registered Account Details'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: SingleChildScrollView(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _buildDetailRow('Username', widget.customer.username.isNotEmpty ? widget.customer.username : 'Not provided'),
            _buildDetailRow('Email', widget.customer.email),
            _buildDetailRow('Full Name', widget.customer.fullName.isNotEmpty ? widget.customer.fullName : 'Not provided'),
            _buildDetailRow('Phone Number', widget.customer.phoneNumber.isNotEmpty ? widget.customer.phoneNumber : 'Not provided'),
            _buildDetailRow('Age', widget.customer.age > 0 ? '${widget.customer.age}' : 'Not provided'),
            _buildDetailRow('Gender', widget.customer.gender.isNotEmpty ? widget.customer.gender : 'Not provided'),
            _buildDetailRow('ID Type', widget.customer.idType.isNotEmpty ? widget.customer.idType : 'Not specified'),
            _buildDetailRow('Address', widget.customer.address.isNotEmpty ? widget.customer.address : 'Not provided'),
            _buildDetailRow('Barangay', widget.customer.barangay.isNotEmpty ? widget.customer.barangay : 'Not provided'),
            _buildDetailRow('City', widget.customer.city.isNotEmpty ? widget.customer.city : 'Not provided'),
            _buildDetailRow('State', widget.customer.state.isNotEmpty ? widget.customer.state : 'Not provided'),
            _buildDetailRow('Zip Code', widget.customer.zipCode.isNotEmpty ? widget.customer.zipCode : 'Not provided'),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            const Divider(),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            _buildDetailRow('Account Status', widget.customer.accountStatus.isNotEmpty ? widget.customer.accountStatus.toUpperCase() : 'PENDING'),
            _buildDetailRow('Verification Status', widget.customer.verificationStatus.isNotEmpty ? widget.customer.verificationStatus.toUpperCase() : 'PENDING'),
            if (widget.customer.verificationDate != null)
              _buildDetailRow('Verification Date', formatDateTimeWithTime(widget.customer.verificationDate)),
            if (widget.customer.rejectionReason != null && widget.customer.rejectionReason!.isNotEmpty)
              _buildDetailRow('Rejection Reason', widget.customer.rejectionReason!),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            const Divider(),
            SizedBox(height: Responsive.getHeight(context, mobile: 12)),
            _buildDetailRow('Registration Date', formatDateTimeWithTime(widget.customer.createdAt)),
            _buildDetailRow('Total Orders', '${widget.cumulativeTotalOrders}'),
            _buildDetailRow('Total Spent', '\u20B1${widget.cumulativeTotalSpent.toStringAsFixed(2)}'),
            // ID Photos Section
            if (isLoading) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              const Divider(),
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (idFrontPhotoUrl != null || idBackPhotoUrl != null) ...[
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              const Divider(),
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              Text(
                'Valid ID Photos',
                style: TextStyle(
                  fontSize: Responsive.getFontSize(context, mobile: 16),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: Responsive.getHeight(context, mobile: 12)),
              if (idFrontPhotoUrl != null && idFrontPhotoUrl!.isNotEmpty) ...[
                Text(
                  'Front Side:',
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 14),
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                GestureDetector(
                  onTap: () => _showImageFullScreen(context, idFrontPhotoUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    child: SizedBox(
                      width: double.infinity,
                      height: Responsive.getHeight(context, mobile: 200),
                      child: Image.network(
                        _fixIdImageUrl(idFrontPhotoUrl!),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: Responsive.getHeight(context, mobile: 200),
                            color: Colors.grey[200],
                            child: Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: Responsive.getHeight(context, mobile: 200),
                            color: Colors.grey[200],
                            child: Center(
                              child: Icon(Icons.broken_image, size: Responsive.getIconSize(context, mobile: 48), color: Colors.grey),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 16)),
              ],
              if (idBackPhotoUrl != null && idBackPhotoUrl!.isNotEmpty) ...[
                Text(
                  'Back Side:',
                  style: TextStyle(
                    fontSize: Responsive.getFontSize(context, mobile: 14),
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: Responsive.getHeight(context, mobile: 8)),
                GestureDetector(
                  onTap: () => _showImageFullScreen(context, idBackPhotoUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Responsive.getBorderRadius(context, mobile: 8)),
                    child: SizedBox(
                      width: double.infinity,
                      height: Responsive.getHeight(context, mobile: 200),
                      child: Image.network(
                        _fixIdImageUrl(idBackPhotoUrl!),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: Responsive.getHeight(context, mobile: 200),
                            color: Colors.grey[200],
                            child: Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: Responsive.getHeight(context, mobile: 200),
                            color: Colors.grey[200],
                            child: Center(
                              child: Icon(Icons.broken_image, size: Responsive.getIconSize(context, mobile: 48), color: Colors.grey),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ],
            ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}