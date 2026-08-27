import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/market_report_repository.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Analisa pasar Merchant-POS — hanya Super Admin.
///
/// Empat pertanyaan yang selama ini cuma bisa dijawab dengan membuka
/// satu per satu resto. Dua di antaranya sengaja tentang yang **belum**
/// terjadi: pelanggan yang mendaftar lalu berhenti, dan resto yang
/// terpasang tapi belum berjualan. Peringkat teratas menyenangkan
/// dilihat, tapi yang bisa ditindaklanjuti justru daftar yang diam.
class MarketReportScreen extends StatefulWidget {
  const MarketReportScreen({super.key});

  @override
  State<MarketReportScreen> createState() => _MarketReportScreenState();
}

class _MarketReportScreenState extends State<MarketReportScreen> {
  final _repo = MarketReportRepository();

  List<ReportRow> _topPelanggan = const [];
  List<ReportRow> _pelangganDiam = const [];
  List<ReportRow> _topResto = const [];
  List<ReportRow> _restoDiam = const [];
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final hasil = await Future.wait([
        _repo.topCustomers(),
        _repo.idleCustomers(),
        _repo.topRestos(),
        _repo.idleRestos(),
      ]);
      if (!mounted) return;
      setState(() {
        _topPelanggan = hasil[0];
        _pelangganDiam = hasil[1];
        _topResto = hasil[2];
        _restoDiam = hasil[3];
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      AppToast.show(context, 'Gagal memuat laporan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalTop = _topResto.fold<int>(0, (a, r) => a + r.amount);

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Analisa Pasar')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  children: [
                    KartuBerdampingan(kartu: [
                    _Bagian(
                      icon: Icons.emoji_events_outlined,
                      warna: const Color(0xFFF59E0B),
                      judul: 'Top 5 Pelanggan',
                      catatan: 'Hanya pesanan yang benar-benar dibayar. '
                          'Pesanan batal pernah ada di layar kasir, tapi '
                          'tidak pernah jadi uang.',
                      kosong: 'Belum ada pelanggan yang bertransaksi.',
                      baris: _topPelanggan,
                      nilai: (r) => _rupiah.format(r.amount),
                      bawah: (r) => '${r.count} pesanan',
                      berperingkat: true,
                    ),
                    _Bagian(
                      icon: Icons.storefront_outlined,
                      warna: const Color(0xFF10B981),
                      judul: 'Top 5 Merchant',
                      catatan: totalTop == 0
                          ? null
                          : 'Lima ini menyumbang ${_rupiah.format(totalTop)}.',
                      kosong: 'Belum ada merchant yang menghasilkan.',
                      baris: _topResto,
                      nilai: (r) => _rupiah.format(r.amount),
                      bawah: (r) => '${r.count} pesanan',
                      berperingkat: true,
                    ),
                    _Bagian(
                      icon: Icons.person_off_outlined,
                      warna: const Color(0xFF059669),
                      judul: 'Pelanggan Belum Pernah Memesan',
                      catatan: 'Sudah memasang aplikasinya dan berhenti di '
                          'situ — bagian tersulitnya sudah lewat, yang '
                          'kurang cuma alasan untuk kembali.',
                      kosong: 'Semua pelanggan terdaftar sudah pernah memesan.',
                      baris: _pelangganDiam,
                      nilai: null,
                      bawah: (r) => r.sublabel ?? '',
                      berperingkat: false,
                    ),
                    _Bagian(
                      icon: Icons.store_mall_directory_outlined,
                      warna: const Color(0xFFEF4444),
                      judul: 'Merchant Belum Ada Penghasilan',
                      catatan: 'Yang jumlah pesanannya bukan nol berarti '
                          'sudah mencoba memakainya tapi tidak ada yang '
                          'sampai terbayar.',
                      kosong: 'Semua merchant sudah menghasilkan.',
                      baris: _restoDiam,
                      nilai: null,
                      bawah: (r) =>
                          r.count == 0 ? 'Belum ada pesanan' : '${r.count} pesanan terbayar',
                      berperingkat: false,
                    ),
                    ]),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Bagian extends StatelessWidget {
  final IconData icon;
  final Color warna;
  final String judul;
  final String? catatan;
  final String kosong;
  final List<ReportRow> baris;
  final String Function(ReportRow)? nilai;
  final String Function(ReportRow) bawah;
  final bool berperingkat;

  const _Bagian({
    required this.icon,
    required this.warna,
    required this.judul,
    required this.catatan,
    required this.kosong,
    required this.baris,
    required this.nilai,
    required this.bawah,
    required this.berperingkat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: warna.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: warna),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(judul,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
              Text('${baris.length}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: warna)),
            ],
          ),
          if (catatan != null) ...[
            const SizedBox(height: 6),
            Text(catatan!,
                style: TextStyle(
                    fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
          ],
          const SizedBox(height: 10),
          if (baris.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(kosong,
                  style: TextStyle(
                      fontSize: 12.5, color: MerchantPosTheme.mutedOf(context))),
            ),
          for (var i = 0; i < baris.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  if (berperingkat) ...[
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: warna)),
                    ),
                    const SizedBox(width: 2),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(baris[i].label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 1),
                        Text(bawah(baris[i]),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: MerchantPosTheme.mutedOf(context))),
                      ],
                    ),
                  ),
                  if (nilai != null) ...[
                    const SizedBox(width: 8),
                    Text(nilai!(baris[i]),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: warna)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
