import 'package:shared_preferences/shared_preferences.dart';

class RiderSession {
  static const _kId = 'rider_id';
  static const _kName = 'rider_name';
  static const _kEmail = 'rider_email';

  static Future<void> save({required String riderId, String? name, String? email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kId, riderId);
    if (name != null) await prefs.setString(_kName, name);
    if (email != null) await prefs.setString(_kEmail, email);
  }

  static Future<String?> getId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kId);
  }

  static Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kName);
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kId);
    await prefs.remove(_kName);
    await prefs.remove(_kEmail);
  }
}
