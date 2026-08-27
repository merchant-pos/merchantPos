import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bagan akun bawaan hidup di SQL, bukan di Dart — jadi yang diperiksa
/// di sini adalah berkasnya sendiri.
///
/// Terlihat berlebihan sampai diingat apa yang terjadi kalau salah satu
/// nomornya hilang: pemicu jurnal melewatkan baris yang GL-nya kosong,
/// jadi transaksinya benar-benar terjadi tapi tidak pernah masuk Jurnal
/// GL. Yang menemukannya adalah Finance, berminggu-minggu kemudian.
void main() {
  final sql = File('supabase/default_gl_accounts.sql').readAsStringSync();

  group('bagan akun bawaan', () {
    test('setiap jenis akun punya nomor bawaannya', () {
      // Daftar ini harus sama dengan yang diterima batasan
      // gl_accounts_payment_method_check.
      for (final method in [
        'cash',
        'qris',
        'transfer',
        'income_aggregate',
        'ppn',
        'service',
        'petty_cash',
        'total_balance',
        'suspense',
        'suspense_petty',
        'gateway_fee',
        'discount',
      ]) {
        expect(sql, contains("('$method',"), reason: 'belum ada bawaan: $method');
      }
    });

    test('pengelompokan nomornya sesuai', () {
      expect(sql, contains("('cash',             '195"));
      expect(sql, contains("('ppn',              '196"));
      expect(sql, contains("('petty_cash',       '198"));
      expect(sql, contains("('total_balance',    '199"));
      expect(sql, contains("('suspense',         '210"));
      expect(sql, contains("('gateway_fee',      '220"));
      expect(sql, contains("('discount',         '220"));
    });

    test('tarif bawaannya 11% dan 5%', () {
      expect(sql, contains('ppn_percent set default 11'));
      expect(sql, contains('service_percent set default 5'));
    });

    test('tidak menimpa nomor yang sudah disetel Finance', () {
      // `do update` di sini akan mengembalikan bagan akun resto yang
      // sudah berjalan ke bawaan, tiap kali berkasnya dijalankan lagi.
      //
      // Barisan komentar dibuang dulu — kalimat penjelasnya sendiri
      // menyebut 'do update', dan tes yang tertipu oleh komentarnya
      // sendiri tidak menjaga apa pun.
      final perintah = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');

      expect(perintah, contains('do nothing'));
      expect(perintah, isNot(contains('do update')));
    });

    test('merchant baru terisi lewat pemicu, bukan lewat aplikasi', () {
      // Resto bisa dibuat dari layar Super Admin, dari SQL saat
      // memulihkan data, atau dari alat lain nanti.
      expect(sql, contains('after insert on restaurants'));
    });
  });

  group('diskon', () {
    test('nomor GL diskon sama di kedua berkas', () {
      // discounts.sql menyisipkannya juga untuk resto yang sudah ada;
      // dua nomor berbeda berarti dua akun diskon di resto yang sama.
      final discounts = File('supabase/discounts.sql').readAsStringSync();
      expect(discounts, contains('2200002'));
      expect(sql, contains('2200002'));
    });
  });

  group('daftar batasan tidak boleh mundur', () {
    // Tiga kali berturut-turut migrasi gagal dengan sebab yang sama:
    // berkas lama menuliskan daftar nilai sepanjang zamannya sendiri,
    // lalu dijalankan ulang sesudah berkas baru menambah nilai. Daftar
    // menyempit, baris yang sudah memakai nilai baru melanggarnya, dan
    // pesannya menuduh datanya yang salah.
    //
    // Tes ini membaca berkasnya langsung: tiap batasan bernama hanya
    // boleh punya SATU bentuk daftar di seluruh folder supabase.
    test('satu nama batasan, satu daftar nilai', () {
      final pola = RegExp(
        r'add constraint (\w+)\s*\n?\s*check \((.*?)\);',
        dotAll: true,
      );
      final daftar = <String, Set<String>>{};

      for (final f in Directory('supabase').listSync()) {
        if (f is! File || !f.path.endsWith('.sql')) continue;
        if (f.path.endsWith('JALANKAN-INI.sql')) continue;
        for (final m in pola.allMatches(f.readAsStringSync())) {
          final nama = m.group(1)!;
          final isi = m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
          daftar.putIfAbsent(nama, () => {}).add(isi);
        }
      }

      final bercabang = {
        for (final e in daftar.entries)
          if (e.value.length > 1) e.key: e.value.length,
      };
      expect(bercabang, isEmpty,
          reason: 'daftarnya harus sama persis di semua berkas');
    });
  });
}
