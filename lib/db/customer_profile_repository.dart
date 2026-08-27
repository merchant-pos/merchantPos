import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_profile.dart';

/// Stores a logged-in customer's profile (name, phone, photo), keyed by
/// their lowercased email — filled in once, right after their first
/// login, via [CustomerProfileScreen], and editable anytime afterward.
///
/// The photo is stored as base64 directly in the `customers` row rather
/// than a separate object-storage bucket.
class CustomerProfileRepository {
  final _client = Supabase.instance.client;

  Future<CustomerProfile?> getOnce(String email) async {
    final rows =
        await _client.from('customers').select().eq('email', email.toLowerCase()).limit(1);
    if (rows.isEmpty) return null;
    return CustomerProfile.fromMap(email, rows.first);
  }

  Future<void> save(CustomerProfile profile) async {
    await _client.from('customers').upsert({
      'email': profile.email.toLowerCase(),
      ...profile.toMap(),
    });
  }
}
