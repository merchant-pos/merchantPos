import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/voucher_repository.dart';
import '../models/voucher.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Voucher milik pelanggan: tempat menebus kode, dan tempat melihat apa
/// yang sudah ditebus.
///
/// Penebusan dipisah dari pemakaian dengan sengaja. Mengetik kode saat
/// sudah berdiri di kasir adalah tempat paling buruk untuk mengetahui
/// kodenya salah ketik atau kuotanya habis — di sini orangnya masih
/// punya waktu.
class MyVouchersScreen extends StatefulWidget {
  const MyVouchersScreen({super.key});

  @override
  State<MyVouchersScreen> createState() => _MyVouchersScreenState();
}

class _MyVouchersScreenState extends State<MyVouchersScreen> {
  final _repo = VoucherRepository();
  final _kode = TextEditingController();

  List<VoucherClaim> _items = const [];
  bool _memuat = true;
  bool _menebus = false;
  String? _galat;

  /// Tab mana yang sedang dilihat.
  ///
  /// Sebagai pilihan berdampingan, bukan tab di bilah atas: kartu
  /// "Siap dipakai" dan kolom tebus kode harus tetap terlihat di
  /// keduanya — kode voucher datang kapan saja, dan menyembunyikan
  /// kolomnya di balik satu tab berarti orang harus tahu dulu tab mana
  /// yang benar sebelum bisa menebus.
  bool _lihatRiwayat = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _kode.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final items = await _repo.mine();
      if (!mounted) return;
      setState(() {
        _items = items;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _tebus() async {
    final kode = _kode.text.trim();
    if (kode.isEmpty) return;

    setState(() => _menebus = true);
    try {
      final hasil = await _repo.claim(kode);
      if (!mounted) return;
      if (hasil.berhasil) {
        _kode.clear();
        AppToast.show(context,
            'Voucher ${_rupiah.format(hasil.amount)} masuk ke daftarmu.');
        await _muat();
      } else {
        // Alasannya ditampilkan apa adanya. "Voucher tidak berlaku"
        // tanpa sebab membuat orang mencoba lagi dengan kode yang sama,
        // lalu menyalahkan aplikasinya.
        AppToast.show(context, hasil.reason ?? 'Voucher tidak bisa ditebus',
            isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal menebus: $e', isError: true);
    } finally {
      if (mounted) setState(() => _menebus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final masuk = context.watch<AuthProvider>().user?.email != null;
    final siap = _items.where((v) => v.siapDipakai).toList();
    final lampau = _items.where((v) => !v.siapDipakai).toList();
    final nilai = siap.fold<int>(0, (s, v) => s + v.amount);

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Voucher Saya')),
      body: !masuk
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  // Voucher menempel pada orang, bukan pada perangkat:
                  // yang menebusnya di HP lama harus tetap menemukannya
                  // di HP baru. Tanpa akun, tidak ada yang bisa dipegang.
                  'Masuk dulu dengan akun supaya vouchermu tersimpan dan '
                  'tetap ada saat ganti HP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [MerchantPosTheme.brand, MerchantPosTheme.brandDark],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Siap dipakai',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12.5)),
                          const SizedBox(height: 6),
                          Text(_rupiah.format(nilai),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            siap.isEmpty
                                ? 'Belum ada voucher. Punya kode? Tebus di '
                                    'bawah.'
                                : '${siap.length} voucher menunggu dipakai',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _kode,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[A-Za-z0-9]')),
                              TextInputFormatter.withFunction((lama, baru) =>
                                  baru.copyWith(text: baru.text.toUpperCase())),
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Punya kode voucher?',
                              hintText: 'HEMAT100',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _tebus(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Lebarnya wajib disebut. Tema aplikasi memberi
                        // tombol `minimumSize: Size.fromHeight(50)`, dan
                        // itu berarti lebar minimum **tak terhingga** —
                        // di dalam Row, tombolnya menuntut seluruh
                        // lebar, Expanded kebagian nol, dan kolom
                        // kodenya menyusut jadi garis tipis tanpa satu
                        // pun galat muncul.
                        SizedBox(
                          width: 104,
                          height: 46,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(104, 46),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _menebus ? null : _tebus,
                            child: _menebus
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Tebus'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_memuat)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: CircularProgressIndicator(),
                      ))
                    else if (_galat != null)
                      Text('Gagal memuat: $_galat',
                          style:
                              TextStyle(color: MerchantPosTheme.mutedOf(context)))
                    else ...[
                      // Yang hangus dan yang sudah dipakai dipisah,
                      // supaya voucher yang masih bisa dipakai tidak
                      // tenggelam di bawah tumpukan yang sudah lewat.
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text('Siap Dipakai (${siap.length})'),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Riwayat (${lampau.length})'),
                            ),
                          ],
                          selected: {_lihatRiwayat},
                          showSelectedIcon: false,
                          onSelectionChanged: (v) =>
                              setState(() => _lihatRiwayat = v.first),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final v in (_lihatRiwayat ? lampau : siap))
                        _Kartu(claim: v),
                      if ((_lihatRiwayat ? lampau : siap).isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _lihatRiwayat
                                ? 'Belum ada voucher yang sudah dipakai atau '
                                    'hangus.'
                                : 'Belum ada voucher yang siap dipakai. Punya '
                                    'kode? Tebus di atas.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: MerchantPosTheme.mutedOf(context)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final VoucherClaim claim;
  const _Kartu({required this.claim});

  @override
  Widget build(BuildContext context) {
    final (label, warna) = switch (claim.status) {
      VoucherClaimStatus.used => ('Sudah Dipakai', Colors.grey),
      VoucherClaimStatus.expired => ('Hangus', Colors.grey),
      VoucherClaimStatus.claimed =>
        claim.kedaluwarsa ? ('Hangus', Colors.grey) : ('Siap Dipakai', Colors.green),
    };
    final aktif = claim.siapDipakai;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: aktif
              ? Colors.green.withOpacity(0.4)
              : MerchantPosTheme.borderOf(context),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.confirmation_number_outlined,
              size: 26, color: aktif ? Colors.green : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.name ?? claim.code ?? 'Voucher',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (claim.code != null) claim.code!,
                    if (claim.expiresOn != null)
                      'sampai ${_tanggal.format(claim.expiresOn!)}',
                    if (claim.minPurchase > 0)
                      'min ${_rupiah.format(claim.minPurchase)}',
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_rupiah.format(claim.amount),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: aktif ? Colors.green : MerchantPosTheme.mutedOf(context))),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: warna)),
            ],
          ),
        ],
      ),
    );
  }
}
