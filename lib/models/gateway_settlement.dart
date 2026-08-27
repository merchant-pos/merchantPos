/// Dana payment gateway yang benar-benar cair ke rekening resto.
///
/// Pesanan QRIS dicatat lunas saat pelanggan membayar, tapi uangnya
/// masih ditahan penyedia dan baru dikirim sehari dua hari kemudian,
/// dikurangi potongan. Baris ini adalah kejadian keduanya — dan tanpa
/// mencatatnya, GL QRIS terus bertambah tanpa pernah cocok dengan mutasi
/// bank mana pun.
class GatewaySettlement {
  final String id;
  final String restoId;

  /// Tanggal dananya masuk rekening menurut mutasi bank, bukan tanggal
  /// pesanannya dibayar. Keduanya memang berbeda hari — itu justru
  /// alasan catatan ini ada.
  final DateTime settledOn;

  /// Jumlah kotor sebelum potongan, seperti tertulis di laporan
  /// penyedia.
  final int grossAmount;

  /// Potongan penyedia (MDR).
  final int feeAmount;

  /// Yang benar-benar masuk rekening, seperti tertulis di mutasi bank.
  ///
  /// Disimpan apa adanya, bukan dihitung dari dua yang lain: saat bruto
  /// dikurangi biaya ternyata tidak sama dengan yang masuk — pembulatan,
  /// biaya tambahan, penyesuaian — yang dibutuhkan justru ketiganya
  /// sebagaimana tercatat.
  final int netAmount;

  final String provider;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;

  GatewaySettlement({
    required this.id,
    required this.restoId,
    required this.settledOn,
    required this.grossAmount,
    required this.feeAmount,
    required this.netAmount,
    this.provider = 'xendit',
    this.note,
    this.createdBy,
    required this.createdAt,
  });

  /// Selisih antara yang seharusnya masuk dan yang benar-benar masuk.
  ///
  /// Nol pada pencairan yang normal. Bukan nol berarti ada yang perlu
  /// ditanyakan ke penyedia — dan itulah gunanya ketiga angkanya
  /// disimpan terpisah.
  int get discrepancy => grossAmount - feeAmount - netAmount;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'settled_on': settledOn.toIso8601String().split('T').first,
        'gross_amount': grossAmount,
        'fee_amount': feeAmount,
        'net_amount': netAmount,
        'provider': provider,
        if (note != null) 'note': note,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory GatewaySettlement.fromMap(Map<String, dynamic> map) {
    return GatewaySettlement(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      settledOn: DateTime.parse(map['settled_on'] as String),
      grossAmount: (map['gross_amount'] as num).toInt(),
      feeAmount: (map['fee_amount'] as num?)?.toInt() ?? 0,
      netAmount: (map['net_amount'] as num).toInt(),
      provider: map['provider'] as String? ?? 'xendit',
      note: map['note'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
