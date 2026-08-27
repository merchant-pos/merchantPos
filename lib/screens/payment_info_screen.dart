import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';

/// Admin's read-only look at the merchant's payment details (QRIS merchant +
/// bank account). Finance is the only role allowed to change these, so
/// there's deliberately no form here at all — disabled text fields just
/// look like something you ought to be able to type in. Plain detail rows
/// say "this is information" far more clearly.
class PaymentInfoScreen extends StatefulWidget {
  const PaymentInfoScreen({super.key});

  @override
  State<PaymentInfoScreen> createState() => _PaymentInfoScreenState();
}

class _PaymentInfoScreenState extends State<PaymentInfoScreen> {
  String _merchantName = '';
  String _qrisId = '';
  String _bankName = '';
  String _accountNumber = '';
  String _accountHolder = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Local cache first so there's no flash of empty rows, then refresh
    // from Supabase — Finance edits these on a different device.
    final s = context.read<SettingsProvider>();
    _merchantName = s.merchantName;
    _qrisId = s.qrisId;
    _bankName = s.bankName;
    _accountNumber = s.accountNumber;
    _accountHolder = s.accountHolder;
    _load();
  }

  Future<void> _load() async {
    try {
      final restoId = context.read<AuthProvider>().restoId!;
      final rows = await Supabase.instance.client
          .from('settings')
          .select()
          .eq('resto_id', restoId)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        final row = rows.first;
        setState(() {
          _merchantName = row['merchant_name'] as String? ?? _merchantName;
          _qrisId = row['qris_id'] as String? ?? _qrisId;
          _bankName = row['bank_name'] as String? ?? _bankName;
          _accountNumber = row['account_number'] as String? ?? _accountNumber;
          _accountHolder = row['account_holder'] as String? ?? _accountHolder;
        });
      }
    } catch (_) {
      // Offline — keep showing the local cache loaded above.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Info Pembayaran'),
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
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // QRIS tidak lagi diisi resto.
            //
            // Kodenya dibuat Xendit per transaksi, atas nama sub-akun
            // restonya — bukan dari ID merchant yang diketik di sini.
            // Menyisakan kolomnya berarti menawarkan setelan yang tidak
            // dipakai apa pun, dan yang mengisinya akan menunggu
            // hasilnya sia-sia.
            _InfoCard(
              icon: Icons.account_balance_outlined,
              color: const Color(0xFFEC4899),
              title: 'Transfer Bank',
              rows: [
                ('Nama Bank', _bankName),
                ('Nomor Rekening', _accountNumber),
                ('Atas Nama', _accountHolder),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: MerchantPosTheme.mutedOf(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Data ini hanya bisa diubah oleh Finance.',
                    style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<(String, String)> rows;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
          Divider(height: 1, color: MerchantPosTheme.softFillOf(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Column(
              children: [
                for (final (label, value) in rows) _DetailRow(label: label, value: value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
            ),
          ),
          Expanded(
            child: SelectableText(
              empty ? 'Belum diatur' : value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: empty ? FontWeight.normal : FontWeight.w600,
                color: empty ? MerchantPosTheme.mutedOf(context) : MerchantPosTheme.textOf(context),
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
