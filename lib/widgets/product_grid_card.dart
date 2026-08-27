import '../utils/gambar_base64.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../models/product_badge.dart';
import '../models/product_review.dart';
import '../theme.dart';
import '../utils/tax_calculator.dart';
import 'product_badge_chips.dart';

/// One product tile in the ordering grid — used by Kasir/Admin and
/// Customer alike. The photo is the hero: it fills the whole upper half
/// of a portrait-shaped card, with the name/price block sized to its own
/// content underneath so it can never overflow no matter how tall the
/// grid cell ends up.
///
/// Products with no photo get a branded placeholder rather than a blank
/// gap, and sold-out ones are dimmed with an explicit badge instead of
/// only turning one line of text red — which was far too easy to miss.
class ProductGridCard extends StatelessWidget {
  final Product product;
  final int quantityInCart;
  final VoidCallback? onTap;

  /// Resto's PPN rate. Menu prices are shown inclusive of it, so this is
  /// what turns the product's stored original price into the figure the
  /// customer is quoted.
  final double ppnPercent;

  /// Angka sisa stok ditampilkan atau tidak.
  ///
  /// Mati untuk pelanggan. Sisa stok adalah urusan dapur: pelanggan yang
  /// melihat "sisa 2" jadi terburu-buru atau justru mengurungkan
  /// niatnya, dan angka yang ternyata tidak diperbarui membuatnya
  /// merasa dibohongi. Yang perlu dia tahu cuma satu — masih bisa
  /// dipesan atau tidak.
  final bool showStock;

  /// Sedang kena promo yang berlaku hari ini.
  ///
  /// Datang dari luar, bukan dari produknya: label diskon adalah
  /// kenyataan yang tersimpan di tabel promo, dan menyalinnya ke menu
  /// berarti label yang masih terpasang seminggu setelah promonya habis.
  final bool sedangDiskon;

  /// Bintang dan angka terjual. Null berarti belum sempat dimuat — dan
  /// itu berbeda dari nol, jadi barisnya disembunyikan, bukan diisi nol.
  final ProductStats? stats;

  const ProductGridCard({
    super.key,
    required this.product,
    required this.quantityInCart,
    required this.onTap,
    this.ppnPercent = 0,
    this.showStock = false,
    this.sedangDiskon = false,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final selected = quantityInCart > 0;
    final inStock = product.available;
    final lowStock = showStock && product.stock > 0 && product.stock <= 5;
    final badges = [
      ...badgeDariKodeList(product.badges),
      if (sedangDiskon) ProductBadge.diskon,
    ];

    return Container(
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? MerchantPosTheme.brand : MerchantPosTheme.softFillOf(context),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? MerchantPosTheme.brand.withOpacity(0.18)
                : Colors.black.withOpacity(0.05),
            blurRadius: selected ? 12 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: inStock ? onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ProductPhoto(product: product, dimmed: !inStock),
                    if (!inStock)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'HABIS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    // Label menempel di pojok kiri atas foto, bukan di
                    // bawah namanya. Yang menggulir daftar menu membaca
                    // foto lebih dulu daripada teks — label di bawah
                    // nama baru terbaca setelah orangnya sudah memutuskan
                    // untuk melewati menunya.
                    if (badges.isNotEmpty && inStock)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: ProductBadgeChips(badges: badges),
                      ),
                    // Tap affordance — without it the tile reads as a
                    // static picture rather than something orderable.
                    if (inStock && !selected)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: MerchantPosTheme.surfaceOf(context),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add, size: 16, color: MerchantPosTheme.brand),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          constraints: const BoxConstraints(minWidth: 26),
                          decoration: BoxDecoration(
                            color: MerchantPosTheme.brand,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: [
                              BoxShadow(
                                color: MerchantPosTheme.brand.withOpacity(0.45),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '$quantityInCart',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.15,
                        color: inStock ? MerchantPosTheme.textOf(context) : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currency.format(menuPrice(product.price,
                                ppnPercent: ppnPercent, ppnExempt: product.ppnExempt)),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: inStock ? MerchantPosTheme.brand : Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (inStock && showStock && product.stock > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: lowStock
                                  ? Colors.orange.withOpacity(0.12)
                                  : Colors.grey.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${product.stock}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: lowStock ? Colors.orange.shade800 : MerchantPosTheme.mutedOf(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (stats != null &&
                        (stats!.adaNilai || stats!.terjual > 0)) ...[
                      const SizedBox(height: 3),
                      ProductStatsLine(stats: stats),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPhoto extends StatelessWidget {
  final Product product;
  final bool dimmed;

  const _ProductPhoto({required this.product, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    final photo = product.photoBase64;

    final Widget image = photo != null
        ? Image.memory(
            byteGambar(photo),
            width: double.infinity,
            fit: BoxFit.cover,
            // A corrupt/truncated base64 payload would otherwise throw
            // during paint and blank out the whole grid.
            errorBuilder: (_, __, ___) => const _PhotoPlaceholder(),
          )
        : const _PhotoPlaceholder();

    if (!dimmed) return image;
    return Opacity(opacity: 0.4, child: image);
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MerchantPosTheme.brand.withOpacity(0.09),
            MerchantPosTheme.brand.withOpacity(0.02),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_menu,
          size: 34,
          color: MerchantPosTheme.brand.withOpacity(0.30),
        ),
      ),
    );
  }
}
