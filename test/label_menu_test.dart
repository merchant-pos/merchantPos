import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/product.dart';
import 'package:merchant_pos/models/product_badge.dart';
import 'package:merchant_pos/models/product_review.dart';
import 'package:merchant_pos/widgets/product_badge_chips.dart';

void main() {
  group('kode label', () {
    test('kode yang dikenal terbaca', () {
      expect(badgeDariKode('new'), ProductBadge.baru);
      expect(badgeDariKode('best_seller'), ProductBadge.terlaris);
      expect(badgeDariKode('recommended'), ProductBadge.rekomendasi);
      expect(badgeDariKode('discount'), ProductBadge.diskon);
    });

    // Baris yang ditulis versi aplikasi yang lebih baru tidak boleh
    // membuat versi lama gagal menampilkan menunya sama sekali.
    test('kode asing diabaikan, bukan melempar galat', () {
      expect(badgeDariKode('halal'), isNull);
      expect(badgeDariKodeList(['new', 'halal', 'best_seller']),
          [ProductBadge.baru, ProductBadge.terlaris]);
    });

    test('diskon tidak ditawarkan sebagai centangan di formulir', () {
      expect(kBadgeBisaDipilih, isNot(contains(ProductBadge.diskon)));
      expect(kBadgeBisaDipilih.length, 3);
    });

    // Kalau daftarnya bertambah tapi warnanya tidak, labelnya tampil
    // tanpa warna latar sama sekali — dan tidak ada yang memberi tahu.
    test('setiap label punya tulisan, warna, dan ikonnya', () {
      for (final b in ProductBadge.values) {
        expect(kBadgeKode[b], isNotNull, reason: '$b tanpa kode');
        expect(kBadgeLabel[b], isNotNull, reason: '$b tanpa tulisan');
        expect(kBadgeKeterangan[b], isNotNull, reason: '$b tanpa keterangan');
        expect(kBadgeWarna[b], isNotNull, reason: '$b tanpa warna');
        expect(kBadgeIkon[b], isNotNull, reason: '$b tanpa ikon');
      }
    });
  });

  group('urutan label', () {
    test('diskon selalu paling depan', () {
      final urut = urutkanBadge(
          {ProductBadge.rekomendasi, ProductBadge.diskon, ProductBadge.baru});
      expect(urut.first, ProductBadge.diskon);
    });

    test('urutannya tetap sama apa pun urutan masuknya', () {
      final a = urutkanBadge([ProductBadge.baru, ProductBadge.terlaris]);
      final b = urutkanBadge([ProductBadge.terlaris, ProductBadge.baru]);
      expect(a, b);
    });

    test('yang tidak ada tidak ikut muncul', () {
      expect(urutkanBadge([ProductBadge.baru]), [ProductBadge.baru]);
    });
  });

  group('label tersimpan di menunya', () {
    test('bolak-balik lewat teks JSON — bentuk sqflite', () {
      final p = Product(
        id: '1',
        name: 'Nasi Goreng',
        category: 'Makanan',
        price: 20000,
        badges: const ['new', 'best_seller'],
      );
      final map = p.toMap();
      expect(map['badges'], '["new","best_seller"]');
      expect(Product.fromMap({...map, 'badges': map['badges']}).badges,
          ['new', 'best_seller']);
    });

    test('bolak-balik lewat daftar — bentuk Postgres', () {
      final p = Product.fromMap({
        'id': '1',
        'name': 'Es Teh',
        'category': 'Minuman',
        'price': 5000,
        'badges': ['recommended'],
      });
      expect(p.badges, ['recommended']);
    });

    test('menu lama tanpa kolomnya tetap terbaca', () {
      final p = Product.fromMap({
        'id': '1',
        'name': 'Lama',
        'category': 'Makanan',
        'price': 1000,
      });
      expect(p.badges, isEmpty);
    });

    test('isi yang rusak dibaca sebagai tanpa label, bukan layar kosong', () {
      final p = Product.fromMap({
        'id': '1',
        'name': 'Rusak',
        'category': 'Makanan',
        'price': 1000,
        'badges': 'bukan json',
      });
      expect(p.badges, isEmpty);
    });

    test('copyWith mempertahankan labelnya', () {
      final p = Product(
        id: '1',
        name: 'A',
        category: 'B',
        price: 1,
        badges: const ['new'],
      );
      expect(p.copyWith(name: 'C').badges, ['new']);
      expect(p.copyWith(badges: const []).badges, isEmpty);
    });
  });

  group('bintang dan terjual', () {
    // Nol di sebelah bintang terbaca sebagai penilaian terburuk,
    // padahal artinya belum ada yang menilai.
    test('belum dinilai berbeda dari dinilai nol', () {
      expect(const ProductStats().adaNilai, isFalse);
      expect(const ProductStats(rata: 4.5, jumlah: 2).adaNilai, isTrue);
    });

    test('angka di bawah seribu ditulis apa adanya', () {
      expect(ringkasJumlah(0), '0');
      expect(ringkasJumlah(999), '999');
    });

    test('ribuan diringkas', () {
      expect(ringkasJumlah(1000), '1,0rb');
      expect(ringkasJumlah(1240), '1,2rb');
      expect(ringkasJumlah(9950), '10,0rb');
      expect(ringkasJumlah(24000), '24rb');
    });

    test('jutaan diringkas', () {
      expect(ringkasJumlah(1200000), '1,2jt');
    });
  });

  group('SQL-nya', () {
    final sql = File('supabase/product_badges_reviews.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      final skrip = File('scripts/gabung_sql.sh').readAsStringSync();
      expect(skrip, contains('product_badges_reviews.sql'));
    });

    // Aturan yang hanya ada di aplikasi bukan aturan — ia cuma tampilan.
    test('menilai menu menuntut pesanan lunas atas menu itu', () {
      expect(sql, contains('payment_status = \'paid\''));
      expect(sql, contains('o.items @>'));
      expect(sql, contains('with check'));
    });

    test('angka terjual hanya dari pesanan yang lunas', () {
      final terjual = sql.substring(sql.indexOf('with terjual'));
      expect(terjual, contains("o.payment_status = 'paid'"));
    });

    test('satu orang satu penilaian per menu, per pesanan', () {
      final per = File('supabase/product_review_per_order.sql')
          .readAsStringSync();
      // Harus indeks atas kolomnya langsung. `on conflict (order_id,
      // product_id, customer_email)` menolak indeks berbentuk ekspresi
      // dengan galat 42P10 — dan galatnya baru muncul saat orangnya
      // menekan Simpan.
      expect(
          per,
          contains('create unique index if not exists '
              'product_reviews_order_menu_orang\n'
              '  on product_reviews (order_id, product_id, customer_email);'));
      // Diperiksa pada SQL-nya saja — baris komentar di berkas itu
      // memang menyebut bentuk lamanya, justru untuk menerangkan kenapa
      // ia tidak boleh dipakai.
      final perintah = per
          .split('\n')
          .where((b) => !b.trimLeft().startsWith('--'))
          .join('\n');
      expect(perintah, isNot(contains('coalesce(order_id')));
    });

    // Di dalam indeks unik, dua NULL dianggap berbeda. Tanpa penjaga
    // terpisah, baris yang ditulis sebelum penilaian menempel pada
    // pesanan bisa berlipat ganda tanpa ketahuan.
    test('baris lama tanpa pesanan tetap dibatasi satu per menu', () {
      final per = File('supabase/product_review_per_order.sql')
          .readAsStringSync();
      expect(per, contains('where order_id is null'));
    });

    // Angkanya harus terbaca tamu yang belum masuk juga.
    test('ringkasannya bisa dipanggil tanpa akun', () {
      expect(sql, contains('security definer'));
      expect(sql, contains('to anon, authenticated'));
    });
  });
}
