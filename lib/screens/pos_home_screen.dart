import '../widgets/side_cart_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/responsive.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/level_group_provider.dart';
import '../providers/product_provider.dart';
import '../utils/menu_meta.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/product_category_list.dart';
import '../widgets/product_lines_sheet.dart';
import '../widgets/quantity_dialog.dart';
import 'checkout_screen.dart';

/// The actual ordering screen: tap products to add to cart, then go to
/// checkout. Reached via a menu tile on [AdminHomeScreen] or
/// [KasirHomeScreen] — both hub screens are where Riwayat Transaksi,
/// other menus, and Logout live instead, keeping this screen's app bar
/// uncluttered. The back button returns to whichever hub opened it.
class PosHomeScreen extends StatefulWidget {
  const PosHomeScreen({super.key});

  @override
  State<PosHomeScreen> createState() => _PosHomeScreenState();
}

class _PosHomeScreenState extends State<PosHomeScreen> {
  /// Label promo, bintang, dan angka terjual.
  ///
  /// Kasir melihat yang sama persis dengan pelanggan. Itu disengaja:
  /// yang ditanya "yang enak apa ya?" di depan meja kasir adalah kasir,
  /// dan menjawabnya dari layar yang berbeda dengan layar pelanggan
  /// berarti dua jawaban yang tidak sama.
  MenuMeta _meta = MenuMeta.kosong;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;
      await context.read<ProductProvider>().syncWithResto(restoId);
      // Kelompok level disusun tiap resto sendiri.
      if (restoId != null) await primeLevelGroups(restoId);
      await _loadRates(restoId);
      if (restoId != null) {
        final meta = await muatMenuMeta(restoId);
        if (mounted) setState(() => _meta = meta);
      }
    });
  }

  /// Menu prices are shown inclusive of the resto's PPN, so the cart has
  /// to know the rates before it can price anything.
  Future<void> _loadRates(String? restoId) async {
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted || resto == null) return;
      context.read<CartProvider>().setRates(ppn: resto.ppnPercent, service: resto.servicePercent);
    } catch (_) {
      // Offline — prices fall back to the stored originals.
    }
  }

  /// Nama menu, untuk menyebut isi paket bundling di keterangan promo.
  ///
  /// Dibaca dari katalog yang sudah ada di layar ini, bukan diambil
  /// lagi dari server: promo bundling menyebut menu lain milik resto
  /// yang sama, dan daftarnya sudah ada di tangan.
  Map<String, String> _namaMenu(BuildContext context) => {
        for (final p in context.read<ProductProvider>().products) p.id: p.name,
      };

  /// Menu yang belum ada di keranjang langsung membuka popup jumlah.
  /// Yang sudah ada membuka daftar barisnya, supaya jumlahnya bisa
  /// dikurangi atau dihapus tanpa harus maju dulu ke keranjang — di
  /// depan menu inilah orang berubah pikiran.
  Future<void> _onTapProduct(BuildContext context, Product product) async {
    final cart = context.read<CartProvider>();
    if (cart.linesOf(product.id).isEmpty) {
      await _addLine(context, product);
      return;
    }
    await _openLinesSheet(context, product);
  }

  Future<void> _addLine(BuildContext context, Product product) async {
    final cart = context.read<CartProvider>();
    final result = await showDialogBesideCart<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: product,
        ppnPercent: cart.ppnPercent,
        showStock: true,
        stats: _meta.stats[product.id],
        sedangDiskon: _meta.diskonProductIds.contains(product.id),
        diskon: _meta.diskonUntuk(product.id),
        namaMenu: _namaMenu(context),
      ),
    );
    if (result == null) return;
    cart.addLine(
      product,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      selectedToppings: result.selectedToppings,
      notes: result.notes,
    );
  }

  Future<void> _editLine(BuildContext context, CartItem line) async {
    final cart = context.read<CartProvider>();
    final result = await showDialogBesideCart<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        showStock: true,
        product: line.product,
        initialQuantity: line.quantity,
        initialLevels: line.selectedLevels,
        initialToppings: line.selectedToppings,
        initialNotes: line.notes,
        ppnPercent: cart.ppnPercent,
        editing: true,
        stats: _meta.stats[line.product.id],
        sedangDiskon: _meta.diskonProductIds.contains(line.product.id),
        diskon: _meta.diskonUntuk(line.product.id),
        namaMenu: _namaMenu(context),
      ),
    );
    if (result == null) return;
    cart.updateLine(
      line.lineId,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      selectedToppings: result.selectedToppings,
      notes: result.notes,
    );
  }

  Future<void> _openLinesSheet(BuildContext context, Product product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Consumer<CartProvider>(
        builder: (_, cart, __) {
          final lines = cart.linesOf(product.id);
          // Baris terakhir dihapus berarti tidak ada lagi yang bisa
          // diatur — menutup sendiri lebih baik daripada menyisakan
          // panel kosong yang harus ditutup manual.
          if (lines.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(sheetContext).canPop()) Navigator.of(sheetContext).pop();
            });
            return const SizedBox.shrink();
          }
          return ProductLinesSheet(
            product: product,
            lines: lines,
            unitPriceOf: (l) => cart.menuSubtotalOf(l) ~/ l.quantity,
            lineTotalOf: cart.menuSubtotalOf,
            onIncrement: cart.incrementLine,
            onDecrement: cart.decrementLine,
            onDelete: cart.removeLine,
            onEdit: (line) => _editLine(sheetContext, line),
            onAddVariant: () {
              Navigator.pop(sheetContext);
              _addLine(context, product);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final employeeName = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Kasir';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${auth.roleLabel ?? 'Kasir'} • ${auth.user?.email ?? ''}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Consumer2<ProductProvider, CartProvider>(
        builder: (context, provider, cart, _) {
          final products = provider.products;
          if (products.isEmpty) {
            return const Center(
              child: Text('Belum ada produk.\nTambah dulu lewat menu Kelola Produk.',
                  textAlign: TextAlign.center),
            );
          }

          final grid = ProductCategoryList(
            showStock: true,
            products: products,
            quantityOf: cart.quantityOf,
            ppnPercent: cart.ppnPercent,
            diskonProductIds: _meta.diskonProductIds,
            stats: _meta.stats,
            onTapProduct: (p) => _onTapProduct(context, p),
          );

          // Di monitor kasir, keranjang jadi panel tetap di kanan. Bar
          // bawah memaksa kasir membuka layar terpisah untuk memeriksa
          // pesanan yang sedang dibacakan pelanggan — padahal ruangnya
          // ada. Di HP tata letaknya tidak berubah sama sekali.
          if (!Breakpoints.isWide(context)) return grid;

          return Row(
            children: [
              Expanded(child: grid),
              const VerticalDivider(width: 1),
              SizedBox(
                width: kSideCartWidth,
                child: _CartPanel(
                  onEditLine: (line) => _editLine(context, line),
                  onCheckout: cart.items.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                          ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Breakpoints.isWide(context)
          ? null
          : Consumer<CartProvider>(
              builder: (context, cart, _) {
                return CartBottomBar(
                  itemCount: cart.itemCount,
                  total: cart.total,
                  actionLabel: 'Bayar',
                  actionIcon: Icons.point_of_sale_outlined,
                  onPressed: cart.items.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                          ),
                );
              },
            ),
    );
  }
}

/// Keranjang sebagai panel tetap, untuk layar kasir yang lebar.
///
/// Isinya sama dengan layar keranjang biasa — baris yang bisa diubah dan
/// dihapus, ringkasan, tombol bayar — hanya saja selalu terlihat, jadi
/// kasir bisa mencocokkan pesanan sambil pelanggan masih membacakannya.
class _CartPanel extends StatelessWidget {
  final void Function(CartItem line) onEditLine;
  final VoidCallback? onCheckout;

  const _CartPanel({required this.onEditLine, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              color: MerchantPosTheme.backgroundOf(context),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 18, color: MerchantPosTheme.brandDark),
                  const SizedBox(width: 8),
                  const Text('Keranjang',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  if (cart.items.isNotEmpty)
                    TextButton(
                      onPressed: cart.clear,
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Kosongkan'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: cart.items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Belum ada item.\nPilih menu di sebelah kiri.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: cart.items.length,
                      itemBuilder: (context, index) {
                        final item = cart.items[index];
                        return CartLineTile(
                          item: item,
                          unitPrice: cart.menuSubtotalOf(item) ~/ item.quantity,
                          lineTotal: cart.menuSubtotalOf(item),
                          currency: currency,
                          onIncrement: () => cart.incrementLine(item.lineId),
                          onDecrement: () => cart.decrementLine(item.lineId),
                          onDelete: () => cart.removeLine(item.lineId),
                          onEdit: () => onEditLine(item),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${cart.itemCount} item', style: TextStyle(color: MerchantPosTheme.mutedOf(context))),
                      Text(
                        currency.format(cart.total),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.point_of_sale_outlined),
                      label: const Text('Bayar'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: onCheckout,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
