import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../theme.dart';
import 'cart_line_tile.dart';

/// Mengatur menu yang sudah masuk keranjang, langsung dari layar pilih
/// menu.
///
/// Sebelumnya mengubah pikiran berarti harus maju dulu ke keranjang:
/// salah tambah baru bisa diperbaiki di layar berikutnya. Padahal justru
/// di depan menu inilah orang menimbang-nimbang — "tadi dua, ternyata
/// satu saja".
///
/// Tetap menampilkan tiap varian sebagai baris sendiri, dan menyediakan
/// jalan menambah varian baru, supaya kemampuan memesan satu menu dengan
/// dua level pedas tidak hilang demi kemudahan mengedit.
class ProductLinesSheet extends StatelessWidget {
  final Product product;
  final List<CartItem> lines;

  /// Harga satuan seperti yang tampil di menu (sudah termasuk PPN).
  final int Function(CartItem line) unitPriceOf;
  final int Function(CartItem line) lineTotalOf;

  final void Function(String lineId) onIncrement;
  final void Function(String lineId) onDecrement;
  final void Function(String lineId) onDelete;
  final void Function(CartItem line) onEdit;
  final VoidCallback onAddVariant;

  const ProductLinesSheet({
    super.key,
    required this.product,
    required this.lines,
    required this.unitPriceOf,
    required this.lineTotalOf,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onEdit,
    required this.onAddVariant,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final totalQty = lines.fold<int>(0, (sum, l) => sum + l.quantity);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MerchantPosTheme.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          '$totalQty di keranjang'
                          '${lines.length > 1 ? ' · ${lines.length} varian' : ''}',
                          style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: MerchantPosTheme.mutedOf(context),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final line in lines)
                      CartLineTile(
                        item: line,
                        unitPrice: unitPriceOf(line),
                        lineTotal: lineTotalOf(line),
                        currency: currency,
                        onIncrement: () => onIncrement(line.lineId),
                        onDecrement: () => onDecrement(line.lineId),
                        onDelete: () => onDelete(line.lineId),
                        onEdit: () => onEdit(line),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Varian Baru'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MerchantPosTheme.brand,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onAddVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
