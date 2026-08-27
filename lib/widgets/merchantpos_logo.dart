import 'package:flutter/material.dart';

import '../theme.dart';

/// Lambang MerchantPOS: huruf K yang lengan bawahnya melaju jadi anak panah.
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
  /// Warna anak panah — amber aksen MerchantPOS.
  static const _amber = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    // Koordinatnya disalin apa adanya dari kanvas 512x512 milik berkas
    // SVG-nya, lalu diskalakan. Menuliskannya ulang dalam pecahan
    // membuat kedua bentuk pelan-pelan melenceng satu sama lain setiap
    // kali salah satunya disentuh.
    final k = size.width / 512;
    Offset p(double x, double y) => Offset(x * k, y * k);

    final white = Paint()..color = Colors.white;
    final amber = Paint()..color = _amber;

    // Batang tegak huruf K
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(132 * k, 140 * k, 54 * k, 232 * k),
        Radius.circular(14 * k),
      ),
      white,
    );

    void polygon(List<Offset> points, Paint paint) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path..close(), paint);
    }

    // Lengan atas
    polygon([p(200, 256), p(318, 141), p(402, 141), p(284, 256)], white);
    // Lengan bawah, diteruskan jadi anak panah
    polygon([p(200, 256), p(284, 256), p(402, 371), p(318, 371)], amber);
    polygon([p(362, 300), p(436, 256), p(436, 344)], amber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
