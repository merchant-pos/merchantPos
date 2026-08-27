import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Lebar isi yang wajar dibaca di layar lebar.
///
/// Formulir dan popup di aplikasi ini dirancang untuk layar selebar
/// telapak tangan, jadi hampir semuanya memakai `width: double.infinity`
/// — di ponsel itu berarti "selebar layar", yang benar. Di jendela 1600
/// piksel arti kalimat yang sama berubah total: kolom isian jadi
/// membentang satu setengah meter, dan kotak foto setinggi 160 piksel
/// yang melebar sampai ujung membuat gambarnya gepeng.
///
/// Angkanya bukan selera. Baris isian yang lebih lebar dari ini menuntut
/// mata berpindah jauh antara label di kiri dan isinya di kanan, dan
/// tetikus menempuh jarak yang tidak perlu untuk tiap kolom berikutnya.
const double kLebarIsiWeb = 560;

/// Popup lebih sempit lagi dari formulir sehalaman penuh — isinya
/// biasanya satu-dua kolom dan sepasang tombol.
const double kLebarDialogWeb = 460;

/// Jarak tepi popup supaya lebarnya berhenti di [maks].
///
/// Dihitung dari lebar jendela, bukan angka mati. `insetPadding` yang
/// dipatok 24 piksel benar di ponsel dan menghasilkan popup selebar
/// 1552 piksel di layar 1600 — bukan popup lagi, tapi halaman yang
/// kebetulan punya sudut membulat.
EdgeInsets insetDialogWeb(
  BuildContext context, {
  double maks = kLebarDialogWeb,
  double minimal = 24,
  double vertikal = 40,
}) {
  final lebar = MediaQuery.sizeOf(context).width;
  final sisi = ((lebar - maks) / 2).clamp(minimal, double.infinity);
  return EdgeInsets.symmetric(horizontal: sisi, vertical: vertikal);
}

/// Membatasi lebar isi lalu menaruhnya di tengah — hanya di web.
///
/// Di ponsel dikembalikan apa adanya, tanpa widget tambahan, supaya
/// tidak ada satu pun tata letak yang ikut berubah di sana.
class IsiWebTerpusat extends StatelessWidget {
  final Widget child;
  final double maks;

  const IsiWebTerpusat({super.key, required this.child, this.maks = kLebarIsiWeb});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maks),
        child: child,
      ),
    );
  }
}
