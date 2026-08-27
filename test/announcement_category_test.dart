import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/announcement.dart';

Map<String, dynamic> _row({
  String? category,
  String? restoId,
  String? image,
  String? version,
}) =>
    {
      'id': 'a1',
      'title': 'Judul',
      'body': 'Isi',
      'created_at': DateTime.utc(2026, 8, 14).toIso8601String(),
      if (category != null) 'category': category,
      if (restoId != null) 'resto_id': restoId,
      if (image != null) 'image_base64': image,
      if (version != null) 'version': version,
    };

void main() {
  group('kategori', () {
    test('baris lama tanpa kolom kategori dibaca sebagai Update Aplikasi', () {
      // Seluruh pengumuman sebelum pembagian ini memang pemberitahuan
      // versi. Kalau jatuh ke General, kabar versi baru akan pindah tab
      // sendiri di HP orang yang sudah terbiasa mencarinya di satu tempat.
      expect(Announcement.fromMap(_row()).category, AnnouncementCategory.update);
    });

    test('general terbaca sebagai general', () {
      expect(
        Announcement.fromMap(_row(category: 'general')).category,
        AnnouncementCategory.general,
      );
    });

    test('nilai tak dikenal jatuh ke Update Aplikasi, bukan melempar galat', () {
      expect(
        Announcement.fromMap(_row(category: 'entah-apa')).category,
        AnnouncementCategory.update,
      );
    });

    test('labelnya lengkap untuk setiap jenis', () {
      for (final c in AnnouncementCategory.values) {
        expect(kAnnouncementCategoryLabels[c], isNotNull);
      }
    });
  });

  group('visibleTo', () {
    test('tanpa merchant berlaku untuk semua orang', () {
      final a = Announcement.fromMap(_row());
      expect(a.visibleTo('merchant-1'), isTrue);
      expect(a.visibleTo('merchant-2'), isTrue);
      expect(a.visibleTo(null), isTrue);
    });

    test('yang terikat merchant hanya untuk merchant itu', () {
      final a = Announcement.fromMap(_row(category: 'general', restoId: 'merchant-1'));
      expect(a.visibleTo('merchant-1'), isTrue);
      expect(a.visibleTo('merchant-2'), isFalse);
    });

    test('orang tanpa merchant tidak melihat pengumuman merchant mana pun', () {
      // Super Admin tidak terikat resto; kotak masuknya tidak seharusnya
      // dipenuhi promo tiap cabang.
      final a = Announcement.fromMap(_row(category: 'general', restoId: 'merchant-1'));
      expect(a.visibleTo(null), isFalse);
    });
  });

  group('gambar promo', () {
    test('hasImage hanya benar kalau isinya ada', () {
      expect(Announcement.fromMap(_row()).hasImage, isFalse);
      expect(Announcement.fromMap(_row(image: '')).hasImage, isFalse);
      expect(Announcement.fromMap(_row(image: 'AAAA')).hasImage, isTrue);
    });

    test('copyWith mempertahankan jenis, merchant, dan gambarnya', () {
      // copyWith dipakai saat menandai sudah dibaca. Kalau salah satunya
      // hilang di situ, pesannya akan melompat tab tepat setelah dibuka.
      final a = Announcement.fromMap(
        _row(category: 'general', restoId: 'merchant-1', image: 'AAAA'),
      );
      final read = a.copyWith(read: true);
      expect(read.read, isTrue);
      expect(read.category, AnnouncementCategory.general);
      expect(read.restoId, 'merchant-1');
      expect(read.imageBase64, 'AAAA');
    });
  });
}
