import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/customer_order.dart';

/// Pesanan yang batal berhenti punya status dapur.
///
/// Sebelumnya `kitchen_status` berhenti di nilai terakhirnya, dan tiap
/// layar harus ingat sendiri untuk mengabaikannya. Yang lupa mengingat
/// itu menampilkan "Sedang Dimasak" ke pelanggan yang pesanannya sudah
/// batal.
void main() {
  final sql = File('supabase/order_cancel_kitchen.sql').readAsStringSync();

  group('di datanya', () {
    test('kolomnya menerima nilai cancelled', () {
      expect(sql,
          contains("check (kitchen_status in ('waiting', 'onProgress', 'done', 'cancelled'))"));
    });

    test('ditulis pemicu, bukan diserahkan ke tiap layar', () {
      // Lebih baik keadaannya ditulis apa adanya sekali daripada
      // diperbaiki berulang kali di tiap layar yang menampilkannya.
      expect(sql, contains('before update on orders'));
      expect(sql, contains("new.kitchen_status := 'cancelled'"));
    });

    test('batal dan hangus diperlakukan sama', () {
      // Keduanya berarti sama bagi dapur: makanannya tidak jadi dibuat.
      expect(sql, contains("in ('cancelled', 'expired')"));
    });

    test('yang sudah matang tidak dihapus jejaknya', () {
      // Pesanan yang matang lalu dibatalkan tetap pernah dimasak, dan
      // bahannya sudah terpakai.
      expect(sql, contains("new.kitchen_status <> 'done'"));
    });

    test('hanya saat statusnya benar-benar berubah', () {
      expect(sql, contains('old.payment_status is distinct from new.payment_status'));
    });

    test('data lama ikut dibereskan', () {
      // Tanggal berkas ini dijalankan bukan garis pemisah antara data
      // yang benar dan yang menyesatkan.
      expect(sql, contains('update orders'));
      expect(sql, contains("kitchen_status in ('waiting', 'onProgress')"));
    });
  });

  group('di aplikasinya', () {
    test('enumnya mengenal cancelled', () {
      expect(KitchenStatus.values, contains(KitchenStatus.cancelled));
    });

    test('nilai tak dikenal tidak menjatuhkan barisnya', () {
      final o = CustomerOrder.fromMap({
        'id': 'x',
        'created_at': '2026-08-24T10:00:00Z',
        'items': <dynamic>[],
        'total': 1000,
        'payment_status': 'cancelled',
        'customer_label': 'Tamu',
        'resto_id': 'r1',
        'kitchen_status': 'entah',
      });
      expect(o.kitchenStatus, KitchenStatus.waiting);
    });

    test('terbaca dari baris database', () {
      final o = CustomerOrder.fromMap({
        'id': 'x',
        'created_at': '2026-08-24T10:00:00Z',
        'items': <dynamic>[],
        'total': 1000,
        'payment_status': 'cancelled',
        'customer_label': 'Tamu',
        'resto_id': 'r1',
        'kitchen_status': 'cancelled',
      });
      expect(o.kitchenStatus, KitchenStatus.cancelled);
      expect(o.dibatalkan, isTrue);
    });

    test('tiap layar punya label dan warnanya', () {
      for (final f in [
        'lib/screens/customer_order_status_screen.dart',
        'lib/screens/customer_history_screen.dart',
      ]) {
        final isi = File(f).readAsStringSync();
        expect(isi, contains("KitchenStatus.cancelled: 'Dibatalkan'"),
            reason: f);
        expect(isi, contains('KitchenStatus.cancelled: Colors.grey'),
            reason: f);
      }
    });

    test('riwayat pesanan ikut diperbaiki, bukan cuma status berjalan', () {
      // Layar ini sempat tertinggal saat perbaikan pertama.
      final riwayat =
          File('lib/screens/customer_history_screen.dart').readAsStringSync();
      expect(riwayat, contains('KitchenStatus.cancelled'));
    });

    test('dapur tidak menawarkan tombol untuk yang batal', () {
      final chef =
          File('lib/screens/chef_home_screen.dart').readAsStringSync();
      final blok = chef.substring(chef.indexOf('switch (order.kitchenStatus)'));
      // Digabung dengan `done` — keduanya sama-sama tidak menawarkan
      // tombol apa pun.
      expect(blok, contains('case KitchenStatus.done:'));
      expect(blok, contains('case KitchenStatus.cancelled:\n        return null;'));
      // Dan barisnya memang sudah disaring keluar dari tab mana pun.
      expect(chef, contains('!o.dibatalkan'));
    });
  });
}
