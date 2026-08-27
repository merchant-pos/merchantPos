import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/restaurant.dart';

void main() {
  final sql = File('supabase/resto_soft_delete.sql').readAsStringSync();
  final repo = File('lib/db/restaurant_repository.dart').readAsStringSync();
  final layar =
      File('lib/screens/restaurant_manage_list_screen.dart').readAsStringSync();

  group('penanda terhapus', () {
    test('bawaannya belum terhapus', () {
      final r = Restaurant(id: 'r1', name: 'Warung A', address: 'Jl. 1');
      expect(r.isDeleted, isFalse);
      expect(r.deletedAt, isNull);
    });

    test('terbaca dari database', () {
      final r = Restaurant.fromMap('r1', {
        'name': 'Warung A',
        'address': 'Jl. 1',
        'is_deleted': true,
        'deleted_at': '2026-08-17T10:00:00Z',
      });
      expect(r.isDeleted, isTrue);
      expect(r.deletedAt, isNotNull);
    });

    test('baris lama tanpa kolomnya dibaca sebagai belum terhapus', () {
      final r = Restaurant.fromMap('r1', {'name': 'A', 'address': ''});
      expect(r.isDeleted, isFalse);
    });
  });

  group('yang terhapus benar-benar berhenti', () {
    test('bukan sekadar disembunyikan dari daftar', () {
      // Pelanggan yang memindai QR meja yang masih tertempel akan tetap
      // sampai ke menunya — dan memesan dari resto yang sudah tidak
      // melayani siapa pun.
      expect(sql, contains('"orders: deleted resto"'));
      expect(sql, contains('"products: deleted resto"'));
    });

    test('dipasang RESTRICTIVE, bukan permissive', () {
      // Permissive digabung dengan OR: menambah satu justru
      // melonggarkan aksesnya.
      final blok = sql.substring(sql.indexOf('"orders: deleted resto"'));
      expect(blok, contains('as restrictive'));
    });

    test('berhenti ditagih bulan depan', () {
      expect(sql, contains('r.is_deleted = false'));
    });

    test('tagihan yang sudah terbit tidak dihapus', () {
      // Itu utang yang benar-benar pernah ada; menghapusnya berarti
      // menghapus catatan pendapatan yang mungkin sudah masuk.
      expect(sql, isNot(contains('delete from billing_invoices')));
    });

    test('tidak dikunci karena tagihan', () {
      // Layar penguncian menawarkan membayar, dan tidak ada gunanya
      // menagih resto yang sudah kita hentikan sendiri.
      expect(sql, contains('when is_resto_deleted(p_resto_id) then false'));
    });
  });

  group('wewenang dan pengaman', () {
    test('hanya Super Admin yang boleh menghapus', () {
      expect(sql, contains('Hanya Super Admin yang dapat menghapus merchant'));
    });

    test('penyewa platform tidak bisa dihapus', () {
      expect(sql, contains('Penyewa platform tidak dapat dihapus'));
    });

    test('mencatat siapa dan kapan', () {
      // Penghapusan tanpa jejak pelakunya adalah pertanyaan yang tidak
      // akan pernah terjawab saat ada yang menanyakannya nanti.
      expect(sql, contains('deleted_by ='));
      expect(sql, contains('deleted_at ='));
    });

    test('lewat RPC, bukan update langsung', () {
      expect(repo, contains("rpc('set_resto_deleted'"));
    });
  });

  group('daftar merchant', () {
    test('menyaring yang terhapus secara bawaan', () {
      expect(repo, contains("if (!includeDeleted) q = q.eq('is_deleted', false)"));
    });

    test('daftar pelanggan tidak pernah memuat yang terhapus', () {
      final aktif = repo.substring(repo.indexOf('getAllActive'));
      expect(aktif, contains(".eq('is_deleted', false)"));
    });

    test('yang terhapus hanya menawarkan Kembalikan', () {
      // Menyisakan saklar aktif dan tombol ubah berarti tiga tombol yang
      // dua di antaranya tidak berpengaruh apa pun.
      expect(layar, contains("label: const Text('Kembalikan')"));
      expect(layar, contains('resto.isDeleted\n'));
    });

    test('dikembalikan tidak langsung ikut aktif', () {
      // Resto yang dikembalikan belum tentu siap melayani, dan
      // menyalakannya diam-diam berarti pelanggan bisa memesan sebelum
      // ada yang memeriksa menunya.
      expect(layar, contains('Aktifkan lagi kalau sudah siap melayani'));
    });
  });
}
