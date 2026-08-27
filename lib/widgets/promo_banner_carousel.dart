import '../utils/gambar_base64.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../db/promo_banner_repository.dart';
import '../models/promo_banner.dart';
import '../theme.dart';
import '../utils/lebar_web.dart';

/// Banner promo resto di bagian atas halaman menu.
///
/// Tidak menampilkan apa pun kalau restonya belum memasang banner —
/// ruang kosong bergaris di atas daftar menu lebih mengganggu daripada
/// tidak ada apa-apa, dan sebagian besar resto baru memang belum punya
/// promo.
class PromoBannerCarousel extends StatefulWidget {
  final String restoId;

  const PromoBannerCarousel({super.key, required this.restoId});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  final _controller = PageController();
  List<PromoBanner> _banners = [];
  int _index = 0;
  Timer? _timer;

  /// Perbandingan sisi gambar bannernya, dibaca dari gambarnya sendiri.
  ///
  /// Sebelumnya kotaknya dipatok 16:9 dengan anggapan banner promo
  /// hampir selalu dibuat begitu. Yang bukan 16:9 jadi menyisakan pita
  /// kabur di sisinya — dan pita itu yang membuat bannernya terlihat
  /// tidak menyatu dengan halamannya.
  ///
  /// Sudah terisi sebelum bannernya pertama kali tampil — ukurannya
  /// dibaca lebih dulu, supaya tidak ada lompatan tata letak. Null cuma
  /// kalau seluruh gambarnya gagal dibaca, dan 16:9 jadi jatuhannya.
  double? _rasio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PromoBannerCarousel old) {
    super.didUpdateWidget(old);
    // Berpindah resto berarti bannernya ikut berganti; tanpa ini, promo
    // resto sebelumnya tertinggal di layar.
    if (old.restoId != widget.restoId) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await PromoBannerRepository().activeForResto(widget.restoId);
      if (!mounted) return;

      // Ukuran gambarnya dibaca DULU, baru bannernya ditampilkan.
      //
      // Sempat sebaliknya: bannernya muncul pada 16:9 lalu melompat ke
      // bentuk aslinya begitu ukurannya selesai dibaca. Dua perubahan
      // tata letak untuk satu banner, dan yang kedua terjadi tepat saat
      // orangnya mulai membaca — itu kedipannya.
      final rasio = await _hitungRasio(items);
      if (!mounted) return;

      setState(() {
        _banners = items;
        _index = 0;
        _rasio = rasio;
      });
      _restartAutoplay();
    } catch (_) {
      // Offline atau tabelnya belum ada — halaman menunya tetap jalan
      // tanpa banner.
    }
  }

  void _restartAutoplay() {
    _timer?.cancel();
    if (_banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % _banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _openDetail(PromoBanner banner) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: insetDialogWeb(context, minimal: 16, vertikal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.memory(
                byteGambar(banner.imageBase64),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            if ((banner.title != null && banner.title!.isNotEmpty) ||
                (banner.description != null && banner.description!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (banner.title != null && banner.title!.isNotEmpty)
                      Text(banner.title!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (banner.description != null && banner.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(banner.description!,
                            style: TextStyle(fontSize: 13, color: MerchantPosTheme.mutedOf(context))),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Membaca ukuran asli tiap banner, lalu memakai yang paling jangkung.
  ///
  /// Yang paling jangkung, bukan rata-ratanya: kotak yang lebih pendek
  /// dari salah satu gambarnya akan menyisakan pita untuk gambar itu —
  /// dan tidak ada satu kotak pun yang pas untuk semuanya kalau
  /// bannernya beda-beda bentuk.
  Future<double?> _hitungRasio(List<PromoBanner> items) async {
    double? paling;
    for (final b in items) {
      try {
        final gambar = await decodeImageFromList(base64Decode(b.imageBase64));
        final r = gambar.width / gambar.height;
        gambar.dispose();
        if (paling == null || r < paling) paling = r;
      } catch (_) {
        // Satu banner rusak tidak boleh menghentikan pembacaan yang lain.
      }
    }
    // Dijepit supaya banner yang salah ukuran — potret, atau pita
    // sangat panjang — tidak mengambil alih halaman menunya.
    return paling?.clamp(1.6, 3.2);
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 10),
        // Lebarnya dibatasi lalu ditaruh di tengah. Tanpa ini, 16:9
        // selebar tablet berarti banner ratusan piksel tingginya yang
        // mendorong seluruh menunya keluar layar. Di HP batas ini tidak
        // berpengaruh apa-apa — layarnya memang lebih sempit.
        // Jaraknya dari tepi layar dipasang DI LUAR rasio, bukan di
        // dalam tiap halaman.
        //
        // Sebelumnya tiap halaman punya padding 14 di kiri-kanan
        // sementara rasionya dipasang pada kotak sebelum padding itu —
        // jadi gambarnya 28 piksel lebih sempit daripada kotaknya, dan
        // sisa tingginya menyembul sebagai pita berwarna lain di atas
        // dan bawah. Pita itulah yang membuat bannernya terlihat lebih
        // besar daripada gambarnya sendiri.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AspectRatio(
          // Mengikuti bentuk gambarnya, bukan angka yang dipatok. Kotak
          // yang bentuknya berbeda dari gambarnya menyisakan pita di
          // sisinya, dan pita itu yang membuat bannernya terlihat tidak
          // menyatu dengan halamannya.
          aspectRatio: _rasio ?? 16 / 9,
          child: PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final banner = _banners[i];
              return GestureDetector(
                  onTap: () => _openDetail(banner),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Latar: gambar yang sama, dipotong penuh lalu
                        // dikaburkan. Yang tampil di depan harus utuh,
                        // dan itu menyisakan pita kosong di sisi gambar
                        // yang bentuknya tidak pas — pita abu-abu polos
                        // terlihat seperti gambarnya gagal dimuat,
                        // sedangkan latar kabur ini terbaca sebagai
                        // bagian dari bannernya.
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Image.memory(
                            byteGambar(banner.imageBase64),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: MerchantPosTheme.softFillOf(context)),
                          ),
                        ),
                        Image.memory(
                          byteGambar(banner.imageBase64),
                          // Utuh, tidak dipotong: yang terpotong biasanya
                          // justru nominal diskon atau tanggal
                          // berlakunya, yang ditaruh perancangnya di tepi
                          // gambar.
                          fit: BoxFit.contain,
                          // Satu banner rusak tidak boleh mengosongkan
                          // seluruh halaman menu.
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        if (banner.title != null && banner.title!.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.55),
                                  ],
                                ),
                              ),
                              child: Text(
                                banner.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              );
            },
          ),
            ),
          ),
          ),
        ),
        // Titik penanda halaman disembunyikan.
        //
        // Bannernya berganti sendiri tiap lima detik dan bisa digeser;
        // titik-titik di bawahnya tidak menambah apa pun yang belum
        // terlihat, dan justru memisahkan bannernya dari daftar menu
        // yang mestinya langsung menyambung.
        const SizedBox(height: 4),
      ],
    );
  }
}
