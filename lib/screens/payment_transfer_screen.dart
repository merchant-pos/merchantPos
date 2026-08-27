import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/app_toast.dart';

/// Dummy bank-transfer payment screen. Shows the merchant's configured
/// account number (see Settings) so the cashier can "share" it with the
/// customer. Nothing here is a real bank account by default.
class PaymentTransferScreen extends StatelessWidget {
  final int amount;

  const PaymentTransferScreen({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Bayar dengan Transfer')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currency.format(amount),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(settings.bankName,
                        style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          settings.accountNumber,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Salin nomor rekening',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: settings.accountNumber.replaceAll(' ', '')));
                            showAppToast(context, 'Nomor rekening disalin');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(settings.accountHolder,
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '(Rekening dummy — belum terhubung ke rekening bank sungguhan)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Simulasikan: Sudah Transfer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }
}
