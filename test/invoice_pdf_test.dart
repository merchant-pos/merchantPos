import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sumber = File('lib/utils/invoice_pdf.dart').readAsStringSync();

  group('kepala surat invoice', () {
    test('logonya dipasang di samping tulisan Merchant-POS', () {
      expect(sumber, contains("rootBundle.load('assets/icon/merchantpos_icon.png')"));
      expect(sumber, contains('pw.Image(logo, width: 34, height: 34)'));
    });

    test('logonya di kiri, sebelum tulisannya', () {
      final blok = sumber.substring(sumber.indexOf('pw.Row('));
      expect(blok.indexOf('pw.Image(logo'),
          lessThan(blok.indexOf("pw.Text('Merchant-POS'")));
    });

    test('gagal memuat logo tidak menjatuhkan struknya', () {
      // Bukti bayar yang tidak terbit karena satu gambar tidak ada
      // adalah kehilangan yang jauh lebih besar daripada kepala surat
      // tanpa logo.
      expect(sumber, contains('logo = null;'));
      expect(sumber, contains('if (logo != null) ...['));
    });
  });

  test('berkas logonya memang ada dan terbaca', () async {
    // Jalur yang salah ketik tidak akan ketahuan dari analyzer — yang
    // terjadi cuma struk tanpa logo, diam-diam, selamanya.
    final data = await rootBundle.load('assets/icon/merchantpos_icon.png');
    expect(data.lengthInBytes, greaterThan(0));
  });

  test('asetnya ikut dibundel', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/icon/'));
  });
}
