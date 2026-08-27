import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/merchant_report.dart';

void main() {
  group('model laporan', () {
    test('ringkasan kosong berbeda dari nol rupiah', () {
      expect(const RingkasanPenjualan().kosong, isTrue);
      expect(
        RingkasanPenjualan.fromMap(const {'orders_count': 3, 'omzet': 0})
            .kosong,
        isFalse,
      );
    });

    test('angkanya terbaca dari jawaban server', () {
      final r = RingkasanPenjualan.fromMap(const {
        'orders_count': 12,
        'omzet': 480000,
        'rata_transaksi': 40000,
        'menu_terjual': 31,
      });
      expect(r.jumlahPesanan, 12);
      expect(r.omzet, 480000);
      expect(r.rataTransaksi, 40000);
      expect(r.menuTerjual, 31);
    });

    // Menu yang sudah dihapus tetap punya sejarah penjualan. Laporan
    // yang menghilangkannya menyebut omzet lebih kecil daripada yang
    // benar-benar diterima.
    test('menu tanpa nama tetap punya sebutan', () {
      final m = PenjualanMenu.fromMap(const {'product_id': 'p1', 'qty': 3});
      expect(m.nama, 'Menu sudah dihapus');
    });

    test('jam ditulis dua digit berikut menitnya', () {
      expect(JamRamai.fromMap(const {'jam': 7}).label, '07:00');
      expect(JamRamai.fromMap(const {'jam': 14}).label, '14:00');
    });
  });

  group('SQL-nya', () {
    final sql = File('supabase/merchant_report.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('merchant_report.sql'));
    });

    // Yang tidak berhak menerima daftar kosong. Pesan galat justru
    // mengonfirmasi bahwa datanya ada.
    test('hanya Owner dan Admin, ditulis sebagai syarat WHERE', () {
      final fungsi = [
        'report_menu_sales',
        'report_idle_menus',
        'report_busy_hours',
        'report_sales_summary',
      ];
      for (final f in fungsi) {
        final badan = sql.substring(sql.indexOf('function $f'));
        final sampai = badan.indexOf(r'$$;');
        expect(badan.substring(0, sampai),
            contains("is_resto_employee(p_resto_id, array['owner', 'admin'])"),
            reason: '$f tanpa penjaga peran');
      }
      expect(sql, isNot(contains('raise exception')));
    });

    test('hanya pesanan lunas yang dihitung', () {
      expect("'paid'".allMatches(sql).length, greaterThanOrEqualTo(4));
      expect(sql, isNot(contains("payment_status = 'pending'")));
    });

    // Jam ramai yang bergeser tujuh jam adalah jadwal shift yang salah.
    test('tanggal dan jamnya WIB, bukan UTC', () {
      expect("at time zone 'Asia/Jakarta'".allMatches(sql).length,
          greaterThanOrEqualTo(5));
    });

    // Menu yang tidak pernah terjual tidak punya baris di orders sama
    // sekali — jadi harus dibaca dari katalognya.
    test('menu tidak laku dibaca dari katalog, lewat LEFT JOIN', () {
      final fn = sql.substring(sql.indexOf('function report_idle_menus'));
      expect(fn, contains('from products p'));
      expect(fn, contains('left join terjual'));
      expect(fn, contains('coalesce(t.qty, 0) = 0'));
    });

    test('batas peringkatnya dijepit, tidak dipercaya apa adanya', () {
      expect(sql, contains('greatest(1, least(coalesce(p_limit, 10), 100))'));
    });
  });

  group('pintunya', () {
    test('ada di beranda Owner dan Admin', () {
      for (final f in ['owner_home_screen', 'admin_home_screen']) {
        final isi = File('lib/screens/$f.dart').readAsStringSync();
        expect(isi, contains("title: 'Laporan Penjualan'"), reason: f);
        expect(isi, contains('MerchantReportScreen()'), reason: f);
      }
    });

    // Yang dibutuhkan kasir dan chef pesanan yang sedang berjalan, bukan
    // peringkat menu — dan omzet merchant bukan angka yang perlu beredar
    // di antara semua orang yang memegang HP.
    test('tidak ada di beranda kasir, chef, maupun finance', () {
      for (final f in [
        'kasir_home_screen',
        'chef_home_screen',
        'finance_home_screen',
      ]) {
        final isi = File('lib/screens/$f.dart').readAsStringSync();
        expect(isi, isNot(contains('MerchantReportScreen')), reason: f);
      }
    });
  });
}
