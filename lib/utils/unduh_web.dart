library;

/// Menyerahkan berkas ke peramban sebagai unduhan.
///
/// Diimpor bersyarat: `dart:html` tidak ada di Android maupun iOS, dan
/// mengimpornya tanpa syarat membuat aplikasinya gagal dibangun di
/// sana.
export 'unduh_web_kosong.dart'
    if (dart.library.html) 'unduh_web_html.dart';
