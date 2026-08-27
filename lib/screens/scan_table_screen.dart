import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/table_session_provider.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/required_label.dart';
import '../utils/tautan_meja.dart';

/// Required before a customer can order: scan the QR code printed/shown
/// at their table. The dummy QR codes encode "RESTO:<restoId>|TABLE:<n>"
/// — see [TableQrGeneratorScreen] for generating them.
class ScanTableScreen extends StatefulWidget {
  const ScanTableScreen({super.key});

  @override
  State<ScanTableScreen> createState() => _ScanTableScreenState();
}

class _ScanTableScreenState extends State<ScanTableScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    // Dua bentuk diterima: tautan web yang dipakai stiker baru, dan
    // teks lama yang masih tertempel di meja-meja yang tercetak
    // sebelumnya. Lihat bacaTautanMeja.
    final meja = bacaTautanMeja(raw);
    if (meja == null) {
      setState(() => _error = 'QR tidak dikenali: "$raw"');
      return;
    }

    _handled = true;
    await context
        .read<TableSessionProvider>()
        .setTable(meja.restoId, meja.meja);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _enterManually() async {
    final restoCtrl = TextEditingController();
    final tableCtrl = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Input Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: restoCtrl,
              decoration: InputDecoration(label: requiredLabel('Merchant ID')),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tableCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                label: requiredLabel('Nomor Meja'),
                hintText: 'Contoh: 7 atau A01',
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'OK',
            onCancel: () => Navigator.pop(context),
            onConfirm: () {
              final resto = restoCtrl.text.trim();
              final table = tableCtrl.text.trim();
              if (resto.isEmpty || table.isEmpty) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context, (resto, table));
            },
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await context.read<TableSessionProvider>().setTable(result.$1, result.$2);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Meja'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Input manual',
            onPressed: _enterManually,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Arahkan kamera ke QR code di meja kamu.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
