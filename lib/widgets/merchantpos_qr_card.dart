import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme.dart';
import 'merchantpos_logo.dart';

/// Kartu QR bergaya Merchant-POS: bidang ungu bergradasi, siku amber di
/// keempat pojok, lambang di atas, dan kartu putih berisi kodenya.
///
/// Dipakai dua tempat yang isinya berbeda tapi bentuknya harus sama —
/// QR meja yang dicetak resto, dan QR pembayaran di layar pelanggan.
/// Ditulis sekali di sini, bukan disalin: dua salinan bentuk yang sama
/// akan pelan-pelan berbeda pada perubahan berikutnya, dan yang paling
/// mudah berbeda justru warnanya, yang justru itu yang membuat orang
/// mengenalinya sebagai Merchant-POS.
///
/// Versi cetaknya digambar terpisah dalam PDF (lihat
/// `utils/table_qr_image.dart`) dengan koordinat yang sama, karena
/// kertas tidak bisa dirender dari widget.
class MerchantPosQrCard extends StatelessWidget {
  /// Isi kode QR-nya.
  final String data;

  /// Baris kecil di atas kartu putih, huruf besar berjarak.
  final String kicker;

  /// Judul di dalam kartu putih — nama resto, atau nama merchant.
  final String title;

  /// Keterangan di bawah judulnya.
  final String subtitle;

  /// Pil amber di bawah QR-nya. Null berarti tidak ada.
  final String? badge;

  /// Baris terakhir di dalam bidang ungunya.
  final String footer;

  /// Kartunya diredupkan dan diberi tulisan melintang.
  ///
  /// Dipakai QR pembayaran yang masa berlakunya habis. Menghilangkan
  /// kodenya sama sekali membuat layarnya terlihat rusak; meredupkannya
  /// menjelaskan bahwa kodenya memang masih ada, hanya tidak berlaku
  /// lagi.
  final String? overlayText;

  final double width;

  const MerchantPosQrCard({
    super.key,
    required this.data,
    required this.title,
    this.kicker = 'PESAN SENDIRI DARI MEJA',
    this.subtitle = 'Scan untuk pesan dari meja ini',
    this.badge,
    this.footer = 'Arahkan kamera HP ke kode di atas',
    this.overlayText,
    this.width = 260,
  });

  /// Semua ukurannya diturunkan dari lebar kartunya lewat satu faktor
  /// skala, memakai angka yang sama dengan kartu PDF-nya (lebar 384).
  double _s(double atCardWidth384) => atCardWidth384 * width / 384;

  @override
  Widget build(BuildContext context) {
    final expired = overlayText != null;

    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [MerchantPosTheme.brand, MerchantPosTheme.brandDark],
          ),
          borderRadius: BorderRadius.circular(_s(28)),
          boxShadow: [
            BoxShadow(
              color: MerchantPosTheme.brand.withOpacity(0.28),
              blurRadius: _s(30),
              offset: Offset(0, _s(10)),
            ),
          ],
        ),
        child: Stack(
          children: [
            ..._corners(),
            Padding(
              padding: EdgeInsets.all(_s(26)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MerchantPosLogo(size: _s(22), showBadgeBackground: false),
                      SizedBox(width: _s(7)),
                      Text(
                        'Merchant-POS',
                        style: TextStyle(
                          fontSize: _s(17),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: _s(4)),
                  Text(
                    kicker,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _s(7.5),
                      color: MerchantPosTheme.accent,
                      letterSpacing: _s(1.8),
                    ),
                  ),
                  SizedBox(height: _s(16)),
                  _inner(expired),
                  SizedBox(height: _s(12)),
                  Text(
                    footer,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: _s(8.5), color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inner(bool expired) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: _s(20), vertical: _s(18)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_s(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            // Warnanya ditulis, tidak diwarisi. Kartu ini selalu berlatar
            // putih — juga saat dicetak — tapi gaya teks bawaannya ikut
            // tema aplikasi, sehingga di mode gelap nama merchantnya
            // menjadi abu-abu terang di atas putih dan praktis hilang.
            style: TextStyle(
              fontSize: _s(15),
              fontWeight: FontWeight.bold,
              color: MerchantPosTheme.brandDark,
            ),
          ),
          SizedBox(height: _s(3)),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: _s(8.5), color: Colors.grey.shade600),
          ),
          SizedBox(height: _s(14)),
          Stack(
            alignment: Alignment.center,
            children: [
              ImageFiltered(
                imageFilter: expired
                    ? ImageFilter.blur(sigmaX: 4, sigmaY: 4)
                    : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Opacity(
                  opacity: expired ? 0.25 : 1,
                  child: QrImageView(
                    data: data,
                    version: QrVersions.auto,
                    size: _s(196),
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: MerchantPosTheme.brandDark,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: MerchantPosTheme.brandDark,
                    ),
                  ),
                ),
              ),
              if (expired)
                Text(
                  overlayText!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _s(15),
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
            ],
          ),
          if (badge != null) ...[
            SizedBox(height: _s(14)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: _s(22), vertical: _s(7)),
              decoration: BoxDecoration(
                color: MerchantPosTheme.accent,
                borderRadius: BorderRadius.circular(_s(22)),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: _s(19),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Siku amber di keempat pojok.
  ///
  /// Sekadar garis lurus di dalam bidang ungu akan terbaca sebagai
  /// bingkai kedua yang menyempit; siku terputus di tengah sisi justru
  /// membingkai isinya tanpa mengecilkan ruang QR-nya.
  List<Widget> _corners() {
    Widget bar(double w, double h) => Container(
          width: _s(w),
          height: _s(h),
          decoration: BoxDecoration(
            color: MerchantPosTheme.accent,
            borderRadius: BorderRadius.circular(_s(1.5)),
          ),
        );

    final inset = _s(12);
    return [
      Positioned(left: inset, top: inset, child: bar(34, 3)),
      Positioned(left: inset, top: inset, child: bar(3, 34)),
      Positioned(right: inset, top: inset, child: bar(34, 3)),
      Positioned(right: inset, top: inset, child: bar(3, 34)),
      Positioned(left: inset, bottom: inset, child: bar(34, 3)),
      Positioned(left: inset, bottom: inset, child: bar(3, 34)),
      Positioned(right: inset, bottom: inset, child: bar(34, 3)),
      Positioned(right: inset, bottom: inset, child: bar(3, 34)),
    ];
  }
}
