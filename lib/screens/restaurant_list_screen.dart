import '../models/merchant_review.dart';
import '../db/merchant_review_repository.dart';
import '../widgets/app_toast.dart';
import 'merchant_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../providers/table_session_provider.dart';
import '../theme.dart';
import '../utils/resto_location.dart';
import '../widgets/resto_logo_avatar.dart';

/// Batas sebuah resto masih disebut "terdekat".
///
/// Lima kilometer. Sepuluh terlalu jauh untuk kata "terdekat": di jam
/// sibuk itu setengah jam perjalanan, dan daftar yang menjanjikan
/// kedekatan lalu menawarkan tempat sejauh itu lebih buruk daripada
/// tidak menjanjikan apa pun.
///
/// Yang di luar radius tidak hilang — mereka tetap ada di tab Semua.
/// Yang dipersempit hanya janjinya, bukan pilihannya.
const _nearbyRadiusKm = 5.0;

/// Resto yang bisa dibuka pelanggan tanpa memindai QR meja.
///
/// Terbagi dua: yang dekat dari tempatnya berdiri, dan seluruhnya. Yang
/// dicari orang lapar hampir selalu yang pertama — tapi yang kedua tetap
/// harus ada, karena dia mungkin sedang memesan untuk nanti, untuk orang
/// lain, atau dari tempat yang lokasinya tidak diizinkan dibaca.
class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  final _repo = RestaurantRepository();
  final _searchCtrl = TextEditingController();

  List<Restaurant> _restaurants = [];

  /// Bintang tiap merchant, dihitung server sekali untuk seluruh daftar.
  ///
  /// Bukan per baris: daftar ini menampilkan puluhan merchant sekaligus,
  /// dan satu panggilan per baris berarti puluhan permintaan berbaris
  /// tiap kali layarnya dibuka.
  Map<String, RatingRingkas> _rating = const {};
  Position? _me;
  bool _loading = true;

  /// Kenapa jaraknya tidak bisa dihitung, atau null kalau bisa.
  ///
  /// Ditampilkan apa adanya, bukan disembunyikan: daftar "terdekat" yang
  /// diam-diam kosong terlihat seperti tidak ada resto di dekat sini,
  /// padahal yang terjadi cuma izin lokasi belum diberikan.
  String? _locationNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await _repo.getAllActive();
    if (!mounted) return;
    setState(() {
      _restaurants = all;
      _loading = false;
    });
    _locate();
    _muatRating();
  }

  /// Bintangnya menyusul setelah daftarnya tampil.
  ///
  /// Menahan daftarnya sampai ratingnya selesai dibaca berarti layar
  /// kosong demi satu angka kecil — dan yang paling dicari di sini
  /// tetap nama dan jaraknya.
  Future<void> _muatRating() async {
    try {
      final r = await MerchantReviewRepository().ringkasan();
      if (!mounted) return;
      setState(() => _rating = r);
    } catch (_) {
      // Gagal membaca bintangnya bukan alasan menjatuhkan daftarnya.
    }
  }

  /// Lokasinya diminta setelah daftarnya tampil, bukan sebelum.
  ///
  /// Meminta izin lebih dulu berarti layar kosong yang menahan orang di
  /// depan dialog izin sebelum dia sempat melihat ada apa di sini. Dan
  /// kalau izinnya ditolak, daftarnya toh tetap berguna.
  Future<void> _locate() async {
    try {
      final me = await currentPosition();
      if (!mounted) return;
      setState(() {
        _me = me;
        _locationNote = null;
      });
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() => _locationNote = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationNote = 'Lokasi tidak bisa dibaca.');
    }
  }

  /// Jarak garis lurus dalam kilometer, atau null kalau salah satunya
  /// tidak diketahui.
  ///
  /// Garis lurus, bukan jarak tempuh — yang dijawab angka ini adalah
  /// "kira-kira sejauh apa", bukan "berapa lama sampai". Untuk memilih
  /// di antara beberapa resto itu sudah cukup, dan menghitung rute
  /// sungguhan berarti memanggil layanan berbayar untuk tiap baris di
  /// daftar ini.
  double? _distanceKm(Restaurant resto) {
    final me = _me;
    if (me == null || !resto.hasLocation) return null;
    return Geolocator.distanceBetween(
          me.latitude,
          me.longitude,
          resto.latitude!,
          resto.longitude!,
        ) /
        1000;
  }

  String _distanceText(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

  /// Yang cocok dengan pencarian, terurut dari yang paling dekat.
  ///
  /// Yang tidak diketahui lokasinya ditaruh paling belakang, bukan
  /// dianggap berjarak nol. Resto yang belum mengisi titik lokasinya
  /// bukan resto yang ada di sebelah kita — dan menaruhnya di puncak
  /// daftar "terdekat" persis membalik arti daftar itu.
  List<Restaurant> get _matching {
    final q = _searchCtrl.text.trim().toLowerCase();
    final matched = q.isEmpty
        ? [..._restaurants]
        : _restaurants
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                r.address.toLowerCase().contains(q))
            .toList();

    if (_me == null) return matched;

    matched.sort((a, b) {
      // Yang tutup selalu di bawah, sedekat apa pun. Tempat terdekat
      // yang sedang tutup bukan tempat yang bisa dipilih — menaruhnya
      // di puncak daftar berarti baris teratas justru satu-satunya yang
      // tidak berguna sekarang.
      final ta = _tutup(a);
      final tb = _tutup(b);
      if (ta != tb) return ta ? 1 : -1;

      final da = _distanceKm(a);
      final db = _distanceKm(b);
      if (da == null && db == null) return a.name.compareTo(b.name);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return matched;
  }

  /// Yang dekat, terurut dari yang paling dekat.
  List<Restaurant> get _nearby {
    if (_me == null) return const [];
    final withDistance = <(Restaurant, double)>[];
    for (final r in _matching) {
      final km = _distanceKm(r);
      if (km != null && km <= _nearbyRadiusKm && !_tutup(r)) {
        withDistance.add((r, km));
      }
    }
    // Yang tutup tidak masuk saran sama sekali.
    //
    // "Terdekat" adalah saran, bukan katalog — dan menyarankan tempat
    // yang tidak bisa dipilih membuat bagian ini berhenti berarti apa
    // pun. Yang tutup tetap ada di Semua Merchant, di bawah, lengkap
    // dengan tandanya.
    withDistance.sort((a, b) => a.$2.compareTo(b.$2));
    return withDistance.map((e) => e.$1).toList();
  }

  /// Sedang tutup menurut jam bukanya sendiri.
  ///
  /// Merchant yang belum mengisi jam bukanya tidak dianggap tutup —
  /// daftar kosong berarti belum diisi, bukan berarti tutup selamanya,
  /// dan menutup pintunya karena setelan yang belum disentuh adalah
  /// kehilangan pesanan yang tidak pernah dia sadari.
  bool _tutup(Restaurant resto) =>
      resto.openingHours.adaIsinya &&
      !resto.openingHours.bukaPada(DateTime.now());

  Future<void> _select(Restaurant resto) async {
    if (_tutup(resto)) {
      // Dihentikan di sini, bukan dibiarkan masuk lalu gagal saat
      // checkout. Yang sudah memilih menu dan menyusun keranjang lalu
      // ditolak di ujung akan mengira aplikasinya yang rusak.
      AppToast.show(
        context,
        'Merchant lagi tutup nih, silakan pilih merchant lainnya dulu ya.',
        isError: true,
      );
      return;
    }
    await context.read<TableSessionProvider>().setResto(resto.id);
    if (!mounted) return;
    // Pola yang sama dengan ScanTableScreen: kembali ke layar customer,
    // yang sekarang menampilkan menu resto pilihannya.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final matching = _matching;
    final nearby = _nearby;
    final searching = _searchCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Pilih Merchant'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama merchant atau alamat',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_searchCtrl.clear),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('Belum ada merchant terdaftar.'))
              : matching.isEmpty
                  ? _EmptySearch(query: _searchCtrl.text.trim())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        children: [
                          if (nearby.isNotEmpty) ...[
                            _SectionHeader(
                              icon: Icons.near_me_outlined,
                              title: 'Terdekat',
                              subtitle: 'Dalam ${_nearbyRadiusKm.round()} km dari kamu',
                            ),
                            for (final r in nearby) _card(r),
                            const SizedBox(height: 18),
                          ] else if (_locationNote != null) ...[
                            _LocationNote(
                              message: _locationNote!,
                              onRetry: _locate,
                            ),
                            const SizedBox(height: 14),
                          ],
                          _SectionHeader(
                            icon: Icons.storefront_outlined,
                            title: 'Semua Merchant',
                            subtitle: _me == null
                                ? '${matching.length} merchant'
                                : '${matching.length} merchant · terdekat dulu',
                          ),
                          // Yang dekat tetap ikut muncul di sini. Daftar
                          // "semua" yang diam-diam menyembunyikan
                          // sebagian isinya akan membuat orang mengira
                          // restonya hilang saat dia menggulir mencari
                          // yang tadi dia lihat di atas.
                          for (final r in matching) _card(r),
                        ],
                      ),
                    ),
    );
  }

  Widget _card(Restaurant resto) {
    final km = _distanceKm(resto);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: RestoLogoAvatar(logoBase64: resto.logoBase64),
        title: Row(
          children: [
            Flexible(
              child: Text(resto.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (_tutup(resto)) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Tutup',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.red),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resto.address.isEmpty ? 'Alamat belum diisi' : resto.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // Bintang dan jarak sebaris: keduanya angka pendek, dan
            // keduanya yang paling menentukan pilihan.
            if (km != null || (_rating[resto.id]?.adaPenilaian ?? false)) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  if (_rating[resto.id]?.adaPenilaian ?? false) ...[
                    const Icon(Icons.star,
                        size: 13, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 3),
                    Text(
                      _rating[resto.id]!.teks,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    Text(
                      ' (${_rating[resto.id]!.jumlah})',
                      style: TextStyle(
                          fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
                    ),
                    if (km != null) const SizedBox(width: 10),
                  ],
                  if (km != null) ...[
                    const Icon(Icons.near_me, size: 12, color: MerchantPosTheme.brand),
                    const SizedBox(width: 4),
                    Text(
                      _distanceText(km),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: MerchantPosTheme.brand,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            // Fasilitasnya berwarna dan berbentuk kartu kecil, bukan
            // teks abu-abu sebaris.
            //
            // Ini yang paling sering menentukan pilihan — ada AC atau
            // tidak, boleh merokok atau tidak, aman untuk anak atau
            // tidak — dan keterangan yang sepucat alamat akan terlewat
            // oleh mata yang sedang menyapu daftar.
            if (resto.facilities.isNotEmpty) ...[
              const SizedBox(height: 6),
              _BarisFasilitas(
                nama: resto.facilities,
                onLainnya: () => _bukaInfo(context, resto),
              ),
            ],
          ],
        ),
        isThreeLine: km != null || resto.facilities.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ikut ditawarkan di sini, bukan hanya setelah masuk:
            // memilih resto sering justru soal "yang mana yang paling
            // dekat".
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Info merchant',
              onPressed: () => _bukaInfo(context, resto),
            ),
            if (resto.hasLocation)
              IconButton(
                icon: const Icon(Icons.directions_outlined),
                tooltip: 'Buka di Google Maps',
                onPressed: () => openInMaps(
                  resto.latitude!,
                  resto.longitude!,
                  label: resto.name,
                ),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _select(resto),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: MerchantPosTheme.brand),
          const SizedBox(width: 7),
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationNote extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LocationNote({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me_disabled_outlined, size: 18, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Merchant terdekat belum bisa ditampilkan. $message',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba Lagi')),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final String query;

  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 52, color: MerchantPosTheme.borderOf(context)),
            const SizedBox(height: 12),
            Text(
              'Tidak ada merchant bernama "$query".',
              textAlign: TextAlign.center,
              style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu fasilitas, sebagai kartu kecil berwarna.
///
/// Warnanya diambil dari namanya sendiri, bukan diacak tiap kali
/// digambar: fasilitas yang sama harus berwarna sama di seluruh daftar,
/// supaya mata bisa mengenalinya tanpa membaca ulang tiap barisnya.
class _FasilitasChip extends StatelessWidget {
  final String nama;

  const _FasilitasChip({required this.nama});

  static const _palet = [
    Color(0xFF10B981),
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
  ];

  /// Fasilitas yang punya ikonnya sendiri — dipakai menghitung lebar
  /// chip sebelum digambar.
  static bool punyaIkon(String nama) => _ikon.containsKey(nama.toLowerCase());

  static const _ikon = {
    'ac': Icons.ac_unit,
    'smoking area': Icons.smoking_rooms_outlined,
    'kids friendly': Icons.child_friendly_outlined,
    'live music': Icons.music_note_outlined,
    'wifi gratis': Icons.wifi,
    'parkir luas': Icons.local_parking_outlined,
    'mushola': Icons.mosque_outlined,
    'toilet': Icons.wc_outlined,
    'colokan listrik': Icons.power_outlined,
    'ramah difabel': Icons.accessible_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final warna = _palet[nama.toLowerCase().hashCode.abs() % _palet.length];
    final ikon = _ikon[nama.toLowerCase()];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warna.withOpacity(0.13),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: warna.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[
            Icon(ikon, size: 12, color: warna),
            const SizedBox(width: 4),
          ],
          // Dipotong rapi kalau ruangnya kurang. Perkiraan lebar di
          // _BarisFasilitas bisa meleset beberapa piksel — dan tanpa
          // ini, selisih sekecil apa pun berubah jadi garis
          // kuning-hitam alih-alih nama yang terpotong satu huruf.
          Flexible(
            child: Text(
              nama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: warna,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Membuka Info Merchant — alamat, fasilitas lengkap, jam buka, dan
/// penilaian orang yang sudah ke sana.
void _bukaInfo(BuildContext context, Restaurant merchant) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => MerchantInfoScreen(merchant: merchant)),
  );
}

/// Fasilitas dalam satu baris, sebanyak yang muat.
///
/// Sebelumnya barisnya bisa digeser menyamping — dan itu salah dua arah:
/// chip yang tergulir keluar terlihat terpotong di tepi kartu seperti
/// tampilan yang rusak, dan tidak ada yang menyangka baris sesempit itu
/// bisa digeser, jadi sisanya tidak pernah dilihat siapa pun.
///
/// Sekarang lebarnya diukur lebih dulu: yang muat ditampilkan utuh,
/// sisanya diringkas jadi "+N" yang bisa diketuk. Tidak ada yang
/// terpotong, dan yang disembunyikan punya jalan untuk dilihat.
class _BarisFasilitas extends StatelessWidget {
  final List<String> nama;
  final VoidCallback onLainnya;

  const _BarisFasilitas({required this.nama, required this.onLainnya});

  /// Lebar sebuah chip, dihitung dari teksnya.
  ///
  /// Angka-angkanya mengikuti _FasilitasChip: padding 8+8, ikon 12,
  /// jarak 4, plus 2 untuk garis tepinya.
  double _lebar(BuildContext context, String teks, {required bool berikon}) {
    final tp = TextPainter(
      text: TextSpan(
        text: teks,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    // Dilebihkan sedikit: padding 16, garis tepi 2, ikon 12 + jarak 4.
    // Dan dua piksel lagi sebagai kelonggaran — huruf yang diukur
    // TextPainter tidak selalu selebar huruf yang benar-benar
    // digambar, dan meleset ke bawah berarti melimpah.
    return tp.width + 20 + (berikon ? 16 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const jarak = 6.0;
        // Ruang untuk "+N" disisihkan sejak awal. Menghitungnya
        // belakangan berarti chip terakhir sudah terlanjur masuk, lalu
        // "+N"-nya yang melimpah keluar kartu.
        const lebarLainnya = 42.0;

        final muat = <String>[];
        var dipakai = 0.0;
        for (final f in nama) {
          final w = _lebar(context, f, berikon: _FasilitasChip.punyaIkon(f));
          final sisaSetelahIni = c.maxWidth - (dipakai + w);
          final adaSisa = nama.length > muat.length + 1;
          // Chip terakhir hanya boleh masuk kalau "+N" masih kebagian
          // tempat — kecuali memang tidak ada sisanya lagi.
          if (sisaSetelahIni < (adaSisa ? lebarLainnya : 0)) break;
          muat.add(f);
          dipakai += w + jarak;
        }

        // Selalu tampilkan minimal satu, walau namanya panjang sekali.
        // Baris kosong berarti fasilitasnya seolah tidak ada.
        if (muat.isEmpty) muat.add(nama.first);

        final sisa = nama.length - muat.length;
        return Row(
          children: [
            for (final f in muat) ...[
              Flexible(child: _FasilitasChip(nama: f)),
              const SizedBox(width: jarak),
            ],
            if (sisa > 0)
              InkWell(
                onTap: onLainnya,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: MerchantPosTheme.brandOf(context).withOpacity(0.5)),
                  ),
                  child: Text(
                    '+$sisa',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: MerchantPosTheme.brandOf(context),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}


/// Pembungkus untuk pengujian tata letak barisan fasilitas.
///
/// Widget aslinya privat dan hanya masuk akal di dalam kartunya; yang
/// perlu diuji cuma perilaku muat-tidaknya, dan itu tidak butuh seluruh
/// layar daftar merchant beserta lokasinya.
class RestaurantFacilityRowForTest extends StatelessWidget {
  final List<String> nama;

  const RestaurantFacilityRowForTest({super.key, required this.nama});

  @override
  Widget build(BuildContext context) =>
      _BarisFasilitas(nama: nama, onLainnya: () {});
}
