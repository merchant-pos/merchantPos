import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/discount.dart';
import 'package:merchant_pos/utils/promo_period.dart';

final _hariIni = DateTime(2026, 8, 16);

Discount _d({
  String id = 'd1',
  DiscountBasis basis = DiscountBasis.products,
  DiscountKind kind = DiscountKind.percent,
  int value = 10,
  List<DiscountItem> items = const [DiscountItem(productId: 'p1')],
  int minPurchase = 0,
  MinCompare compare = MinCompare.atLeast,
  DateTime? startsOn,
  DateTime? endsOn,
  bool active = true,
}) =>
    Discount(
      id: id,
      restoId: 'r1',
      name: 'Promo $id',
      basis: basis,
      kind: kind,
      value: value,
      items: items,
      minPurchase: minPurchase,
      compare: compare,
      startsOn: startsOn,
      endsOn: endsOn,
      active: active,
      createdAt: _hariIni,
    );

void main() {
  group('potongan', () {
    test('persen dibulatkan ke bawah', () {
      expect(_d(value: 10).amountFor(40793), 4079);
    });

    test('tidak pernah melebihi tagihannya sendiri', () {
      // Diskon rupiah tetap yang lebih besar daripada tagihannya
      // menghasilkan total negatif — uang yang harus dikembalikan resto
      // kepada orang yang belum membayar apa pun.
      final potong50rb = _d(kind: DiscountKind.amount, value: 50000);
      expect(potong50rb.amountFor(20000), 20000);
    });
  });

  group('minimum belanja', () {
    test('≥ memberi diskon pada nilai yang pas', () {
      final d = _d(
        basis: DiscountBasis.minPurchase,
        minPurchase: 200000,
        compare: MinCompare.atLeast,
      );
      expect(d.meetsMinimum(200000), isTrue);
      expect(d.meetsMinimum(199999), isFalse);
    });

    test('> menolak nilai yang pas', () {
      // Yang membedakan keduanya cuma satu transaksi — yang nilainya
      // persis di batas — dan justru itu yang paling sering jadi
      // perselisihan di meja kasir.
      final d = _d(
        basis: DiscountBasis.minPurchase,
        minPurchase: 200000,
        compare: MinCompare.moreThan,
      );
      expect(d.meetsMinimum(200000), isFalse);
      expect(d.meetsMinimum(200001), isTrue);
    });
  });

  group('masa berlaku', () {
    test('hari terakhirnya masih berlaku penuh', () {
      // "Promo sampai 31 Agustus" berarti sampai tutup toko tanggal 31,
      // bukan sampai pukul 00:00 tanggal 31.
      final d = _d(endsOn: DateTime(2026, 8, 16));
      expect(d.isLive(DateTime(2026, 8, 16, 23, 59)), isTrue);
      expect(d.isLive(DateTime(2026, 8, 17)), isFalse);
    });

    test('yang belum mulai tidak ikut dihitung', () {
      final d = _d(startsOn: DateTime(2026, 8, 20));
      expect(d.isLive(_hariIni), isFalse);
      expect(d.period.isScheduled(_hariIni), isTrue);
    });

    test('yang dimatikan tidak berlaku walau tanggalnya pas', () {
      expect(_d(active: false).isLive(_hariIni), isFalse);
    });
  });

  group('pemilihan diskon', () {
    int subtotal(String id) => {'p1': 50000, 'p2': 30000}[id] ?? 0;

    test('bundling menjumlahkan menunya dulu, baru dipotong', () {
      // Kalau tiap baris dipotong sendiri-sendiri, diskon rupiah tetap
      // akan terkalikan sebanyak menu yang ikut promo.
      final bundling = _d(
        kind: DiscountKind.amount,
        value: 10000,
        items: const [DiscountItem(productId: 'p1'), DiscountItem(productId: 'p2')],
      );

      final hasil = bestDiscountFor(
        discounts: [bundling],
        total: 80000,
        subtotalOf: (i) => subtotal(i.productId),
        qtyOf: (_) => 1,
        now: _hariIni,
      );

      expect(hasil!.amount, 10000);
    });

    test('diskon menu hanya mengenai menu yang ikut promo', () {
      final d = _d(value: 50, items: const [DiscountItem(productId: 'p2')]);

      final hasil = bestDiscountFor(
        discounts: [d],
        total: 80000,
        subtotalOf: (i) => subtotal(i.productId),
        qtyOf: (_) => 1,
        now: _hariIni,
      );

      // 50% dari 30.000 (harga p2), bukan dari 80.000.
      expect(hasil!.amount, 15000);
    });

    test('hanya satu diskon yang dipakai — yang paling menguntungkan', () {
      // Menumpuk terdengar murah hati sampai dua promo yang kebetulan
      // berlaku bersamaan melebihi harga barangnya.
      final kecil = _d(id: 'a', value: 10);
      final besar = _d(
        id: 'b',
        basis: DiscountBasis.minPurchase,
        minPurchase: 50000,
        value: 20,
      );

      final hasil = bestDiscountFor(
        discounts: [kecil, besar],
        total: 80000,
        subtotalOf: (i) => subtotal(i.productId),
        qtyOf: (_) => 1,
        now: _hariIni,
      );

      expect(hasil!.discount.id, 'b');
      expect(hasil.amount, 16000);
    });

    test('tidak ada yang cocok berarti tidak ada potongan', () {
      final hasil = bestDiscountFor(
        discounts: [_d(items: const [DiscountItem(productId: 'p9')])],
        total: 80000,
        subtotalOf: (i) => subtotal(i.productId),
        qtyOf: (_) => 1,
        now: _hariIni,
      );
      expect(hasil, isNull);
    });
  });

  group('batas tanggal', () {
    test('mulai tidak boleh mundur ke belakang', () {
      final error = validatePeriod(
        startsOn: DateTime(2026, 8, 15),
        now: _hariIni,
      );
      expect(error, isNotNull);
    });

    test('berakhir harus setelah hari ini', () {
      expect(validatePeriod(endsOn: _hariIni, now: _hariIni), isNotNull);
      expect(
        validatePeriod(endsOn: DateTime(2026, 8, 17), now: _hariIni),
        isNull,
      );
    });

    test('berakhir harus setelah mulai', () {
      final error = validatePeriod(
        startsOn: DateTime(2026, 8, 20),
        endsOn: DateTime(2026, 8, 18),
        now: _hariIni,
      );
      expect(error, isNotNull);
    });
  });

  group('berlaku untuk pesanan mandiri pelanggan', () {
    int subtotal(String id) => {'p1': 50000}[id] ?? 0;

    test('aturan yang sama dipakai kasir maupun HP pelanggan', () {
      // Promo yang cuma berlaku kalau kasir yang mengetikkan pesanannya
      // bukan promo — ia janji yang gagal ditepati tepat di depan orang
      // yang membacanya di layar menu.
      //
      // Keduanya memanggil bestDiscountFor yang sama persis; tes ini
      // menjaga supaya tidak ada yang diam-diam menambahkan syarat
      // "hanya dari kasir" di salah satunya.
      final promo = _d(
        basis: DiscountBasis.minPurchase,
        minPurchase: 40000,
        value: 10,
      );

      final hasil = bestDiscountFor(
        discounts: [promo],
        total: 50000,
        subtotalOf: (i) => subtotal(i.productId),
        qtyOf: (_) => 1,
        now: _hariIni,
      );

      expect(hasil, isNotNull);
      expect(hasil!.amount, 5000);
    });

    test('yang dibayar adalah total dikurangi potongan', () {
      final promo = _d(kind: DiscountKind.amount, value: 7500);

      final hasil = bestDiscountFor(
        discounts: [promo],
        total: 50000,
        subtotalOf: (i) => subtotal(i.productId),
        qtyOf: (_) => 1,
        now: _hariIni,
      );

      expect(50000 - hasil!.amount, 42500);
    });
  });

  group('syarat jumlah per menu', () {
    int harga(String id) => {'p1': 50000, 'p2': 30000, 'p3': 5000}[id] ?? 0;

    AppliedDiscount? jalankan(Discount d, Map<String, int> qty) =>
        bestDiscountFor(
          discounts: [d],
          total: 200000,
          subtotalOf: (i) => harga(i.productId) * (qty[i.productId] ?? 0),
          qtyOf: (i) => qty[i.productId] ?? 0,
          now: _hariIni,
        );

    Discount promo(List<DiscountItem> items, {int value = 30}) =>
        _d(value: value, items: items);

    test('minimal: beli satu belum dapat kalau syaratnya dua', () {
      final d = promo(const [DiscountItem(productId: 'p1', qty: 2)]);
      expect(jalankan(d, {'p1': 1}), isNull);
    });

    test('minimal: beli dua dapat, dan lebih dari dua tetap dapat', () {
      final d = promo(const [DiscountItem(productId: 'p1', qty: 2)]);
      expect(jalankan(d, {'p1': 2})!.amount, 30000);
      expect(jalankan(d, {'p1': 3})!.amount, 45000);
    });

    test('tepat: lebih banyak justru tidak dapat', () {
      // Paket yang isinya sudah pasti. Tiga ayam bukan lagi paket itu,
      // dan kalau tetap diberi potongan, harga paketnya tidak berarti
      // apa-apa.
      final d = promo(const [
        DiscountItem(productId: 'p1', qty: 2, mode: QtyMode.exactly),
      ]);
      expect(jalankan(d, {'p1': 1}), isNull);
      expect(jalankan(d, {'p1': 2})!.amount, 30000);
      expect(jalankan(d, {'p1': 3}), isNull);
    });

    group('bundling harus lengkap', () {
      // Inilah yang bocor sebelumnya: satu angka jumlah untuk seluruh
      // promo, dan cukup salah satu menunya terpenuhi. Keranjang berisi
      // 2 nasi goreng, 1 teh manis, dan 1 kopi lolos promo yang
      // sebenarnya menjanjikan paket lain sama sekali.
      final paket = promo(const [
        DiscountItem(productId: 'p1', qty: 2),
        DiscountItem(productId: 'p2', qty: 1),
      ]);

      test('kurang satu menu berarti tidak berlaku sama sekali', () {
        expect(jalankan(paket, {'p1': 2}), isNull);
      });

      test('menu lain di keranjang tidak menggantikan yang kurang', () {
        expect(jalankan(paket, {'p1': 2, 'p3': 5}), isNull);
      });

      test('jumlahnya kurang di salah satu menu juga menggugurkan', () {
        expect(jalankan(paket, {'p1': 1, 'p2': 1}), isNull);
      });

      test('lengkap semuanya baru dapat', () {
        // 30% dari (2 × 50.000 + 1 × 30.000).
        expect(jalankan(paket, {'p1': 2, 'p2': 1})!.amount, 39000);
      });

      test('menu di luar promo tidak ikut dipotong', () {
        final hasil = jalankan(paket, {'p1': 2, 'p2': 1, 'p3': 10});
        expect(hasil!.amount, 39000);
      });

      test('mencampur minimal dan tepat dalam satu paket', () {
        final campur = promo(const [
          DiscountItem(productId: 'p1', qty: 2, mode: QtyMode.exactly),
          DiscountItem(productId: 'p2', qty: 1),
        ]);
        expect(jalankan(campur, {'p1': 3, 'p2': 1}), isNull);
        expect(jalankan(campur, {'p1': 2, 'p2': 4})!.amount, 66000);
      });
    });

    test('diskon minimum belanja tidak terpengaruh jumlah menu', () {
      final d = _d(
        basis: DiscountBasis.minPurchase,
        minPurchase: 50000,
        value: 10,
        items: const [],
      );
      expect(jalankan(d, {'p1': 1})!.amount, 20000);
    });

    test('promo tanpa satu pun menu tidak pernah mengenai apa pun', () {
      expect(jalankan(promo(const []), {'p1': 9}), isNull);
    });

    group('tersimpan dan terbaca kembali', () {
      Discount baca(Map<String, dynamic> map) => Discount.fromMap(
          {...map, 'created_at': _hariIni.toIso8601String()});

      test('aturan tiap menu ikut tersimpan', () {
        final map = promo(const [
          DiscountItem(productId: 'p1', qty: 2, mode: QtyMode.exactly),
          DiscountItem(productId: 'p2', qty: 3),
        ]).toMap();

        final lagi = baca(map);
        expect(lagi.items.first.qty, 2);
        expect(lagi.items.first.mode, QtyMode.exactly);
        expect(lagi.items.last.qty, 3);
        expect(lagi.items.last.mode, QtyMode.atLeast);
      });

      test('daftar id polos tetap ditulis untuk versi aplikasi lama', () {
        final map = promo(const [
          DiscountItem(productId: 'p1', qty: 2),
          DiscountItem(productId: 'p2'),
        ]).toMap();
        expect(map['product_ids'], ['p1', 'p2']);
      });

      test('baris lama tanpa aturan dibaca sebagai minimal satu', () {
        final lagi = baca({
          'id': 'x',
          'resto_id': 'r1',
          'name': 'Promo lama',
          'basis': 'products',
          'kind': 'percent',
          'value': 10,
          'product_ids': ['p1', 'p2'],
        });
        expect(lagi.items.map((i) => i.productId), ['p1', 'p2']);
        expect(lagi.items.every((i) => i.qty == 1), isTrue);
        expect(lagi.items.every((i) => i.mode == QtyMode.atLeast), isTrue);
      });

      test('baris dari 1.45.3 memakai min_qty untuk seluruh menunya', () {
        // Versi itu menyimpan satu angka untuk seluruh promo. Dibaca
        // sebagai syarat tiap menu — arti yang paling dekat dengan apa
        // yang dimaksud orang yang membuatnya.
        final lagi = baca({
          'id': 'x',
          'resto_id': 'r1',
          'name': 'Beli 2',
          'basis': 'products',
          'kind': 'percent',
          'value': 30,
          'product_ids': ['p1'],
          'min_qty': 2,
        });
        expect(lagi.items.single.qty, 2);
      });
    });
  });

}
