/// Setoran modal ke saldo utama.
///
/// Bukan penghasilan. Uangnya benar-benar masuk, tapi tidak dijual ke
/// siapa pun — investor menyetor ke Merchant-POS, atau pemilik resto menaruh
/// uang awal supaya kasnya tidak minus di hari pertama. Mencatatnya
/// sebagai penghasilan membuat laporan penjualan memuat uang yang tidak
/// pernah dijual.
class BalanceTopup {
  final String id;
  final String restoId;
  final int amount;

  /// Dari siapa. Setoran tanpa nama penyetor adalah uang yang tidak bisa
  /// dipertanggungjawabkan ke siapa pun.
  final String source;

  final String? note;
  final String? proofBase64;
  final String? createdBy;
  final DateTime createdAt;

  const BalanceTopup({
    required this.id,
    required this.restoId,
    required this.amount,
    required this.source,
    this.note,
    this.proofBase64,
    this.createdBy,
    required this.createdAt,
  });

  bool get punyaBukti => proofBase64 != null && proofBase64!.isNotEmpty;

  factory BalanceTopup.fromMap(Map<String, dynamic> map) => BalanceTopup(
        id: map['id'].toString(),
        restoId: map['resto_id'] as String,
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        source: map['source'] as String? ?? '',
        note: map['note'] as String?,
        proofBase64: map['proof_base64'] as String?,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
      );
}
