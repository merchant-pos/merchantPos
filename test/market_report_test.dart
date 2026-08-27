import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Analisa pasar dihitung seluruhnya di server, jadi yang diperiksa di
/// sini adalah kueri-nya sendiri.
///
/// Terlihat berlebihan sampai diingat apa yang terjadi kalau salah satu
/// syaratnya hilang: angkanya tetap keluar, tetap terlihat masuk akal,
/// dan tidak ada satu pun tanda bahwa peringkatnya salah.
void main() {
  final sql = File('supabase/market_report.sql').readAsStringSync();
  final repo =
      File('lib/db/market_report_repository.dart').readAsStringSync();

  group('siapa yang boleh membacanya', () {
    test('keempatnya menuntut Super Admin', () {
      // SECURITY DEFINER tanpa penjaga ini membocorkan seluruh pasar
      // KaataGo ke siapa pun yang bisa memanggil RPC.
      expect('is_super_admin()'.allMatches(sql).length, greaterThanOrEqualTo(4));
    });

    test('penolakannya berupa daftar kosong, bukan pesan', () {
      // Pesan galat mengonfirmasi bahwa datanya ada.
      expect(sql, isNot(contains('raise exception')));
      expect(sql, contains('where is_super_admin()'));
    });

    test('anon tidak bisa memanggilnya', () {
      for (final fn in [
        'report_top_customers',
        'report_idle_customers',
        'report_top_restos',
        'report_idle_restos',
      ]) {
        expect(sql, contains('revoke all on function $fn(integer) from public, anon;'),
            reason: fn);
      }
    });
  });

  group('apa yang dihitung', () {
    test('hanya pesanan yang benar-benar dibayar', () {
      // Pesanan batal pernah ada di layar kasir tapi tidak pernah jadi
      // uang; memasukkannya membuat resto yang banyak batal terlihat
      // lebih besar daripada yang benar-benar berjualan.
      expect("payment_status = 'paid'".allMatches(sql).length, 4);
    });

    test('merchant platform dan yang terhapus tidak ikut', () {
      expect('coalesce(r.is_platform, false) = false'.allMatches(sql).length, 3);
      expect('coalesce(r.is_deleted, false) = false'.allMatches(sql).length, 3);
    });

    test('peringkat pelanggan terbatas pada akun terdaftar', () {
      // Dua tamu bernama "Budi" di dua resto berbeda bukan satu orang.
      expect(sql, contains('exists (select 1 from customers c2'));
    });

    test('merchant tanpa penghasilan dicari lewat LEFT JOIN', () {
      // Resto yang seluruh pesanannya batal punya baris di orders tapi
      // nol rupiah — dan itu justru yang paling perlu ditengok.
      expect(sql, contains('left join orders o'));
      expect(sql, contains('having coalesce(sum(o.total), 0) = 0'));
    });

    test('jumlah pesanannya ikut supaya yang mencoba lalu gagal kelihatan', () {
      expect(sql, contains('count(o.id) filter (where o.id is not null)'));
    });

    test('pelanggan diam dinilai dari pesanan terbayar', () {
      expect(sql,
          contains("o.customer_label = c.email and o.payment_status = 'paid'"));
    });

    test('batasnya dijepit, tidak dipercaya apa adanya', () {
      // p_limit datang dari pemanggil; tanpa jepitan, satu panggilan
      // bisa meminta seluruh tabel.
      expect('greatest(1, least('.allMatches(sql).length, 4);
    });
  });

  group('sisi aplikasi', () {
    test('tidak menghitung apa pun sendiri', () {
      // Menjumlahkan di HP berarti batas 1.000 baris PostgREST
      // memotongnya diam-diam.
      expect(repo, isNot(contains(".from('orders')")));
      expect(repo, contains('_client.rpc(fn'));
    });

    test('keempat laporannya terpanggil', () {
      for (final fn in [
        'report_top_customers',
        'report_idle_customers',
        'report_top_restos',
        'report_idle_restos',
      ]) {
        expect(repo, contains(fn), reason: fn);
      }
    });
  });
}
