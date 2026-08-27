import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';

import '../models/cart_item.dart';

/// One line in the cart, shared by the Kasir/Admin checkout and the
/// customer's cart so both behave identically.
///
/// A line is a *configuration*, not a product: the options that make it
/// distinct are shown as chips right under the name, because with the
/// same dish appearing twice at different spice levels the options are
/// the only thing telling the two rows apart.
///
/// Deleting is its own button rather than counting the quantity down to
/// zero — adding something by mistake is common enough that removing it
/// shouldn't take four taps.
class CartLineTile extends StatelessWidget {
  final CartItem item;

  /// Menu price for one unit (original + PPN), so the row matches what
  /// was shown on the product grid.
  final int unitPrice;
  final int lineTotal;

  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  /// Opens the options editor. Null hides the affordance entirely.
  final VoidCallback? onEdit;

  /// Produknya ternyata sudah habis sejak dimasukkan ke keranjang.
  ///
  /// Ditandai di barisnya sendiri, bukan cuma disebut di dialog
  /// peringatan: yang harus dilakukan orangnya adalah menghapus baris
  /// tertentu, dan dialog yang sudah ditutup tidak menolongnya
  /// menemukan yang mana di antara tujuh baris lain.
  final bool soldOut;

  final NumberFormat currency;

  const CartLineTile({
    super.key,
    required this.item,
    required this.unitPrice,
    required this.lineTotal,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.currency,
    this.onEdit,
    this.soldOut = false,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final e in item.selectedLevels.entries) '${e.key}: ${e.value}',
    ];
    final note = item.notes?.trim() ?? '';

    return InkWell(
      onTap: onEdit,
      child: Container(
        color: soldOut ? MerchantPosTheme.tintOf(context, Colors.red) : null,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: soldOut ? MerchantPosTheme.onTintOf(context, Colors.red) : null,
                            decoration:
                                soldOut ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (soldOut)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: MerchantPosTheme.onTintOf(context, Colors.red),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('HABIS',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                      if (onEdit != null)
                        Icon(Icons.edit_outlined, size: 15, color: MerchantPosTheme.mutedOf(context)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${currency.format(unitPrice)} / item',
                    style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                  ),
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final option in options)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: MerchantPosTheme.softFillOf(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: MerchantPosTheme.borderOf(context)),
                            ),
                            child: Text(option, style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined, size: 13, color: MerchantPosTheme.mutedOf(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              color: MerchantPosTheme.mutedOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StepButton(icon: Icons.remove, onPressed: onDecrement),
                      Container(
                        constraints: const BoxConstraints(minWidth: 34),
                        alignment: Alignment.center,
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      _StepButton(icon: Icons.add, onPressed: onIncrement),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: Colors.red.shade400,
                        tooltip: 'Hapus',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text(
                currency.format(lineTotal),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MerchantPosTheme.borderOf(context)),
        ),
        child: Icon(icon, size: 17),
      ),
    );
  }
}
