/// Satu giliran jaga laci kasir, dari dibuka sampai uangnya dihitung.
class CashierShift {
  final String id;
  final String restoId;
  final String employeeEmail;
  final String? employeeName;
  final DateTime openedAt;
  final int openingCash;

  final DateTime? closedAt;

  /// Yang benar-benar dihitung tangan. Null selama shiftnya masih buka.
  final int? countedCash;

  /// Yang seharusnya ada menurut pembukuan. Dihitung server saat tutup.
  final int? expectedCash;

  /// [countedCash] − [expectedCash]. Negatif berarti uangnya kurang.
  final int? difference;

  final String? note;
  final String? closedBy;

  CashierShift({
    required this.id,
    required this.restoId,
    required this.employeeEmail,
    this.employeeName,
    required this.openedAt,
    this.openingCash = 0,
    this.closedAt,
    this.countedCash,
    this.expectedCash,
    this.difference,
    this.note,
    this.closedBy,
  });

  bool get terbuka => closedAt == null;

  /// Uangnya pas. Nol bukan sekadar "selisih kecil" — itu satu-satunya
  /// hasil yang tidak butuh penjelasan.
  bool get pas => (difference ?? 0) == 0;

  bool get kurang => (difference ?? 0) < 0;

  String get namaTampil {
    final n = employeeName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return employeeEmail.split('@').first;
  }

  factory CashierShift.fromMap(Map<String, dynamic> map) => CashierShift(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        employeeEmail: map['employee_email']?.toString() ?? '',
        employeeName: map['employee_name']?.toString(),
        openedAt: DateTime.tryParse(map['opened_at']?.toString() ?? '') ??
            DateTime.now(),
        openingCash: (map['opening_cash'] as num?)?.toInt() ?? 0,
        closedAt: DateTime.tryParse(map['closed_at']?.toString() ?? ''),
        countedCash: (map['counted_cash'] as num?)?.toInt(),
        expectedCash: (map['expected_cash'] as num?)?.toInt(),
        difference: (map['difference'] as num?)?.toInt(),
        note: map['note']?.toString(),
        closedBy: map['closed_by']?.toString(),
      );
}
