/// One printed line on a receipt.
class ReceiptLine {
  final String name;
  final int quantity;
  final int unitPrice;
  final int subtotal;

  /// Level selections and free-text note, already combined for display.
  final String? note;

  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.note,
  });
}

/// Everything a receipt shows, independent of where the sale came from —
/// a Kasir/Admin sale ([PosTransaction]) and a customer self-order
/// ([CustomerOrder]) use different models but print the same paper.
///
/// Shared by the on-screen receipt ([ReceiptView]) and the PNG saved to
/// the gallery, so the two can't drift apart.
class ReceiptData {
  final String restoName;
  final String? restoAddress;

  /// Contact number, printed under the address when the resto has one.
  final String? restoPhone;

  /// Base64 store logo, uploaded via Info Resto. Falls back to a generic
  /// storefront mark when the resto hasn't set one.
  final String? restoLogoBase64;

  /// Order/transaction number, already shortened for print.
  final String reference;
  final DateTime dateTime;

  /// Label/value pairs printed above the items — cashier, order type,
  /// table, and so on.
  final List<(String, String)> headerRows;

  final List<ReceiptLine> lines;
  final int total;

  /// Label/value pairs printed under the total — payment method and when
  /// it went through.
  final List<(String, String)> footerRows;

  /// Service charge and PPN already contained in [total]. Printed as
  /// their own lines so the customer can see what they're paying for.
  final int? serviceAmount;
  final int? ppnAmount;

  /// Explains that the listed prices already include these charges.
  final String? inclusiveNote;

  /// Cash handed over, for a cash sale. When set, the receipt prints
  /// "Uang Bayar" and "Kembalian" beneath the total — the two figures a
  /// customer actually checks at the counter.
  final int? cashReceived;

  /// Drives the "Pembayaran berhasil" stamp at the foot of the receipt.
  final bool paid;

  const ReceiptData({
    required this.restoName,
    this.restoAddress,
    this.restoPhone,
    this.restoLogoBase64,
    required this.reference,
    required this.dateTime,
    this.headerRows = const [],
    required this.lines,
    required this.total,
    this.footerRows = const [],
    this.serviceAmount,
    this.ppnAmount,
    this.inclusiveNote,
    this.cashReceived,
    this.paid = true,
  });

  /// What the items came to before service and PPN were unwound out of
  /// them. Falls back to the total for orders taken before tax existed.
  int get subtotal => total - (serviceAmount ?? 0) - (ppnAmount ?? 0);

  bool get hasCharges => (serviceAmount ?? 0) > 0 || (ppnAmount ?? 0) > 0;

  int? get changeDue => cashReceived == null ? null : cashReceived! - total;

  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
}
