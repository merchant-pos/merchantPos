import '../utils/promo_period.dart';
import 'product.dart';

/// Dasar perhitungan diskon.
enum DiscountBasis {
  /// Menu tertentu — satu atau beberapa sekaligus, untuk kasus bundling.
  products,

  /// Seluruh tagihan, asal mencapai nilai minimum.
  minPurchase,
}

/// Bentuk potongannya.
enum DiscountKind { percent, amount }

/// Bagaimana nilai minimum dibandingkan.
///
/// Dipisah dan bisa dipilih karena keduanya benar-benar berbeda di
/// telinga pelanggan: "belanja 200 ribu dapat diskon" hampir selalu
/// dimaksudkan termasuk yang pas 200 ribu, tapi tidak selalu. Menebak
/// salah satunya berarti ada transaksi di batas persis yang ditolak
/// kasirnya sementara spanduknya menjanjikan sebaliknya.
enum MinCompare {
  /// ≥ — yang pas nilainya ikut dapat.
  atLeast,

  /// > — harus melebihi.
  moreThan,
}

const _basisDb = {
  DiscountBasis.products: 'products',
  DiscountBasis.minPurchase: 'min_purchase',
};

const _kindDb = {
  DiscountKind.percent: 'percent',
  DiscountKind.amount: 'amount',
};

const _compareDb = {
  MinCompare.atLeast: 'at_least',
  MinCompare.moreThan: 'more_than',
};

const kDiscountBasisLabels = {
  DiscountBasis.products: 'Menu tertentu',
  DiscountBasis.minPurchase: 'Minimum belanja',
};

const kMinCompareLabels = {
  MinCompare.atLeast: '≥ (termasuk nilainya)',
  MinCompare.moreThan: '> (harus lebih dari)',
};

/// Bagaimana jumlah sebuah menu dibandingkan.
enum QtyMode {
  /// Minimal sekian — lebih banyak tetap dapat.
  atLeast,

  /// Tepat sekian — kurang maupun lebih tidak dapat.
  ///
  /// Dipakai promo paket yang isinya sudah pasti: "paket 2 ayam + 1 nasi"
  /// dengan tiga ayam bukan lagi paket itu, dan kalau tetap diberi
  /// potongan, harga paketnya jadi tidak berarti apa-apa.
  exactly,
}

const _qtyModeDb = {
  QtyMode.atLeast: 'at_least',
  QtyMode.exactly: 'exactly',
};

const kQtyModeLabels = {
  QtyMode.atLeast: 'Minimal',
  QtyMode.exactly: 'Tepat',
};

/// Satu menu di dalam sebuah promo, berikut syarat jumlahnya sendiri.
///
/// Syaratnya menempel di menunya, bukan di promonya. Satu angka untuk
/// seluruh promo terdengar lebih sederhana sampai dipakai: "beli 2"
/// pada promo berisi Nasi Goreng dan Es Teh akan lolos oleh keranjang
/// berisi dua Nasi Goreng saja — paket yang dijanjikan spanduknya tidak
/// pernah benar-benar dibeli, tapi potongannya tetap keluar.
class DiscountItem {
  final String productId;
  final int qty;
  final QtyMode mode;

  /// Bagian-bagian menu yang dipotong, lebih sempit dari seluruh
  /// menunya.
  ///
  /// Kosong berarti yang dipotong harga menunya sendiri. Berisi berarti
  /// yang dipotong hanya tambahan harga dari sasaran-sasaran itu —
  /// dengan potongan 100%, "Ukuran Besar" jadi gratis sementara menunya
  /// tetap dibayar penuh.
  ///
  /// Daftar, bukan satu. Promo "topping gratis" nyaris tidak pernah
  /// berarti satu topping tertentu: yang dimaksud biasanya beberapa
  /// sekaligus, dan menyatakannya sebagai beberapa promo terpisah
  /// membuat semuanya jadi syarat yang harus dipenuhi berbarengan —
  /// pelanggan yang memilih Keju saja lalu tidak dapat apa-apa.
  final List<DiscountTarget> targets;

  const DiscountItem({
    required this.productId,
    this.qty = 1,
    this.mode = QtyMode.atLeast,
    this.targets = const [],
  });

  /// Mengenai tambahan harga saja, bukan seluruh menunya.
  bool get targetsAddOn => targets.isNotEmpty;

  /// Nama sasarannya untuk ditampilkan, atau null kalau seluruh menu.
  String? get targetLabel {
    if (targets.isEmpty) return null;
    return targets.map((t) => t.label).join(', ');
  }

  /// Terpenuhi oleh [ordered] buah menu ini di keranjang.
  bool satisfiedBy(int ordered) =>
      mode == QtyMode.exactly ? ordered == qty : ordered >= qty;

  String get label =>
      mode == QtyMode.exactly ? 'tepat $qty pcs' : 'min $qty pcs';

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'qty': qty,
        'mode': _qtyModeDb[mode],
        if (targets.isNotEmpty)
          'targets': [for (final t in targets) t.toMap()],
        // Sasaran pertama ditulis ulang dalam bentuk lama.
        //
        // Bukan untuk dibaca versi ini, melainkan versi aplikasi yang
        // belum mengenal `targets` — dan itu termasuk HP kasir yang
        // belum sempat memperbarui. Tanpa ini, promo yang disunting di
        // HP baru berubah jadi promo seluruh menu di HP lama, dan
        // potongannya melonjak tanpa ada yang mengubahnya.
        if (targets.isNotEmpty) ...targets.first.toMap(),
      };

  factory DiscountItem.fromMap(Map<String, dynamic> map) {
    final daftar = map['targets'];
    return DiscountItem(
      productId: map['product_id'].toString(),
      qty: (map['qty'] as num?)?.toInt() ?? 1,
      mode: _qtyModeDb.entries
          .firstWhere((e) => e.value == map['mode'],
              orElse: () => _qtyModeDb.entries.first)
          .key,
      targets: daftar is List
          ? [
              for (final t in daftar)
                DiscountTarget.fromMap(Map<String, dynamic>.from(t as Map)),
            ]
          // Baris yang ditulis sebelum satu menu boleh punya beberapa
          // sasaran. Bentuk lamanya dibaca apa adanya jadi satu sasaran.
          : DiscountTarget.dariBentukLama(map),
    );
  }

  DiscountItem copyWith({
    int? qty,
    QtyMode? mode,
    List<DiscountTarget>? targets,
  }) =>
      DiscountItem(
        productId: productId,
        qty: qty ?? this.qty,
        mode: mode ?? this.mode,
        targets: targets ?? this.targets,
      );
}

/// Satu bagian menu yang dipotong: sebuah topping, atau sebuah pilihan
/// level.
class DiscountTarget {
  final String? levelGroup;
  final String? levelOption;
  final String? toppingName;

  /// Harga menu utamanya sendiri, tanpa tambahan apa pun.
  ///
  /// Berbeda dari "seluruh harga menu" — yang itu ikut memotong topping
  /// dan tambahan ukuran yang dipilih pemesan. Bedanya nyata di menu
  /// yang toppingnya mahal: "diskon 20%" yang dimaksud merchant hampir
  /// selalu 20% dari harga menunya, bukan 20% dari menu berikut empat
  /// topping yang ditambahkan pemesan sendiri.
  final bool utama;

  const DiscountTarget({
    this.levelGroup,
    this.levelOption,
    this.toppingName,
    this.utama = false,
  });

  const DiscountTarget.topping(String nama) : this(toppingName: nama);

  const DiscountTarget.level(String grup, String pilihan)
      : this(levelGroup: grup, levelOption: pilihan);

  const DiscountTarget.menuUtama() : this(utama: true);

  String get label {
    if (utama) return 'Harga menu utama';
    if (toppingName != null) return 'Topping: $toppingName';
    return '$levelGroup: $levelOption';
  }

  /// Kunci tunggal untuk membandingkan dan menyimpan pilihan di layar.
  String get kunci {
    if (utama) return 'M';
    return toppingName != null
        ? 'T|$toppingName'
        : 'L|$levelGroup|$levelOption';
  }

  static DiscountTarget? dariKunci(String kunci) {
    if (kunci == 'M') return const DiscountTarget.menuUtama();
    final bagian = kunci.split('|');
    if (bagian.first == 'T' && bagian.length == 2) {
      return DiscountTarget.topping(bagian[1]);
    }
    if (bagian.first == 'L' && bagian.length == 3) {
      return DiscountTarget.level(bagian[1], bagian[2]);
    }
    return null;
  }

  /// Baris pesanan ini memang membawa sasarannya.
  bool cocok(Map<String, String> levels, List<String> toppings) {
    // Harga menu utama dibawa setiap baris, apa pun pilihannya.
    if (utama) return true;
    if (toppingName != null) return toppings.contains(toppingName);
    if (levelOption != null) return levels[levelGroup] == levelOption;
    return false;
  }

  /// Harga yang dibawa sasaran ini pada menunya.
  int tambahanHarga(Product produk) {
    if (utama) return produk.price;
    if (toppingName != null) return produk.toppingPrice(toppingName!);
    if (levelOption != null) {
      return produk.priceDeltaFor(levelGroup!, levelOption!);
    }
    return 0;
  }

  Map<String, dynamic> toMap() => {
        if (utama) 'base': true,
        if (levelGroup != null) 'level_group': levelGroup,
        if (levelOption != null) 'level_option': levelOption,
        if (toppingName != null) 'topping': toppingName,
      };

  factory DiscountTarget.fromMap(Map<String, dynamic> map) => DiscountTarget(
        utama: map['base'] == true,
        levelGroup: map['level_group'] as String?,
        levelOption: map['level_option'] as String?,
        toppingName: map['topping'] as String?,
      );

  /// Bentuk lama: sasarannya menempel langsung di barisnya, paling
  /// banyak satu. Yang tidak menyebut sasaran apa pun berarti seluruh
  /// menu — dan itu daftar kosong, bukan satu sasaran kosong.
  static List<DiscountTarget> dariBentukLama(Map<String, dynamic> map) {
    final topping = map['topping'] as String?;
    final pilihan = map['level_option'] as String?;
    if (topping != null) return [DiscountTarget.topping(topping)];
    if (pilihan != null) {
      return [DiscountTarget.level(map['level_group'] as String? ?? '', pilihan)];
    }
    return const [];
  }

  @override
  bool operator ==(Object other) =>
      other is DiscountTarget && other.kunci == kunci;

  @override
  int get hashCode => kunci.hashCode;
}

/// Satu aturan diskon milik sebuah resto.
class Discount {
  final String id;
  final String restoId;
  final String name;

  final DiscountBasis basis;
  final DiscountKind kind;

  /// Persen (1–100) atau rupiah, tergantung [kind].
  final int value;

  /// Menu yang kena diskon — hanya untuk [DiscountBasis.products].
  /// Boleh lebih dari satu: itulah cara bundling dinyatakan, dan tiap
  /// menu membawa syarat jumlahnya sendiri.
  final List<DiscountItem> items;

  /// Id menunya saja. Masih ditulis ke database supaya baris ini tetap
  /// terbaca oleh versi aplikasi yang lebih lama.
  List<String> get productIds => [for (final i in items) i.productId];

  /// Ambang minimum belanja — hanya untuk [DiscountBasis.minPurchase].
  final int minPurchase;
  final MinCompare compare;

  final DateTime? startsOn;
  final DateTime? endsOn;

  final bool active;
  final String? createdBy;
  final DateTime createdAt;

  const Discount({
    required this.id,
    required this.restoId,
    required this.name,
    required this.basis,
    required this.kind,
    required this.value,
    this.items = const [],
    this.minPurchase = 0,
    this.compare = MinCompare.atLeast,
    this.startsOn,
    this.endsOn,
    this.active = true,
    this.createdBy,
    required this.createdAt,
  });

  PromoPeriod get period => PromoPeriod(startsOn: startsOn, endsOn: endsOn);

  /// Berlaku hari ini dan tidak dimatikan.
  bool isLive([DateTime? now]) => active && period.isLive(now);

  /// Potongan untuk sebuah nilai dasar.
  ///
  /// Dibulatkan ke bawah, dan tidak pernah melebihi dasarnya sendiri.
  /// Diskon yang lebih besar daripada tagihannya menghasilkan total
  /// negatif — uang yang harus dikembalikan resto kepada orang yang
  /// belum membayar apa pun.
  int amountFor(int base) {
    if (base <= 0) return 0;
    final raw = kind == DiscountKind.percent ? base * value ~/ 100 : value;
    return raw.clamp(0, base);
  }

  /// Ambang minimumnya terpenuhi.
  bool meetsMinimum(int total) => compare == MinCompare.atLeast
      ? total >= minPurchase
      : total > minPurchase;

  String get valueLabel =>
      kind == DiscountKind.percent ? '$value%' : 'Rp $value';

  Map<String, dynamic> toMap() => {
        'id': id,
        'resto_id': restoId,
        'name': name,
        'basis': _basisDb[basis],
        'kind': _kindDb[kind],
        'value': value,
        'product_ids': productIds,
        'product_rules': [for (final i in items) i.toMap()],
        'min_purchase': minPurchase,
        'compare_mode': _compareDb[compare],
        'starts_on': startsOn?.toIso8601String().split('T').first,
        'ends_on': endsOn?.toIso8601String().split('T').first,
        'active': active,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory Discount.fromMap(Map<String, dynamic> map) => Discount(
        id: map['id'] as String,
        restoId: map['resto_id'] as String,
        name: map['name'] as String? ?? 'Diskon',
        basis: _basisDb.entries
            .firstWhere((e) => e.value == map['basis'],
                orElse: () => _basisDb.entries.first)
            .key,
        kind: _kindDb.entries
            .firstWhere((e) => e.value == map['kind'],
                orElse: () => _kindDb.entries.first)
            .key,
        value: (map['value'] as num?)?.toInt() ?? 0,
        items: _items(map),
        minPurchase: (map['min_purchase'] as num?)?.toInt() ?? 0,
        compare: _compareDb.entries
            .firstWhere((e) => e.value == map['compare_mode'],
                orElse: () => _compareDb.entries.first)
            .key,
        startsOn: _date(map['starts_on']),
        endsOn: _date(map['ends_on']),
        active: map['active'] != false,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// Menu berikut syarat jumlahnya.
  ///
  /// Baris yang ditulis versi lama tidak punya product_rules — cuma
  /// daftar id, dan mungkin satu min_qty untuk seluruh promo. Keduanya
  /// dibaca sebagai aturan per menu supaya promo lama tetap berarti
  /// persis seperti saat dibuat.
  static List<DiscountItem> _items(Map<String, dynamic> map) {
    final rules = map['product_rules'] as List<dynamic>?;
    if (rules != null && rules.isNotEmpty) {
      return [
        for (final r in rules)
          DiscountItem.fromMap(Map<String, dynamic>.from(r as Map)),
      ];
    }
    final qty = (map['min_qty'] as num?)?.toInt() ?? 1;
    return [
      for (final id in (map['product_ids'] as List<dynamic>? ?? const []))
        DiscountItem(productId: id.toString(), qty: qty),
    ];
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v.toString());

  Discount copyWith({
    String? name,
    DiscountBasis? basis,
    DiscountKind? kind,
    int? value,
    List<DiscountItem>? items,
    int? minPurchase,
    MinCompare? compare,
    Object? startsOn = _unset,
    Object? endsOn = _unset,
    bool? active,
  }) =>
      Discount(
        id: id,
        restoId: restoId,
        name: name ?? this.name,
        basis: basis ?? this.basis,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        items: items ?? this.items,
        minPurchase: minPurchase ?? this.minPurchase,
        compare: compare ?? this.compare,
        startsOn:
            identical(startsOn, _unset) ? this.startsOn : startsOn as DateTime?,
        endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as DateTime?,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  static const _unset = Object();
}

/// Diskon terpilih untuk sebuah tagihan, berikut potongannya.
class AppliedDiscount {
  final Discount discount;
  final int amount;

  const AppliedDiscount(this.discount, this.amount);
}

/// Memilih diskon terbaik untuk sebuah tagihan.
///
/// Satu diskon, bukan ditumpuk semuanya. Menumpuk terdengar murah hati
/// sampai ada dua promo yang kebetulan berlaku bersamaan dan totalnya
/// melebihi harga barangnya — dan yang menemukan itu lebih dulu selalu
/// bukan restonya.
///
/// [subtotalOf] mengembalikan nilai yang boleh dipotong untuk sebuah
/// sasaran: seluruh baris menunya, atau — kalau sasarannya menyempit ke
/// sebuah level/topping — tambahan harga pilihan itu saja.
///
/// [qtyOf] mengembalikan jumlah yang cocok dengan sasaran itu, nol kalau
/// tidak ada. Keduanya menerima [DiscountItem] utuh, bukan sekadar id
/// produk: sasaran yang menyempit tidak bisa dijawab hanya dari id-nya.
AppliedDiscount? bestDiscountFor({
  required List<Discount> discounts,
  required int total,
  required int Function(DiscountItem item) subtotalOf,
  required int Function(DiscountItem item) qtyOf,
  DateTime? now,
}) {
  AppliedDiscount? terbaik;

  for (final d in discounts) {
    if (!d.isLive(now)) continue;

    int potongan;
    if (d.basis == DiscountBasis.minPurchase) {
      if (!d.meetsMinimum(total)) continue;
      potongan = d.amountFor(total);
    } else {
      if (d.items.isEmpty) continue;

      // Seluruh menu yang disebut promo harus terpenuhi, bukan salah
      // satunya. Sebagian-cukup terdengar murah hati sampai dilihat apa
      // artinya: promo "Nasi Goreng + Es Teh" akan keluar untuk
      // keranjang berisi dua Nasi Goreng dan segelas kopi — paket yang
      // dijanjikan spanduknya tidak pernah benar-benar dibeli, tapi
      // restonya tetap membayar potongannya.
      final lengkap = d.items.every((i) => i.satisfiedBy(qtyOf(i)));
      if (!lengkap) continue;

      // Bundling: semua menu yang ikut promo dijumlahkan dulu, baru
      // dipotong. Memotong tiap baris sendiri-sendiri membuat diskon
      // rupiah tetap (misal "potong 10.000") terkalikan sebanyak menu
      // yang ikut.
      final dasar = d.items.fold<int>(0, (sum, i) => sum + subtotalOf(i));
      potongan = d.amountFor(dasar);
    }

    if (potongan <= 0) continue;
    if (terbaik == null || potongan > terbaik.amount) {
      terbaik = AppliedDiscount(d, potongan);
    }
  }
  return terbaik;
}
