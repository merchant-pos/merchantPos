import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// The cart summary docked at the bottom of both ordering screens
/// (Kasir/Admin's POS and the Customer's menu). Shows what's in the cart
/// at a glance — item count and running total — instead of cramming it
/// all into one button label.
///
/// Collapses to a slim muted hint when the cart is empty, so an untouched
/// screen isn't dominated by a dead full-width button.
class CartBottomBar extends StatelessWidget {
  final int itemCount;
  final int total;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onPressed;

  const CartBottomBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.actionLabel,
    required this.actionIcon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final empty = itemCount == 0;

    return Container(
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: empty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 17, color: MerchantPosTheme.mutedOf(context)),
                      const SizedBox(width: 8),
                      Text(
                        'Keranjang masih kosong',
                        style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 13.5),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$itemCount item',
                              style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              currency.format(total),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: MerchantPosTheme.brandDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: onPressed,
                        icon: Icon(actionIcon, size: 18),
                        label: Text(actionLabel),
                        style: FilledButton.styleFrom(
                          // The theme pins every FilledButton to full
                          // width; this one shares the row with the total.
                          minimumSize: const Size(0, 50),
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
