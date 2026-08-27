/// Selisih kurang sebuah shift yang masih ditagihkan kepada kasirnya.
///
/// Hanya yang **kurang** yang jadi tagihan. Tidak ada yang bisa ditagih
/// dari uang yang justru berlebih — yang perlu dilakukan menelusuri
/// penjualan yang belum diinput, dan itu pekerjaan Finance, bukan utang
/// kasir.
class CashVariance {
  final String id;
  final String restoId;
  final String shiftId;
  final String employeeEmail;
  final String? employeeName;

  /// Selalu positif: sebesar itulah uang yang kurang.
  final int amount;

  final bool lunas;
  final String? note;
  final DateTime createdAt;
  final DateTime? settledAt;
  final String? settledBy;
  final String? settleNote;

  CashVariance({
    required this.id,
    required this.restoId,
    required this.shiftId,
    required this.employeeEmail,
    this.employeeName,
    required this.amount,
    this.lunas = false,
    this.note,
    required this.createdAt,
    this.settledAt,
    this.settledBy,
    this.settleNote,
  });

  String get namaTampil {
    final n = employeeName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return employeeEmail.split('@').first;
  }

  factory CashVariance.fromMap(Map<String, dynamic> map) => CashVariance(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        shiftId: map['shift_id'].toString(),
        employeeEmail: map['employee_email']?.toString() ?? '',
        employeeName: map['employee_name']?.toString(),
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        lunas: map['status'] == 'settled',
        note: map['note']?.toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        settledAt: DateTime.tryParse(map['settled_at']?.toString() ?? ''),
        settledBy: map['settled_by']?.toString(),
        settleNote: map['settle_note']?.toString(),
      );
}
