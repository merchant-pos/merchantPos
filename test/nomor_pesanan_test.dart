import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/customer_order.dart';

/// Nomor pesanan harian per resto.
///
/// UUID cukup untuk mesin, tidak untuk orang: kasir tidak bisa
/// memanggil "pesanan 8f3a1c2e" ke ruangan.
void main() {
  final sql = File('supabase/order_number.sql').readAsStringSync();

  CustomerOrder pesanan({int? no}) => CustomerOrder(
        id: '8f3a1c2e-0000-0000-0000-000000000000',
        orderNo: no,
        createdAt: DateTime(2026, 8, 20, 9),
        items: const [],
        total: 50000,
        paymentStatus: OrderPaymentStatus.pending,
        customerLabel: 'Tamu',
        restoId: 'r1',
      );

  group('bentuk nomornya', () {
    test('tiga digit supaya deretannya rata', () {
      expect(pesanan(no: 1).nomorTampil, '#001');
      expect(pesanan(no: 14).nomorTampil, '#014');
      expect(pesanan(no: 250).nomorTampil, '#250');
    });

    test('merchant yang tembus seribu tidak terpotong', () {
      expect(pesanan(no: 1024).nomorTampil, '#1024');
    });

    test('pesanan lama tanpa nomor tidak berpura-pura punya', () {
      expect(pesanan().punyaNomor, isFalse);
      expect(pesanan().nomorTampil, '');
    });

    test('terbaca dari baris database', () {
      final o = CustomerOrder.fromMap({
        'id': 'x',
        'created_at': '2026-08-20T02:00:00Z',
        'items': <dynamic>[],
        'total': 1000,
        'payment_status': 'pending',
        'customer_label': 'Tamu',
        'resto_id': 'r1',
        'order_no': 7,
      });
      expect(o.orderNo, 7);
      expect(o.nomorTampil, '#007');
    });
  });

  group('cara servernya memberi nomor', () {
    test('diberikan saat pesanannya dibuat, bukan saat dibayar', () {
      // Pelanggan yang masih menunggu QRIS sudah memegang nomornya —
      // itu yang disebut kasir kalau QRIS-nya gagal dan dia beralih
      // membayar tunai.
      expect(sql, contains('before insert on orders'));
      final awal = sql.indexOf('function assign_order_no');
      final fn = sql.substring(awal, sql.indexOf('drop trigger', awal));
      expect(fn, isNot(contains('payment_status')),
          reason: 'status bayar tidak boleh jadi syarat pemberian nomor');
    });

    test('pertambahannya di dalam basis data, bukan di aplikasi', () {
      // Membacanya dulu lalu menambah satu di aplikasi berarti dua
      // pesanan yang datang bersamaan membaca angka yang sama.
      expect(sql, contains('do update set last_no = order_counters.last_no + 1'));
      expect(sql, contains('returning last_no into v_no'));
    });

    test('nomor kembar ditolak basis data', () {
      expect(sql, contains('create unique index if not exists orders_no_harian_idx'));
      expect(sql, contains('on orders (resto_id, order_date, order_no)'));
    });

    test('harinya memakai waktu Jakarta', () {
      // UTC berarti nomornya berganti pukul tujuh pagi — di tengah
      // persiapan buka.
      expect(sql, contains("at time zone 'Asia/Jakarta'"));
    });

    test('berdiri sendiri per merchant dan per hari', () {
      expect(sql, contains('primary key (resto_id, order_date)'));
    });

    test('pencacahnya tidak bisa disentuh siapa pun', () {
      expect(sql, contains('alter table order_counters enable row level security'));
      expect(sql, isNot(contains('create policy "order_counters')));
    });

    test('pesanan lama ikut diberi nomor menurut urutan waktunya', () {
      expect(sql, contains('row_number() over ('));
      expect(sql, contains('where order_no is null'));
    });

    test('pencacahnya ikut disetel supaya tidak menabrak nomor lama', () {
      expect(sql, contains('greatest(order_counters.last_no, excluded.last_no)'));
    });

    test('nomor yang sudah terbit tidak ditimpa', () {
      expect(sql, contains('if new.order_no is not null then'));
    });
  });

  group('di layar', () {
    test('pelanggan melihatnya di status pesanannya', () {
      final layar = File('lib/screens/customer_order_status_screen.dart')
          .readAsStringSync();
      expect(layar, contains('order.punyaNomor'));
      expect(layar, contains('order.nomorTampil'));
    });

    test('kartu pesanan menaruhnya paling depan', () {
      // Itu yang diteriakkan ke ruangan.
      final kartu = File('lib/widgets/order_card.dart').readAsStringSync();
      expect(kartu, contains('if (order.punyaNomor) ...['));
      expect(kartu.indexOf('order.nomorTampil'),
          lessThan(kartu.indexOf("'Meja \${order.tableNumber}'")));
    });

    test('kedua struk menyebutnya', () {
      for (final f in [
        'lib/screens/customer_receipt_screen.dart',
        'lib/screens/receipt_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains("('No. Pesanan',"),
            reason: f);
      }
    });
  });
}
