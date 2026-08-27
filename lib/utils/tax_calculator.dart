/// How a bill splits into revenue, service charge and PPN. The three
/// always sum to [total].
class TaxBreakdown {
  /// Revenue actually earned — the sum of the products' original prices.
  final int base;
  final int service;
  final int ppn;

  /// What the customer pays.
  final int total;

  const TaxBreakdown({
    required this.base,
    required this.service,
    required this.ppn,
    required this.total,
  });

  static const zero = TaxBreakdown(base: 0, service: 0, ppn: 0, total: 0);

  bool get hasService => service > 0;
  bool get hasPpn => ppn > 0;
  bool get hasAny => hasService || hasPpn;
}

/// One line to be charged, priced at its **original** (pre-tax) amount.
class TaxableLine {
  /// Original unit price × quantity, before any charge.
  final int baseTotal;
  final bool ppnExempt;
  final bool serviceExempt;

  const TaxableLine({
    required this.baseTotal,
    this.ppnExempt = false,
    this.serviceExempt = false,
  });
}

/// Builds the bill up from original prices.
///
///     service = base × service%
///     ppn     = (base + service) × ppn%
///     total   = base + service + ppn
///
/// PPN is charged on base **plus** service, not on base alone, because
/// service charge is itself subject to PPN. Taxing the bare base instead
/// under-reports by a few hundred rupiah per bill — small enough to go
/// unnoticed until it has to be reconciled against a tax filing.
///
/// [serviceApplies] is false for Take Away: a service charge pays for
/// table service, so there is nothing to charge for.
TaxBreakdown calculateCharges({
  required List<TaxableLine> lines,
  required double ppnPercent,
  required double servicePercent,
  required bool serviceApplies,
}) {
  var base = 0;
  var service = 0;
  var ppn = 0;

  for (final line in lines) {
    final s = (!line.serviceExempt && serviceApplies) ? servicePercent / 100 : 0.0;
    final v = line.ppnExempt ? 0.0 : ppnPercent / 100;

    final lineService = (line.baseTotal * s).round();
    final linePpn = ((line.baseTotal + lineService) * v).round();

    base += line.baseTotal;
    service += lineService;
    ppn += linePpn;
  }

  return TaxBreakdown(base: base, service: service, ppn: ppn, total: base + service + ppn);
}

/// The price shown on the menu: the original price plus PPN only.
///
/// Service is deliberately left out — it's a per-bill charge that only
/// applies to Dine In, and baking it into the menu would mean the same
/// dish showing two different prices depending on how it's ordered.
int menuPrice(int basePrice, {required double ppnPercent, bool ppnExempt = false}) {
  if (ppnExempt || ppnPercent <= 0) return basePrice;
  return (basePrice * (1 + ppnPercent / 100)).round();
}

/// Note shown next to menu prices, or null when there's nothing to say.
String? menuPriceNote(double ppnPercent) =>
    ppnPercent > 0 ? 'Harga sudah termasuk PPN ${formatPercent(ppnPercent)}' : null;

/// Drops a trailing ".0" so 11 prints as "11%" rather than "11.0%".
String formatPercent(double value) {
  final trimmed = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$trimmed%';
}
