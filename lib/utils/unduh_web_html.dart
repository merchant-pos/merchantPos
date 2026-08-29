import 'dart:typed_data';

// Lint ini menjaga aplikasi yang salah memakai pustaka web di kode
// bersama. Di sini justru itu tugasnya: berkas ini hanya pernah
// dikompilasi untuk web, lewat impor bersyarat di unduh_web.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Mengunduh [bytes] sebagai berkas PNG bernama [namaBerkas].
///
/// Peramban tidak punya galeri foto, dan tidak ada izin yang bisa
/// diminta untuk menulis ke sana. Yang setara adalah unduhan: berkasnya
/// masuk ke folder unduhan, lalu orangnya sendiri yang memindahkannya
/// ke mana pun dia mau.
void unduhPngWeb(Uint8List bytes, String namaBerkas) {
  final blob = html.Blob(<Object>[bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.AnchorElement(href: url)
      ..download = namaBerkas
      ..style.display = 'none'
      ..click();
  } finally {
    // Dilepas supaya bytes-nya tidak menetap di memori tab sampai
    // halamannya ditutup — dan pada layar yang menyimpan puluhan QR
    // meja sekaligus, itu puluhan salinan yang tidak pernah dipakai
    // lagi.
    html.Url.revokeObjectUrl(url);
  }
}
