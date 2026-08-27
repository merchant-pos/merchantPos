import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/order_type.dart';
import 'package:merchant_pos/models/restaurant.dart';

Restaurant _resto({bool dineIn = true, bool takeAway = true}) => Restaurant(
      id: 'r1',
      name: 'MerchantPos Merchant',
      address: 'Jl. Contoh',
      dineInEnabled: dineIn,
      takeAwayEnabled: takeAway,
    );

void main() {
  group('Restaurant.orderTypes', () {
    test('merchant lama tanpa kolomnya melayani keduanya', () {
      final resto = Restaurant.fromMap('r1', {'name': 'Lama', 'address': 'x'});

      expect(resto.dineInEnabled, isTrue);
      expect(resto.takeAwayEnabled, isTrue);
      expect(resto.orderTypes, [OrderType.dineIn, OrderType.takeAway]);
    });

    test('yang dimatikan tidak ikut ditawarkan', () {
      expect(_resto(dineIn: false).orderTypes, [OrderType.takeAway]);
      expect(_resto(takeAway: false).orderTypes, [OrderType.dineIn]);
    });

    test('tidak pernah kosong, walau keduanya dimatikan', () {
      // Kalau kosong, layar checkout tidak punya satu pun pilihan yang
      // bisa ditekan dan resto itu berhenti bisa menerima pesanan sama
      // sekali. Dine In yang dipaksakan jauh lebih ringan akibatnya.
      final buntu = _resto(dineIn: false, takeAway: false);

      expect(buntu.orderTypes, isNotEmpty);
      expect(buntu.orderTypes, [OrderType.dineIn]);
    });

    test('kedua kolomnya selalu dikirim saat menyimpan', () {
      // toMap() yang melewatkan kolomnya akan membuat penyimpanan dari
      // layar lain diam-diam menyalakan ulang keduanya.
      final map = _resto(takeAway: false).toMap();

      expect(map['dine_in_enabled'], isTrue);
      expect(map['take_away_enabled'], isFalse);
    });
  });
}
