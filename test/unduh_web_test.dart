import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:merchant_pos/utils/gallery_saver.dart';

/// Peramban tidak punya galeri foto, dan tidak ada izin yang bisa
/// diminta untuk menulis ke sana.
void main() {
  final penyimpan = File('lib/utils/gallery_saver.dart').readAsStringSync();

  group('menyimpan gambar di web', () {
    // Sebelumnya jalur ini tetap menanyakan izin galeri lewat Gal, yang
    // di web menjawab dengan galat — jadi tombolnya berhenti sebagai
    // "gagal memeriksa izin galeri" pada perangkat yang memang tidak
    // punya galeri sama sekali.
    test('tidak menanyakan izin galeri', () {
      final blok = penyimpan.substring(
          penyimpan.indexOf('Future<bool> ensureGalleryAccess'));
      final sampaiTry = blok.substring(0, blok.indexOf('try {'));
      expect(sampaiTry, contains('if (kIsWeb) return true;'));
    });

    test('menyerahkannya ke peramban sebagai unduhan', () {
      expect(penyimpan, contains('unduhPngWeb(bytes, namaBerkas)'));
      final pintu = File('lib/utils/unduh_web.dart').readAsStringSync();
      expect(pintu, contains("if (dart.library.html) 'unduh_web_html.dart'"));
      // Sisi bukan-web harus ada, kalau tidak Android gagal dibangun.
      expect(File('lib/utils/unduh_web_kosong.dart').existsSync(), isTrue);
    });

    // Bytes-nya menetap di memori tab sampai halamannya ditutup kalau
    // tidak dilepas — dan pada layar yang menyimpan puluhan QR meja
    // sekaligus, itu puluhan salinan yang tidak pernah dipakai lagi.
    test('object URL-nya dilepas sesudah dipakai', () {
      final html = File('lib/utils/unduh_web_html.dart').readAsStringSync();
      expect(html, contains('revokeObjectUrl'));
      expect(html, contains('finally {'));
    });
  });

  group('nama berkas unduhan', () {
    // Nomor meja bebas bentuk, dan garis miring di dalamnya membuat
    // peramban memperlakukannya sebagai folder.
    test('membuang tanda yang merusak jalur berkas', () {
      expect(namaBerkasAman('A/01'), 'A-01');
      expect(namaBerkasAman('Meja 3 (pojok)'), 'Meja 3 -pojok');
      expect(namaBerkasAman('VIP-2'), 'VIP-2');
    });

    // "///" sempat lolos sebagai "---": bukan kosong, jadi penjaganya
    // tidak berbunyi, dan berkasnya terunduh bernama tiga setrip.
    test('tidak pernah kosong, dan tidak pernah cuma setrip', () {
      expect(namaBerkasAman('///'), 'Merchant-POS');
      expect(namaBerkasAman(''), 'Merchant-POS');
      expect(namaBerkasAman('   '), 'Merchant-POS');
    });
  });

  test('tiap pemanggil memberi nama berkasnya sendiri', () {
    for (final f in ['table_qr_image', 'qris_image', 'receipt_image']) {
      final isi = File('lib/utils/$f.dart').readAsStringSync();
      expect(isi, contains('namaBerkas:'), reason: f);
    }
  });
}
