import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/firestore_product_repository.dart';
import '../db/order_repository.dart';
import '../db/product_repository.dart';
import '../db/transaction_repository.dart';
import '../models/cart_item.dart';
import '../models/discount.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../utils/tax_calculator.dart';

class CartProvider extends ChangeNotifier {
  final _productRepo = ProductRepository();
  final _firestoreProductRepo = FirestoreProductRepository();
  final _txRepo = TransactionRepository();
  final _orderRepo = OrderRepository();
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

  /// Diskon yang berlaku hari ini di resto ini, dimuat layar kasir.
  List<Discount> discounts = const [];

  void setDiscounts(List<Discount> value) {
    discounts = value;
    notifyListeners();
  }

  /// Diskon terbaik untuk isi keranjang sekarang, atau null.
  ///
  /// Dihitung dari total tagihan — sesudah service dan PPN — karena
  /// itulah angka yang dilihat dan dijanjikan ke pelanggan. "Belanja 200
  /// ribu dapat diskon" dibaca orang sebagai yang tertulis di struk,
  /// bukan sebagai subtotal sebelum pajak yang tidak pernah dia lihat.
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

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Semua baris untuk satu produk — bisa lebih dari satu kalau menu
  /// yang sama dipesan dengan opsi berbeda.
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

  /// Lowercase keys, not display labels — matches `gl_accounts.payment_
  /// method` and what customer self-orders write for their own payment_
  /// method, so the shared `orders` table relates to `gl_accounts`
  /// directly without needing a translation step. The local SQLite
  /// [PosTransaction] (receipt/riwayat transaksi) keeps using the
  /// [PaymentMethod] enum's own display labels — unaffected, unrelated
  /// to gl_accounts.
  static const _glPaymentKeys = {
    PaymentMethod.cash: 'cash',
    PaymentMethod.qris: 'qris',
    PaymentMethod.transfer: 'transfer',
  };

  /// Finalizes the sale: saves the transaction, deducts stock, clears cart.
  /// This is the single "checkout" entry point — every payment method
  /// (cash, QRIS, transfer) flows through here so the reconciliation
  /// ledger stays consistent regardless of how the customer paid.
  ///
  /// [cashierLabel] (the logged-in Kasir/Admin's email) identifies the
  /// account; [cashierName] is their display name, recorded on the sale
  /// itself so a receipt or a day's Riwayat Transaksi can say who was on
  /// shift without anyone having to decode an email. [tableNumber]
  /// and [restoId] (required at checkout) are used to mirror this sale
  /// into the shared Firestore "orders" feed so the Chef sees it
  /// alongside customer self-orders, with a table to deliver it to and
  /// scoped to the right restaurant. [tableNumber] is null for a
  /// [OrderType.takeAway] sale — no table involved.
  /// [customerName] is mandatory (validated by the checkout screen, not
  /// here) for [OrderType.takeAway] — the Kasir types in who to call out
  /// when it's ready, since there's no table to deliver it to.
  Future<PosTransaction> checkout(
    PaymentMethod method, {
    String? cashierLabel,
    String? cashierName,
    String? tableNumber,
    required String restoId,
    OrderType orderType = OrderType.dineIn,
    String? customerName,
    int? cashReceived,
  }) async {
    final tax = chargesFor(orderType);
    final applied = discountFor(orderType);
    final payable = tax.total - (applied?.amount ?? 0);

    var tx = PosTransaction(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      paymentMethod: method,
      // Yang tersimpan adalah yang benar-benar dibayar. Menyimpan harga
      // sebelum potongan berarti Riwayat Kasir menjumlahkan uang yang
      // tidak pernah masuk laci.
      total: payable,
      orderType: orderType,
      customerName: customerName,
      cashierName: cashierName,
      cashReceived: cashReceived,
      baseAmount: tax.base,
      serviceAmount: tax.service,
      ppnAmount: tax.ppn,
      items: _items
          .map((i) => TransactionItem(
                productId: i.product.id,
                productName: i.product.name,
                price: i.effectiveUnitPrice,
                quantity: i.quantity,
                notes: i.noteSummary,
              ))
          .toList(),
    );

    await _txRepo.insert(tx);
    final stockDeltas = <String, int>{};
    for (final item in _items) {
      await _productRepo.adjustStock(item.product.id, -item.quantity);
      // Accumulated, not assigned: the same product can now occupy
      // several lines (pedas and tidak pedas), and overwriting would
      // deduct only the last line's quantity from stock.
      stockDeltas.update(item.product.id, (q) => q + item.quantity,
          ifAbsent: () => item.quantity);
    }
    // Best-effort mirror so the customer-facing catalog reflects the same
    // stock. Skipped silently if offline.
    _firestoreProductRepo.decrementStockForOrder(stockDeltas).catchError((_) {});

    // Mirror into the shared order feed so the Chef sees walk-in sales too.
    //
    // Ditunggu sebentar, bukan dilepas begitu saja: nomor antreannya
    // diberikan pemicu di basis data, dan struk yang dicetak sedetik
    // kemudian harus menyebut nomor yang sama dengan yang diteriakkan
    // ke ruangan.
    //
    // Batas waktunya pendek dan kegagalannya diabaikan. Kasir yang
    // menunggu jaringan untuk mencetak struk adalah antrean yang
    // berhenti; struk tanpa nomor jauh lebih murah daripada itu.
    final nomor = await _orderRepo
        .createReturningNo(CustomerOrder(
      id: '',
      createdAt: tx.createdAt,
      items: tx.items
          .map((i) => CustomerOrderItem(
                productId: i.productId,
                productName: i.productName,
                price: i.price,
                quantity: i.quantity,
                notes: i.notes,
              ))
          .toList(),
      total: tx.total,
      paymentStatus: OrderPaymentStatus.paid,
      customerLabel: cashierLabel ?? 'Kasir',
      source: OrderSource.kasir,
      paymentMethod: _glPaymentKeys[method],
      tableNumber: tableNumber,
      restoId: restoId,
      orderType: orderType,
      customerName: customerName,
      cashierName: cashierName,
      baseAmount: tax.base,
      serviceAmount: tax.service,
      ppnAmount: tax.ppn,
      discountAmount: applied?.amount ?? 0,
      discountId: applied?.discount.id,
      discountName: applied?.discount.name,
    ))
        .timeout(const Duration(seconds: 4))
        .catchError((_) => null);

    if (nomor != null) {
      tx = tx.denganNomor(nomor);
      await _txRepo.updateNomor(tx.id, nomor);
    }

    clear();
    return tx;
  }
}
