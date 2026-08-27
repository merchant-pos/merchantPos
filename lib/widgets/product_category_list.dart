import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/product_review.dart';
import '../theme.dart';
import 'product_grid_card.dart';

/// Groups products by category into collapsible sections — used by
/// Kasir/Admin and Customer's ordering screens alike so both share the
/// exact same grouping/expand behavior and card look.
///
/// Cards are portrait-shaped so the photo gets real room, and the column
/// count follows the available width rather than being pinned at 2 — on a
/// tablet (a likely Kasir setup) two stretched columns looked wrong.
class ProductCategoryList extends StatefulWidget {
  final List<Product> products;
  final int Function(String productId) quantityOf;
  final void Function(Product product) onTapProduct;
  final double ppnPercent;

  /// Diteruskan ke kartunya — mati untuk layar pelanggan.
  final bool showStock;

  /// Ditempel di atas daftar, di dalam gulirannya.
  ///
  /// Dipakai layar pelanggan untuk banner promo. Ditaruh di luar
  /// daftar, bannernya diam di tempat dan memakan sepertiga layar
  /// selamanya — yang ingin melihat menu harus menggulir di sisa ruang
  /// yang tinggal sedikit, dan promonya berubah dari tawaran jadi
  /// halangan.
  final Widget? header;

  /// Menu yang sedang kena promo hari ini. Kosong berarti tidak ada —
  /// atau promonya belum sempat dimuat, dan keduanya sama-sama benar
  /// ditampilkan sebagai tanpa label.
  final Set<String> diskonProductIds;

  /// Bintang dan angka terjual per menu, dari satu panggilan untuk
  /// seluruh katalog.
  final Map<String, ProductStats> stats;

  const ProductCategoryList({
    super.key,
    required this.products,
    required this.quantityOf,
    required this.onTapProduct,
    this.ppnPercent = 0,
    this.showStock = false,
    this.header,
    this.diskonProductIds = const {},
    this.stats = const {},
  });

  @override
  State<ProductCategoryList> createState() => _ProductCategoryListState();
}

class _ProductCategoryListState extends State<ProductCategoryList> {
  /// Kategori yang sedang dilipat orangnya.
  ///
  /// Disimpan di sini, bukan diserahkan ke ExpansionTile lewat
  /// PageStorageKey.
  ///
  /// Kunci itu dipakai bersama oleh dua penghuni yang tidak saling
  /// tahu: ExpansionTile menyimpan keadaan buka/tutup sebagai bool, dan
  /// GridView di dalamnya menyimpan posisi gulir sebagai double — di
  /// ember penyimpanan yang sama. Begitu kategorinya dibuka lagi, grid
  /// membaca bool itu sebagai double, melempar "type 'bool' is not a
  /// subtype of type 'double?'", dan menyisakan blok kosong di tempat
  /// menunya.
  ///
  /// Disimpan di sini, keadaannya juga selamat dari daur ulang
  /// ListView — yang justru jadi alasan kunci itu dipasang.
  final Set<String> _terlipat = <String>{};

  final _cari = TextEditingController();

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  /// Menu yang cocok dengan pencarian.
  ///
  /// Namanya saja yang dicari, bukan keterangannya: yang mengetik "nasi"
  /// mencari menu bernama nasi, bukan menu yang keterangannya kebetulan
  /// menyebut nasi sebagai pelengkap.
  List<Product> get _cocok {
    final q = _cari.text.trim().toLowerCase();
    if (q.isEmpty) return widget.products;
    return [
      for (final p in widget.products)
        if (p.name.toLowerCase().contains(q)) p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cocok = _cocok;
    final mencari = _cari.text.trim().isNotEmpty;

    final byCategory = <String, List<Product>>{};
    for (final p in cocok) {
      byCategory.putIfAbsent(p.category, () => []).add(p);
    }
    final categoryNames = byCategory.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        // ~170px per card keeps the photo legible; clamped so a phone
        // always gets 2 and a wide tablet never goes past 5.
        final columns = (constraints.maxWidth / 190).floor().clamp(2, 5);

        // Kolom cari selalu ada, bahkan saat menunya sedikit — yang
        // mencarinya tidak tahu menunya sedikit sampai dia sudah
        // menggulir seluruhnya.
        final kolomCari = Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _cari,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cari menu',
                prefixIcon: const Icon(Icons.search, size: 19),
                suffixIcon: _cari.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 17),
                        tooltip: 'Hapus pencarian',
                        onPressed: () => setState(() => _cari.clear()),
                      ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        );

        // Header (banner promo) tetap di atas kolom cari — ia bagian
        // dari halamannya, bukan bagian dari daftarnya.
        final atas = <Widget>[
          if (widget.header != null) widget.header!,
          kolomCari,
          if (mencari && categoryNames.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Tidak ada menu bernama "${_cari.text.trim()}"',
                  style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                ),
              ),
            ),
        ];

        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          itemCount: categoryNames.length + atas.length,
          itemBuilder: (context, index) {
            if (index < atas.length) return atas[index];
            index -= atas.length;
            final category = categoryNames[index];
            final items = byCategory[category]!;

            return Theme(
              // Removes the default divider lines ExpansionTile draws
              // above/below.
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                // Kuncinya wajib. ListView.builder membuang widget yang
                // tergulir keluar layar lalu membangunnya lagi saat
                // kembali terlihat — dan tanpa kunci, ExpansionTile
                // kehilangan ingatannya, memakai `initiallyExpanded`
                // lagi, lalu memainkan animasi bukanya dari awal. Yang
                // terlihat: menu berkedip tiap kali digulir, dan
                // kategori yang barusan dilipat membuka sendiri.
                key: ValueKey<String>(category),
                // Terbuka sejak awal. Menu yang bersembunyi di balik
                // judul kategori adalah menu yang tidak ditemukan —
                // kasir yang sedang melayani antrean tidak membuka satu
                // per satu kategori untuk mencari satu item, dan
                // pelanggan yang membuka halaman berisi tiga baris judul
                // akan mengira restonya belum mengisi menunya.
                //
                // Melipatnya tetap bisa, dan itu yang berguna: yang
                // sudah tahu isinya bisa merapikan layar sendiri.
                // Saat mencari, semuanya dibuka: hasil pencarian yang
                // bersembunyi di balik kategori terlipat sama saja
                // dengan tidak ada hasil.
                initiallyExpanded: mencari || !_terlipat.contains(category),
                onExpansionChanged: (buka) => setState(() {
                  if (buka) {
                    _terlipat.remove(category);
                  } else {
                    _terlipat.add(category);
                  }
                }),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: MerchantPosTheme.brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: MerchantPosTheme.brandDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: MerchantPosTheme.brand.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${items.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: MerchantPosTheme.brand,
                        ),
                      ),
                    ),
                  ],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      // Portrait: photo on top, name/price beneath. Wider
                      // than this and the photo flattens into a strip.
                      // Sedikit lebih jangkung sejak kartunya membawa
                      // baris bintang dan angka terjual. Tanpa itu,
                      // baris barunya diambil dari tinggi fotonya.
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final product = items[i];
                      return ProductGridCard(
                        product: product,
                        quantityInCart: widget.quantityOf(product.id),
                        ppnPercent: widget.ppnPercent,
                        showStock: widget.showStock,
                        sedangDiskon:
                            widget.diskonProductIds.contains(product.id),
                        stats: widget.stats[product.id],
                        onTap: () => widget.onTapProduct(product),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
