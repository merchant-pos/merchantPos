import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/merchant_review.dart';
import 'package:merchant_pos/models/opening_hours.dart';

void main() {
  final sql = File('supabase/merchant_reviews.sql').readAsStringSync();

  group('jam buka', () {
    test('hari tanpa entri berarti tutup', () {
      // Lebih jujur daripada menyimpan 00:00–00:00 yang bisa terbaca
      // sebagai buka 24 jam.
      const j = OpeningHours({1: ('08:00', '22:00')});
      expect(j.bukaPada(DateTime(2026, 8, 24, 12)), isTrue); // Senin
      expect(j.bukaPada(DateTime(2026, 8, 25, 12)), isFalse); // Selasa
    });

    test('di luar jamnya dianggap tutup', () {
      const j = OpeningHours({1: ('08:00', '22:00')});
      expect(j.bukaPada(DateTime(2026, 8, 24, 7, 59)), isFalse);
      expect(j.bukaPada(DateTime(2026, 8, 24, 22, 0)), isFalse);
    });

    test('yang melewati tengah malam tetap terhitung buka', () {
      // Warung yang buka 18:00 sampai 02:00 tidak boleh dianggap tutup
      // sepanjang malam.
      const j = OpeningHours({1: ('18:00', '02:00')});
      expect(j.bukaPada(DateTime(2026, 8, 24, 23)), isTrue);
      expect(j.bukaPada(DateTime(2026, 8, 24, 1)), isTrue);
      expect(j.bukaPada(DateTime(2026, 8, 24, 10)), isFalse);
    });

    test('penomoran harinya sama dengan DateTime.weekday', () {
      // Tanpa itu ada penyesuaian yang bisa meleset satu hari.
      expect(OpeningHours.namaHari[DateTime.monday], 'Senin');
      expect(OpeningHours.namaHari[DateTime.sunday], 'Minggu');
    });

    test('bolak-balik lewat JSON tanpa berubah', () {
      const j = OpeningHours({1: ('08:00', '22:00'), 7: ('10:00', '20:00')});
      expect(OpeningHours.fromRaw(j.toJson()).perHari, j.perHari);
    });

    test('isi rusak tidak menjatuhkan barisnya', () {
      expect(OpeningHours.fromRaw('bukan json').adaIsinya, isFalse);
      expect(OpeningHours.fromRaw({'9': {'buka': '08:00', 'tutup': '10:00'}})
          .adaIsinya, isFalse);
    });
  });

  group('penilaian', () {
    test('satu orang satu penilaian per merchant', () {
      // Tanpa ini, satu orang yang kecewa bisa menenggelamkan
      // rata-ratanya sendirian.
      expect(sql, contains('unique (resto_id, customer_email)'));
    });

    test('bintangnya dibatasi 1 sampai 5', () {
      expect(sql, contains('check (rating between 1 and 5)'));
    });

    test('nama penulisnya disalin, bukan dibaca ulang', () {
      // Profil bisa berganti nama besok; ulasan yang tiba-tiba berganti
      // penulis adalah ulasan yang tidak bisa dipercaya.
      expect(sql, contains('customer_name text not null'));
    });

    test('bisa dibaca siapa saja, termasuk tamu', () {
      // Yang paling membutuhkannya justru yang belum punya akun.
      expect(sql, contains('"merchant_reviews: public read"'));
      expect(sql, contains('for select using (true)'));
    });

    test('hanya pemiliknya yang bisa menulis', () {
      expect(sql, contains("customer_email = auth.jwt() ->> 'email'"));
    });

    test('rata-ratanya dihitung server', () {
      // Daftar merchant menampilkan puluhan baris; menarik seluruh
      // ulasan tiap merchant berarti ribuan baris tiap layar dibuka.
      expect(sql, contains('function merchant_rating_summary'));
      expect(sql, contains('avg(r.rating)'));
    });

    test('terbaca dari baris database', () {
      final u = MerchantReview.fromMap({
        'id': 'x',
        'resto_id': 'r1',
        'customer_email': 'a@b.com',
        'customer_name': 'Budi',
        'rating': 4,
        'comment': 'Enak',
        'photos': ['abc'],
        'created_at': '2026-08-24T10:00:00Z',
      });
      expect(u.rating, 4);
      expect(u.customerName, 'Budi');
      expect(u.punyaFoto, isTrue);
    });

    test('foto rusak tidak menjatuhkan daftarnya', () {
      final u = MerchantReview.fromMap({
        'id': 'x',
        'resto_id': 'r1',
        'customer_email': 'a@b.com',
        'customer_name': 'Budi',
        'rating': 4,
        'photos': 'bukan json',
        'created_at': '2026-08-24T10:00:00Z',
      });
      expect(u.photos, isEmpty);
    });
  });

  group('di layar', () {
    test('pelanggan bisa membuka info merchant dari daftar', () {
      final daftar =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      expect(daftar, contains('MerchantInfoScreen(merchant: merchant)'));
      expect(daftar, contains('lainnya'));
    });

    test('"+N" bisa diketuk, bukan sekadar keterangan', () {
      // Yang disembunyikan itu bisa jadi justru yang dicari.
      final daftar =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      expect(daftar, contains('onLainnya: () => _bukaInfo(context, resto)'));
      expect(daftar, contains('onTap: onLainnya,'));
    });

    test('pegawai membacanya lewat satu widget bersama', () {
      // Menyalinnya ke lima beranda berarti lima tempat yang harus
      // diingat berbarengan.
      final tile = File('lib/widgets/penilaian_tile.dart').readAsStringSync();
      expect(tile, contains('bolehMenilai: false'));
      for (final f in [
        'lib/screens/kasir_home_screen.dart',
        'lib/screens/finance_home_screen.dart',
        'lib/screens/settings_menu_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('PenilaianTile'),
            reason: f);
      }
      expect(File('lib/screens/chef_home_screen.dart').readAsStringSync(),
          contains('bukaPenilaian(context)'));
    });

    test('KaataGo Admin tidak diberi menunya', () {
      // Tempatnya bukan miliknya, dan daftar keluhan yang tidak bisa
      // dia tindaklanjuti cuma menumpuk.
      final sa =
          File('lib/screens/super_admin_home_screen.dart').readAsStringSync();
      expect(sa, isNot(contains('PenilaianTile')));
      expect(sa, isNot(contains('bukaPenilaian')));
    });
  });

  group('merchant yang tutup', () {
    final daftar =
        File('lib/screens/restaurant_list_screen.dart').readAsStringSync();

    test('yang belum mengisi jam bukanya tidak dianggap tutup', () {
      // Daftar kosong berarti belum diisi, bukan tutup selamanya —
      // menutup pintunya karena setelan yang belum disentuh adalah
      // kehilangan pesanan yang tidak pernah dia sadari.
      expect(daftar, contains('resto.openingHours.adaIsinya &&'));
    });

    test('diturunkan ke bawah, sedekat apa pun', () {
      // Tempat terdekat yang sedang tutup bukan tempat yang bisa
      // dipilih.
      expect(daftar, contains('if (ta != tb) return ta ? 1 : -1;'));
    });

    test('ditandai Tutup di barisnya', () {
      expect(daftar, contains("'Tutup'"));
    });

    test('tidak bisa dipilih, dan alasannya disebut', () {
      expect(daftar,
          contains('Merchant lagi tutup nih, silakan pilih merchant lainnya'));
    });

    test('dihentikan di daftar, bukan saat checkout', () {
      // Yang sudah menyusun keranjang lalu ditolak di ujung akan
      // mengira aplikasinya yang rusak.
      final blok = daftar.substring(daftar.indexOf('Future<void> _select('));
      expect(blok.indexOf('_tutup(resto)'),
          lessThan(blok.indexOf('setResto(resto.id)')));
    });
  });

  group('ajakan menilai', () {
    final sql = File('supabase/review_prompt.sql').readAsStringSync();
    final router =
        File('lib/services/notification_router.dart').readAsStringSync();

    test('datang sejam sesudah bayar, bukan seketika', () {
      // Yang baru membayar sedang makan atau berjalan keluar; ajakan di
      // detik itu ditutup tanpa dibaca.
      expect(sql, contains("created_at < now() - interval '1 hour'"));
    });

    test('dan tidak lebih dari tiga jam', () {
      // Ajakan yang datang esok hari menanyakan sesuatu yang sudah
      // kabur, dan jawabannya jadi asal.
      expect(sql, contains("created_at > now() - interval '3 hours'"));
    });

    test('hanya untuk pesanan yang benar-benar dibayar', () {
      expect(sql, contains("payment_status = 'paid'"));
    });

    test('yang sudah menilai tidak diajak lagi', () {
      expect(sql, contains('from merchant_reviews mr'));
    });

    test('satu kunjungan tidak diajak berulang kali', () {
      expect(sql, contains('create table if not exists review_prompts'));
      expect(sql, contains('order_id uuid primary key'));
    });

    test('tamu tidak diajak — tidak ada perangkat yang dituju', () {
      expect(sql, contains('from customers c where c.email = ord.customer_label'));
    });

    test('menyasar emailnya', () {
      expect(sql, contains("'audience', 'email'"));
    });

    test('membuka formulir ulasan merchant itu', () {
      expect(router, contains("event == 'review_prompt'"));
      expect(router, contains('MerchantReviewForm(merchant: m)'));
    });

    test('merchant-nya ikut di payload notifikasi', () {
      final notif =
          File('lib/services/notification_service.dart').readAsStringSync();
      expect(notif, contains("?resto_id=\$restoId"));
      final main_ = File('lib/main.dart').readAsStringSync();
      expect(main_, contains('Uri.splitQueryString'));
    });

    test('tampil juga saat aplikasinya sedang dibuka', () {
      final push = File('lib/services/push_service.dart').readAsStringSync();
      // Daftarnya bertambah seiring waktu — yang dijaga di sini cuma
      // bahwa ajakan menilai ada di dalamnya, bukan isi persisnya.
      final daftar = push.substring(push.indexOf('_foregroundEvents = {'));
      expect(daftar.substring(0, daftar.indexOf('};')),
          contains("'review_prompt'"));
    });
  });

  group('yang disembunyikan', () {
    test('titik penanda banner sudah tidak ada', () {
      final b =
          File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();
      expect(b, isNot(contains('AnimatedContainer(')));
    });

    test('spanduk unduhan hanya untuk tamu', () {
      final beranda =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(beranda, contains('if (!loggedInAsCustomer)\n                const Padding'));
    });

    test('tombol tes notifikasi sudah hilang dari layar dapur', () {
      final chef =
          File('lib/screens/chef_home_screen.dart').readAsStringSync();
      expect(chef, isNot(contains('showNotificationTest')));
    });
  });
}
