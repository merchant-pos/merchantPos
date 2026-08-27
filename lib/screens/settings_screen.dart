import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/edit_action_bar.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';

/// Payment settings (QRIS + bank transfer info) — Finance only, since
/// they're the only role allowed to change these. Admin gets
/// [PaymentInfoScreen] instead, a plain read-only detail view.
///
/// Opens read-only even for Finance: tapping "Edit" is what unlocks the
/// fields, so nothing can change just from opening the screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _qrisIdCtrl;
  late final TextEditingController _bankNameCtrl;
  late final TextEditingController _accountNumberCtrl;
  late final TextEditingController _accountHolderCtrl;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from this device's local cache first (instant, no flash of
    // empty fields), then refresh from Supabase below — the source of
    // truth, since Admin and Finance are very likely different devices.
    final s = context.read<SettingsProvider>();
    _merchantCtrl = TextEditingController(text: s.merchantName);
    _qrisIdCtrl = TextEditingController(text: s.qrisId);
    _bankNameCtrl = TextEditingController(text: s.bankName);
    _accountNumberCtrl = TextEditingController(text: s.accountNumber);
    _accountHolderCtrl = TextEditingController(text: s.accountHolder);
    _loadFromSupabase();
  }

  Future<void> _loadFromSupabase() async {
    try {
      final restoId = context.read<AuthProvider>().restoId!;
      final rows = await Supabase.instance.client
          .from('settings')
          .select()
          .eq('resto_id', restoId)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        final row = rows.first;
        _merchantCtrl.text = row['merchant_name'] as String? ?? _merchantCtrl.text;
        _qrisIdCtrl.text = row['qris_id'] as String? ?? _qrisIdCtrl.text;
        _bankNameCtrl.text = row['bank_name'] as String? ?? _bankNameCtrl.text;
        _accountNumberCtrl.text = row['account_number'] as String? ?? _accountNumberCtrl.text;
        _accountHolderCtrl.text = row['account_holder'] as String? ?? _accountHolderCtrl.text;
      }
    } catch (_) {
      // Offline — keep showing the local cache loaded above.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _qrisIdCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  /// Snapshot taken when Edit is tapped, so Batal can put every field
  /// back exactly as it was rather than leaving half-typed changes on
  /// screen looking saved.
  Map<String, String> _snapshot = const {};

  void _startEdit() {
    _snapshot = {
      'merchant': _merchantCtrl.text,
      'qrisId': _qrisIdCtrl.text,
      'bankName': _bankNameCtrl.text,
      'accountNumber': _accountNumberCtrl.text,
      'accountHolder': _accountHolderCtrl.text,
    };
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _merchantCtrl.text = _snapshot['merchant'] ?? '';
    _qrisIdCtrl.text = _snapshot['qrisId'] ?? '';
    _bankNameCtrl.text = _snapshot['bankName'] ?? '';
    _accountNumberCtrl.text = _snapshot['accountNumber'] ?? '';
    _accountHolderCtrl.text = _snapshot['accountHolder'] ?? '';
    // Drops any validation errors raised during the abandoned edit.
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = context.read<AuthProvider>().restoId!;
    setState(() => _saving = true);
    try {
      await context.read<SettingsProvider>().save(
            restoId: restoId,
            merchantName: _merchantCtrl.text.trim(),
            qrisId: _qrisIdCtrl.text.trim(),
            bankName: _bankNameCtrl.text.trim(),
            accountNumber: _accountNumberCtrl.text.trim(),
            accountHolder: _accountHolderCtrl.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      showAppToast(context, 'Pengaturan disimpan');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  /// [required] menambahkan bintang merah di belakang labelnya.
  ///
  /// Hanya saat sedang menyunting. Dalam keadaan hanya-lihat tidak ada
  /// yang bisa dikosongkan siapa pun, dan tanda wajib di sana cuma
  /// menandai hal yang tidak sedang diminta.
  InputDecoration _decoration(String label, {bool required = false}) {
    return InputDecoration(
      labelText: required && _editing ? null : label,
      label: required && _editing ? requiredLabel(label) : null,
      filled: !_editing,
      fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Pembayaran'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'QRIS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _merchantCtrl,
                enabled: _editing,
                decoration: _decoration('Nama Merchant', required: true),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    _editing ? validateName(v, label: 'Nama merchant') : null,
              ),
              // Kolom ID QRIS Merchant dihapus: kodenya dibuat Xendit
              // per transaksi atas nama sub-akun restonya. Nilainya
              // tetap disimpan apa adanya supaya data lama tidak
              // terhapus hanya karena kolomnya tidak lagi tampil.
              const SizedBox(height: 24),
              const Text(
                'Transfer Bank',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bankNameCtrl,
                enabled: _editing,
                decoration: _decoration('Nama Bank', required: true),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => _editing ? validateName(v, label: 'Nama bank') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberCtrl,
                enabled: _editing,
                decoration: _decoration('Nomor Rekening', required: true),
                keyboardType: TextInputType.number,
                inputFormatters: accountNumberFormatters,
                validator: (v) => _editing ? validateAccountNumber(v) : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountHolderCtrl,
                enabled: _editing,
                decoration: _decoration('Atas Nama (a.n. ...)', required: true),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    _editing ? validateName(v, label: 'Nama pemilik rekening') : null,
              ),
              const SizedBox(height: 24),
              if (_editing)
                EditActionBar(
                  onCancel: _cancelEdit,
                  onSave: _save,
                  saving: _saving,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
