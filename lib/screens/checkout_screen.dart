import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order_type.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import 'payment_qris_screen.dart';
import 'payment_transfer_screen.dart';
import 'receipt_screen.dart';
import '../widgets/cash_payment_dialog.dart';
import '../db/discount_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../widgets/charge_summary.dart';
import '../widgets/quantity_dialog.dart';
import '../widgets/cart_line_tile.dart';
import '../models/cart_item.dart';
import '../utils/field_rules.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _tableCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  OrderType _orderType = OrderType.dineIn;

  @override
  void initState() {
    super.initState();
    _loadResto();
    _loadDiscounts();
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  final _restoRepo = RestaurantRepository();
  Restaurant? _resto;

  /// Produk di keranjang yang ternyata sudah habis. Dapur bisa
  /// menandainya di sela kasir menyusun pesanan.
  Set<String> _soldOut = {};

  /// Rates come from the resto record, so the same order rung up on any
  /// device splits identically.
  double get _ppnPercent => _resto?.ppnPercent ?? 0;
  double get _servicePercent => _resto?.servicePercent ?? 0;

  /// Diskon yang berlaku hari ini, dimuat sekali saat layar dibuka.
  Future<void> _loadDiscounts() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final live = await DiscountRepository().liveForResto(restoId);
      if (!mounted) return;
      context.read<CartProvider>().setDiscounts(live);
    } catch (_) {
      // Luring, atau tabelnya belum dimigrasi. Tanpa diskon, harganya
      // kembali ke harga daftar — bukan transaksi yang gagal.
    }
  }

  Future<void> _loadResto() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await _restoRepo.getOnce(restoId);
      if (!mounted) return;
      setState(() {
        _resto = resto;
        // Kalau resto ini tidak melayani cara makan yang sedang
        // terpilih, pindahkan sekarang — bukan menunggu kasir menekan
        // tombol bayar lalu ditolak.
        if (resto != null && !resto.orderTypes.contains(_orderType)) {
          _orderType = resto.orderTypes.first;
        }
      });
      context.read<CartProvider>().setRates(
            ppn: resto?.ppnPercent ?? 0,
            service: resto?.servicePercent ?? 0,
          );
    } catch (_) {
      // Offline — fall back to no charges rather than guessing a rate.
    }
  }

  bool get _isDineIn => _orderType == OrderType.dineIn;

  /// Cara makan yang dilayani resto ini. Sebelum datanya termuat,
  /// keduanya dianggap dilayani — itu keadaan sebelum ini dan berlaku
  /// untuk hampir semua resto.
  List<OrderType> get _orderTypes =>
      _resto?.orderTypes ?? const [OrderType.dineIn, OrderType.takeAway];

  /// Free-form label, not a number — "A01" and "VIP-2" are valid tables.
  String? get _tableNumber {
    final raw = _tableCtrl.text.trim();
    return raw.isEmpty ? null : raw;
  }

  String get _customerName => _customerNameCtrl.text.trim();

  /// Dine In needs a table number; Take Away needs a customer name
  /// instead (there's no table to deliver it to).
  bool get _canPay => _isDineIn ? _tableNumber != null : _customerName.isNotEmpty;

  /// Reopens the options popup on an existing line, so a wrong spice
  /// level or a mistaken add can be fixed without clearing the cart.
  Future<void> _editLine(BuildContext context, CartProvider cart, CartItem item) async {
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        showStock: true,
        product: item.product,
        initialQuantity: item.quantity,
        initialLevels: item.selectedLevels,
        initialToppings: item.selectedToppings,
        initialNotes: item.notes,
        ppnPercent: cart.ppnPercent,
        editing: true,
      ),
    );
    if (result == null) return;
    cart.updateLine(
      item.lineId,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      selectedToppings: result.selectedToppings,
      notes: result.notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir')),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong. Pilih produk dulu.'));
          }
          // Satu gulungan untuk daftar item dan rinciannya sekaligus,
          // bukan dua bagian yang berebut tinggi lewat Expanded.
          //
          // Dengan Expanded, blok rincian di bawah lebih tinggi daripada
          // layar tablet yang pendek: daftar itemnya diperas jadi nol
          // dan tombol bayarnya terpotong di tepi bawah, tanpa ada yang
          // bisa digulir untuk menemukannya.
          return ListView(
            children: [
              for (final item in cart.items)
                CartLineTile(
                  item: item,
                  unitPrice: cart.menuSubtotalOf(item) ~/ item.quantity,
                  lineTotal: cart.menuSubtotalOf(item),
                  currency: currency,
                  onIncrement: () => cart.incrementLine(item.lineId),
                  onDecrement: () => cart.decrementLine(item.lineId),
                  onDelete: () => cart.removeLine(item.lineId),
                  onEdit: () => _editLine(context, cart, item),
                  soldOut: _soldOut.contains(item.product.id),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Hanya cara makan yang benar-benar dilayani resto
                    // ini. Tombol yang selalu ada berarti pesanan yang
                    // tidak bisa dilayani tetap masuk, dan yang menolak
                    // belakangan adalah orang — di depan pelanggan yang
                    // sudah membayar.
                    if (_orderTypes.length > 1)
                      SegmentedButton<OrderType>(
                        segments: const [
                          ButtonSegment(
                            value: OrderType.dineIn,
                            label: Text('Dine In'),
                            icon: Icon(Icons.restaurant_outlined),
                          ),
                          ButtonSegment(
                            value: OrderType.takeAway,
                            label: Text('Take Away'),
                            icon: Icon(Icons.shopping_bag_outlined),
                          ),
                        ],
                        selected: {_orderType},
                        onSelectionChanged: (v) => setState(() => _orderType = v.first),
                      )
                    else
                      // Satu-satunya pilihan tetap ditulis, bukan
                      // dihilangkan begitu saja: struk dan layar dapur
                      // menyebut Dine In atau Take Away, dan kasir harus
                      // tahu yang mana tanpa harus menebak.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: Icon(
                            _isDineIn
                                ? Icons.restaurant_outlined
                                : Icons.shopping_bag_outlined,
                            size: 17,
                          ),
                          label: Text(_isDineIn ? 'Dine In' : 'Take Away'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (_isDineIn) ...[
                      TextField(
                        controller: _tableCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Nomor Meja',
                          hintText: 'Contoh: 7, A01, VIP-2',
                          prefixIcon: Icon(Icons.table_bar_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      // Namanya opsional di Dine In, dan sengaja begitu.
                      //
                      // Yang mengantarkan makanannya sudah tahu ke meja
                      // mana — nomor mejanya di atas sudah cukup. Nama di
                      // sini gunanya untuk yang datang sesudahnya:
                      // struk yang dicari, pesanan yang ditanyakan
                      // ulang, atau meja yang isinya dua rombongan.
                      // Mewajibkannya cuma menambah satu ketikan di
                      // tiap transaksi untuk sesuatu yang tidak selalu
                      // ditanyakan kasirnya.
                      TextField(
                        controller: _customerNameCtrl,
                        inputFormatters: nameFormatters,
                        textCapitalization: TextCapitalization.words,
                        maxLength: kNameMaxLength,
                        decoration: const InputDecoration(
                          labelText: 'Nama Customer (opsional)',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          helperText: 'Muncul di struk dan layar dapur',
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ] else
                      TextField(
                        controller: _customerNameCtrl,
                        inputFormatters: nameFormatters,
                        textCapitalization: TextCapitalization.words,
                        maxLength: kNameMaxLength,
                        decoration: const InputDecoration(
                          labelText: 'Nama Customer',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          helperText: 'Wajib diisi — dipanggil saat pesanan siap diambil',
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 16),
                    ChargeSummary(
                      charges: cart.chargesFor(_orderType),
                      menuSubtotal: cart.total,
                      ppnPercent: _ppnPercent,
                      servicePercent: _servicePercent,
                      serviceApplies: _isDineIn,
                      currency: currency,
                    ),
                    if (cart.discountFor(_orderType) case final applied?) ...[
                      const SizedBox(height: 8),
                      _DiscountLine(
                        name: applied.discount.name,
                        amount: applied.amount,
                        payable: cart.payableFor(_orderType),
                        currency: currency,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.cash),
                            child: const Text('Tunai'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.qris),
                            child: const Text('QRIS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.transfer),
                            child: const Text('Transfer'),
                          ),
                        ),
                      ],
                    ),
                    if (!_canPay) ...[
                      const SizedBox(height: 8),
                      Text(
                        _isDineIn
                            ? 'Isi nomor meja dulu sebelum bisa checkout.'
                            : 'Isi nama customer dulu sebelum bisa checkout.',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Memeriksa ulang ketersediaan sebelum uang diterima.
  ///
  /// Sumbernya daftar produk yang sudah disinkronkan layar kasir, bukan
  /// panggilan jaringan baru: kasir sering bekerja dengan koneksi
  /// seadanya, dan menahan pembayaran sambil menunggu jawaban server
  /// adalah antrean yang berhenti.
  Future<bool> _pastikanMasihAda(BuildContext context, CartProvider cart) async {
    final terbaru = context.read<ProductProvider>().products;
    if (terbaru.isEmpty) return true;

    final habis = <String>{
      for (final p in terbaru)
        if (p.outOfStock) p.id,
    };
    final kena = <String>{
      for (final item in cart.items)
        if (habis.contains(item.product.id)) item.product.id,
    };

    setState(() => _soldOut = kena);
    if (kena.isEmpty) return true;

    final nama = <String>{
      for (final item in cart.items)
        if (kena.contains(item.product.id)) item.product.name,
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.remove_shopping_cart_outlined,
            size: 38, color: Colors.red),
        title: const Text('Ada menu yang sudah habis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final n in nama)
              Text('• $n', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              'Hapus dulu dari keranjang sebelum menerima pembayaran.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kembali ke Keranjang'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _handlePayment(BuildContext context, CartProvider cart, PaymentMethod method) async {
    if (!_canPay) return;
    if (!await _pastikanMasihAda(context, cart)) return;
    if (!context.mounted) return;
    final tableNumber = _isDineIn ? _tableNumber : null;

    // Yang ditagih adalah total tagihannya, bukan subtotal menunya.
    //
    // `cart.total` berhenti di harga menu (dasar + PPN) dan tidak
    // memuat biaya service. Pada Take Away keduanya kebetulan sama
    // persis — dan justru itu yang membuat selisihnya lolos begitu
    // lama: hanya Dine In yang salah, dan salahnya selalu kurang.
    // QR yang menagih kurang berarti lacinya kurang tiap hari, dan
    // baru ketahuan saat tutup buku.
    // Sesudah potongan: inilah yang ditagihkan, dicetak di QR, dan
    // dihitung kembaliannya.
    final amount = cart.payableFor(_orderType);

    // Cash: the cashier keys in what the customer handed over so the
    // change is worked out here instead of in their head — and so the
    // receipt can print both figures.
    int? cashReceived;
    if (method == PaymentMethod.cash) {
      cashReceived = await showDialog<int>(
        context: context,
        builder: (_) => CashPaymentDialog(total: amount),
      );
      if (cashReceived == null || !context.mounted) return;
    }

    // QRIS/Transfer show a dummy "simulate payment" screen first, and
    // only proceed if the cashier confirms it went through.
    if (method != PaymentMethod.cash) {
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => method == PaymentMethod.qris
              ? PaymentQrisScreen(amount: amount)
              : PaymentTransferScreen(amount: amount),
        ),
      );
      if (confirmed != true) return;
    }

    if (!context.mounted) return;

    final auth = context.read<AuthProvider>();
    final tx = await cart.checkout(
      method,
      cashierLabel: auth.user?.email,
      cashierName:
          auth.employeeName?.isNotEmpty == true ? auth.employeeName : (auth.roleLabel ?? 'Kasir'),
      tableNumber: tableNumber,
      restoId: auth.restoId!,
      orderType: _orderType,
      customerName: _customerName.isEmpty ? null : _customerName,
      cashReceived: cashReceived,
    );

    // Refresh product list so updated stock is reflected everywhere
    // (grid on the home screen, product management list, etc.)
    if (context.mounted) {
      await context.read<ProductProvider>().load();
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(transaction: tx)),
    );
  }
}

/// Asks how much cash the customer handed over and shows the change back
/// live as it's typed.
///
/// Quick-pick chips cover what a cashier reaches for most — exact money,
/// then the next round notes up from the total — because typing the full
/// amount on every sale is the slowest part of taking cash.

/// Baris potongan di bawah rincian tagihan.
///
/// Ditampilkan sebagai baris tersendiri berikut nama promonya, bukan
/// dengan diam-diam mengecilkan totalnya. Kasir harus bisa menjawab
/// "kenapa jadi segini" tanpa membuka menu lain — dan pelanggan yang
/// bertanya sedang berdiri di depannya.
class _DiscountLine extends StatelessWidget {
  final String name;
  final int amount;
  final int payable;
  final NumberFormat currency;

  const _DiscountLine({
    required this.name,
    required this.amount,
    required this.payable,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined,
                  size: 16, color: Color(0xFF15803D)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D)),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('− ${currency.format(amount)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D))),
            ],
          ),
          const Divider(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DIBAYAR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(currency.format(payable),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
        ],
      ),
    );
  }
}
