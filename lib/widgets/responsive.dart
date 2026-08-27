import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Ambang lebar layar.
///
/// Angkanya diambil dari perangkat yang benar-benar dipakai di resto:
/// HP genggam di bawah 600, tablet 7–10 inci di kisaran 600–1000, dan
/// monitor kasir atau tablet besar di atas itu.
class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 1000.0;

  static bool isPhone(BuildContext c) => MediaQuery.sizeOf(c).width < tablet;
  static bool isTablet(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return w >= tablet && w < desktop;
  }

  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= desktop;
}

/// Ruang kosong yang harus disisakan di dasar daftar bergulir pada layar
/// yang punya tombol mengambang.
///
/// Tombol mengambang melayang di atas isi, jadi tanpa ruang ini baris
/// terakhir selalu tertutup — dan justru baris terakhir yang paling
/// sering baru saja ditambahkan orangnya. Ukurannya: tinggi tombol
/// diperpanjang (56) + jarak amannya.
const kFabSafeBottom = 96.0;

/// Membatasi lebar isi lalu menaruhnya di tengah.
///
/// Di monitor kasir, daftar dan formulir yang dibiarkan selebar layar
/// membuat mata harus menyapu 1300 piksel untuk membaca satu baris, dan
/// tombol di ujung kanan jauh dari isi yang dituju. Membatasi lebarnya
/// membuat layar lebar terasa lapang, bukan melar.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;

  /// Null berarti pakai batas bawaan, dan bawaannya berbeda di web.
  ///
  /// Angka 840 lahir dari tablet kasir yang dipegang melintang. Konsol
  /// web dibuka di monitor 1600–1900 piksel, dan di sana batas yang
  /// sama menyisakan dua pita kosong selebar telapak tangan di kiri
  /// dan kanan — ruang yang justru dicari orang saat membuka konsol
  /// dari PC alih-alih dari HP-nya.
  ///
  /// Yang menyetel angkanya sendiri tidak tersentuh ini: formulir yang
  /// sengaja dipersempit tetap sempit, karena baris isian yang panjang
  /// menyusahkan di lebar berapa pun.
  final double? maxWidth;

  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  static const _bawaanPonsel = 840.0;
  static const _bawaanWeb = 1280.0;

  double get _batas => maxWidth ?? (kIsWeb ? _bawaanWeb : _bawaanPonsel);

  @override
  Widget build(BuildContext context) {
    return Align(
      // heightFactor: 1 — tingginya mengikuti isinya, bukan memakan
      // seluruh ruang yang ditawarkan.
      //
      // `Center` biasa melebar ke ukuran terbesar yang diizinkan di
      // kedua arah. Di badan layar itu tidak terasa, karena badan layar
      // memberi ukuran yang sudah pasti. Tapi di bottomNavigationBar —
      // yang batasnya longgar setinggi layar — Center akan tumbuh
      // setinggi layar penuh, mendorong badan layarnya jadi nol, dan
      // hasilnya sebuah layar yang isinya lenyap sama sekali sementara
      // deretan tombolnya melayang di tengah.
      //
      // Di tempat yang batasnya sudah pasti, heightFactor ini tidak
      // berpengaruh apa-apa: ukuran pasti tetap menang.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _batas),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// Menyusun kartu menu hub jadi beberapa kolom saat layarnya cukup lebar.
///
/// Satu kolom di tablet berarti setengah layar kosong dan menu paling
/// bawah butuh gulir — padahal seluruhnya muat sekaligus kalau dibagi
/// dua. Pada HP tetap satu kolom, karena kartu berdampingan di layar
/// sempit menyisakan terlalu sedikit ruang untuk keterangannya.
class HubMenuLayout extends StatelessWidget {
  final List<Widget> tiles;

  final EdgeInsetsGeometry padding;

  /// Isi tambahan di atas daftar menu (mis. judul "Menu").
  final List<Widget> header;

  const HubMenuLayout({
    super.key,
    required this.tiles,
    this.header = const [],
    // Ruang di bawah untuk tombol mengambang.
    //
    // Tanpa itu tombol MerchantPOS Support duduk tepat di atas tombol menu
    // terakhir — dan yang tertutup justru menu yang paling jarang
    // digulir sampai ke sana, jadi tidak ada yang menyadarinya sampai
    // ada yang mencarinya.
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, kFabSafeBottom),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= Breakpoints.desktop
            ? 3
            : constraints.maxWidth >= Breakpoints.tablet
                ? 2
                : 1;

        if (columns == 1) {
          return ListView(
            padding: padding,
            children: [
              ...header,
              for (final tile in tiles) ...[tile, const SizedBox(height: 12)],
            ],
          );
        }

        return ListView(
          padding: padding,
          children: [
            ...header,
            // Wrap, bukan GridView: tinggi tiap kartu mengikuti panjang
            // keterangannya, dan grid berpetak sama besar akan memaksa
            // semuanya setinggi kartu terpanjang.
            LayoutBuilder(
              builder: (context, inner) {
                const gap = 12.0;
                final width = (inner.maxWidth - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final tile in tiles)
                      SizedBox(width: width, child: tile),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Menyusun kartu berdampingan saat ruangnya cukup.
///
/// Beberapa layar hanya berisi empat-lima kartu ringkasan yang
/// ditumpuk ke bawah. Di HP itu satu-satunya susunan yang mungkin. Di
/// monitor, tumpukan yang sama memaksa orang menggulir melewati ruang
/// kosong selebar kartunya sendiri di sebelah kanan — padahal yang
/// dicari justru membandingkan angka-angka itu sekaligus.
class KartuBerdampingan extends StatelessWidget {
  final List<Widget> kartu;

  /// Lebar minimal tiap kartu. Di bawah ini kartunya terlalu sempit
  /// untuk isinya sendiri, dan dua kolom sempit lebih buruk daripada
  /// satu kolom lapang.
  final double lebarMinimal;

  final double jarak;

  const KartuBerdampingan({
    super.key,
    required this.kartu,
    this.lebarMinimal = 420,
    this.jarak = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final kolom =
            ((c.maxWidth + jarak) / (lebarMinimal + jarak)).floor().clamp(1, 3);
        if (kolom == 1) {
          return Column(
            children: [
              for (final k in kartu) ...[k, SizedBox(height: jarak)],
            ],
          );
        }
        final lebar = (c.maxWidth - jarak * (kolom - 1)) / kolom;
        // Wrap, bukan GridView: tinggi tiap kartu mengikuti isinya, dan
        // petak sama besar akan memaksa semuanya setinggi yang
        // terpanjang.
        return Wrap(
          spacing: jarak,
          runSpacing: jarak,
          children: [
            for (final k in kartu) SizedBox(width: lebar, child: k),
          ],
        );
      },
    );
  }
}
