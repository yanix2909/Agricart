import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class DeliveryFeeService {
  /// Get delivery fee for a specific barangay
  /// Returns the fee amount or 0 if barangay not found or service unavailable
  static Future<double> getDeliveryFeeForBarangay(String barangayName) async {
    try {
      // Ensure Supabase is initialized
      await SupabaseService.initialize();
      final supabase = SupabaseService.client;
      
      // Convert barangay name to column name (matching SQL table structure)
      final columnName = _barangayNameToColumnName(barangayName);
      
      print('🚚 Looking up delivery fee for: "$barangayName" (column: "$columnName")');
      
      // Fetch the delivery_fees row (id=1)
      final response = await supabase
          .from('delivery_fees')
          .select(columnName)
          .eq('id', 1)
          .single();
      
      if (response == null || response[columnName] == null) {
        print('🚚 No delivery fee found for barangay: $barangayName (column: $columnName)');
        return 0.0; // No delivery available to this barangay
      }
      
      final fee = response[columnName];
      final feeAmount = (fee is num) ? fee.toDouble() : (double.tryParse(fee.toString()) ?? 0.0);
      
      print('🚚 Delivery fee for $barangayName: ₱$feeAmount');
      return feeAmount;
      
    } catch (e) {
      print('🚚 Error fetching delivery fee for $barangayName: $e');
      return 0.0; // Default to no delivery if error occurs
    }
  }
  
  /// Convert barangay name to SQL column name
  /// This matches the column names in the Supabase delivery_fees table
  static String _barangayNameToColumnName(String barangayName) {
    if (barangayName.isEmpty) return '';
    
    // Handle specific mappings FIRST (before sanitization) for barangays with special names
    final specialMappings = {
      'Bagong (also Bagongbong)': 'bagong_also_bagongbong',
      'bagong (also bagongbong)': 'bagong_also_bagongbong',
      'Bagongbong': 'bagong_also_bagongbong',  // Handle shortened name
      'bagongbong': 'bagong_also_bagongbong',  // Handle shortened name lowercase
      'Barangay 1 (Poblacion South)': 'barangay_1_poblacion_south',
      'barangay 1 (poblacion south)': 'barangay_1_poblacion_south',
      'Barangay 2 (Poblacion South)': 'barangay_2_poblacion_south',
      'barangay 2 (poblacion south)': 'barangay_2_poblacion_south',
      'Barangay 3 (Poblacion South)': 'barangay_3_poblacion_south',
      'barangay 3 (poblacion south)': 'barangay_3_poblacion_south',
      'Barangay 4 (Poblacion South)': 'barangay_4_poblacion_south',
      'barangay 4 (poblacion south)': 'barangay_4_poblacion_south',
      'Barangay 5 (Poblacion South)': 'barangay_5_poblacion_south',
      'barangay 5 (poblacion south)': 'barangay_5_poblacion_south',
      'Barangay 6 (Poblacion South)': 'barangay_6_poblacion_south',
      'barangay 6 (poblacion south)': 'barangay_6_poblacion_south',
      'Barangay 7 (Poblacion South)': 'barangay_7_poblacion_south',
      'barangay 7 (poblacion south)': 'barangay_7_poblacion_south',
      'Barangay 8 (Poblacion South)': 'barangay_8_poblacion_south',
      'barangay 8 (poblacion south)': 'barangay_8_poblacion_south',
      'Barangay 9 (Poblacion South)': 'barangay_9_poblacion_south',
      'barangay 9 (poblacion south)': 'barangay_9_poblacion_south',
      'Barangay 10 (Poblacion South)': 'barangay_10_poblacion_south',
      'barangay 10 (poblacion south)': 'barangay_10_poblacion_south',
      'Barangay 11 (Poblacion North)': 'barangay_11_poblacion_north',
      'barangay 11 (poblacion north)': 'barangay_11_poblacion_north',
      'Barangay 12 (Poblacion North)': 'barangay_12_poblacion_north',
      'barangay 12 (poblacion north)': 'barangay_12_poblacion_north',
      'Barangay 13 (Poblacion North)': 'barangay_13_poblacion_north',
      'barangay 13 (poblacion north)': 'barangay_13_poblacion_north',
      'Barangay 14 (Poblacion North)': 'barangay_14_poblacion_north',
      'barangay 14 (poblacion north)': 'barangay_14_poblacion_north',
      'Barangay 15 (Poblacion North)': 'barangay_15_poblacion_north',
      'barangay 15 (poblacion north)': 'barangay_15_poblacion_north',
      'Barangay 16 (Poblacion North)': 'barangay_16_poblacion_north',
      'barangay 16 (poblacion north)': 'barangay_16_poblacion_north',
      'Barangay 17 (Poblacion North)': 'barangay_17_poblacion_north',
      'barangay 17 (poblacion north)': 'barangay_17_poblacion_north',
      'Barangay 18 (Poblacion North)': 'barangay_18_poblacion_north',
      'barangay 18 (poblacion north)': 'barangay_18_poblacion_north',
      'Barangay 19 (Poblacion North)': 'barangay_19_poblacion_north',
      'barangay 19 (poblacion north)': 'barangay_19_poblacion_north',
      'Barangay 20 (Poblacion North)': 'barangay_20_poblacion_north',
      'barangay 20 (poblacion north)': 'barangay_20_poblacion_north',
      'Barangay 21 (Poblacion East)': 'barangay_21_poblacion_east',
      'barangay 21 (poblacion east)': 'barangay_21_poblacion_east',
      'Barangay 22 (Poblacion East)': 'barangay_22_poblacion_east',
      'barangay 22 (poblacion east)': 'barangay_22_poblacion_east',
      'Barangay 23 (Poblacion East)': 'barangay_23_poblacion_east',
      'barangay 23 (poblacion east)': 'barangay_23_poblacion_east',
      'Barangay 24 (Poblacion East)': 'barangay_24_poblacion_east',
      'barangay 24 (poblacion east)': 'barangay_24_poblacion_east',
      'Barangay 25 (Poblacion East)': 'barangay_25_poblacion_east',
      'barangay 25 (poblacion east)': 'barangay_25_poblacion_east',
      'Barangay 26 (Poblacion West)': 'barangay_26_poblacion_west',
      'barangay 26 (poblacion west)': 'barangay_26_poblacion_west',
      'Barangay 27 (Poblacion West)': 'barangay_27_poblacion_west',
      'barangay 27 (poblacion west)': 'barangay_27_poblacion_west',
      'Barangay 28 (Poblacion West)': 'barangay_28_poblacion_west',
      'barangay 28 (poblacion west)': 'barangay_28_poblacion_west',
      'Barangay 29 (Poblacion West)': 'barangay_29_poblacion_west',
      'barangay 29 (poblacion west)': 'barangay_29_poblacion_west',
      'Labrador (Balion)': 'labrador_balion',
      'labrador (balion)': 'labrador_balion',
      'Don Felipe Larrazabal': 'don_felipe_larrazabal',
      'don felipe larrazabal': 'don_felipe_larrazabal',
      'Don Potenciano Larrazabal': 'don_potenciano_larrazabal',
      'don potenciano larrazabal': 'don_potenciano_larrazabal',
      'Doña Feliza Z. Mejia': 'dona_feliza_z_mejia',
      'doña feliza z. mejia': 'dona_feliza_z_mejia',
      'San Pablo (Simangan)': 'san_pablo_simangan',
      'san pablo (simangan)': 'san_pablo_simangan',
      'Quezon, Jr.': 'quezon_jr',
      'quezon, jr.': 'quezon_jr',
      'Rufina M. Tan': 'rufina_m_tan',
      'rufina m. tan': 'rufina_m_tan'
    };
    
    // Check if there's a direct mapping first
    if (specialMappings.containsKey(barangayName)) {
      return specialMappings[barangayName]!;
    }
    
    // Convert to lowercase and replace spaces/special chars with underscores
    String columnName = barangayName
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')           // Replace spaces with underscores
        .replaceAll(RegExp(r'[()]'), '')            // Remove parentheses
        .replaceAll(RegExp(r'[.,]'), '')            // Remove periods and commas
        .replaceAll('-', '_')                       // Replace hyphens with underscores
        .replaceAll("'", '')                        // Remove apostrophes
        .replaceAll('ñ', 'n')                       // Replace ñ with n
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')      // Remove any other special characters
        .replaceAll(RegExp(r'_+'), '_')              // Replace multiple underscores with single
        .replaceAll(RegExp(r'^_|_$'), '');          // Remove leading/trailing underscores
    
    // Check if there's a special mapping for the sanitized name
    if (specialMappings.containsKey(columnName)) {
      return specialMappings[columnName]!;
    }
    
    return columnName;
  }
  
  /// Extract barangay name from a full address string
  /// This handles various address formats and extracts the barangay part
  static String extractBarangayFromAddress(String address) {
    if (address.isEmpty) return '';
    
    print('🔍 Parsing address: $address');
    
    // Split address by commas and clean each part
    final parts = address.split(',').map((part) => part.trim()).toList();
    print('🔍 Address parts: $parts');
    
    // Look for barangay patterns in the address parts
    for (final part in parts) {
      final cleanPart = part.toLowerCase();
      print('🔍 Checking part: "$part" (clean: "$cleanPart")');
      
      // Check if this part looks like a barangay name
      if (_isBarangayName(cleanPart)) {
        print('✅ Found barangay: $part');
        return part.trim(); // Return original case
      }
    }
    
    // If no clear barangay found, try to extract from common patterns
    final extracted = _extractBarangayFromPatterns(address);
    print('🔍 Extracted from patterns: $extracted');
    return extracted;
  }
  
  /// Check if a string looks like a barangay name
  static bool _isBarangayName(String text) {
    final barangayPatterns = [
      'barangay',
      'brgy',
      'poblacion',
      'airport',
      'alta vista',
      'bagong',
      'bantigue',
      'batuan',
      'bayog',
      'biliboy',
      'borok',
      'cabaon-an',
      'cabintan',
      'cabulihan',
      'cagbuhangin',
      'camp downes',
      'can-adieng',
      'can-untog',
      'candugay',
      'catmon',
      'cogon',
      'concepcion',
      'curva',
      'dolores',
      'domonar',
      'donghol',
      'esperanza',
      'gaas',
      'green valley',
      'guintigui-an',
      'hugpa',
      'ibabao',
      'jabonga',
      'jagobiao',
      'kabankalan',
      'kabongaan',
      'labog',
      'lahug',
      'libas',
      'liberty',
      'liloan',
      'linao',
      'luna',
      'macabug',
      'magasang',
      'mahatma gandhi',
      'malbasag',
      'mas-in',
      'matter',
      'milagro',
      'montebello',
      'naungan',
      'naval',
      'patag',
      'punta',
      'rio de janeiro',
      'san antonio',
      'san isidro',
      'san jose',
      'san juan',
      'santo niño',
      'sumangga',
      'tambulilid',
      'tongonan',
      'valencia',
      'villa paz',
    ];
    
    // Check if text contains any barangay pattern
    for (final pattern in barangayPatterns) {
      if (text.contains(pattern)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Extract barangay from common address patterns
  static String _extractBarangayFromPatterns(String address) {
    final cleanAddress = address.toLowerCase();
    
    // Pattern 1: "Barangay X" or "Brgy X"
    final barangayMatch = RegExp(r'(barangay|brgy)\s+(\d+|[a-z\s]+)', caseSensitive: false)
        .firstMatch(cleanAddress);
    if (barangayMatch != null) {
      return address.substring(barangayMatch.start, barangayMatch.end).trim();
    }
    
    // Pattern 2: Look for common barangay names
    final commonBarangays = [
      'airport', 'alta vista', 'bagong', 'bantigue', 'batuan', 'bayog',
      'biliboy', 'borok', 'cabaon-an', 'cabintan', 'cabulihan', 'cagbuhangin',
      'camp downes', 'can-adieng', 'can-untog', 'candugay', 'catmon', 'cogon',
      'concepcion', 'curva', 'dolores', 'domonar', 'donghol', 'esperanza',
      'gaas', 'green valley', 'guintigui-an', 'hugpa', 'ibabao', 'jabonga',
      'jagobiao', 'kabankalan', 'kabongaan', 'labog', 'lahug', 'libas',
      'liberty', 'liloan', 'linao', 'luna',       'macabug', 'magasang',
      'mahatma gandhi', 'malbasag', 'margen', 'mas-in', 'matter', 'milagro', 'montebello',
      'naungan', 'naval', 'patag', 'punta', 'rio de janeiro', 'san antonio',
      'san isidro', 'san jose', 'san juan', 'santo niño', 'sumangga',
      'tambulilid', 'tongonan', 'valencia', 'villa paz'
    ];
    
    for (final barangay in commonBarangays) {
      if (cleanAddress.contains(barangay)) {
        // Find the original case version in the address
        final index = cleanAddress.indexOf(barangay);
        final endIndex = index + barangay.length;
        
        // Try to find word boundaries
        final startIndex = index;
        final originalText = address.substring(startIndex, endIndex);
        return originalText.trim();
      }
    }
    
    // If no pattern matches, return empty string
    return '';
  }
  
  
  /// Check if delivery is available to a specific barangay
  /// Returns true if delivery fee > 0, false otherwise
  static Future<bool> isDeliveryAvailable(String barangayName) async {
    final fee = await getDeliveryFeeForBarangay(barangayName);
    return fee > 0;
  }
  
  /// Get delivery fee with availability check
  /// Returns a map with fee amount and availability status
  static Future<Map<String, dynamic>> getDeliveryInfo(String barangayName) async {
    final fee = await getDeliveryFeeForBarangay(barangayName);
    return {
      'fee': fee,
      'available': fee > 0,
      'barangay': barangayName,
    };
  }
}
