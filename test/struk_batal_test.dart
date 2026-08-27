import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/customer_order.dart';
import 'package:merchant_pos/models/order_type.dart';

CustomerOrder pesanan(OrderPaymentStatus status) => CustomerOrder(
      id: 'o1',
      createdAt: DateTime(2026, 8, 24),
      items: const [],
      total: 50000,
      paymentStatus: status,
      customerLabel: 'budi@toko.com',
      source: OrderSource.customer,
      kitchenStatus: KitchenStatus.waiting,
      itemsDone: const {},
      restoId: 'r1',
      orderType: OrderType.dineIn,
    );

/// Struk adalah bukti pembayaran.
///
/// Menerbitkannya untuk pesanan yang uangnya tidak pernah berpindah
/// berarti membuat bukti atas sesuatu yang tidak terjadi — dan yang
/// memegangnya bisa memakainya untuk menagih, mengklaim ke kantor, atau
/// menuntut barangnya.
void main() {
  group('mana yang dianggap batal', () {
    test('dibatalkan dan hangus sama-sama tanpa struk', () {
      expect(pesanan(OrderPaymentStatus.cancelled).dibatalkan, isTrue);
      expect(pesanan(OrderPaymentStatus.expired).dibatalkan, isTrue);
    });

    test('yang lunas dan yang menunggu tidak', () {
      expect(pesanan(OrderPaymentStatus.paid).dibatalkan, isFalse);
      expect(pesanan(OrderPaymentStatus.pending).dibatalkan, isFalse);
    });
  });

  group('penjaganya', () {
    final struk =
        File('lib/screens/customer_receipt_screen.dart').readAsStringSync();

    // Ada tiga pintu menuju layar ini hari ini, dan pintu keempat yang
    // dibuat nanti tidak akan ingat memasang penjaganya sendiri.
    test('dipasang di struknya, bukan di tiap pintu', () {
      final build = struk.substring(struk.indexOf('Widget build(BuildContext'));
      expect(build.substring(0, build.indexOf('return Scaffold(')),
          contains('if (widget.order.dibatalkan)'));
    });

    test('menjelaskan kenapa, bukan sekadar layar kosong', () {
      expect(struk, contains('Pesanan ini tidak punya struk'));
      expect(struk, contains('tidak ada pembayaran yang bisa dibuktikan'));
    });
  });

  group('pintunya', () {
    // Tombol yang membuka penjelasan "tidak ada struk" tetap tombol yang
    // mengecewakan.
    test('riwayat pelanggan tidak membuka struk pesanan batal', () {
      final isi =
          File('lib/screens/customer_history_screen.dart').readAsStringSync();
      expect(isi, contains('onTap: order.dibatalkan'));
    });

    test('layar status tidak menawarkan tombol struknya', () {
      final isi = File('lib/screens/customer_order_status_screen.dart')
          .readAsStringSync();
      expect(isi, contains('if (!order.dibatalkan)'));
    });
  });
}
