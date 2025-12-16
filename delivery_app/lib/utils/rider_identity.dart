import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class RiderIdentity {
  static Future<String?> resolveEffectiveRiderId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    // Prefer a rider record key that matches the user's email (admin-created riders may not match auth uid)
    try {
      final email = user.email;
      if (email != null && email.isNotEmpty) {
        final snap = await FirebaseDatabase.instance
            .ref('riders')
            .orderByChild('email')
            .equalTo(email)
            .limitToFirst(1)
            .get();
        if (snap.exists && snap.children.isNotEmpty) {
          return snap.children.first.key;
        }
      }
    } catch (_) {}

    // Fallback to auth uid
    return user.uid;
  }
}
