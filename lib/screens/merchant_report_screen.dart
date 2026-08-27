import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/merchant_report_repository.dart';
import '../models/merchant_report.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';

/// Laporan Penjualan — Owner dan Admin.
///
/// Angka penjualan selama ini hanya bisa dibaca sebagai daftar transaksi
/// satu per satu. Itu cukup untuk mencocokkan uang, tapi tidak menjawab
/// pertanyaan yang benar-benar menentukan: menu mana yang sebaiknya
/// ditambah porsinya, menu mana yang sebaiknya dibuang dari daftar, dan
/// jam berapa orang harus disiapkan lebih banyak.
class MerchantReportScreen extends StatefulWidget {
  const MerchantReportScreen({super.key});

  @override
  State<MerchantReportScreen> createState() => _MerchantReportScreenState();
}

class _MerchantReportScreenState extends State<MerchantReportScreen> {
  final _repo = MerchantReportRepository();

  late DateTime _dari;
  late DateTime _sampai;

  RingkasanPenjualan _ringkasan = const RingkasanPenjualan();
  List<PenjualanMenu> _terlaris = const [];
  List<MenuTidakLaku> _tidakLaku = const [];
  List<JamRamai> _jamRamai = const [];
  bool _memuat = true;

  static final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _ringkas = NumberFormat.decimalPattern('id_ID');
  static final _tgl = DateFormat('d MMM yyyy', 'id_ID');

  @override
  void initState() {
    super.initState();
    // Tiga puluh hari terakhir, bukan bulan berjalan. Tanggal 2 bulan
    // depan, "bulan ini" berisi dua hari — dan laporan yang isinya dua
    // hari tidak memberi tahu apa pun tentang menu mana yang laku.
    final kini = DateTime.now();
    _sampai = DateTime(kini.year, kini.month, kini.day);
    _dari = _sampai.subtract(const Duration(days: 29));
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
  }

  Future<void> _muat() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    setState(() => _memuat = true);
    try {
      final hasil = await Future.wait([
        _repo.ringkasan(restoId, _dari, _sampai),
        _repo.terlaris(restoId, _dari, _sampai),
        _repo.tidakLaku(restoId, _dari, _sampai),
        _repo.jamRamai(restoId, _dari, _sampai),
      ]);
      if (!mounted) return;
      setState(() {
        _ringkasan = hasil[0] as RingkasanPenjualan;
        _terlaris = hasil[1] as List<PenjualanMenu>;
        _tidakLaku = hasil[2] as List<MenuTidakLaku>;
        _jamRamai = hasil[3] as List<JamRamai>;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      showAppToast(context, 'Gagal memuat laporan: $e', isError: true);
    }
  }

  Future<void> _pilihRentang() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dari, end: _sampai),
      helpText: 'Rentang laporan',
      saveText: 'Terapkan',
    );
    if (hasil == null || !mounted) return;
    setState(() {
      _dari = hasil.start;
      _sampai = hasil.end;
    });
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Laporan Penjualan')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    _pemilihRentang(),
                    const SizedBox(height: 14),
                    if (_ringkasan.kosong)
                      _Kosong(dari: _dari, sampai: _sampai)
                    else ...[
                      _kartuRingkasan(),
                      const SizedBox(height: 14),
                      _bagianTerlaris(),
                      const SizedBox(height: 14),
                      _bagianJamRamai(),
                    ],
                    const SizedBox(height: 14),
                    _bagianTidakLaku(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _pemilihRentang() {
    return Material(
      color: MerchantPosTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pilihRentang,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(Icons.event_outlined,
                  size: 18, color: MerchantPosTheme.brandOf(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_tgl.format(_dari)} — ${_tgl.format(_sampai)}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: MerchantPosTheme.mutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartuRingkasan() {
    return _Kartu(
      ikon: Icons.insights_outlined,
      judul: 'Ringkasan',
      anak: [
        Row(
          children: [
            Expanded(
              child: _Angka(
                  label: 'Omzet', nilai: _rp.format(_ringkasan.omzet)),
            ),
            Expanded(
              child: _Angka(
                  label: 'Pesanan',
                  nilai: _ringkas.format(_ringkasan.jumlahPesanan)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Angka(
                  label: 'Rata-rata transaksi',
                  nilai: _rp.format(_ringkasan.rataTransaksi)),
            ),
            Expanded(
              child: _Angka(
                  label: 'Porsi terjual',
                  nilai: _ringkas.format(_ringkasan.menuTerjual)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bagianTerlaris() {
    final muted = MerchantPosTheme.mutedOf(context);
    // Batang dibandingkan dengan yang teratas, bukan dengan omzet total.
    // Batang yang semuanya pendek karena dibagi total tidak membedakan
    // apa pun — dan membedakan justru satu-satunya gunanya.
    final tertinggi = _terlaris.isEmpty ? 1 : _terlaris.first.qty;

    return _Kartu(
      ikon: Icons.local_fire_department_outlined,
      judul: 'Menu Terlaris',
      anak: [
        if (_terlaris.isEmpty)
          Text('Belum ada penjualan di rentang ini.',
              style: TextStyle(fontSize: 12.5, color: muted))
        else
          for (var i = 0; i < _terlaris.length; i++)
            _BarisMenu(
              nomor: i + 1,
              nama: _terlaris[i].nama,
              kanan: '${_ringkas.format(_terlaris[i].qty)} porsi',
              bawah: _rp.format(_terlaris[i].omzet),
              rasio: tertinggi == 0 ? 0 : _terlaris[i].qty / tertinggi,
            ),
      ],
    );
  }

  Widget _bagianJamRamai() {
    final muted = MerchantPosTheme.mutedOf(context);
    if (_jamRamai.isEmpty) {
      return _Kartu(
        ikon: Icons.schedule_outlined,
        judul: 'Jam Ramai',
        anak: [
          Text('Belum ada pesanan di rentang ini.',
              style: TextStyle(fontSize: 12.5, color: muted)),
        ],
      );
    }

    final tertinggi =
        _jamRamai.map((j) => j.jumlahPesanan).reduce((a, b) => a > b ? a : b);
    final teramai = _jamRamai
        .reduce((a, b) => a.jumlahPesanan >= b.jumlahPesanan ? a : b);

    return _Kartu(
      ikon: Icons.schedule_outlined,
      judul: 'Jam Ramai',
      anak: [
        Text(
          'Paling ramai pukul ${teramai.label} — '
          '${_ringkas.format(teramai.jumlahPesanan)} pesanan.',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
        const SizedBox(height: 12),
        // Jamnya ditulis sebagai batang mendatar, bukan grafik.
        // Grafik butuh sumbu, label, dan ruang; yang dicari di sini cuma
        // "jam berapa yang paling tinggi", dan itu terbaca dari panjang
        // batangnya saja.
        for (final j in _jamRamai)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(j.label,
                      style: TextStyle(fontSize: 11.5, color: muted)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: tertinggi == 0 ? 0 : j.jumlahPesanan / tertinggi,
                      minHeight: 8,
                      backgroundColor: MerchantPosTheme.softFillOf(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text('${j.jumlahPesanan}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bagianTidakLaku() {
    final muted = MerchantPosTheme.mutedOf(context);
    return _Kartu(
      ikon: Icons.remove_shopping_cart_outlined,
      judul: 'Menu Tidak Laku',
      keterangan: 'Tidak terjual satu porsi pun sepanjang rentang ini.',
      anak: [
        if (_tidakLaku.isEmpty)
          Text('Semua menu terjual. Bagus.',
              style: TextStyle(fontSize: 12.5, color: muted))
        else
          for (final m in _tidakLaku)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.nama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text(m.kategori,
                            style: TextStyle(fontSize: 11.5, color: muted)),
                      ],
                    ),
                  ),
                  Text(_rp.format(m.harga),
                      style: TextStyle(fontSize: 12.5, color: muted)),
                ],
              ),
            ),
      ],
    );
  }
}

class _Kosong extends StatelessWidget {
  final DateTime dari;
  final DateTime sampai;

  const _Kosong({required this.dari, required this.sampai});

  @override
  Widget build(BuildContext context) {
    final tgl = DateFormat('d MMM yyyy', 'id_ID');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined,
              size: 40, color: MerchantPosTheme.mutedOf(context)),
          const SizedBox(height: 10),
          Text(
            'Belum ada pesanan lunas antara\n'
            '${tgl.format(dari)} dan ${tgl.format(sampai)}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
          ),
        ],
      ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final String? keterangan;
  final List<Widget> anak;

  const _Kartu({
    required this.ikon,
    required this.judul,
    this.keterangan,
    required this.anak,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 17, color: MerchantPosTheme.brandOf(context)),
              const SizedBox(width: 8),
              Text(judul,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5)),
            ],
          ),
          if (keterangan != null) ...[
            const SizedBox(height: 3),
            Text(keterangan!,
                style: TextStyle(
                    fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
          ],
          const SizedBox(height: 12),
          ...anak,
        ],
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final String nilai;

  const _Angka({required this.label, required this.nilai});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
        const SizedBox(height: 2),
        Text(nilai,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _BarisMenu extends StatelessWidget {
  final int nomor;
  final String nama;
  final String kanan;
  final String bawah;
  final double rasio;

  const _BarisMenu({
    required this.nomor,
    required this.nama,
    required this.kanan,
    required this.bawah,
    required this.rasio,
  });

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('$nomor.',
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
              Expanded(
                child: Text(nama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text(kanan,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rasio.clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: MerchantPosTheme.softFillOf(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(bawah, style: TextStyle(fontSize: 11.5, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
