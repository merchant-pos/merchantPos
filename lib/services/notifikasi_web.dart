library;

/// Menampilkan notifikasi peramban saat tabnya sedang dibuka.
///
/// Firebase menyerahkan pesan yang tiba saat halamannya di depan ke
/// aplikasi, tanpa menampilkan apa pun sendiri — sama seperti Android.
/// Bedanya, `flutter_local_notifications` tidak punya sisi web, jadi
/// yang dipakai API notifikasi milik peramban langsung.
///
/// Diimpor bersyarat: `dart:html` tidak ada di Android maupun iOS, dan
/// mengimpornya tanpa syarat membuat aplikasinya gagal dibangun di
/// sana.
export 'notifikasi_web_kosong.dart'
    if (dart.library.html) 'notifikasi_web_html.dart';
