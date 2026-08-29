import 'dart:typed_data';

/// Sisi bukan-web: tidak pernah dipanggil.
///
/// Ada supaya berkas yang memanggilnya tetap bisa dibangun untuk
/// Android tanpa percabangan `kIsWeb` di tempat pemakaiannya.
void unduhPngWeb(Uint8List bytes, String namaBerkas) {}
