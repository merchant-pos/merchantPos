import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/customer_profile_repository.dart';
import '../db/restaurant_repository.dart';
import '../db/discount_repository.dart';
import '../db/voucher_repository.dart';
import '../db/firestore_product_repository.dart';
import '../models/product.dart';
import '../models/restaurant.dart';
import '../db/guest_order_store.dart';
import '../models/order_type.dart';
import '../models/voucher.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/table_session_provider.dart';
import 'customer_cash_pending_screen.dart';
import 'customer_qris_screen.dart';
import '../widgets/charge_summary.dart';
import '../widgets/quantity_dialog.dart';
import '../widgets/cart_line_tile.dart';
import '../models/cart_item.dart';
import '../utils/field_rules.dart';
import '../widgets/required_label.dart';
import '../widgets/app_toast.dart';

/// Checkout screen. Lets the customer pick Dine In or Take Away first —
/// for Take Away no table is needed at all, so the table-number field is
/// hidden entirely, but a customer name IS required (there's no table
/// to deliver it to, so the name is what gets called out when it's
/// ready) — pre-filled from their profile if logged in, but editable.
/// For Dine In: if the session came from scanning a table QR code, the
/// table number is already known — shown here read-only/greyed out. If
/// it came from picking a restaurant off the list instead (no QR),
/// there's no table number yet, so this screen makes it a mandatory
/// field before "Pesan & Bayar" can be pressed.
class CustomerCartScreen extends StatefulWidget {
  /// Ditanam sebagai panel di samping daftar menu, bukan halaman
  /// sendiri.
  ///
  /// Yang berubah hanya bungkusnya — tanpa Scaffold dan tanpa AppBar.
  /// Isinya tetap yang ini juga: jenis pesanan, nomor meja, voucher,
  /// rincian tagihan, dan tombol bayarnya. Menyalinnya jadi panel
  /// terpisah berarti dua tempat yang harus diingat berbarengan tiap
  /// kali aturan pembayarannya berubah, dan yang kedua selalu
  /// ketinggalan.
  final bool embedded;

  const CustomerCartScreen({super.key, this.embedded = false});

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tableCtrl;
  final _nameCtrl = TextEditingController();
  OrderType _orderType = OrderType.dineIn;

  /// Cara bayar yang dipilih, memakai kunci yang sama dengan
  /// `gl_accounts` — 'qris' atau 'cash'.
  ///
  /// QRIS tetap yang terpilih di awal: itu yang menyelesaikan pesanan
  /// tanpa siapa pun harus beranjak, dan justru itulah gunanya memesan
  /// dari HP sendiri.
  String _paymentMethod = 'qris';

  bool get _payAtCashier => _paymentMethod == 'cash';

  bool _placing = false;

  /// Voucher milik pelanggan yang sedang dipasang di tagihan ini.
  VoucherClaim? _voucher;

  /// Voucher hanya untuk yang sudah masuk dengan akunnya.
  ///
  /// Penebusannya pun menuntut akun — server menolak tanpa email — jadi
  /// tamu tidak akan pernah punya satu pun untuk dipakai.
  bool get _bisaPakaiVoucher {
    final auth = context.read<AuthProvider>();
    return auth.isLoggedIn && !auth.isEmployee;
  }
  bool _memeriksaVoucher = false;

  /// Yang benar-benar dibayar: sesudah diskon resto, lalu sesudah
  /// voucher Merchant-POS.
  ///
  /// Satu tempat, dipakai layar bayar maupun ringkasannya. Dua
  /// perhitungan terpisah akan berpisah, dan yang terlihat adalah
  /// nominal QRIS yang berbeda dari angka yang baru saja dibaca
  /// pelanggan.
  int _dibayar(CustomerCartProvider cart) {
    final sesudahDiskon = cart.payableFor(_orderType);
    final potong = _voucher?.amount ?? 0;
    return potong >= sesudahDiskon ? 0 : sesudahDiskon - potong;
  }

  /// Memilih dari voucher yang sudah ditebus pelanggan.
  ///
  /// Tidak ada pengetikan kode di sini: kodenya ditebus lebih dulu di
  /// halaman Voucher Saya, dan yang tersisa di layar bayar cuma memilih
  /// mana yang dipakai. Mengetik kode saat sudah berdiri di kasir adalah
  /// tempat paling buruk untuk mengetahui kodenya salah.
  Future<void> _pilihVoucher() async {
    final session = context.read<TableSessionProvider>();
    final cart = context.read<CustomerCartProvider>();
    final restoId = session.restoId;
    if (restoId == null) return;

    setState(() => _memeriksaVoucher = true);
    List<VoucherClaim> punya;
    try {
      punya = await VoucherRepository()
          .usableAt(restoId, cart.payableFor(_orderType));
    } catch (e) {
      if (!mounted) return;
      setState(() => _memeriksaVoucher = false);
      AppToast.show(context, 'Gagal memuat voucher: $e', isError: true);
      return;
    }
    if (!mounted) return;
    setState(() => _memeriksaVoucher = false);

    if (punya.isEmpty) {
      AppToast.show(context,
          'Belum ada voucher yang bisa dipakai untuk pesanan ini.');
      return;
    }

    final rupiah = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final pilih = await showModalBottomSheet<VoucherClaim>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Voucher Saya',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final v in punya)
                    ListTile(
                      leading: const Icon(Icons.confirmation_number_outlined),
                      title: Text(v.name ?? v.code ?? 'Voucher'),
                      subtitle: Text(rupiah.format(v.amount)),
                      onTap: () => Navigator.pop(context, v),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pilih != null) setState(() => _voucher = pilih);
  }

  void _lepasVoucher() => setState(() => _voucher = null);
  Restaurant? _resto;

  /// Produk di keranjang yang ternyata sudah habis, ketahuan saat
  /// hendak membayar.
  ///
  /// Keranjang bisa terisi berjam-jam sebelum dibayar — pelanggan
  /// memilih sambil menunggu teman datang, lalu dapur kehabisan bahan di
  /// sela itu. Memeriksanya hanya saat produk dimasukkan berarti pesanan
  /// yang tidak bisa dimasak tetap dibayar, dan yang menyampaikan
  /// kabarnya adalah pramusaji, setelah uangnya diterima.
  Set<String> _soldOut = {};

  /// Cara makan yang dilayani resto ini; keduanya sampai datanya
  /// termuat.
  List<OrderType> get _orderTypes =>
      _resto?.orderTypes ?? const [OrderType.dineIn, OrderType.takeAway];

  double get _ppnPercent => _resto?.ppnPercent ?? 0;
  double get _servicePercent => _resto?.servicePercent ?? 0;

  /// Diskon yang berlaku hari ini di resto yang sedang dibuka.
  ///
  /// Dimuat di layar keranjang, bukan di layar menu: potongannya
  /// dihitung dari total tagihan, dan tagihannya baru ada di sini.
  Future<void> _loadDiscounts() async {
    final restoId = context.read<TableSessionProvider>().restoId;
    if (restoId == null) return;
    try {
      final live = await DiscountRepository().liveForResto(restoId);
      if (!mounted) return;
      context.read<CustomerCartProvider>().setDiscounts(live);
    } catch (_) {
      // Luring, atau tabelnya belum dimigrasi. Tanpa diskon, harganya
      // kembali ke harga daftar — bukan pesanan yang gagal.
    }
  }

  Future<void> _loadResto() async {
    final restoId = context.read<TableSessionProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted) return;
      setState(() {
        _resto = resto;
        // Pindahkan sekarang kalau resto ini tidak melayani cara makan
        // yang sedang terpilih — pelanggan tidak boleh sampai ke
        // pembayaran untuk sesuatu yang akan ditolak di tempat.
        if (resto != null && !resto.orderTypes.contains(_orderType)) {
          _orderType = resto.orderTypes.first;
        }
      });
      context.read<CustomerCartProvider>().setRates(
            ppn: resto?.ppnPercent ?? 0,
            service: resto?.servicePercent ?? 0,
          );
    } catch (_) {
      // Offline — fall back to no charges rather than guessing a rate.
    }
  }

  @override
  void initState() {
    super.initState();
    final known = context.read<TableSessionProvider>().tableNumber;
    _tableCtrl = TextEditingController(text: known ?? '');
    _prefillNameFromProfile();
    _loadResto();
    _loadDiscounts();
  }

  /// If logged in, use their saved profile name as a starting point —
  /// still freely editable (e.g. ordering for someone else).
  Future<void> _prefillNameFromProfile() async {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null) return;
    final profile = await CustomerProfileRepository().getOnce(email);
    if (!mounted || profile == null || profile.name.isEmpty) return;
    if (_nameCtrl.text.isEmpty) {
      setState(() => _nameCtrl.text = profile.name);
    }
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Memeriksa ulang ketersediaan tepat sebelum membayar.
  ///
  /// Mengembalikan true kalau semuanya masih bisa dipesan. Kalau
  /// pemeriksaannya sendiri gagal — jaringan mati — pesanannya
  /// diteruskan: menahan pesanan yang mungkin baik-baik saja gara-gara
  /// sinyal jelek merugikan lebih banyak orang daripada satu porsi yang
  /// harus dibatalkan di kasir.
  Future<bool> _pastikanMasihAda(CustomerCartProvider cart) async {
    final restoId = context.read<TableSessionProvider>().restoId;
    if (restoId == null) return true;

    final List<Product> terbaru;
    try {
      terbaru = await FirestoreProductRepository().getAllOnce(restoId);
    } catch (_) {
      return true;
    }
    if (!mounted) return false;

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
            Text(
              nama.length == 1
                  ? '${nama.first} baru saja ditandai habis oleh merchant.'
                  : 'Menu berikut baru saja ditandai habis oleh merchant:',
              textAlign: TextAlign.center,
            ),
            if (nama.length > 1) ...[
              const SizedBox(height: 8),
              for (final n in nama)
                Text('• $n',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 10),
            Text(
              'Hapus dulu dari keranjang untuk melanjutkan pembayaran.',
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

  Future<void> _checkout() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await _pastikanMasihAda(context.read<CustomerCartProvider>())) return;
    if (!mounted) return;

    final session = context.read<TableSessionProvider>();
    final cart = context.read<CustomerCartProvider>();
    final auth = context.read<AuthProvider>();
    final isDineIn = _orderType == OrderType.dineIn;

    String? tableNumber;
    if (isDineIn) {
      // Table came in via QR scan already — nothing new to save.
      // Otherwise this is the first time it's known, so persist it.
      tableNumber = session.tableNumber ?? _tableCtrl.text.trim();
      if (session.tableNumber == null) {
        await session.setTableNumber(tableNumber);
      }
    }

    setState(() => _placing = true);
    final label = auth.user?.email ?? 'Tamu';
    // Total yang benar-benar ditagihkan, bukan subtotal menunya.
    //
    // `cart.total` adalah jumlah harga menu — harga bersih + PPN, tanpa
    // biaya service. Angka itu benar untuk daftar belanja, tapi salah
    // untuk dibayar: pesanan Dine In menyimpan total yang sudah termasuk
    // service, dan pelanggan akan melihat nominal yang lebih kecil
    // daripada yang ditagih QR-nya. Pada Take Away keduanya kebetulan
    // sama persis, dan justru itu yang membuat selisihnya lolos begitu
    // lama.
    // Sesudah potongan: inilah yang ditagihkan di layar QRIS dan yang
    // disebutkan ke kasir untuk pembayaran tunai.
    final amount = _dibayar(cart);
    final orderId = await cart.placeOrder(
      label,
      tableNumber: tableNumber,
      sessionId: session.sessionId!,
      restoId: session.restoId!,
      orderType: _orderType,
      // Dipakai juga untuk Dine In sekarang: nomor meja memberi tahu
      // dapur ke mana mengantar, tapi tidak memberi tahu siapa yang
      // dipanggil kalau mejanya berisi beberapa orang yang memesan
      // sendiri-sendiri.
      customerName: _nameCtrl.text.trim(),
      paymentMethod: _paymentMethod,
      voucherClaimId: _voucher?.id,
      voucherCode: _voucher?.code,
      voucherAmount: _voucher?.amount ?? 0,
    );
    // A logged-in customer's history comes from their email, so this is
    // only needed for guests — it's the only record they'd otherwise have.
    if (auth.user?.email == null) {
      await GuestOrderStore().add(orderId);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _payAtCashier
            // Tidak ada layar bayar untuk tunai: yang menerima uangnya
            // kasir, dan pesanannya sudah tercatat lengkap sejak baris
            // di atas. Yang tersisa cuma memberi tahu ke mana harus
            // melangkah.
            ? CustomerCashPendingScreen(orderId: orderId, amount: amount)
            : CustomerQrisScreen(
                orderId: orderId,
                amount: amount,
                restoId: session.restoId!,
              ),
      ),
    );
  }

  /// Reopens the options popup on an existing line, so a wrong spice
  /// level or a mistaken add can be fixed without clearing the cart.
  Future<void> _editLine(BuildContext context, CustomerCartProvider cart, CartItem item) async {
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
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
    final tableKnown = context.watch<TableSessionProvider>().tableNumber != null;
    final isDineIn = _orderType == OrderType.dineIn;

    final isi = Consumer<CustomerCartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong.'));
          }
          return Form(
            key: _formKey,
            // Satu gulungan untuk daftar item dan rinciannya sekaligus,
            // bukan dua bagian yang berebut tinggi lewat Expanded.
            //
            // Dengan Expanded, blok rincian di bawah — jenis pesanan,
            // nomor meja, nama, tagihan, voucher, cara bayar — lebih
            // tinggi daripada layar tablet yang pendek. Daftar itemnya
            // diperas jadi nol dan tombol bayarnya terpotong di tepi
            // bawah, dan tidak ada yang bisa digulir untuk menemukannya.
            child: ListView(
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
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
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
                        // Resto yang cuma melayani satu cara makan tetap
                        // menyebutkannya. Pelanggan yang tidak melihat
                        // pilihan apa pun akan mengira aplikasinya belum
                        // selesai memuat.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            avatar: Icon(
                              isDineIn
                                  ? Icons.restaurant_outlined
                                  : Icons.shopping_bag_outlined,
                              size: 17,
                            ),
                            label: Text(isDineIn
                                ? 'Makan di tempat'
                                : 'Dibungkus (Take Away)'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (isDineIn) ...[
                        TextFormField(
                          controller: _tableCtrl,
                          enabled: !tableKnown,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: tableKnown ? 'Nomor Meja' : null,
                            label: tableKnown ? null : requiredLabel('Nomor Meja'),
                            helperText: tableKnown
                                ? 'Terisi otomatis dari QR yang kamu scan'
                                : 'Nomor meja tempat kamu duduk',
                            // Putih saat bisa diketik, abu-abu hanya saat
                            // memang tidak bisa diubah. Sebelumnya
                            // `filled: false` justru membuat isian yang
                            // aktif menembus ke latar halaman yang
                            // keabu-abuan — terlihat mati, padahal justru
                            // itu satu-satunya yang harus diisi.
                            filled: true,
                            fillColor:
                                tableKnown
                                    ? MerchantPosTheme.softFillOf(context)
                                    : MerchantPosTheme.surfaceOf(context),
                          ),
                          validator: (v) {
                            if (tableKnown) return null;
                            if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: nameFormatters,
                        decoration: InputDecoration(
                          label: requiredLabel('Nama Customer'),
                          helperText: isDineIn
                              ? 'Wajib diisi — supaya pesananmu tidak tertukar dengan teman semeja'
                              : 'Wajib diisi — nama yang akan dipanggil saat pesanan siap',
                        ),
                        validator: (v) => validateName(v, label: 'Nama customer'),
                      ),
                      const SizedBox(height: 16),
                      ChargeSummary(
                        charges: cart.chargesFor(_orderType),
                        menuSubtotal: cart.total,
                        ppnPercent: _ppnPercent,
                        servicePercent: _servicePercent,
                        serviceApplies: isDineIn,
                        currency: currency,
                      ),
                      if (cart.discountFor(_orderType) case final applied?) ...[
                        const SizedBox(height: 8),
                        _DiscountLine(
                          name: applied.discount.name,
                          amount: applied.amount,
                          payable: _dibayar(cart),
                          currency: currency,
                        ),
                      ],
                      // Voucher menempel pada akun, bukan pada
                      // perangkat. Tamu yang belum masuk tidak punya
                      // tempat menyimpannya — menawarkan "Pakai
                      // Voucher" kepadanya cuma menjanjikan daftar yang
                      // selalu kosong, dan yang menekannya akan mengira
                      // vouchernya hilang.
                      if (_bisaPakaiVoucher) ...[
                        const SizedBox(height: 10),
                        _BarisVoucher(
                          voucher: _voucher,
                          memeriksa: _memeriksaVoucher,
                          currency: currency,
                          onPilih: _pilihVoucher,
                          onLepas: _lepasVoucher,
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Cara Bayar',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'qris',
                            label: Text('QRIS'),
                            icon: Icon(Icons.qr_code_2),
                          ),
                          ButtonSegment(
                            value: 'cash',
                            label: Text('Tunai'),
                            icon: Icon(Icons.payments_outlined),
                          ),
                        ],
                        selected: {_paymentMethod},
                        onSelectionChanged: _placing
                            ? null
                            : (v) => setState(() => _paymentMethod = v.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _payAtCashier
                            ? 'Pesanan langsung masuk ke dapur. Pembayaran '
                                'diselesaikan di kasir — statusnya menunggu '
                                'pembayaran sampai kasir menerima uangnya.'
                            : 'Bayar sekarang lewat QRIS, tanpa perlu ke kasir.',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _placing ? null : _checkout,
                          child: _placing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_payAtCashier
                                  ? 'Pesan & Bayar di Kasir'
                                  : 'Pesan & Bayar dengan QRIS'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
    );

    if (widget.embedded) return isi;

    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: isi,
    );
  }
}

/// Baris potongan di bawah rincian tagihan.
///
/// Disebut namanya, bukan diam-diam mengecilkan totalnya. Pelanggan
/// yang melihat angka berkurang tanpa keterangan akan mengira ada yang
/// salah hitung — dan promo yang tidak dikenali namanya tidak pernah
/// diceritakan ke siapa pun.
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
        color: MerchantPosTheme.tintOf(context, Colors.green),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.local_offer_outlined,
                  size: 16, color: MerchantPosTheme.onTintOf(context, Colors.green)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: MerchantPosTheme.onTintOf(context, Colors.green)),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('− ${currency.format(amount)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: MerchantPosTheme.onTintOf(context, Colors.green))),
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

/// Baris pemilih voucher di ringkasan tagihan.
///
/// Ditaruh tepat di atas pilihan cara bayar, bukan di layar terpisah:
/// voucher yang harus dicari di menu lain adalah voucher yang tidak
/// pernah dipakai.
class _BarisVoucher extends StatelessWidget {
  final VoucherClaim? voucher;
  final bool memeriksa;
  final NumberFormat currency;
  final VoidCallback onPilih;
  final VoidCallback onLepas;

  const _BarisVoucher({
    required this.voucher,
    required this.memeriksa,
    required this.currency,
    required this.onPilih,
    required this.onLepas,
  });

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    if (v != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number_outlined,
                size: 17, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.name ?? v.code ?? 'Voucher',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.bold)),
                  Text('\u2212${currency.format(v.amount)}',
                      style: const TextStyle(fontSize: 12, color: Colors.green)),
                ],
              ),
            ),
            TextButton(onPressed: onLepas, child: const Text('Lepas')),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: memeriksa ? null : onPilih,
        icon: memeriksa
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.confirmation_number_outlined, size: 18),
        label: const Text('Pakai Voucher'),
      ),
    );
  }
}
