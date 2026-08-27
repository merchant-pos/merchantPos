import 'package:flutter/material.dart';

import '../theme.dart';

/// Lambang Merchant-POS: huruf M dengan anak panah yang melaju di
/// bawahnya.
///
/// Digambar sebagai bentuk vektor, bukan gambar — jadi tetap tajam di
/// ukuran berapa pun dan bisa dipakai ulang untuk badge splash, app bar,
/// dan header hub tanpa memuat aset. Bentuknya sama persis dengan
/// `assets/icon/merchantpos_icon.png` (ikon peluncur aplikasi) dan
/// `brand/merchantpos-logo.svg`, supaya mereknya seragam di mana pun.
///
/// [size] adalah sisi badge luarnya; isinya ikut menyesuaikan.
class MerchantPosLogo extends StatelessWidget {
  final double size;
  final bool showBadgeBackground;

  const MerchantPosLogo({super.key, this.size = 96, this.showBadgeBackground = true});

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _MerchantPosLogoPainter(),
    );

    if (!showBadgeBackground) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MerchantPosTheme.brand, MerchantPosTheme.brandDark],
        ),
        borderRadius: BorderRadius.circular(size * 0.227),
        boxShadow: [
          BoxShadow(
            color: MerchantPosTheme.brand.withOpacity(0.35),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: mark,
    );
  }
}

class _MerchantPosLogoPainter extends CustomPainter {
  /// Warna anak panah — amber aksen Merchant-POS.
  static const _amber = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    // Koordinatnya di kanvas 512x512, lalu diskalakan — sama seperti
    // berkas SVG-nya, supaya kedua bentuk tidak pelan-pelan melenceng
    // setiap kali salah satunya disentuh.
    final k = size.width / 512;
    Offset p(double x, double y) => Offset(x * k, y * k);

    // Huruf M digambar sebagai satu goresan, bukan empat bangun yang
    // disusun berdampingan. Sambungannya jadi menyatu dengan
    // sendirinya; disusun terpisah, tiap sudutnya harus dihitung
    // supaya tidak menyisakan celah setipis rambut yang baru terlihat
    // pada ukuran besar.
    final goresan = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 52 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(126 * k, 310 * k)
        ..lineTo(126 * k, 112 * k)
        ..lineTo(256 * k, 270 * k)
        ..lineTo(386 * k, 112 * k)
        ..lineTo(386 * k, 310 * k),
      goresan,
    );

    final amber = Paint()..color = _amber;

    // Batang panah
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(126 * k, 340 * k, 214 * k, 40 * k),
        Radius.circular(20 * k),
      ),
      amber,
    );

    // Mata panah
    final path = Path()
      ..moveTo(p(330, 318).dx, p(330, 318).dy)
      ..lineTo(p(404, 360).dx, p(404, 360).dy)
      ..lineTo(p(330, 402).dx, p(330, 402).dy)
      ..close();
    canvas.drawPath(path, amber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
