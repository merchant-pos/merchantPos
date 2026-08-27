
import '../widgets/penampil_foto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/firestore_product_repository.dart';
import '../db/merchant_review_repository.dart';
import '../db/product_review_repository.dart';
import '../models/merchant_review.dart';
import '../models/product_review.dart';
import '../models/opening_hours.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/gambar_base64.dart';
import '../utils/resto_location.dart';
import '../widgets/responsive.dart';
import 'merchant_review_form.dart';

final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Info merchant untuk pelanggan: alamat, fasilitas, jam buka, dan apa
/// kata orang yang sudah ke sana.
///
/// Dipakai juga oleh pegawai merchant untuk membaca penilaian yang masuk
/// — [bolehMenilai] yang membedakan. Menyalinnya jadi dua layar berarti
/// dua tempat yang harus diingat berbarengan tiap kali bentuk ulasannya
/// berubah.
class MerchantInfoScreen extends StatefulWidget {
  final Restaurant merchant;

  /// Tombol "Beri Penilaian" muncul. Mati untuk tamu dan untuk pegawai
  /// merchant — yang menilai tempatnya sendiri bukan penilaian.
  final bool bolehMenilai;

  const MerchantInfoScreen({
    super.key,
    required this.merchant,
    this.bolehMenilai = true,
  });

  @override
  State<MerchantInfoScreen> createState() => _MerchantInfoScreenState();
}

class _MerchantInfoScreenState extends State<MerchantInfoScreen> {
  final _repo = MerchantReviewRepository();
  final _repoMenu = ProductReviewRepository();
  List<MerchantReview> _ulasan = const [];

  /// Penilaian per menu, berikut nama menunya.
  ///
  /// Namanya dibaca dari katalog, bukan disalin ke tiap ulasan: menu
  /// yang berganti nama tetap satu menu, dan ulasannya tidak boleh
  /// terpecah jadi dua daftar karenanya.
  List<ProductReview> _ulasanMenu = const [];
  Map<String, String> _namaMenu = const {};
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final r = await _repo.forResto(widget.merchant.id);
      // Gagal memuat ulasan menu tidak boleh menghapus ulasan merchant
      // yang sudah berhasil diambil — keduanya berdiri sendiri.
      List<ProductReview> rm = const [];
      Map<String, String> nama = const {};
      try {
        rm = await _repoMenu.forResto(widget.merchant.id);
        if (rm.isNotEmpty) {
          final produk =
              await FirestoreProductRepository().getAllOnce(widget.merchant.id);
          nama = {for (final p in produk) p.id: p.name};
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _ulasan = r;
        _ulasanMenu = rm;
        _namaMenu = nama;
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuat = false);
    }
  }

  /// Ulasan menu, dikelompokkan per menu dan diurutkan dari yang paling
  /// banyak dibicarakan — bukan urut abjad. Yang membacanya sedang
  /// mencari menu mana yang jadi bahan omongan.
  Map<String, List<ProductReview>> get _kelompokMenu {
    final map = <String, List<ProductReview>>{};
    for (final u in _ulasanMenu) {
      map.putIfAbsent(u.productId, () => []).add(u);
    }
    final urut = map.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return {for (final e in urut) e.key: e.value};
  }

  double get _rata => _ulasan.isEmpty
      ? 0
      : _ulasan.map((u) => u.rating).reduce((a, b) => a + b) / _ulasan.length;

  Future<void> _beriPenilaian() async {
    final tersimpan = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchantReviewForm(merchant: widget.merchant),
      ),
    );
    if (tersimpan == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.merchant;
    final auth = context.watch<AuthProvider>();
    final bisa = widget.bolehMenilai && auth.isLoggedIn && !auth.isEmployee;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: Text(m.name)),
      floatingActionButton: bisa
          ? FloatingActionButton.extended(
              onPressed: _beriPenilaian,
              icon: const Icon(Icons.star_outline),
              label: const Text('Beri Penilaian'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              _Kartu(
                ikon: Icons.storefront_outlined,
                judul: 'Alamat',
                anak: [
                  Text(m.address.isEmpty ? 'Belum diisi' : m.address,
                      style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  if (m.hasLocation) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                        ),
                        icon: const Icon(Icons.directions_outlined, size: 16),
                        label: const Text('Buka di Google Maps'),
                        onPressed: () => openInMaps(
                          m.latitude!,
                          m.longitude!,
                          label: m.name,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (m.phone != null && m.phone!.isNotEmpty)
                _Kartu(
                  ikon: Icons.call_outlined,
                  judul: 'Nomor Telepon',
                  anak: [
                    Text(m.phone!, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              if (m.facilities.isNotEmpty)
                _Kartu(
                  ikon: Icons.chair_outlined,
                  judul: 'Fasilitas',
                  anak: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in m.facilities)
                          Chip(
                            label: Text(f,
                                style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              if (m.openingHours.adaIsinya)
                _Kartu(
                  ikon: Icons.schedule_outlined,
                  judul: 'Jam Buka',
                  anak: [_JamBuka(jam: m.openingHours)],
                ),
              _Kartu(
                ikon: Icons.star_outline,
                judul: 'Penilaian',
                anak: [
                  if (_memuat)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_ulasan.isEmpty)
                    Text(
                      bisa
                          ? 'Belum ada penilaian. Jadilah yang pertama.'
                          : 'Belum ada penilaian.',
                      style: TextStyle(
                          fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
                    )
                  else ...[
                    Row(
                      children: [
                        Text(
                          _rata.toStringAsFixed(1).replaceAll('.', ','),
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bintang(nilai: _rata),
                            const SizedBox(height: 2),
                            Text('${_ulasan.length} penilaian',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: MerchantPosTheme.mutedOf(context))),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final u in _ulasan) _BarisUlasan(ulasan: u),
                  ],
                ],
              ),
              if (_ulasanMenu.isNotEmpty)
                _Kartu(
                  ikon: Icons.restaurant_menu,
                  judul: 'Ulasan Menu',
                  anak: [
                    for (final e in _kelompokMenu.entries) ...[
                      _JudulMenu(
                        nama: _namaMenu[e.key] ?? 'Menu sudah dihapus',
                        ulasan: e.value,
                      ),
                      for (final u in e.value) _BarisUlasanMenu(ulasan: u),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JamBuka extends StatelessWidget {
  final OpeningHours jam;

  const _JamBuka({required this.jam});

  @override
  Widget build(BuildContext context) {
    final hariIni = DateTime.now().weekday;
    return Column(
      children: [
        for (var h = 1; h <= 7; h++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    OpeningHours.namaHari[h]!,
                    style: TextStyle(
                      fontSize: 13,
                      // Hari ini ditebalkan — yang membuka layar ini
                      // hampir selalu sedang bertanya "sekarang buka
                      // tidak", bukan "hari Kamis buka jam berapa".
                      fontWeight:
                          h == hariIni ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                Text(
                  jam.perHari[h] == null
                      ? 'Tutup'
                      : '${jam.perHari[h]!.$1} – ${jam.perHari[h]!.$2}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        h == hariIni ? FontWeight.bold : FontWeight.normal,
                    color: jam.perHari[h] == null
                        ? MerchantPosTheme.mutedOf(context)
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarisUlasan extends StatelessWidget {
  final MerchantReview ulasan;

  const _BarisUlasan({required this.ulasan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ulasan.customerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text(_tanggal.format(ulasan.createdAt),
                  style: TextStyle(
                      fontSize: 11, color: MerchantPosTheme.mutedOf(context))),
            ],
          ),
          const SizedBox(height: 3),
          _Bintang(nilai: ulasan.rating.toDouble(), ukuran: 14),
          if (ulasan.punyaKomentar) ...[
            const SizedBox(height: 5),
            Text(ulasan.comment!,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (ulasan.punyaFoto) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ulasan.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => InkWell(
                  onTap: () => lihatFoto(context, ulasan.photos, mulai: i),
                  borderRadius: BorderRadius.circular(9),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.memory(
                      byteGambar(ulasan.photos[i]),
                      width: 82,
                      height: 82,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nama menu, rata-ratanya, dan berapa orang yang bicara.
class _JudulMenu extends StatelessWidget {
  final String nama;
  final List<ProductReview> ulasan;

  const _JudulMenu({required this.nama, required this.ulasan});

  @override
  Widget build(BuildContext context) {
    final rata =
        ulasan.map((u) => u.rating).reduce((a, b) => a + b) / ulasan.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13.5)),
          ),
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF59E0B)),
          const SizedBox(width: 3),
          Text(rata.toStringAsFixed(1).replaceAll('.', ','),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text('(${ulasan.length})',
              style:
                  TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
        ],
      ),
    );
  }
}

/// Satu ulasan menu. Lebih ringkas daripada ulasan merchant — tidak ada
/// foto, dan yang membacanya sedang menelusuri banyak menu sekaligus.
class _BarisUlasanMenu extends StatelessWidget {
  final ProductReview ulasan;

  const _BarisUlasanMenu({required this.ulasan});

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Bintang(nilai: ulasan.rating.toDouble(), ukuran: 12),
              const SizedBox(width: 6),
              Flexible(
                child: Text(ulasan.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: muted)),
              ),
              const SizedBox(width: 6),
              Text(DateFormat('d MMM', 'id_ID').format(ulasan.createdAt),
                  style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
          if ((ulasan.comment ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(ulasan.comment!,
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
        ],
      ),
    );
  }
}

class _Bintang extends StatelessWidget {
  final double nilai;
  final double ukuran;

  const _Bintang({required this.nilai, this.ukuran = 17});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            nilai >= i
                ? Icons.star
                : nilai >= i - 0.5
                    ? Icons.star_half
                    : Icons.star_border,
            size: ukuran,
            color: const Color(0xFFF59E0B),
          ),
      ],
    );
  }
}

class _Kartu extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final List<Widget> anak;

  const _Kartu({required this.ikon, required this.judul, required this.anak});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
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
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          ...anak,
        ],
      ),
    );
  }
}
