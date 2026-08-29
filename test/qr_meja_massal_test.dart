import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:merchant_pos/utils/table_qr_image.dart';

void main() {
  group('nomor meja borongan', () {
    test('mulai dari 1 kalau tidak ditentukan', () {
      expect(tableLabels(count: 3), ['1', '2', '3']);
    });

    // Merchant yang menambah lantai dua tidak mulai dari meja 1 lagi.
    // Tanpa ini, satu-satunya jalan adalah membuat 30 QR lalu membuang
    // 15 yang pertama.
    test('bisa mulai dari nomor lain', () {
      expect(tableLabels(count: 3, mulai: 16), ['16', '17', '18']);
      expect(tableLabels(prefix: 'A', count: 2, mulai: 7), ['A7', 'A8']);
    });

    test('nomor awal yang tidak masuk akal ditolak, bukan dibetulkan diam-diam',
        () {
      expect(tableLabels(count: 3, mulai: 0), isEmpty);
      expect(tableLabels(count: 3, mulai: -5), isEmpty);
    });

    test('batas jumlahnya tetap berlaku berapa pun nomor awalnya', () {
      expect(tableLabels(count: 0, mulai: 100), isEmpty);
      expect(tableLabels(count: kMaxTableBatch + 1, mulai: 1), isEmpty);
    });
  });

  group('unduhan borongan di web', () {
    final sumber = File('lib/utils/table_qr_image.dart').readAsStringSync();
    final layar =
        File('lib/screens/table_qr_generator_screen.dart').readAsStringSync();

    // Empat puluh unduhan beruntun: peramban menanyakan izin di unduhan
    // kedua, dan yang menolaknya mendapat satu berkas dari empat puluh
    // tanpa tahu sisanya ke mana.
    test('dikumpulkan jadi satu zip, bukan diunduh satu per satu', () {
      expect(sumber, contains('ZipEncoder().encode(arsip)'));
      expect(sumber, contains("'application/zip'"));
      expect(sumber, contains('arsip.addFile('));
    });

    // Di ponsel zip tidak ada gunanya — galeri tidak bisa membukanya.
    test('di ponsel tetap masuk galeri satu per satu', () {
      expect(sumber, contains('if (kIsWeb) {'));
      expect(sumber, contains('await putPngInGallery(png, namaBerkas: nama)'));
    });

    test('pesannya menyebut yang benar-benar terjadi', () {
      expect(sumber, contains('diunduh sebagai satu zip'));
    });

    test('nomor awal ada di layarnya, dan diperiksa', () {
      expect(layar, contains("labelText: 'Nomor Awal'"));
      expect(layar, contains('mulai: _mulai'));
      expect(layar, contains("'Nomor awal minimal 1.'"));
    });
  });
}
