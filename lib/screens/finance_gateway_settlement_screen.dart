import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/gateway_settlement_repository.dart';
import '../models/gateway_settlement.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/journal_detail_dialog.dart';
import '../widgets/responsive.dart';
import '../widgets/required_label.dart';
import '../utils/lebar_web.dart';

/// Mencatat dana payment gateway yang benar-benar cair ke rekening.
///
/// Pesanan QRIS dicatat lunas saat pelanggan membayar, tapi uangnya
/// masih ditahan penyedia dan baru dikirim sehari dua hari kemudian,
/// dikurangi potongan. Selama pencairannya tidak dicatat, GL QRIS terus
/// bertambah tanpa pernah cocok dengan mutasi bank mana pun — dan
/// selisihnya menumpuk tiap hari sampai tidak ada yang berani menutup
/// buku.
///
/// Yang dicatat di sini bukan pengajuan yang menunggu persetujuan
/// seperti setoran tunai. Finance sedang menyalin apa yang sudah
/// terjadi di rekening, jadi tidak ada yang perlu menyetujuinya.
class FinanceGatewaySettlementScreen extends StatefulWidget {
  const FinanceGatewaySettlementScreen({super.key});

  @override
  State<FinanceGatewaySettlementScreen> createState() =>
      _FinanceGatewaySettlementScreenState();
}

class _FinanceGatewaySettlementScreenState
    extends State<FinanceGatewaySettlementScreen> {
  final _repo = GatewaySettlementRepository();
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<GatewaySettlement> _items = [];
  bool _loading = true;
  String? _error;

  String get _restoId => context.read<AuthProvider>().restoId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_restoId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.getForResto(_restoId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddSettlementDialog(restoId: _restoId),
    );
    if (saved == true) _load();
  }

  int get _totalNet => _items.fold(0, (sum, i) => sum + i.netAmount);
  int get _totalFee => _items.fold(0, (sum, i) => sum + i.feeAmount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Pencairan Gateway')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 40, color: MerchantPosTheme.mutedOf(context)),
                        const SizedBox(height: 12),
                        Text('Gagal memuat.\n$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        _SummaryCard(
                          net: _totalNet,
                          fee: _totalFee,
                          count: _items.length,
                          currency: _currency,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Riwayat Pencairan',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Catat Pencairan'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEC4899),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Belum ada pencairan tercatat.\n'
                              'Catat setiap kali dana dari penyedia masuk ke rekening.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 13),
                            ),
                          )
                        else
                          for (final item in _items) _tile(item),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _tile(GatewaySettlement item) {
    final off = item.discrepancy != 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEC4899).withOpacity(0.12),
          child: const Icon(Icons.credit_card_outlined, color: Color(0xFFEC4899)),
        ),
        title: Text(
          DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(item.settledOn),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          'Bruto ${_currency.format(item.grossAmount)} · '
          'MDR ${_currency.format(item.feeAmount)}'
          '${item.note?.isNotEmpty == true ? '\n${item.note}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: item.note?.isNotEmpty == true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('+ ${_currency.format(item.netAmount)}',
                style: const TextStyle(
                    color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
            // Selisih hanya ditampilkan kalau memang ada. Angka nol di
            // sini cuma derau yang harus dilewati mata tiap baris.
            if (off)
              Text('selisih ${_currency.format(item.discrepancy)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.red)),
          ],
        ),
        onTap: () => showJournalDetail(
          context,
          restoId: _restoId,
          referenceId: item.id,
          title: 'Pencairan Gateway',
          subtitle: _currency.format(item.netAmount),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int net;
  final int fee;
  final int count;
  final NumberFormat currency;

  const _SummaryCard({
    required this.net,
    required this.fee,
    required this.count,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEC4899), Color(0xFF9D174D)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Cair ke Rekening',
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(currency.format(net),
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
          Divider(height: 22, color: Colors.white.withOpacity(0.3)),
          Text(
            '$count pencairan · potongan MDR ${currency.format(fee)}',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddSettlementDialog extends StatefulWidget {
  final String restoId;

  const _AddSettlementDialog({required this.restoId});

  @override
  State<_AddSettlementDialog> createState() => _AddSettlementDialogState();
}

class _AddSettlementDialogState extends State<_AddSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _grossCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _netCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _settledOn = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _grossCtrl.dispose();
    _feeCtrl.dispose();
    _netCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _gross => parseRupiah(_grossCtrl.text) ?? 0;
  int get _fee => parseRupiah(_feeCtrl.text) ?? 0;
  int get _net => parseRupiah(_netCtrl.text) ?? 0;
  int get _discrepancy => _gross - _fee - _net;

  /// Neto diisikan otomatis begitu bruto dan biayanya lengkap, tapi tetap
  /// boleh ditimpa.
  ///
  /// Yang tertulis di mutasi bank adalah kebenarannya; hitungan ini cuma
  /// dugaan yang paling sering benar. Mengunci kolomnya berarti
  /// memaksakan dugaan itu pada hari ketika ternyata keliru.
  void _recalcNet() {
    if (_grossCtrl.text.isEmpty) return;
    setState(() => _netCtrl.text = formatRupiahInput(_gross - _fee));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final toast = AppToast.of(context);
    final navigator = Navigator.of(context);

    setState(() => _saving = true);
    try {
      await GatewaySettlementRepository().create(GatewaySettlement(
        id: '',
        restoId: widget.restoId,
        settledOn: _settledOn,
        grossAmount: _gross,
        feeAmount: _fee,
        netAmount: _net,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        createdBy: auth.user?.email,
        createdAt: DateTime.now(),
      ));
      toast.show('Pencairan tercatat.');
      navigator.pop(true);
    } catch (e) {
      toast.show('Gagal menyimpan: $e', isError: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context, minimal: 20, vertikal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Catat Pencairan',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 2),
                Text(
                  'Salin dari laporan penyedia dan mutasi bank. Jangan '
                  'menghitungnya sendiri — angka yang berbeda justru yang '
                  'perlu ketahuan.',
                  style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _settledOn,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setState(() => _settledOn = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal Masuk Rekening',
                      isDense: true,
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(
                      DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(_settledOn),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _grossCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: InputDecoration(
                    label: requiredLabel('Bruto (sebelum potongan)'),
                    prefixText: 'Rp ',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalcNet(),
                  validator: (v) =>
                      (parseRupiah(v ?? '') ?? 0) <= 0 ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _feeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Potongan MDR',
                    prefixText: 'Rp ',
                    isDense: true,
                  ),
                  onChanged: (_) => _recalcNet(),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _netCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: InputDecoration(
                    label: requiredLabel('Neto (yang masuk rekening)'),
                    prefixText: 'Rp ',
                    isDense: true,
                    helperText: 'Sesuaikan dengan mutasi bank',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      (parseRupiah(v ?? '') ?? 0) <= 0 ? 'Wajib diisi' : null,
                ),
                if (_discrepancy != 0 && _gross > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bruto − MDR tidak sama dengan neto: selisih '
                            '${currency.format(_discrepancy)}. Tetap boleh '
                            'disimpan — selisihnya ikut tercatat.',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                DialogActions(
                  confirmLabel: 'Simpan',
                  busy: _saving,
                  onConfirm: _save,
                  onCancel: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
