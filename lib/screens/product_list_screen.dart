import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/level_group_provider.dart';
import '../providers/product_provider.dart';
import 'category_management_screen.dart';
import 'level_management_screen.dart';
import 'product_form_screen.dart';
import '../models/product_badge.dart';
import '../utils/menu_meta.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/product_badge_chips.dart';
import '../widgets/responsive.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;

      final categories = context.read<CategoryProvider>();
      categories.restoId = restoId;
      await categories.load();
      await categories.pullNewFromSupabase();
      await categories.syncAllToSupabase();

      if (!mounted) return;
      // Products used to be synced only by the cashier screen. Now that
      // Kelola Produk is its own menu entry on the Admin hub, it can be
      // opened without ever going there — which left this list showing
      // whatever happened to be in the local database, i.e. nothing at
      // all on a freshly installed device.
      await context.read<ProductProvider>().syncWithResto(restoId);
      if (!mounted || restoId == null) return;
      await context.read<LevelGroupProvider>().load(restoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Di web, Kategori dan Level punya menunya sendiri di sidebar.
    //
    // Membiarkan tabnya tetap di sini berarti satu hal yang sama bisa
    // dicapai lewat dua jalan yang tampak berbeda — dan yang satu
    // bersarang di dalam menu yang namanya "Kelola Produk", tempat
    // orang tidak akan mencarinya karena sidebarnya sudah menyebut
    // keduanya di luar.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kelola Produk')),
        body: const _ProductTab(),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kelola Produk'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Produk'),
              Tab(text: 'Kategori'),
              Tab(text: 'Level'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProductTab(),
            CategoryManagementScreen(),
            LevelManagementScreen(),
          ],
        ),
      ),
    );
  }
}

class _ProductTab extends StatefulWidget {
  const _ProductTab();

  @override
  State<_ProductTab> createState() => _ProductTabState();
}

class _ProductTabState extends State<_ProductTab> {
  /// Bintang dan angka terjual tiap menu.
  ///
  /// Merchant melihat angka yang sama dengan yang dilihat pelanggannya.
  /// Angka penjualan yang hanya ada di laporan tidak pernah dibaca saat
  /// orangnya sedang memutuskan menu mana yang mau diganti.
  MenuMeta _meta = MenuMeta.kosong;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;
      if (restoId == null) return;
      final meta = await muatMenuMeta(restoId);
      if (mounted) setState(() => _meta = meta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      body: Consumer<ProductProvider>(
        builder: (context, provider, _) {
          final products = provider.products;
          if (products.isEmpty) {
            return const Center(child: Text('Belum ada produk. Tambah dulu yuk.'));
          }
          // Kartu, sama seperti Level. Lihat catatan di
          // category_management_screen.dart.
          return ResponsiveCenter(
            child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, kFabSafeBottom),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              final stats = _meta.stats[p.id];
              final badges = [
                ...badgeDariKodeList(p.badges),
                if (_meta.diskonProductIds.contains(p.id))
                  ProductBadge.diskon,
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                isThreeLine: badges.isNotEmpty || stats != null,
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.outOfStock ? MerchantPosTheme.mutedOf(context) : null,
                        ),
                      ),
                    ),
                    if (p.outOfStock) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: MerchantPosTheme.tintOf(context, Colors.red),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('HABIS',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: MerchantPosTheme.onTintOf(context, Colors.red))),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.category}'
                      '${p.stock > 0 ? ' • Stok: ${p.stock}' : ''}'
                      ' • ${currency.format(p.price)}',
                    ),
                    if (badges.isNotEmpty || stats != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            for (final b in urutkanBadge(badges))
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: kBadgeWarna[b],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    kBadgeLabel[b]!,
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            Flexible(child: ProductStatsLine(stats: stats)),
                          ],
                        ),
                      ),
                  ],
                ),
                // Ditandai habis dari daftar ini, tanpa membuka
                // formulirnya. Yang menandai biasanya sedang berdiri di
                // dapur sambil melayani, dan formulir produk berisi
                // belasan kolom yang tidak ada hubungannya dengan
                // "ayamnya habis".
                trailing: Switch(
                  value: !p.outOfStock,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (tersedia) =>
                      provider.setOutOfStock(p, !tersedia),
                ),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProductFormScreen(existing: p),
                  ));
                },
                onLongPress: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Hapus produk?'),
                      content: Text('Hapus "${p.name}"?'),
                      actions: [
                        DialogActions(
                          confirmLabel: 'Hapus',
                          destructive: true,
                          onConfirm: () => Navigator.pop(context, true),
                        ),
                      ],
                      actionsAlignment: MainAxisAlignment.center,
                    ),
                  );
                  if (confirm == true) {
                    await provider.deleteProduct(p.id);
                  }
                },
              ),
              );
            },
          ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ProductFormScreen(),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
