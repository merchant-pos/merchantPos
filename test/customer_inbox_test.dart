import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/announcement.dart';

Announcement _a({
  String? restoId,
  String? restoName,
  AnnouncementAudience audience = AnnouncementAudience.all,
}) =>
    Announcement(
      id: 'a1',
      title: 'Diskon 20%',
      body: 'Hari ini saja',
      category: AnnouncementCategory.general,
      restoId: restoId,
      restoName: restoName,
      audience: audience,
      createdAt: DateTime(2026, 8, 16),
    );

void main() {
  group('jangkauan kotak masuk pelanggan', () {
    test('promo merchant sampai ke pelanggan yang pernah pesan di sana', () {
      // Inti perubahannya: bukan hanya ke orang yang kebetulan sedang
      // membuka menu resto itu — orang yang paling tidak membutuhkannya,
      // karena dia sudah ada di sana.
      expect(_a(restoId: 'warung-a').visibleToCustomer({'warung-a'}), isTrue);
    });

    test('tetap sampai walau sedang membuka merchant lain', () {
      expect(
        _a(restoId: 'warung-a').visibleToCustomer({'warung-a', 'kedai-b'}),
        isTrue,
      );
    });

    test('promo merchant lain tidak ikut masuk', () {
      expect(_a(restoId: 'warung-a').visibleToCustomer({'kedai-b'}), isFalse);
    });

    test('pengumuman tanpa merchant berlaku untuk semua', () {
      // Pemberitahuan versi baru dari Super Admin.
      expect(_a().visibleToCustomer({}), isTrue);
      expect(_a().visibleToCustomer({'warung-a'}), isTrue);
    });

    test('pelanggan baru yang belum pernah pesan tetap dapat kabar sistem', () {
      expect(_a().visibleToCustomer(const {}), isTrue);
      expect(_a(restoId: 'warung-a').visibleToCustomer(const {}), isFalse);
    });
  });

  group('nama pengirim', () {
    test('ikut terbawa saat ditandai sudah dibaca', () {
      // copyWith yang menjatuhkan nama restonya membuat promo berubah
      // jadi kabar tanpa pengirim tepat setelah dibuka — persis saat
      // orangnya ingin tahu harus datang ke mana.
      final dibaca = _a(restoId: 'warung-a', restoName: 'Warung A')
          .copyWith(read: true);

      expect(dibaca.restoName, 'Warung A');
      expect(dibaca.read, isTrue);
    });
  });

  group('sasaran pengumuman', () {
    test('pengumuman internal tidak pernah sampai ke pelanggan', () {
      // Jadwal shift dan aturan dapur bukan cuma tidak berguna bagi
      // pelanggan — sebagian memang tidak pantas dibaca mereka.
      final internal = _a(
        restoId: 'warung-a',
        audience: AnnouncementAudience.employees,
      );

      expect(internal.visibleToCustomer({'warung-a'}), isFalse);
      expect(internal.visibleToEmployee('warung-a'), isTrue);
    });

    test('promo pelanggan tidak memenuhi kotak masuk karyawan', () {
      final promo = _a(
        restoId: 'warung-a',
        audience: AnnouncementAudience.customers,
      );

      expect(promo.visibleToCustomer({'warung-a'}), isTrue);
      expect(promo.visibleToEmployee('warung-a'), isFalse);
    });

    test('Semua berarti keduanya', () {
      final semua = _a(restoId: 'warung-a');

      expect(semua.visibleToCustomer({'warung-a'}), isTrue);
      expect(semua.visibleToEmployee('warung-a'), isTrue);
    });

    test('karyawan merchant lain tetap tidak menerimanya', () {
      final internal = _a(
        restoId: 'warung-a',
        audience: AnnouncementAudience.employees,
      );
      expect(internal.visibleToEmployee('kedai-b'), isFalse);
    });

    test('pengumuman lama tanpa kolom sasaran berlaku untuk semuanya', () {
      final lama = Announcement.fromMap({
        'id': 'x',
        'title': 'Kabar lama',
        'body': '...',
        'category': 'general',
        'resto_id': 'warung-a',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      });

      expect(lama.audience, AnnouncementAudience.all);
      expect(lama.visibleToCustomer({'warung-a'}), isTrue);
      expect(lama.visibleToEmployee('warung-a'), isTrue);
    });
  });
}
