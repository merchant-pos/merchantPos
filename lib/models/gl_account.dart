/// Which GL (General Ledger) account code a payment method's income
/// should be booked to — set per restaurant by Finance. E.g. Cash income
/// might map to "4100 - Pendapatan Tunai" while QRIS maps to a separate
/// code, so exports/reconciliation line up with the resto's actual
/// chart of accounts.
class GlAccount {
  final String restoId;
  final String paymentMethod; // 'cash' | 'qris' | 'transfer'
  final String glCode;
  final String glName;

  GlAccount({
    required this.restoId,
    required this.paymentMethod,
    required this.glCode,
    required this.glName,
  });

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'payment_method': paymentMethod,
        'gl_code': glCode,
        'gl_name': glName,
      };

  factory GlAccount.fromMap(Map<String, dynamic> map) {
    return GlAccount(
      restoId: map['resto_id'] as String,
      paymentMethod: map['payment_method'] as String,
      glCode: map['gl_code'] as String,
      glName: map['gl_name'] as String,
    );
  }
}
