import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors table-session state to Supabase so a scheduled Edge Function
/// (see supabase/functions/auto-end-sessions) can auto-end sessions even
/// when the customer's app is fully closed — the client-side timer in
/// CustomerHomeScreen only runs while the app is open, this is the
/// backend backstop for that.
///
/// Row id == the same sessionId used everywhere else (TableSessionProvider,
/// orders). `last_order_at` resets every time a new order is placed;
/// `active` flips false once the Edge Function decides the session is
/// done (all orders finished + 5 min idle) or the customer taps "Selesai".
class SessionRepository {
  final _client = Supabase.instance.client;

  /// [tableNumber] is null when the customer entered by picking a
  /// restaurant from the list (no QR scan) — it gets filled in later via
  /// [setTableNumber], mandatorily, at checkout.
  Future<void> upsertActive({
    required String sessionId,
    required String restoId,
    String? tableNumber,
  }) async {
    await _client.from('sessions').upsert({
      'id': sessionId,
      'resto_id': restoId,
      'table_number': tableNumber,
      'active': true,
      'last_order_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Fills in the table number for a session that started without one
  /// (picked a resto from the list instead of scanning) — called once,
  /// mandatorily, at checkout.
  Future<void> setTableNumber(String sessionId, String tableNumber) async {
    await _client.from('sessions').update({'table_number': tableNumber}).eq('id', sessionId);
  }

  /// Called every time a new order is placed in this session — resets the
  /// "5 minutes idle" clock the Edge Function checks against.
  Future<void> touchLastOrder(String sessionId) async {
    await _client.from('sessions').update({
      'last_order_at': DateTime.now().toUtc().toIso8601String(),
      'active': true,
    }).eq('id', sessionId);
  }

  Future<void> setActive(String sessionId, bool active) async {
    await _client.from('sessions').update({'active': active}).eq('id', sessionId);
  }

  /// Live "is this session still active" flag — the customer app listens
  /// to this so a session ended remotely (by the Edge Function) reflects
  /// immediately in the UI too, not just ones ended locally.
  Stream<bool> watchActive(String sessionId) {
    return _client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((rows) => rows.isEmpty ? false : (rows.first['active'] as bool? ?? false));
  }
}
