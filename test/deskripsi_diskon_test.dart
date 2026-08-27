import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:merchant_pos/models/discount.dart';
import 'package:merchant_pos/utils/deskripsi_diskon.dart';

Discount buat({
  required List<DiscountItem> items,
  DiscountKind kind = DiscountKind.percent,
  int value = 10,
  DiscountBasis basis = DiscountBasis.products,
  DateTime? endsOn,
  String nama = 'Paket Hemat',
}) =>
    Discount(
      id: 'd1',
      restoId: 'r1',
      name: nama,
      basis: basis,
      kind: kind,
      value: value,
      items: items,
      endsOn: endsOn,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('promo yang tidak menyentuh menunya tidak dijelaskan', () {
    final hasil = deskripsiDiskon(
      diskon: [buat(items: [const DiscountItem(productId: 'lain')])],
      productId: 'p1',
    );
    expect(hasil, isEmpty);
  });

  // Promo minimum belanja tidak menempel pada menu mana pun. Menempelkan
  // keterangannya di sini berarti janji yang salah.
  test('promo minimum belanja tidak ikut muncul di menu', () {
    final hasil = deskripsiDiskon(
      diskon: [
        buat(
          basis: DiscountBasis.minPurchase,
          items: [const DiscountItem(productId: 'p1')],
        )
      ],
      productId: 'p1',
    );
    expect(hasil, isEmpty);
  });

  test('persen dan rupiah ditulis berbeda', () {
    final persen = deskripsiDiskon(
      diskon: [buat(items: [const DiscountItem(productId: 'p1')])],
      productId: 'p1',
    ).single;
    expect(persen.potongan, 'Potongan 10%');

    final rupiah = deskripsiDiskon(
      diskon: [
        buat(
          items: [const DiscountItem(productId: 'p1')],
          kind: DiscountKind.amount,
          value: 5000,
        )
      ],
      productId: 'p1',
    ).single;
    expect(rupiah.potongan, contains('5.000'));
  });

  group('syaratnya', () {
    test('minimal dan tepat dibedakan', () {
      final minimal = deskripsiDiskon(
        diskon: [
          buat(items: [const DiscountItem(productId: 'p1', qty: 2)])
        ],
        productId: 'p1',
      ).single;
      expect(minimal.syarat, 'Beli minimal 2 pcs');

      final tepat = deskripsiDiskon(
        diskon: [
          buat(items: [
            const DiscountItem(productId: 'p1', qty: 2, mode: QtyMode.exactly)
          ])
        ],
        productId: 'p1',
      ).single;
      expect(tepat.syarat, 'Beli tepat 2 pcs');
    });

    test('sasaran topping disebut', () {
      final hasil = deskripsiDiskon(
        diskon: [
          buat(items: [
            const DiscountItem(
                productId: 'p1', targets: [DiscountTarget.topping('Keju')])
          ])
        ],
        productId: 'p1',
      ).single;
      expect(hasil.syarat, contains('Topping: Keju'));
    });

    test('sasaran level disebut berikut kelompoknya', () {
      final hasil = deskripsiDiskon(
        diskon: [
          buat(items: [
            const DiscountItem(
                productId: 'p1',
                targets: [DiscountTarget.level('Ukuran', 'Large')])
          ])
        ],
        productId: 'p1',
      ).single;
      expect(hasil.syarat, contains('Ukuran: Large'));
    });
  });

  group('bundling', () {
    final bundling = buat(items: [
      const DiscountItem(productId: 'p1'),
      const DiscountItem(productId: 'p2', qty: 2),
    ]);

    test('menu lain dalam paket ikut disebut', () {
      final hasil = deskripsiDiskon(
        diskon: [bundling],
        productId: 'p1',
        namaMenu: {'p2': 'Es Teh'},
      ).single;
      expect(hasil.paket, ['Es Teh (minimal 2 pcs)']);
    });

    test('menunya sendiri tidak disebut sebagai pasangan', () {
      final hasil = deskripsiDiskon(
        diskon: [bundling],
        productId: 'p1',
        namaMenu: {'p1': 'Nasi Goreng', 'p2': 'Es Teh'},
      ).single;
      expect(hasil.paket.join(), isNot(contains('Nasi Goreng')));
    });

    // Menyembunyikan pasangan yang namanya tidak dikenal membuat paket
    // bersyarat terbaca seperti promo satu menu.
    test('nama yang tidak dikenal tetap disebut jumlahnya', () {
      final hasil =
          deskripsiDiskon(diskon: [bundling], productId: 'p1').single;
      expect(hasil.paket.single, contains('minimal 2 pcs'));
    });

    test('promo satu menu tidak punya daftar paket', () {
      final hasil = deskripsiDiskon(
        diskon: [buat(items: [const DiscountItem(productId: 'p1')])],
        productId: 'p1',
      ).single;
      expect(hasil.paket, isEmpty);
    });
  });

  group('masa berlakunya', () {
    test('tanpa tanggal akhir tidak menyebut apa pun', () {
      final hasil = deskripsiDiskon(
        diskon: [buat(items: [const DiscountItem(productId: 'p1')])],
        productId: 'p1',
      ).single;
      expect(hasil.sampai, isNull);
    });

    test('yang punya tanggal akhir menyebutkannya', () {
      final hasil = deskripsiDiskon(
        diskon: [
          buat(
            items: [const DiscountItem(productId: 'p1')],
            endsOn: DateTime(2026, 8, 31),
          )
        ],
        productId: 'p1',
      ).single;
      expect(hasil.sampai, contains('31'));
      expect(hasil.sampai, contains('2026'));
    });
  });

  test('beberapa sasaran disebut semuanya di satu kalimat', () {
    final hasil = deskripsiDiskon(
      diskon: [
        buat(items: [
          const DiscountItem(productId: 'p1', targets: [
            DiscountTarget.menuUtama(),
            DiscountTarget.topping('Keju'),
          ])
        ])
      ],
      productId: 'p1',
    ).single;
    expect(hasil.syarat, contains('Harga menu utama'));
    expect(hasil.syarat, contains('Topping: Keju'));
  });

  test('beberapa promo pada satu menu dijelaskan semuanya', () {
    final hasil = deskripsiDiskon(
      diskon: [
        buat(items: [const DiscountItem(productId: 'p1')], nama: 'Promo A'),
        buat(items: [const DiscountItem(productId: 'p1')], nama: 'Promo B'),
      ],
      productId: 'p1',
    );
    expect(hasil.map((h) => h.judul), ['Promo A', 'Promo B']);
  });
}
