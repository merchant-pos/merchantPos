import 'dart:convert';

/// Satu pilihan tambahan pada sebuah menu, berikut harganya sendiri.
///
/// Dipisah dari level/varian karena bentuknya berbeda: level dipilih
/// satu dari beberapa ("Pedas" ATAU "Tidak Pedas"), topping dipilih
/// beberapa sekaligus ("Keju DAN Telur"). Memaksakannya jadi satu
/// bentuk berarti salah satunya harus berpura-pura jadi yang lain.
class Topping {
  final String name;

  /// Rupiah yang ditambahkan ke harga menunya. Boleh nol — sebagian
  /// topping memang gratis, dan menuliskannya tetap berguna supaya
  /// pelanggan tahu ia bisa memilihnya.
  final int price;

  const Topping({required this.name, this.price = 0});

  Map<String, dynamic> toMap() => {'name': name, 'price': price};

  factory Topping.fromMap(Map<String, dynamic> map) => Topping(
        name: map['name']?.toString() ?? '',
        price: (map['price'] as num?)?.toInt() ?? 0,
      );
}

class Product {
  final String id;
  final String name;
  final String category;
  final int price; // stored in Rupiah, no decimals
  /// Sisa stok — sekadar catatan, bukan penentu tersedia atau tidak.
  ///
  /// Dulu inilah yang menentukan: stok 0 berarti produk hilang dari
  /// menu. Itu memaksa tiap resto mengurus angka yang sebagian besar
  /// tidak pernah mereka hitung — nasi goreng tidak punya "sisa 7
  /// porsi", yang ada cuma "masih ada" atau "bahannya habis". Resto yang
  /// membiarkannya 0 karena tidak relevan justru kehilangan seluruh
  /// menunya.
  ///
  /// Sekarang angka ini boleh diisi atau tidak, dan tidak menyembunyikan
  /// apa pun. Yang menentukan cuma [outOfStock].
  final int stock;

  /// Ditandai habis oleh resto.
  ///
  /// Satu-satunya penentu produk bisa dipesan atau tidak. Dinyatakan
  /// sengaja oleh orang yang tahu keadaannya, bukan disimpulkan dari
  /// angka yang mungkin tidak pernah diperbarui.
  final bool outOfStock;

  final String? description;

  /// Base64-encoded JPEG, stored directly in the row/doc — same
  /// no-separate-storage-service pattern used for customer profile
  /// photos. Kept small via resize/compress before encoding (see
  /// ProductFormScreen).
  final String? photoBase64;

  /// Names of the [kLevelGroups] this product offers (e.g. "Level Pedas",
  /// "Level Gula") — empty if it has no variant options. Shown as
  /// required dropdowns in the quantity/order dialog for whoever is
  /// ordering (customer, kasir, or admin).
  final List<String> levelGroups;

  /// Extra price (can be negative) added on top of [price] when a given
  /// option is picked, keyed by group then option — e.g.
  /// {"Ukuran": {"Regular": 0, "Large": 5000}}. Groups/options with no
  /// entry here are treated as 0 (no price change). Mainly used for
  /// "Ukuran" (size), but works for any level group.
  final Map<String, Map<String, int>> levelPrices;

  /// Opt-outs from the resto-wide PPN / service rates, for the odd item
  /// that genuinely isn't subject to them.
  /// Topping yang ditawarkan menu ini. Kosong berarti tidak menawarkan
  /// apa pun — dan layar pesannya tidak menampilkan bagiannya sama
  /// sekali.
  final List<Topping> toppings;

  /// Paling banyak berapa topping yang boleh dipilih sekaligus.
  ///
  /// Nol berarti tanpa batas. Batasnya ada karena topping bukan hanya
  /// soal harga: dapur punya ruang terbatas di atas satu porsi, dan
  /// "semua topping sekaligus" adalah pesanan yang tidak bisa dibuat.
  final int maxToppings;

  final bool ppnExempt;
  final bool serviceExempt;

  /// Label yang dinyatakan merchant: 'new', 'best_seller', 'recommended'.
  ///
  /// Label diskon tidak pernah ada di sini. Itu dibaca dari promo yang
  /// sedang berlaku, bukan dicentang — label yang dicentang akan tetap
  /// terpasang seminggu setelah promonya habis.
  final List<String> badges;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.stock = 0,
    this.outOfStock = false,
    this.description,
    this.photoBase64,
    this.levelGroups = const [],
    this.toppings = const [],
    this.maxToppings = 0,
    this.levelPrices = const {},
    this.ppnExempt = false,
    this.serviceExempt = false,
    this.badges = const [],
  });

  /// Bisa dipesan sekarang.
  bool get available => !outOfStock;

  /// Extra price for the chosen [option] within [group], or 0 if unset.
  /// Harga sebuah topping, nol kalau namanya tidak dikenal.
  ///
  /// Dicari dari daftar produknya, bukan dari yang dikirim layar:
  /// harga yang datang bersama pilihan bisa diubah siapa pun yang mau
  /// menambahkan keju seharga nol rupiah.
  int toppingPrice(String name) {
    for (final t in toppings) {
      if (t.name == name) return t.price;
    }
    return 0;
  }

  /// Batas yang benar-benar berlaku: tanpa batas berarti sebanyak yang
  /// ditawarkan.
  int get effectiveMaxToppings =>
      maxToppings <= 0 ? toppings.length : maxToppings;

  int priceDeltaFor(String group, String option) =>
      levelPrices[group]?[option] ?? 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'description': description,
      'photo_base64': photoBase64,
      'level_groups': levelGroups.isEmpty ? null : levelGroups.join(','),
      'level_prices': levelPrices.isEmpty ? null : jsonEncode(levelPrices),
      'toppings': toppings.isEmpty
          ? null
          : jsonEncode([for (final t in toppings) t.toMap()]),
      'max_toppings': maxToppings,
      // SQLite has no bool — 0/1 round-trips through both it and Postgres.
      'ppn_exempt': ppnExempt ? 1 : 0,
      'service_exempt': serviceExempt ? 1 : 0,
      'out_of_stock': outOfStock ? 1 : 0,
      // Teks JSON di sqflite, jsonb di Postgres. Keduanya membaca teks
      // JSON yang sama — supabase-dart mengirimnya apa adanya dan
      // Postgres yang menguraikannya.
      'badges': jsonEncode(badges),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawLevels = map['level_groups'] as String?;
    final rawPrices = map['level_prices'] as String?;
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      price: (map['price'] as num).toInt(),
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      description: map['description'] as String?,
      photoBase64: map['photo_base64'] as String?,
      levelGroups: (rawLevels == null || rawLevels.isEmpty)
          ? const []
          : rawLevels.split(','),
      levelPrices: (rawPrices == null || rawPrices.isEmpty)
          ? const {}
          : (jsonDecode(rawPrices) as Map<String, dynamic>).map(
              (group, options) => MapEntry(
                group,
                (options as Map<String, dynamic>)
                    .map((opt, delta) => MapEntry(opt, (delta as num).toInt())),
              ),
            ),
      toppings: _toppings(map['toppings']),
      maxToppings: (map['max_toppings'] as num?)?.toInt() ?? 0,
      ppnExempt: _asBool(map['ppn_exempt']),
      serviceExempt: _asBool(map['service_exempt']),
      outOfStock: _asBool(map['out_of_stock']),
      badges: _badges(map['badges']),
    );
  }

  /// Sama seperti [_toppings]: teks JSON dari sqflite, daftar dari
  /// Postgres. Bentuk yang tidak dikenal dibaca sebagai kosong — menu
  /// tanpa label masih menu, tapi menu yang gagal dibaca berarti layar
  /// kosong.
  static List<String> _badges(Object? raw) {
    if (raw == null) return const [];
    try {
      final data = raw is String
          ? (raw.isEmpty ? const [] : jsonDecode(raw) as List<dynamic>)
          : raw as List<dynamic>;
      return [for (final b in data) b.toString()];
    } catch (_) {
      return const [];
    }
  }

  /// SQLite hands these back as 0/1 ints, Postgres as real booleans.
  static List<Topping> _toppings(Object? raw) {
    if (raw == null) return const [];
    // Dua bentuk: teks JSON dari sqflite, dan daftar dari Postgres.
    final data = raw is String
        ? (raw.isEmpty ? const [] : jsonDecode(raw) as List<dynamic>)
        : raw as List<dynamic>;
    return [
      for (final t in data) Topping.fromMap(Map<String, dynamic>.from(t as Map)),
    ];
  }

  static bool _asBool(Object? value) => value == true || value == 1;

  /// Sentinel used so `copyWith` can tell "not passed" apart from
  /// "explicitly set to null" (e.g. clearing a photo/description).
  static const _unset = Object();

  Product copyWith({
    String? name,
    String? category,
    int? price,
    int? stock,
    bool? outOfStock,
    Object? description = _unset,
    Object? photoBase64 = _unset,
    List<String>? levelGroups,
    List<Topping>? toppings,
    int? maxToppings,
    Map<String, Map<String, int>>? levelPrices,
    bool? ppnExempt,
    bool? serviceExempt,
    List<String>? badges,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      outOfStock: outOfStock ?? this.outOfStock,
      description:
          identical(description, _unset) ? this.description : description as String?,
      photoBase64:
          identical(photoBase64, _unset) ? this.photoBase64 : photoBase64 as String?,
      levelGroups: levelGroups ?? this.levelGroups,
      toppings: toppings ?? this.toppings,
      maxToppings: maxToppings ?? this.maxToppings,
      levelPrices: levelPrices ?? this.levelPrices,
      ppnExempt: ppnExempt ?? this.ppnExempt,
      serviceExempt: serviceExempt ?? this.serviceExempt,
      badges: badges ?? this.badges,
    );
  }
}
