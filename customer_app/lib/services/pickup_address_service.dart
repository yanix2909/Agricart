import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class PickupAddress {
  final String id;
  final String name;
  final String address; // Keep for backward compatibility
  final String? mapLink;
  final String? landmark;
  final String? instructions;
  final bool active;
  final DateTime? updatedAt;
  // New structured address fields
  final String? street;
  final String? sitio;
  final String? barangay;
  final String? city;
  final String? province;

  PickupAddress({
    required this.id,
    required this.name,
    required this.address,
    this.mapLink,
    this.landmark,
    this.instructions,
    this.active = false,
    this.updatedAt,
    this.street,
    this.sitio,
    this.barangay,
    this.city,
    this.province,
  });

  factory PickupAddress.fromMap(Map<String, dynamic> map, String id) {
    return PickupAddress(
      id: id,
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      mapLink: map['mapLink'] ?? map['map_link'], // Support both Firebase and Supabase field names
      landmark: map['landmark'],
      instructions: map['instructions'],
      active: map['active'] ?? false,
      updatedAt: map['updatedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] is int ? map['updatedAt'] : int.tryParse(map['updatedAt'].toString()) ?? 0)
          : (map['updated_at_timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['updated_at_timestamp'] is int ? map['updated_at_timestamp'] : int.tryParse(map['updated_at_timestamp'].toString()) ?? 0)
              : null),
      street: map['street'],
      sitio: map['sitio'],
      barangay: map['barangay'],
      city: map['city'],
      province: map['province'],
    );
  }
  
  /// Create from Supabase data format
  factory PickupAddress.fromSupabase(Map<String, dynamic> map) {
    return PickupAddress(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      mapLink: map['map_link'],
      landmark: map['landmark'],
      instructions: map['instructions'],
      active: map['active'] ?? false,
      updatedAt: map['updated_at_timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at_timestamp'] is int ? map['updated_at_timestamp'] : int.tryParse(map['updated_at_timestamp'].toString()) ?? 0)
          : (map['updated_at'] != null
              ? DateTime.parse(map['updated_at'].toString())
              : null),
      street: map['street'],
      sitio: map['sitio'],
      barangay: map['barangay'],
      city: map['city'],
      province: map['province'],
    );
  }

  /// Get formatted address string, preferring structured components over full address
  String getFormattedAddress() {
    // If we have structured address components, use them
    if (street != null || sitio != null || barangay != null) {
      final parts = <String>[];
      if (street?.isNotEmpty == true) parts.add(street!);
      if (sitio?.isNotEmpty == true) parts.add(sitio!);
      if (barangay?.isNotEmpty == true) parts.add(barangay!);
      if (city?.isNotEmpty == true) parts.add(city!);
      if (province?.isNotEmpty == true) parts.add(province!);
      return '${name} - ${parts.join(', ')}';
    }
    // Fallback to the old full address field
    return '${name} - ${address}';
  }

  @override
  String toString() {
    return 'PickupAddress(id: $id, name: $name, address: $address, active: $active)';
  }
}

class PickupAddressService {
  /// Get the currently active pickup address
  /// Returns null if no active pickup address is found
  static Future<PickupAddress?> getActivePickupAddress() async {
    try {
      print('🏪 Fetching active pickup address from Supabase...');
      
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      print('🏪 Querying pickup_area table for active pickup area...');
      final activeArea = await supabase
          .from('pickup_area')
          .select('*')
          .eq('active', true)
          .maybeSingle() as Map<String, dynamic>?;
      
      if (activeArea == null) {
        print('🏪 No active pickup area found in Supabase');
        return null;
      }
      
      final pickupAddress = PickupAddress.fromSupabase(activeArea);
      print('🏪 ✅ Active pickup address found: ${pickupAddress.name} - ${pickupAddress.address}');
      return pickupAddress;
      
    } catch (e) {
      print('🏪 ❌ Error fetching active pickup address: $e');
      return null;
    }
  }
  
   /// Listen to changes in the active pickup address
   /// Returns a stream that emits the current active pickup address
  static Stream<PickupAddress?> listenToActivePickupAddress() {
     print('🏪 Setting up real-time listener for pickup address changes from Supabase...');
     
     // Initialize Supabase asynchronously and create stream
     return Stream.fromFuture(SupabaseService.initialize())
         .asyncExpand((_) {
           final supabase = SupabaseService.client;
           return supabase
               .from('pickup_area')
               .stream(primaryKey: ['id'])
               .eq('active', true)
               .asyncMap((data) async {
                 if (data.isEmpty) {
                   print('🏪 🔄 Real-time: No active pickup area in Supabase');
                   return null;
                 }
                 final activeArea = data.first;
                 final pickupAddress = PickupAddress.fromSupabase(activeArea);
                 print('🏪 ✅ Real-time update: New active pickup address: ${pickupAddress.name} - ${pickupAddress.address}');
                 return pickupAddress;
               });
         })
         .handleError((e) {
           print('🏪 ❌ Supabase real-time error: $e');
           return null;
         });
   }
  
  
  /// Get all available pickup locations (for debugging or future use)
  static Future<List<PickupAddress>> getAllPickupLocations() async {
    try {
      print('🏪 Fetching all pickup locations from Supabase...');
      
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      final areas = await supabase
          .from('pickup_area')
          .select('*')
          .order('updated_at', ascending: false) as List;
      
      if (areas.isEmpty) {
        print('🏪 No pickup locations found in Supabase');
        return [];
      }
      
      final locations = areas.map((area) => PickupAddress.fromSupabase(area as Map<String, dynamic>)).toList();
      print('🏪 ✅ Found ${locations.length} pickup locations from Supabase');
      return locations;
      
    } catch (e) {
      print('🏪 ❌ Error fetching pickup locations: $e');
      return [];
    }
  }
}
