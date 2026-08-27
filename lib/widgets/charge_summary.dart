import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';

import '../utils/tax_calculator.dart';

/// The bill summary above the pay buttons: what the items came to, what
/// service adds, and the final total.
///
/// Menu prices already carry PPN, so [menuSubtotal] is what the customer
/// saw while ordering. Service is a per-bill Dine In charge, so it shows
/// up here for the first time — together with the PPN charged on it,
/// folded into the same line so the figures add up without needing a
/// separate "PPN atas service" row nobody would understand.
class ChargeSummary extends StatelessWidget {
  final TaxBreakdown charges;

  /// Sum of the menu prices as displayed (original + PPN).
  final int menuSubtotal;

  final double ppnPercent;
  final double servicePercent;
  final bool serviceApplies;
  final NumberFormat currency;

  const ChargeSummary({
    super.key,
    required this.charges,
    required this.menuSubtotal,
    required this.ppnPercent,
    required this.servicePercent,
    required this.serviceApplies,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    // Whatever the total exceeds the menu subtotal by is the service
    // charge plus its own PPN — derived rather than summed so the rows
    // can never fail to reconcile with the total.
    final serviceLine = charges.total - menuSubtotal;
    final showService = serviceApplies && serviceLine > 0;

    return Column(
      children: [
        if (showService) ...[
          _row(context, 'Subtotal', currency.format(menuSubtotal), muted: true),
          const SizedBox(height: 4),
          _row(
            context,
            'Biaya Service ${formatPercent(servicePercent)}',
            currency.format(serviceLine),
            muted: true,
          ),
          const Divider(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total', style: TextStyle(fontSize: 18)),
            Text(
              currency.format(charges.total),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        if (menuPriceNote(ppnPercent) != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              menuPriceNote(ppnPercent)!,
              style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool muted = false}) {
    final style = TextStyle(
      fontSize: 13.5,
      color: muted ? MerchantPosTheme.mutedOf(context) : null,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}
