import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';

import '../utils/rupiah_input.dart';
import 'dialog_actions.dart';
import 'required_label.dart';
import '../utils/lebar_web.dart';

/// Menerima uang tunai dari pelanggan: total tagihannya, nominal yang
/// diserahkan, dan kembaliannya.
///
/// Dipakai dua tempat yang sebetulnya satu pekerjaan yang sama —
/// checkout kasir, dan pelunasan pesanan yang dipesan sendiri dari HP
/// lalu dibayar di meja kasir. Ditulis sekali supaya saran nominal dan
/// perhitungan kembaliannya tidak pelan-pelan berbeda di antara keduanya.
///
/// Mengembalikan nominal yang diterima, atau null kalau dibatalkan.
class CashPaymentDialog extends StatefulWidget {
  final int total;

  const CashPaymentDialog({super.key, required this.total});

  @override
  State<CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<CashPaymentDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _received {
    final n = parseRupiah(_ctrl.text);
    return (n != null && n > 0) ? n : null;
  }

  int? get _change {
    final r = _received;
    return r == null ? null : r - widget.total;
  }

  bool get _enough => _change != null && _change! >= 0;

  /// Exact money, then the next few round notes above the total —
  /// duplicates dropped so "uang pas" never repeats a suggestion.
  List<int> get _suggestions {
    final out = <int>{widget.total};
    for (final note in [5000, 10000, 20000, 50000, 100000]) {
      final rounded = ((widget.total / note).ceil()) * note;
      if (rounded > widget.total) out.add(rounded);
    }
    return out.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.payments_outlined, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pembayaran Tunai',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text('Masukkan uang yang diterima',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: MerchantPosTheme.softFillOf(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(currency.format(widget.total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                autofocus: true,
                decoration: InputDecoration(label: requiredLabel('Uang Diterima'), prefixText: 'Rp '),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in _suggestions)
                    ActionChip(
                      label: Text(amount == widget.total ? 'Uang pas' : currency.format(amount)),
                      onPressed: () => setState(() => _ctrl.text = formatRupiahInput(amount)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: (_enough ? const Color(0xFF10B981) : Colors.orange).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_enough ? 'Kembalian' : 'Kurang',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _enough ? const Color(0xFF0F766E) : Colors.orange.shade900)),
                    Text(
                      _change == null ? '-' : currency.format(_change!.abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: _enough ? const Color(0xFF0F766E) : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              DialogActions(
                confirmLabel: 'Terima Pembayaran',
                onConfirm: _enough ? () => Navigator.pop(context, _received) : null,
                onCancel: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
