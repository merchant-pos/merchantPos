import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/session_repository.dart';

/// Tracks the customer's current restaurant + table (scanned from the
/// table's QR code, which encodes both) and a session id that acts as
/// the "parent" for every order they place afterward — this is how they
/// can track order status without an account: every order carries this
/// same sessionId, and the status screen just queries orders where
/// sessionId == this value.
///
/// Also tracks a permanent per-device id ("deviceId") that stands in for
/// a real JWT/auth token here — this app has no account system for
/// customers, so instead of verifying a signed token we just check
/// whether this same device (i.e. same local storage) is scanning the
/// same table again. That's enough to answer "is this the same customer
/// coming back?" without needing a backend auth server.
///
/// A session can be explicitly ended (button), time out automatically
/// while the app is open (once every order in it is done and 5 minutes
/// pass with no new order — see [CustomerHomeScreen]'s watcher), or be
/// ended by the backend Cloud Function even if the app is fully closed
/// (see functions/index.js) — the same 5-minute rule, enforced
/// server-side via [SessionRepository]. Ending a session does NOT wipe
/// the table/session data — it just flips [sessionActive] to false, so
/// if the *same device* scans the *same table* again afterward, the old
/// session resumes (their order history stays visible). Scanning a
/// different table, or a different device scanning at all (no local
/// cache), always starts a brand-new session.
class TableSessionProvider extends ChangeNotifier {
  static const _kRestoId = 'table_session_resto_id';
  // Deliberately a different key from the int-typed one older builds
  // wrote: SharedPreferences would throw reading that back as a String.
  // The old key is cleaned up in [load].
  static const _kTableNumber = 'table_session_label';
  static const _kLegacyTableNumberInt = 'table_session_number';
  static const _kSessionId = 'table_session_id';
  static const _kSessionActive = 'table_session_active';
  static const _kEnteredViaQr = 'table_session_entered_via_qr';
  final _uuid = const Uuid();
  final _sessionRepo = SessionRepository();

  String? restoId;

  /// Free-form label, not a number — restaurants use things like "A01"
  /// or "VIP-2" as often as "7".
  String? tableNumber;
  String? sessionId;
  bool sessionActive = false;
  bool loaded = false;

  /// True if this session started from scanning a table QR code, false
  /// if it started from picking a restaurant off the list instead.
  /// [CustomerHomeScreen] only offers a "Ganti Resto" menu for the
  /// latter — switching restos mid-QR-session doesn't make sense since
  /// the table itself is tied to one resto.
  bool enteredViaQr = false;

  bool get hasActiveTable =>
      restoId != null && tableNumber != null && sessionId != null && sessionActive;

  /// True once a resto is picked, with or without a table number yet —
  /// covers both entry paths (QR scan, which always has a table; or
  /// picking from the restaurant list, which doesn't until checkout).
  /// [CustomerHomeScreen] gates browsing on this instead of
  /// [hasActiveTable], so browsing-without-a-table works.
  bool get hasActiveResto => restoId != null && sessionId != null && sessionActive;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    restoId = prefs.getString(_kRestoId);
    tableNumber = prefs.getString(_kTableNumber);
    if (tableNumber == null && prefs.containsKey(_kLegacyTableNumberInt)) {
      // Upgrading from a build that stored this as an int — carry the
      // value over once, then drop the old key.
      tableNumber = prefs.getInt(_kLegacyTableNumberInt)?.toString();
      if (tableNumber != null) await prefs.setString(_kTableNumber, tableNumber!);
      await prefs.remove(_kLegacyTableNumberInt);
    }
    sessionId = prefs.getString(_kSessionId);
    sessionActive = prefs.getBool(_kSessionActive) ?? false;
    enteredViaQr = prefs.getBool(_kEnteredViaQr) ?? false;
    loaded = true;
    notifyListeners();
  }

  /// Called right after a successful table QR scan.
  ///
  /// If this exact device previously had a session at this exact
  /// restaurant+table (even one that was ended), that session resumes —
  /// same sessionId, so their order history is still there. Otherwise
  /// (different table, or nothing cached yet) a brand-new session id is
  /// generated.
  Future<void> setTable(String restoId, String table) async {
    final prefs = await SharedPreferences.getInstance();

    final isSameDeviceSameTable =
        this.restoId == restoId && tableNumber == table && sessionId != null;

    this.restoId = restoId;
    tableNumber = table;
    sessionId = isSameDeviceSameTable ? sessionId : _uuid.v4();
    sessionActive = true;
    enteredViaQr = true;

    await prefs.setString(_kRestoId, restoId);
    await prefs.setString(_kTableNumber, table);
    await prefs.setString(_kSessionId, sessionId!);
    await prefs.setBool(_kSessionActive, true);
    await prefs.setBool(_kEnteredViaQr, true);
    notifyListeners();

    // Mirror to Firestore so the Cloud Function (and the customer's own
    // "Pesanan Saya" watcher) sees this session as active again. Skipped
    // silently if offline.
    _sessionRepo
        .upsertActive(sessionId: sessionId!, restoId: restoId, tableNumber: table)
        .catchError((_) {});
  }

  /// Called when a customer picks a restaurant from the list instead of
  /// scanning a table QR — same idea as [setTable] but with no table
  /// number yet (it's mandatory at checkout instead, see
  /// [setTableNumber]).
  Future<void> setResto(String restoId) async {
    final prefs = await SharedPreferences.getInstance();

    final isSameDeviceSameResto =
        this.restoId == restoId && tableNumber == null && sessionId != null;

    this.restoId = restoId;
    tableNumber = null;
    sessionId = isSameDeviceSameResto ? sessionId : _uuid.v4();
    sessionActive = true;
    enteredViaQr = false;

    await prefs.setString(_kRestoId, restoId);
    await prefs.remove(_kTableNumber);
    await prefs.setString(_kSessionId, sessionId!);
    await prefs.setBool(_kSessionActive, true);
    await prefs.setBool(_kEnteredViaQr, false);
    notifyListeners();

    _sessionRepo
        .upsertActive(sessionId: sessionId!, restoId: restoId)
        .catchError((_) {});
  }

  /// Fills in the table number for a session that started without one
  /// (picked from the restaurant list) — mandatory at checkout, entered
  /// once and then greyed out/read-only from then on, same as a QR-scan
  /// session.
  Future<void> setTableNumber(String table) async {
    final prefs = await SharedPreferences.getInstance();
    tableNumber = table;
    await prefs.setString(_kTableNumber, table);
    notifyListeners();

    if (sessionId != null) {
      _sessionRepo.setTableNumber(sessionId!, table).catchError((_) {});
    }
  }

  /// Ends the current session (via the "Selesai" button, or the local
  /// 5-minute auto-end timer). Table/session data stays cached so the
  /// same device can resume by rescanning the same table.
  Future<void> endSession() async {
    if (!sessionActive) return;
    final prefs = await SharedPreferences.getInstance();
    sessionActive = false;
    await prefs.setBool(_kSessionActive, false);
    notifyListeners();

    if (sessionId != null) {
      _sessionRepo.setActive(sessionId!, false).catchError((_) {});
    }
  }

  /// Applies a session-ended signal that came from Firestore (i.e. the
  /// backend Cloud Function decided to end it, not this device) — updates
  /// local state to match without writing back to Firestore again.
  Future<void> applyRemoteEnded() async {
    if (!sessionActive) return;
    final prefs = await SharedPreferences.getInstance();
    sessionActive = false;
    await prefs.setBool(_kSessionActive, false);
    notifyListeners();
  }

  /// Hard reset — wipes everything, including the cached table/session,
  /// so even the same device scanning the same table starts fully fresh
  /// (a fresh scan, no resumed order history). Called on customer
  /// logout, so logging out means logging out of both the account and
  /// the table — resuming after that always requires scanning again.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRestoId);
    await prefs.remove(_kTableNumber);
    await prefs.remove(_kSessionId);
    await prefs.remove(_kSessionActive);
    await prefs.remove(_kEnteredViaQr);
    restoId = null;
    tableNumber = null;
    sessionId = null;
    sessionActive = false;
    enteredViaQr = false;
    notifyListeners();
  }
}
