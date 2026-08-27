import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `alter publication ... add table` gagal kalau tabelnya sudah
/// terdaftar, dan galatnya menghentikan sisa bagiannya.
///
/// Menjalankan ulang JALANKAN-INI.sql adalah hal biasa — dan seluruh
/// gagasan berkas itu bersandar pada aman-diulang.
void main() {
  test('setiap pendaftaran realtime dibungkus penangkap galat', () {
    final telanjang = <String>[];

    for (final f in Directory('supabase').listSync()) {
      if (f is! File || !f.path.endsWith('.sql')) continue;
      if (f.path.endsWith('JALANKAN-INI.sql')) continue;

      final isi = f.readAsStringSync();
      for (final baris in isi.split('\n')) {
        if (!baris.contains('alter publication')) continue;
        // Yang dibungkus DO ditulis menjorok; yang telanjang rata kiri.
        if (!baris.startsWith('  ')) telanjang.add('${f.path}: ${baris.trim()}');
      }
    }

    expect(telanjang, isEmpty,
        reason: 'galat "already member of publication" menghentikan '
            'sisa bagiannya');
  });

  test('yang dipakai menangkap duplicate_object', () {
    final display = File('supabase/customer_display.sql').readAsStringSync();
    expect(display, contains('exception when duplicate_object then null;'));
  });
}
