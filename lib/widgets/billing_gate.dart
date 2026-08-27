import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/billing_repository.dart';
import '../models/billing.dart';
import '../providers/auth_provider.dart';
import '../screens/billing_screen.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMMM yyyy', 'id_ID');

/// Membungkus layar utama tiap peran resto.
///
/// Tiga keadaan, dan urutannya menentukan apa yang dilihat orangnya:
///
///   terkunci   → seluruh layar diganti halaman tagihan
///   H-3        → pita pengingat di atas layarnya, isinya tetap dipakai
///   selain itu → tidak ada apa-apa
///
/// Yang tidak dilakukan di sini: menegakkan penguncian. Layar yang
/// terkunci hanyalah layar — penegakannya ada di kebijakan RLS, dan
/// gerbang ini cuma menerjemahkannya jadi sesuatu yang bisa dibaca
/// orang. Kalau keduanya sampai berbeda pendapat, yang menang database,
/// dan gejalanya adalah tombol yang bisa ditekan tapi tidak menyimpan
/// apa pun.
class BillingGate extends StatefulWidget {
  final Widget child;

  const BillingGate({super.key, required this.child});

  @override
  State<BillingGate> createState() => _BillingGateState();
}

class _BillingGateState extends State<BillingGate> {
  final _repo = BillingRepository();
  BillingState _state = BillingState.tenang;
  bool _sudahMemeriksa = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _periksa());
  }

  Future<void> _periksa() async {
    final auth = context.read<AuthProvider>();
    final restoId = auth.restoId;

    // Super Admin tidak pernah terkunci — dialah yang membuka kuncinya.
    if (restoId == null || auth.isSuperAdmin) {
      if (mounted) setState(() => _sudahMemeriksa = true);
      return;
    }

    try {
      final s = await _repo.stateOf(restoId);
      if (!mounted) return;
      setState(() {
        _state = s;
        _sudahMemeriksa = true;
      });
    } catch (_) {
      // Luring, atau gangguan sesaat. Membiarkan aplikasinya jalan lebih
      // baik daripada mengunci resto yang tagihannya mungkin lunas:
      // penguncian yang sebenarnya tetap dijaga database, jadi tidak ada
      // yang lolos karena kelonggaran di sini.
      if (mounted) setState(() => _sudahMemeriksa = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_sudahMemeriksa) return widget.child;

    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return widget.child;

    if (_state.locked) {
      return _LayarTerkunci(state: _state, restoId: restoId);
    }

    if (!_state.perluDiingatkan) return widget.child;

    return Column(
      children: [
        _PitaPengingat(
          state: _state,
          onBuka: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BillingScreen(restoId: restoId),
            ));
            _periksa();
          },
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _PitaPengingat extends StatelessWidget {
  final BillingState state;
  final VoidCallback onBuka;

  const _PitaPengingat({required this.state, required this.onBuka});

  @override
  Widget build(BuildContext context) {
    final sisa = state.daysLeft ?? 0;
    final mendesak = sisa < 0;

    final pesan = state.menungguVerifikasi
        ? 'Bukti bayar sedang diperiksa MerchantPOS.'
        : mendesak
            ? 'Tagihan lewat ${-sisa} hari. Merchant terkunci kalau belum '
                'dibayar.'
            : sisa == 0
                ? 'Tagihan jatuh tempo hari ini.'
                : 'Tagihan jatuh tempo $sisa hari lagi.';

    final warna = state.menungguVerifikasi
        ? Colors.blue
        : mendesak
            ? Colors.red
            : Colors.orange;

    return Material(
      color: warna.withOpacity(0.12),
      child: InkWell(
        onTap: onBuka,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            child: Row(
              children: [
                Icon(
                  state.menungguVerifikasi
                      ? Icons.hourglass_top_outlined
                      : Icons.info_outline,
                  size: 17,
                  color: warna,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pesan,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: warna)),
                      if (state.amount != null)
                        Text(
                          '${_rupiah.format(state.amount)}'
                          '${state.dueDate == null ? '' : ' · '
                              'jatuh tempo ${_tanggal.format(state.dueDate!)}'}',
                          style: TextStyle(
                              fontSize: 11,
                              color: MerchantPosTheme.mutedOf(context)),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: warna),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Halaman yang menggantikan seluruh isi aplikasi saat resto terkunci.
///
/// Dua tombol saja, dan keduanya harus ada: membuka tagihan supaya bisa
/// membayar, dan keluar akun supaya perangkat yang dipinjam tidak
/// tersangkut di layar ini.
class _LayarTerkunci extends StatelessWidget {
  final BillingState state;
  final String restoId;

  const _LayarTerkunci({required this.state, required this.restoId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      body: SafeArea(
        child: ResponsiveCenter(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 44, color: Colors.red),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Aplikasi Terkunci Sementara',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tagihan langganan MerchantPOS belum lunas. Merchant ini bisa '
                  'dipakai lagi begitu pembayarannya diterima.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: MerchantPosTheme.mutedOf(context)),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MerchantPosTheme.surfaceOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MerchantPosTheme.borderOf(context)),
                  ),
                  child: Column(
                    children: [
                      if (state.amount != null)
                        Text(_rupiah.format(state.amount),
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                      if (state.dueDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Jatuh tempo ${_tanggal.format(state.dueDate!)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: MerchantPosTheme.mutedOf(context)),
                        ),
                      ],
                      if (state.invoiceId != null) ...[
                        const SizedBox(height: 2),
                        Text(state.invoiceId!,
                            style: TextStyle(
                                fontSize: 11,
                                color: MerchantPosTheme.mutedOf(context))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BillingScreen(restoId: restoId),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Lihat & Bayar Tagihan'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
                    if (!await confirmLogout(context)) return;
                    if (!context.mounted) return;
                    await context.read<AuthProvider>().signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.logout, size: 17),
                  label: const Text('Keluar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
