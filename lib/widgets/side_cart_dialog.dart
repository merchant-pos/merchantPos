import 'package:flutter/material.dart';

import 'responsive.dart';

/// Lebar panel keranjang tetap di layar lebar.
///
/// Disebut sekali di sini dan dipakai bersama oleh tata letaknya maupun
/// popup di sebelahnya. Dua angka terpisah akan berpisah, dan yang
/// terlihat adalah popup yang menutupi keranjang sedikit — persis
/// cukup untuk menyembunyikan baris terakhirnya.
const kSideCartWidth = 360.0;

/// Membuka popup di sisi kiri saat keranjang tampil sebagai panel kanan.
///
/// Kasir membacakan pesanan sambil pelanggan menyebutkannya, dan
/// keranjang di kanan itu yang sedang dibaca. Popup yang menutupinya
/// memaksa kasir menutup popup untuk memeriksa, lalu membukanya lagi —
/// dan yang paling sering hilang dari ingatan justru baris yang barusan
/// diucapkan.
///
/// Di layar yang keranjangnya tidak tampil berdampingan, popupnya
/// kembali di tengah seperti biasa: tidak ada yang perlu dihindari.
Future<T?> showDialogBesideCart<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  if (!Breakpoints.isWide(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  final lebarKiri = MediaQuery.sizeOf(context).width - kSideCartWidth - 1;

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        // Dialog punya lebar minimum 280 di dalamnya. Kalau ruang
        // kirinya lebih sempit dari itu, memaksakannya justru membuat
        // popupnya melebar melewati batas dan menutupi keranjang lagi —
        // lebih baik kembali ke tengah.
        constraints: BoxConstraints(maxWidth: lebarKiri.clamp(320.0, 720.0)),
        child: builder(ctx),
      ),
    ),
  );
}
