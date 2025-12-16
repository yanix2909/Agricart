import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/supabase_service.dart';
import '../utils/rider_session.dart';
import '../utils/theme.dart';
import '../utils/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  bool _updating = false;
  bool _loading = true;
  bool _isUploadingPhoto = false;
  String? _uid;
  bool _isOnline = false;
  RiderProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = await RiderSession.getId();
    setState(() { 
      _uid = id; 
    });
    
    if (id != null) {
      await _loadRiderData(id);
    } else {
      setState(() { _loading = false; });
    }
  }

  Future<void> _loadRiderData(String uid) async {
    try {
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }

      final supabase = SupabaseService.client;
      final response = await supabase
          .from('riders')
          .select('*')
          .eq('uid', uid)
          .maybeSingle();

      if (response != null && response.isNotEmpty) {
        setState(() {
          _profile = RiderProfile.fromMap(response);
          _isOnline = response['is_online'] == true;
          _loading = false;
        });
      } else {
        setState(() { _loading = false; });
      }
    } catch (e) {
      debugPrint('Error loading rider data: $e');
      setState(() { _loading = false; });
    }
  }

  Future<void> _toggleOnline(bool value) async {
    final uid = _uid;
    final profile = _profile;
    if (uid == null || profile == null) return;
    
    setState(() { _updating = true; });
    try {
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }

      final supabase = SupabaseService.client;
      final response = await supabase
          .from('riders')
          .update({'is_online': value})
          .eq('uid', uid)
          .select();

      if (response.isNotEmpty) {
        setState(() { 
          _isOnline = value; 
          _profile = profile.copyWith(isOnline: value);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update online status')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling online status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update online status: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() { _updating = false; });
    }
  }

  Future<void> _signOut() async {
    final uid = _uid;
    
    // Update is_online to false in Supabase before logging out
    if (uid != null) {
      try {
        if (SupabaseService.isInitialized) {
          final supabase = SupabaseService.client;
          await supabase
              .from('riders')
              .update({'is_online': false})
              .eq('uid', uid);
        }
      } catch (e) {
        debugPrint('Error updating online status on logout: $e');
        // Continue with logout even if update fails
      }
    }
    
    // Clear local session
    await RiderSession.clear();
    
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = _profile;
    if (profile == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Unable to load rider profile')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppTheme.backgroundColor),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroStack(profile),
              const SizedBox(height: 110),
              _buildSectionHeader('Personal Information'),
              _buildInfoCard([
                _buildInfoTile(Icons.person, 'Full Name', profile.fullName),
                _buildDivider(),
                _buildInfoTile(Icons.wc, 'Gender', profile.gender ?? 'Not provided'),
                _buildDivider(),
                _buildInfoTile(Icons.cake_outlined, 'Birth Date', _formatDate(profile.birthDate)),
              ]),
              const SizedBox(height: 24),
              _buildSectionHeader('Contact Details'),
              _buildInfoCard([
                _buildInfoTile(Icons.email_outlined, 'Email', profile.email),
                _buildDivider(),
                _buildInfoTile(Icons.phone_android, 'Phone Number', profile.phoneNumber),
              ]),
              const SizedBox(height: 24),
              _buildSectionHeader('Address'),
              _buildInfoCard([
                _buildInfoTile(Icons.location_on_outlined, 'Complete Address', _formatAddress(profile)),
                _buildDivider(),
                _buildInfoTile(Icons.map_outlined, 'Barangay', profile.barangay ?? 'Not provided'),
                _buildDivider(),
                _buildInfoTile(Icons.public, 'City / Province', '${profile.city}, ${profile.province}'),
                if ((profile.postalCode ?? '').isNotEmpty) ...[
                  _buildDivider(),
                  _buildInfoTile(Icons.markunread_mailbox_outlined, 'Postal Code', profile.postalCode ?? '—'),
                ],
              ]),
              const SizedBox(height: 24),
              _buildSectionHeader('Vehicle Information'),
              _buildInfoCard([
                _buildInfoTile(Icons.two_wheeler, 'Vehicle Type', profile.vehicleType ?? 'Not provided'),
                _buildDivider(),
                _buildInfoTile(Icons.confirmation_number_outlined, 'Vehicle Number', profile.vehicleNumber ?? 'Not provided'),
                _buildDivider(),
                _buildInfoTile(Icons.badge_outlined, 'License Number', profile.licenseNumber ?? 'Not provided'),
              ]),
              const SizedBox(height: 24),
              _buildSectionHeader('Identification'),
              _buildInfoCard([
                _buildInfoTile(
                  Icons.verified_user_outlined,
                  'ID Verification',
                  profile.idVerified ? 'Verified' : 'Pending verification',
                  trailingChip: _buildStatusChip(
                    label: profile.idVerified ? 'Verified' : 'Pending',
                    color: profile.idVerified ? Colors.green : Colors.orange,
                  ),
                ),
                _buildDivider(),
                _buildInfoTile(Icons.credit_card, 'ID Type', profile.idType ?? 'Not provided'),
                _buildDivider(),
                _buildInfoTile(Icons.numbers, 'ID Number', profile.idNumber ?? 'Not provided'),
              ]),
              const SizedBox(height: 24),
              _buildSectionHeader('Account'),
              _buildInfoCard([
                _buildInfoTile(
                  Icons.toggle_on,
                  'Availability',
                  _isOnline ? 'Online' : 'Offline',
                  trailing: Switch.adaptive(
                    value: _isOnline,
                    onChanged: _updating ? null : (value) => _toggleOnline(value),
                  ),
                ),
                _buildDivider(),
                _buildInfoTile(Icons.policy_outlined, 'Account Status', profile.status.capitalizeFirst()),
                _buildDivider(),
                _buildInfoTile(Icons.calendar_month_outlined, 'Joined AgriCart', _formatDate(profile.createdAt)),
              ]),
              const SizedBox(height: 32),
              _buildSignOutButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStack(RiderProfile profile) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildProfileHero(profile),
        Positioned(
          bottom: -70,
          left: 0,
          right: 0,
          child: _buildSummaryCard(profile),
        ),
      ],
    );
  }

  Widget _buildProfileHero(RiderProfile profile) {
    final tagline = profile.address.isNotEmpty
        ? profile.address
        : '${profile.city}, ${profile.province}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 110),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.96),
            AppTheme.primaryLightColor.withOpacity(0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.2),
            blurRadius: 28,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 3),
                    ),
                    child: ClipOval(
                      child: _buildProfilePhoto(profile),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: _buildPhotoActionButton(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            profile.fullName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            profile.email,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            tagline,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePhoto(RiderProfile profile) {
    if (_isUploadingPhoto) {
      return Container(
        color: Colors.white.withOpacity(0.1),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (profile.profilePhotoUrl.isNotEmpty) {
      return Image.network(
        profile.profilePhotoUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (_, __, ___) => _buildInitialsAvatar(profile),
      );
    }

    return _buildInitialsAvatar(profile);
  }

  Widget _buildInitialsAvatar(RiderProfile profile) {
    return Container(
      color: Colors.white.withOpacity(0.15),
      child: Center(
        child: Text(
          profile.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoActionButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isUploadingPhoto ? null : _changeProfilePhoto,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.camera_alt_outlined,
            size: 18,
            color: _isUploadingPhoto ? Colors.grey : AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(RiderProfile profile) {
    final stats = [
      _ProfileSummaryStat(
        label: 'Total Deliveries',
        value: profile.totalDeliveries.toString(),
        icon: Icons.local_shipping_outlined,
      ),
      _ProfileSummaryStat(
        label: 'Account Status',
        value: profile.status.capitalizeFirst(),
        icon: Icons.verified_outlined,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: stats.map((stat) {
          return Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(stat.icon, color: AppTheme.primaryColor),
                ),
                const SizedBox(height: 10),
                Text(
                  stat.value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stat.label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String label,
    String value, {
    Widget? trailing,
    Widget? trailingChip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? 'Not provided' : value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailingChip != null) ...[
            const SizedBox(width: 10),
            trailingChip,
          ],
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 0,
      thickness: 1,
      color: Colors.grey[200],
    );
  }

  Widget _buildStatusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSignOutButton() {
    return Container(
      margin: EdgeInsets.zero,
      width: double.infinity,
      color: Colors.white,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          alignment: Alignment.centerLeft,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        icon: Icon(Icons.logout, size: 22, color: AppTheme.errorColor),
        label: Text(
          'Sign Out',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.errorColor,
          ),
        ),
        onPressed: _signOut,
      ),
    );
  }

  Future<void> _changeProfilePhoto() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (picked == null) return;
      await _uploadProfilePhoto(File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to pick image: $e')),
      );
    }
  }

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadProfilePhoto(File file) async {
    final uid = _uid;
    final profile = _profile;
    if (uid == null || profile == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      if (!SupabaseService.isInitialized) {
        await SupabaseService.initialize();
      }

      final extension = file.path.split('.').last.toLowerCase();
      final normalizedExtension = ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ? extension : 'jpg';
      final fileName = 'rider_${_uid}_${DateTime.now().millisecondsSinceEpoch}.$normalizedExtension';

      final newUrl = await SupabaseService.uploadRiderProfilePicture(file, fileName);

      await SupabaseService.client
          .from('riders')
          .update({'profile_photo_url': newUrl})
          .eq('uid', uid);

      final previousUrl = profile.profilePhotoUrl;
      setState(() {
        _profile = profile.copyWith(profilePhotoUrl: newUrl);
      });

      if (previousUrl.isNotEmpty) {
        final path = _extractStoragePath(previousUrl);
        if (path != null) {
          await SupabaseService.deleteRiderProfilePicture(path);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update photo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  String? _extractStoragePath(String url) {
    const marker = '/storage/v1/object/public/rider_profile/';
    final index = url.indexOf(marker);
    if (index == -1) return null;
    return url.substring(index + marker.length);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not provided';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  String _formatAddress(RiderProfile profile) {
    if (profile.address.isNotEmpty) return profile.address;
    final parts = [
      profile.street,
      profile.sitio,
      profile.barangay,
      profile.city,
      profile.province,
      profile.postalCode,
    ];
    final filtered = parts.where((value) => value != null && value!.isNotEmpty).map((e) => e!).toList();
    return filtered.isEmpty ? 'Not provided' : filtered.join(', ');
  }
}

class RiderProfile {
  final String uid;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String profilePhotoUrl;
  final String? gender;
  final DateTime? birthDate;
  final String? street;
  final String? sitio;
  final String? barangay;
  final String city;
  final String province;
  final String? postalCode;
  final String address;
  final String? vehicleType;
  final String? vehicleNumber;
  final String? licenseNumber;
  final String? idType;
  final String? idNumber;
  final bool idVerified;
  final bool isOnline;
  final bool isActive;
  final String status;
  final int totalDeliveries;
  final DateTime? createdAt;

  const RiderProfile({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.profilePhotoUrl,
    required this.gender,
    required this.birthDate,
    required this.street,
    required this.sitio,
    required this.barangay,
    required this.city,
    required this.province,
    required this.postalCode,
    required this.address,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.licenseNumber,
    required this.idType,
    required this.idNumber,
    required this.idVerified,
    required this.isOnline,
    required this.isActive,
    required this.status,
    required this.totalDeliveries,
    required this.createdAt,
  });

  factory RiderProfile.fromMap(Map<String, dynamic> map) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
      }
      return null;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return RiderProfile(
      uid: map['uid']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? 'Rider',
      email: map['email']?.toString() ?? '',
      phoneNumber: map['phone_number']?.toString() ?? 'Not provided',
      profilePhotoUrl: map['profile_photo_url']?.toString() ?? '',
      gender: map['gender']?.toString(),
      birthDate: parseTimestamp(map['birth_date']),
      street: map['street']?.toString(),
      sitio: map['sitio']?.toString(),
      barangay: map['barangay']?.toString(),
      city: map['city']?.toString() ?? '',
      province: map['province']?.toString() ?? '',
      postalCode: map['postal_code']?.toString(),
      address: map['address']?.toString() ?? '',
      vehicleType: map['vehicle_type']?.toString(),
      vehicleNumber: map['vehicle_number']?.toString(),
      licenseNumber: map['license_number']?.toString(),
      idType: map['id_type']?.toString(),
      idNumber: map['id_number']?.toString(),
      idVerified: map['id_verified'] == true,
      isOnline: map['is_online'] == true,
      isActive: map['is_active'] != false,
      status: map['status']?.toString() ?? 'pending',
      totalDeliveries: parseInt(map['total_deliveries']),
      createdAt: parseTimestamp(map['created_at']),
    );
  }

  RiderProfile copyWith({
    bool? isOnline,
    String? profilePhotoUrl,
  }) {
    return RiderProfile(
      uid: uid,
      fullName: fullName,
      email: email,
      phoneNumber: phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      gender: gender,
      birthDate: birthDate,
      street: street,
      sitio: sitio,
      barangay: barangay,
      city: city,
      province: province,
      postalCode: postalCode,
      address: address,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      licenseNumber: licenseNumber,
      idType: idType,
      idNumber: idNumber,
      idVerified: idVerified,
      isOnline: isOnline ?? this.isOnline,
      isActive: isActive,
      status: status,
      totalDeliveries: totalDeliveries,
      createdAt: createdAt,
    );
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.isEmpty) return 'R';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _ProfileSummaryStat {
  final String label;
  final String value;
  final IconData icon;

  const _ProfileSummaryStat({
    required this.label,
    required this.value,
    required this.icon,
  });
}

extension _StringCasingExtension on String {
  String capitalizeFirst() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
