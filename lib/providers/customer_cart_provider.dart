import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/firestore_product_repository.dart';
import '../db/order_repository.dart';
import '../db/session_repository.dart';
import '../models/cart_item.dart';
import '../models/discount.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../models/product.dart';
import '../utils/tax_calculator.dart';

/// Cart for the customer self-order flow. Separate from [CartProvider]
/// (used by the cashier) because checkout here creates a Firestore order
/// instead of a local SQLite transaction, and only ever pays via QRIS.
class CustomerCartProvider extends ChangeNotifier {
  final _orderRepo = OrderRepository();
  final _firestoreProductRepo = FirestoreProductRepository();
  final _sessionRepo = SessionRepository();

  final _uuid = const Uuid();

  final List<CartItem> _items = [];
  List<CartItem> get items => List.unmodifiable(_items);

  /// Sum of the menu prices shown to the customer (original + PPN).
  /// Service isn't in here — it lands at checkout, and only for Dine In.
  int get total => _items.fold(0, (sum, item) => sum + menuSubtotalOf(item));

  /// Sum of the original, pre-charge prices.
  int get baseTotal => _items.fold(0, (sum, item) => sum + item.subtotal);

  /// Resto-wide charge rates, pushed in by whichever ordering screen is
  /// open. Menu prices carry PPN only; service is a per-bill Dine In
  /// charge worked out at checkout, so it never changes a line's price.
  double ppnPercent = 0;
  double servicePercent = 0;

  void setRates({required double ppn, required double service}) {
    if (ppnPercent == ppn && servicePercent == service) return;
    ppnPercent = ppn;
    servicePercent = service;
    notifyListeners();
  }

  /// What a line costs on the menu — original price plus PPN.
  int menuSubtotalOf(CartItem item) =>
      menuPrice(item.effectiveUnitPrice,
          ppnPercent: ppnPercent, ppnExempt: item.product.ppnExempt) *
      item.quantity;

  /// Splits the bill for [orderType], building up from original prices.
  TaxBreakdown chargesFor(OrderType orderType) => calculateCharges(
        lines: _items
            .map((i) => TaxableLine(
                  baseTotal: i.subtotal,
                  ppnExempt: i.product.ppnExempt,
                  serviceExempt: i.product.serviceExempt,
                ))
            .toList(),
        ppnPercent: ppnPercent,
        servicePercent: servicePercent,
        serviceApplies: orderType == OrderType.dineIn,
      );

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Semua baris untuk satu produk — bisa lebih dari satu kalau menu
  /// yang sama dipesan dengan opsi berbeda.
  /// Diskon yang berlaku hari ini di resto ini, dimuat layar keranjang.
  ///
  /// Promo yang cuma berlaku kalau kasir yang mengetikkan pesanannya
  /// bukan promo — ia janji yang gagal ditepati tepat di depan orang
  /// yang membacanya di layar menu.
  List<Discount> discounts = const [];

  void setDiscounts(List<Discount> value) {
    discounts = value;
    notifyListeners();
  }

  /// Diskon terbaik untuk isi keranjang sekarang, atau null.
  ///
  /// Dihitung dari total tagihan — sesudah service dan PPN — karena
  /// itulah angka yang dilihat dan dijanjikan ke pelanggan.
  AppliedDiscount? discountFor(OrderType orderType) => bestDiscountFor(
        discounts: discounts,
        total: chargesFor(orderType).total,
        subtotalOf: _dasarDiskon,
        qtyOf: _jumlahDiskon,
      );


  /// Nilai yang boleh dipotong untuk sebuah sasaran diskon.
  ///
  /// Sasaran yang menyempit ke sebuah level atau topping hanya memotong
  /// TAMBAHAN harganya, bukan harga menunya. Itulah yang membuat "gratis
  /// ukuran besar" bisa dinyatakan: menunya tetap dibayar penuh, yang
  /// hilang cuma selisih ukurannya.
  int _dasarDiskon(DiscountItem item) {
    final baris = linesOf(item.productId);
    if (baris.isEmpty) return 0;
    final produk = baris.first.product;

    // Tanpa sasaran berarti seluruh harga menunya — berikut tambahan
    // apa pun yang dipilih pemesan.
    if (item.targets.isEmpty) {
      return baris.fold<int>(0, (s, l) => s + menuSubtotalOf(l));
    }

    // Beberapa sasaran dijumlahkan, bukan dipilih salah satu. Promo
    // "topping gratis" yang menyebut tiga topping memang berarti
    // ketiganya — yang memilih dua di antaranya mendapat potongan untuk
    // dua-duanya sekaligus.
    var total = 0;
    for (final l in baris) {
      for (final t in item.targets) {
        if (!t.cocok(l.selectedLevels, l.selectedToppings)) continue;
        total += _hargaMenu(t.tambahanHarga(produk), l) * l.quantity;
      }
    }
    return total;
  }

  /// Tambahan harga dipajaki sama seperti menunya sendiri — kalau tidak,
  /// potongan 100% menyisakan beberapa ratus rupiah yang tidak bisa
  /// dijelaskan ke pelanggan.
  int _hargaMenu(int harga, CartItem line) => menuPrice(harga,
      ppnPercent: ppnPercent, ppnExempt: line.product.ppnExempt);

  /// Jumlah yang cocok dengan sasarannya.
  int _jumlahDiskon(DiscountItem item) {
    if (item.targets.isEmpty) return quantityOf(item.productId);
    // Baris yang membawa salah satu sasarannya sudah dihitung — bukan
    // yang membawa semuanya. Menuntut semuanya berarti promo tiga
    // topping cuma berlaku bagi yang memesan ketiganya sekaligus.
    return linesOf(item.productId)
        .where((l) => item.targets
            .any((t) => t.cocok(l.selectedLevels, l.selectedToppings)))
        .fold<int>(0, (s, l) => s + l.quantity);
  }

  /// Yang benar-benar harus dibayar setelah potongan.
  int payableFor(OrderType orderType) {
    final total = chargesFor(orderType).total;
    return total - (discountFor(orderType)?.amount ?? 0);
  }

  List<CartItem> linesOf(String productId) =>
      _items.where((i) => i.product.id == productId).toList();

  /// How many of [productId] are in the cart across every variant —
  /// used by the grid badge, where "2" should mean two plates of nasi
  /// goreng regardless of how many lines they're split over.
  int quantityOf(String productId) => _items
      .where((i) => i.product.id == productId)
      .fold(0, (sum, i) => sum + i.quantity);

  /// Adds a configured line. Merges into an existing line only when the
  /// options and note match exactly — otherwise the same dish ordered
  /// two different ways stays as two separate lines.
  void addLine(
    Product product, {
    int quantity = 1,
    Map<String, String>? selectedLevels,
    List<String>? selectedToppings,
    String? notes,
  }) {
    if (quantity <= 0) return;
    final candidate = CartItem(
      lineId: _uuid.v4(),
      product: product,
      quantity: quantity,
      selectedLevels: selectedLevels,
      selectedToppings: selectedToppings,
      notes: notes,
    );
    final existing = _items.where((i) => i.variantKey == candidate.variantKey);
    if (existing.isNotEmpty) {
      existing.first.quantity += quantity;
    } else {
      _items.add(candidate);
    }
    notifyListeners();
  }

  /// Edits one line in place. A quantity of 0 or less deletes it.
  void updateLine(
    String lineId, {
    required int quantity,
    Map<String, String>? selectedLevels,
    List<String>? selectedToppings,
    String? notes,
  }) {
    final index = _items.indexWhere((i) => i.lineId == lineId);
    if (index == -1) return;
    if (quantity <= 0) {
      _items.removeAt(index);
      notifyListeners();
      return;
    }
    final item = _items[index];
    item.quantity = quantity;
    if (selectedLevels != null) item.selectedLevels = selectedLevels;
    item.notes = notes;

    // Editing a line's options can turn it into a duplicate of another
    // line — fold them together rather than leaving two identical rows.
    final twin = _items.where((i) => i.lineId != lineId && i.variantKey == item.variantKey);
    if (twin.isNotEmpty) {
      twin.first.quantity += item.quantity;
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void incrementLine(String lineId) {
    final item = _items.where((i) => i.lineId == lineId);
    if (item.isEmpty) return;
    item.first.quantity++;
    notifyListeners();
  }

  /// Steps a line down, deleting it when it would hit zero.
  void decrementLine(String lineId) {
    final index = _items.indexWhere((i) => i.lineId == lineId);
    if (index == -1) return;
    if (_items[index].quantity > 1) {
      _items[index].quantity--;
    } else {
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void removeLine(String lineId) {
    _items.removeWhere((i) => i.lineId == lineId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// Places the order in Firestore with status "pending" — it shows up
  /// immediately in the employee app's "Pesanan Masuk" list — and returns
  /// the order id so the QR screen can mark it paid once confirmed.
  ///
  /// [sessionId] and [restoId] come from [TableSessionProvider] —
  /// required so the order can be tied to the right restaurant and so
  /// the customer can track its status afterward without an account.
  /// [tableNumber] is null for a [OrderType.takeAway] order (no table
  /// involved); required for [OrderType.dineIn]. [customerName] is
  /// mandatory (validated by the checkout screen, not here) for
  /// take-away — who to call out when it's ready.
  Future<String> placeOrder(
    String customerLabel, {
    String? tableNumber,
    required String sessionId,
    required String restoId,
    OrderType orderType = OrderType.dineIn,
    String? customerName,
    String paymentMethod = 'qris',
    String? voucherClaimId,
    String? voucherCode,
    int voucherAmount = 0,
  }) async {
    final tax = chargesFor(orderType);
    final applied = discountFor(orderType);

    final order = CustomerOrder(
      id: '', // assigned by Firestore
      createdAt: DateTime.now(),
      items: _items
          .map((i) => CustomerOrderItem(
                productId: i.product.id,
                productName: i.product.name,
                price: i.effectiveUnitPrice,
                quantity: i.quantity,
                notes: i.noteSummary,
              ))
          .toList(),
      // Yang tersimpan adalah yang benar-benar ditagihkan. Menyimpan
      // harga sebelum potongan berarti kasir menagih angka yang tidak
      // pernah dilihat pelanggannya.
      // Voucher ikut mengurangi yang dibayar. Potongannya ditanggung
      // Merchant-POS, tapi yang dilihat pelanggan tetap satu angka — dan
      // angka itulah yang harus tersimpan sebagai total pesanannya.
      total: tax.total - (applied?.amount ?? 0) - voucherAmount,
      voucherClaimId: voucherClaimId,
      voucherCode: voucherCode,
      voucherAmount: voucherAmount,
      paymentStatus: OrderPaymentStatus.pending,
      customerLabel: customerLabel,
      // Selalu diisi, tidak pernah dibiarkan kosong, supaya kolomnya
      // berhubungan langsung dengan gl_accounts persis seperti penjualan
      // lewat kasir. 'cash' berarti pelanggan memilih membayar di meja
      // kasir: pesanannya tetap masuk sekarang, uangnya menyusul.
      paymentMethod: paymentMethod,
      tableNumber: tableNumber,
      sessionId: sessionId,
      restoId: restoId,
      orderType: orderType,
      customerName: customerName,
      baseAmount: tax.base,
      serviceAmount: tax.service,
      ppnAmount: tax.ppn,
      discountAmount: applied?.amount ?? 0,
      discountId: applied?.discount.id,
      discountName: applied?.discount.name,
    );
    final id = await _orderRepo.create(order);

    // Reserve stock immediately (same behavior as the cashier checkout) so
    // two customers can't both order the last unit of something.
    final stockDeltas = <String, int>{};
    for (final item in _items) {
      // Accumulated, not assigned: the same product can now occupy
      // several lines (pedas and tidak pedas), and overwriting would
      // deduct only the last line's quantity from stock.
      stockDeltas.update(item.product.id, (q) => q + item.quantity,
          ifAbsent: () => item.quantity);
    }
    await _firestoreProductRepo.decrementStockForOrder(stockDeltas);

    // Reset the backend's "5 minutes idle" clock for this session so the
    // Cloud Function doesn't end it while a fresh order is still cooking.
    _sessionRepo.touchLastOrder(sessionId).catchError((_) {});

    clear();
    return id;
  }
}
