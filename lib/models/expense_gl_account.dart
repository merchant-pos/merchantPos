/// One entry in the resto's expense GL chart of accounts (e.g. "5100 —
/// Sewa Tempat") — distinct from [GlAccount], which maps income by
/// payment method. Finance can add/remove as many of these as needed;
/// each expense recorded can optionally be tagged to one.
class ExpenseGlAccount {
  final String id;
  final String restoId;
  final String glCode;
  final String glName;

  ExpenseGlAccount({
    required this.id,
    required this.restoId,
    required this.glCode,
    required this.glName,
  });

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'gl_code': glCode,
        'gl_name': glName,
      };

  factory ExpenseGlAccount.fromMap(Map<String, dynamic> map) {
    return ExpenseGlAccount(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      glCode: map['gl_code'] as String,
      glName: map['gl_name'] as String,
    );
  }
}
