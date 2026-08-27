import 'product.dart';

/// One line in the cart.
///
/// Identified by [lineId], not by product: the same dish can appear
/// several times with different options — a pedas nasi goreng and a
/// tidak pedas one are two lines, not a quantity of two — so keying on
/// the product would collapse them and lose the distinction the kitchen
/// needs.
class CartItem {
  /// Stable per-line identity, so edits and deletes hit the right line
  /// even after the list is reordered or another line is removed.
  final String lineId;

  final Product product;
  int quantity;

  /// Chosen option per level group (e.g. {"Level Pedas": "Pedas"}) — one
  /// entry per group in [Product.levelGroups].
  Map<String, String> selectedLevels;

  /// Topping yang dipilih, disebut namanya.
  ///
  /// Yang disimpan namanya saja, bukan harganya: harga dicari dari
  /// produknya saat dihitung. Harga yang ikut dibawa pilihan bisa
  /// diubah siapa pun yang mau menambahkan keju seharga nol rupiah.
  List<String> selectedToppings;

  /// Free-text note from whoever is ordering (customer/kasir/admin), e.g.
  /// "tanpa bawang" — always optional, on top of the level selections.
  String? notes;

  CartItem({
    required this.lineId,
    required this.product,
    this.quantity = 1,
    Map<String, String>? selectedLevels,
    List<String>? selectedToppings,
    this.notes,
  })  : selectedLevels = selectedLevels ?? {},
        selectedToppings = selectedToppings ?? [];

  /// Identifies the *configuration* rather than the line: two lines of
  /// the same product with identical options and note are the same thing
  /// ordered twice, so they get merged instead of stacking up as
  /// duplicate rows.
  String get variantKey {
    final options = selectedLevels.entries.map((e) => '${e.key}=${e.value}').toList()..sort();
    // Toppingnya diurutkan lebih dulu: keju+telur dan telur+keju adalah
    // pesanan yang sama, dan tanpa diurutkan keduanya jadi dua baris
    // berbeda di keranjang maupun di layar dapur.
    final tops = [...selectedToppings]..sort();
    return '${product.id}|${options.join(',')}|${tops.join(',')}|'
        '${notes?.trim() ?? ''}';
  }

  /// Unit price after adding any per-level price deltas (e.g. "Ukuran:
  /// Large" adding Rp 5.000 on top of the base price) dan harga tiap
  /// topping yang dipilih.
  int get effectiveUnitPrice {
    final level = selectedLevels.entries
        .fold<int>(0, (sum, e) => sum + product.priceDeltaFor(e.key, e.value));
    final topping = selectedToppings
        .fold<int>(0, (sum, t) => sum + product.toppingPrice(t));
    return product.price + level + topping;
  }

  int get subtotal => effectiveUnitPrice * quantity;

  /// Combined human-readable line for receipts/kitchen tickets, e.g.
  /// "Level Pedas: Pedas, Level Gula: Kurang Manis • tanpa bawang".
  String? get noteSummary {
    final parts = <String>[
      for (final entry in selectedLevels.entries) '${entry.key}: ${entry.value}',
      if (selectedToppings.isNotEmpty) 'Topping: ${selectedToppings.join(', ')}',
    ];
    final combined = parts.join(', ');
    final trimmedNotes = notes?.trim() ?? '';
    if (combined.isEmpty && trimmedNotes.isEmpty) return null;
    if (combined.isEmpty) return trimmedNotes;
    if (trimmedNotes.isEmpty) return combined;
    return '$combined • $trimmedNotes';
  }
}
