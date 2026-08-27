import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores merchant-configurable payment info (QRIS identity + bank account
/// used on the Transfer screen). Persisted locally with SharedPreferences
/// so the employee app works fully offline, and mirrored to a
/// per-restaurant Supabase row (`settings` table, id = restoId) so the
/// customer app — a separate install/device — shows the right
/// restaurant's QRIS info at checkout.
class SettingsProvider extends ChangeNotifier {
  static const _kMerchantName = 'settings_merchant_name';
  static const _kQrisId = 'settings_qris_id';
  static const _kBankName = 'settings_bank_name';
  static const _kAccountNumber = 'settings_account_number';
  static const _kAccountHolder = 'settings_account_holder';

  String merchantName = 'Toko Kamu';
  String qrisId = 'ID12345678901';
  String bankName = 'Bank Dummy Indonesia (BDI)';
  String accountNumber = '1234 5678 9099';
  String accountHolder = 'a.n. Toko Kamu';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    merchantName = prefs.getString(_kMerchantName) ?? merchantName;
    qrisId = prefs.getString(_kQrisId) ?? qrisId;
    bankName = prefs.getString(_kBankName) ?? bankName;
    accountNumber = prefs.getString(_kAccountNumber) ?? accountNumber;
    accountHolder = prefs.getString(_kAccountHolder) ?? accountHolder;
    notifyListeners();
  }

  Future<void> save({
    required String restoId,
    required String merchantName,
    required String qrisId,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMerchantName, merchantName);
    await prefs.setString(_kQrisId, qrisId);
    await prefs.setString(_kBankName, bankName);
    await prefs.setString(_kAccountNumber, accountNumber);
    await prefs.setString(_kAccountHolder, accountHolder);

    this.merchantName = merchantName;
    this.qrisId = qrisId;
    this.bankName = bankName;
    this.accountNumber = accountNumber;
    this.accountHolder = accountHolder;
    notifyListeners();

    // Best-effort mirror to Supabase for the customer app. Skipped
    // silently if there's no internet right now.
    try {
      await Supabase.instance.client.from('settings').upsert({
        'resto_id': restoId,
        'merchant_name': merchantName,
        'qris_id': qrisId,
        'bank_name': bankName,
        'account_number': accountNumber,
        'account_holder': accountHolder,
      });
    } catch (_) {}
  }
}
