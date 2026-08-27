import 'package:flutter/material.dart';

import '../db/customer_profile_repository.dart';
import '../db/guest_order_store.dart';
import '../db/order_repository.dart';
import '../screens/customer_profile_screen.dart';

/// After a customer's Google login succeeds, call this once — it checks
/// whether they've already filled in their profile (name/phone) before;
/// if not, it shows [CustomerProfileScreen] and waits for them to save.
/// If a profile already exists, this returns immediately (no-op).
///
/// Takes a [NavigatorState] rather than a BuildContext because the screen
/// that started the login is often torn down partway through it (a
/// logged-in customer makes RootScreen swap to CustomerHomeScreen), and
/// a NavigatorState stays valid where that context wouldn't.
Future<void> ensureCustomerProfile(NavigatorState navigator, String email) async {
  final existing = await CustomerProfileRepository().getOnce(email);
  if (existing != null || !navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute(builder: (_) => CustomerProfileScreen(email: email)),
  );
}

/// Offers this device's guest orders to the account that just signed in.
///
/// The server only accepts them when the email has never ordered before
/// (see supabase/claim_guest_orders.sql) — someone ordering as a guest
/// then signing in for the first time keeps their history, and it's now
/// tied to the account rather than the phone.
///
/// A returning customer gets nothing claimed, deliberately: their
/// account history and this device's guest history stay separate, and
/// the local list is left untouched so it reappears when they log out.
///
/// Returns how many orders moved across, for the caller to message.
/// Never throws — a failure here shouldn't block the login itself, it
/// just leaves the guest list where it was.
Future<int> claimGuestOrdersForLogin() async {
  final store = GuestOrderStore();
  try {
    final ids = await store.ids();
    if (ids.isEmpty) return 0;

    final claimed = await OrderRepository().claimGuestOrders(ids);
    // Only drop the local list once the orders genuinely belong to the
    // account — otherwise the guest would lose the only record they have.
    if (claimed > 0) await store.clear();
    return claimed;
  } catch (_) {
    return 0;
  }
}
