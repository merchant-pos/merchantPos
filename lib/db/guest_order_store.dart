import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which orders were placed on this device *without* logging
/// in, so a guest still gets an order history.
///
/// Only the order ids live here — the orders themselves stay in Supabase
/// and are re-fetched by id (the `orders` table allows public select), so
/// a guest's history shows live kitchen/payment status just like a
/// logged-in customer's does, instead of a frozen local snapshot.
///
/// Being device-local is the whole trade-off: clear the app's data or
/// switch phones and it's gone. That's what logging in is for — see
/// [CustomerHistoryScreen], which prefers the account-wide history
/// whenever an email is attached.
class GuestOrderStore {
  static const _key = 'guest_order_ids';

  /// Newest first, capped so a heavy user's list can't grow without
  /// bound — well past what anyone scrolls back through.
  static const _maxEntries = 100;

  Future<List<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  Future<void> add(String orderId) async {
    if (orderId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? <String>[];
    // Re-inserting an id it already knows would duplicate the row in the
    // history list, since the fetch is a plain `id in (...)`.
    existing.remove(orderId);
    final updated = [orderId, ...existing];
    if (updated.length > _maxEntries) updated.removeRange(_maxEntries, updated.length);
    await prefs.setStringList(_key, updated);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
