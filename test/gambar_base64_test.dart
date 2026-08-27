import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/utils/gambar_base64.dart';

/// Gambar base64 tidak boleh didekode ulang tiap layar dibangun.
///
/// MemoryImage membandingkan dirinya lewat identitas bytenya. Byte baru
/// berarti kunci cache gambar yang baru — Flutter mendekode ulang dari
/// nol, dan selama sekejap itu tempatnya kosong.
void main() {
  final contoh = base64Encode(Uint8List.fromList(List.filled(64, 7)));

  group('ingatannya', () {
    test('mengembalikan byte yang sama persis, bukan salinan baru', () {
      final a = byteGambar(contoh);
      final b = byteGambar(contoh);
      expect(identical(a, b), isTrue);
    });

    test('base64Decode biasa justru sebaliknya', () {
      // Inilah sebab kedipannya.
      expect(identical(base64Decode(contoh), base64Decode(contoh)), isFalse);
    });

    test('MemoryImage-nya jadi setara, jadi cache gambarnya kena', () {
      // Kesetaraan inilah yang dipakai Flutter sebagai kunci cache.
      expect(MemoryImage(byteGambar(contoh)) == MemoryImage(byteGambar(contoh)),
          isTrue);
      expect(
          MemoryImage(base64Decode(contoh)) ==
              MemoryImage(base64Decode(contoh)),
          isFalse);
    });

    test('isinya benar, bukan sekadar dikembalikan apa adanya', () {
      expect(byteGambar(contoh), base64Decode(contoh));
    });

    test('gambar berbeda tidak tertukar', () {
      final lain = base64Encode(Uint8List.fromList(List.filled(64, 9)));
      expect(byteGambar(contoh), isNot(byteGambar(lain)));
    });

    test('ingatannya dibatasi supaya tidak tumbuh selamanya', () {
      // Tablet kasir yang tidak pernah dimatikan berhari-hari yang
      // akan menemukannya kalau tidak dibatasi.
      final pertama = byteGambar(contoh);
      for (var i = 0; i < 200; i++) {
        byteGambar(base64Encode(Uint8List.fromList(List.filled(8, i % 251))));
      }
      // Yang paling lama tidak tersentuh sudah dibuang, jadi ia
      // didekode ulang — instansinya berbeda dari yang dulu.
      expect(identical(byteGambar(contoh), pertama), isFalse);
    });
  });

  group('dipakai di tiap tempat yang menggambar berulang', () {
    for (final f in [
      'lib/widgets/product_grid_card.dart',
      'lib/widgets/promo_banner_carousel.dart',
      'lib/widgets/quantity_dialog.dart',
      'lib/widgets/resto_logo_avatar.dart',
    ]) {
      test(f.split('/').last, () {
        final isi = File(f).readAsStringSync();
        expect(isi, contains('byteGambar('), reason: f);
      });
    }

    test('banner tidak lagi mendekode dua kali per build', () {
      // Latar kaburnya dan gambar depannya memakai gambar yang sama.
      final isi =
          File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();
      expect('byteGambar(banner.imageBase64)'.allMatches(isi).length, 3);
      // Yang tersisa cuma pembacaan ukuran, dan itu sekali saat dimuat.
      expect('base64Decode('.allMatches(isi).length, 1);
    });
  });
}
