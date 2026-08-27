/// One recorded expense. Always paid out of the Petty Cash float — that's
/// what the journal credits (see supabase/journal_integrity.sql) and what
/// the Saldo & Pengeluaran screen deducts from.
class Expense {
  final String id;
  final String restoId;
  final int amount;
  final String description;
  final String? glCode;

  /// Optional photo of the receipt/nota, base64-encoded — same storage
  /// approach as product photos. Null when none was attached.
  final String? receiptBase64;
  final String createdBy;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.restoId,
    required this.amount,
    required this.description,
    this.glCode,
    this.receiptBase64,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        'description': description,
        if (glCode != null) 'gl_code': glCode,
        if (receiptBase64 != null) 'receipt_base64': receiptBase64,
        'created_by': createdBy,
      };

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      amount: (map['amount'] as num).toInt(),
      description: map['description'] as String,
      glCode: map['gl_code'] as String?,
      receiptBase64: map['receipt_base64'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
