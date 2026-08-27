import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tombol simpan tidak boleh berubah jadi lingkaran memuat untuk sesuatu
/// yang tidak pernah dikirim.
///
/// Di layar banner promo urutannya sempat terbalik: `_saving = true`
/// lebih dulu, lalu pemeriksaan tanggal menolak dan keluar begitu saja —
/// meninggalkan tombol yang berputar selamanya. Yang melihatnya menunggu
/// simpanan yang tidak akan pernah selesai, dan satu-satunya jalan
/// keluar menutup layarnya.
void main() {
  test('pemeriksaan tanggal dijalankan sebelum tombolnya memuat', () {
    final layar = <String, String>{
      'promo_banner_screen': 'ada',
      'discount_screen': 'ada',
      'billing_discount_screen': 'ada',
    };

    for (final nama in layar.keys) {
      final isi = File('lib/screens/$nama.dart').readAsStringSync();
      final periksa = isi.indexOf('validatePeriod(');
      if (periksa < 0) continue;

      final memuat = RegExp(r'_(saving|menyimpan) = true')
          .firstMatch(isi.substring(0, periksa));
      expect(memuat, isNull,
          reason: '$nama menyalakan tombol memuat sebelum tanggalnya '
              'diperiksa — kalau tanggalnya ditolak, tombolnya berputar '
              'selamanya');
    }
  });

  test('setiap keluar lebih awal terjadi sebelum tombolnya memuat', () {
    // Semua layar yang punya tombol simpan bertahap: kalau ada `return`
    // sesudah menyalakan penanda memuat, penandanya harus dimatikan lagi
    // di jalan itu.
    for (final f in Directory('lib/screens').listSync()) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final isi = f.readAsStringSync();
      for (final m
          in RegExp(r'_(saving|menyimpan) = true\);').allMatches(isi)) {
        final sisa = isi.substring(m.end);
        final tutupFungsi = sisa.indexOf('\n  }');
        if (tutupFungsi < 0) continue;
        final badan = sisa.substring(0, tutupFungsi);
        // Yang punya `finally` sudah pasti mematikannya.
        if (badan.contains('finally')) continue;
        // Sisanya harus mematikannya sendiri di tiap jalan keluar.
        final keluarPolos = RegExp(r'\n      return;').allMatches(badan);
        for (final _ in keluarPolos) {
          expect(badan, contains(RegExp(r'_(saving|menyimpan) = false')),
              reason: '${f.path}: ada jalan keluar tanpa mematikan '
                  'penanda memuat');
        }
      }
    }
  });
}
