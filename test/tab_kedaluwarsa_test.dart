import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Daftar yang menumpuk terus dipisah antara yang masih hidup dan yang
/// sudah lewat.
///
/// Batch voucher, diskon langganan, dan voucher pelanggan sama-sama
/// bertambah dan tidak pernah menyusut — dan yang dicari hampir selalu
/// yang masih berlaku.
void main() {
  final voucher = File('lib/screens/voucher_screen.dart').readAsStringSync();
  final diskon =
      File('lib/screens/billing_discount_screen.dart').readAsStringSync();
  final punyaku =
      File('lib/screens/my_vouchers_screen.dart').readAsStringSync();

  group('voucher pelanggan (Merchant-POS Admin)', () {
    test('punya dua tab', () {
      expect(voucher, contains('TabController(length: 2'));
      expect(voucher, contains("Tab(text: 'Berjalan (\${_aktif.length})')"));
      expect(voucher, contains("Tab(text: 'Kedaluwarsa (\${_lampau.length})')"));
    });

    test('yang ditutup manual tetap di tab berjalan', () {
      // Ia bisa dibuka lagi; memindahkannya ke riwayat berarti
      // menyembunyikan sesuatu yang masih bisa diubah.
      expect(voucher, contains('if (!v.kedaluwarsa) v'));
    });

    test('kartu ringkasan hanya di tab yang berjalan', () {
      // Yang menggantung selalu berasal dari voucher yang belum hangus.
      expect(voucher, contains('if (aktif && _items.isNotEmpty)'));
    });

    test('tiap tab punya kalimat kosongnya sendiri', () {
      expect(voucher, contains('Belum ada voucher yang berjalan.'));
      expect(voucher, contains('Belum ada voucher yang kedaluwarsa.'));
    });

    test('controllernya dilepas', () {
      expect(voucher, contains('_tab.dispose();'));
    });
  });

  group('diskon langganan', () {
    test('punya dua tab', () {
      expect(diskon, contains('TabController(length: 2'));
      expect(diskon, contains("Tab(text: 'Berlaku (\${_aktif.length})')"));
      expect(diskon, contains("Tab(text: 'Sudah Lewat (\${_lampau.length})')"));
    });

    test('yang tanpa tanggal akhir tidak pernah lewat', () {
      // Itu memang diskon yang berlaku sampai dicabut orangnya.
      expect(diskon, contains('if (akhir == null) return false;'));
    });

    test('yang sudah lewat tetap bisa dibaca', () {
      // Satu-satunya catatan kenapa tagihan bulan lalu berbeda.
      expect(diskon, contains('_daftar(_lampau, aktif: false)'));
    });

    test('controllernya dilepas', () {
      expect(diskon, contains('_tab.dispose();'));
    });
  });

  group('voucher saya (pelanggan)', () {
    test('dipisah jadi dua pilihan', () {
      expect(punyaku, contains('SegmentedButton<bool>('));
      expect(punyaku, contains('Siap Dipakai (\${siap.length})'));
      expect(punyaku, contains('Riwayat (\${lampau.length})'));
    });

    test('kolom tebus tetap terlihat di keduanya', () {
      // Kode voucher datang kapan saja; menyembunyikan kolomnya di balik
      // satu tab berarti orang harus tahu dulu tab mana yang benar.
      final i = punyaku.indexOf("hintText: 'Punya kode voucher?'");
      final j = punyaku.indexOf('SegmentedButton<bool>(');
      expect(i, lessThan(j));
    });

    test('tiap sisi punya kalimat kosongnya sendiri', () {
      expect(punyaku, contains('Belum ada voucher yang sudah dipakai atau '));
      expect(punyaku, contains('Belum ada voucher yang siap dipakai.'));
    });
  });
}
