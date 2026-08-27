/// Dari mana uang petty cash datang.
///
/// [incomeWithdrawal] dulu berarti "dari seluruh penghasilan", waktu
/// tunai dan non-tunai belum dibedakan. Baris lama dibiarkan apa adanya
/// dan sekarang dibaca sebagai Non Cash — menulis ulang riwayat justru
/// akan mengaku tahu sesuatu yang saat itu memang tidak tercatat.
enum PettyCashSource { manual, incomeWithdrawal, cashWithdrawal }

const _sourceDbValues = {
  PettyCashSource.manual: 'manual',
  PettyCashSource.incomeWithdrawal: 'income_withdrawal',
  PettyCashSource.cashWithdrawal: 'cash_withdrawal',
};

const kPettyCashSourceLabels = {
  PettyCashSource.manual: 'Top Up Manual',
  PettyCashSource.incomeWithdrawal: 'Withdraw dari Saldo Non Cash',
  PettyCashSource.cashWithdrawal: 'Withdraw dari Saldo Cash',
};

extension PettyCashSourceDb on PettyCashSource {
  String get dbValue => _sourceDbValues[this]!;

  static PettyCashSource fromDb(String? value) {
    return _sourceDbValues.entries
        .firstWhere((e) => e.value == value, orElse: () => const MapEntry(PettyCashSource.manual, ''))
        .key;
  }
}

/// Tahap persetujuan sebuah top up.
///
/// Kasir kini boleh mengajukan, tapi uangnya belum diakui masuk petty
/// cash sampai Finance menyetujui. Top up yang dibuat Finance sendiri
/// langsung berstatus disetujui — tidak ada gunanya menyetujui
/// permintaan sendiri.
enum PettyCashStatus { pending, approved, rejected }

const _statusDbValues = {
  PettyCashStatus.pending: 'pending',
  PettyCashStatus.approved: 'approved',
  PettyCashStatus.rejected: 'rejected',
};

const kPettyCashStatusLabels = {
  PettyCashStatus.pending: 'Pending',
  PettyCashStatus.approved: 'Completed',
  PettyCashStatus.rejected: 'Ditolak',
};

extension PettyCashStatusDb on PettyCashStatus {
  String get dbValue => _statusDbValues[this]!;

  static PettyCashStatus fromDb(String? value) => _statusDbValues.entries
      .firstWhere((e) => e.value == value,
          orElse: () => const MapEntry(PettyCashStatus.approved, 'approved'))
      .key;
}

/// A single top-up into the Petty Cash float — either a manual entry
/// (day-one cash before any income has come in) or a withdrawal moving
/// money out of Saldo Penghasilan. Never negative: there's no "usage"
/// entry yet, only funding — spending petty cash is still tracked the
/// same way as any other expense (see [Expense]).
class PettyCashEntry {
  final String id;
  final String restoId;
  final int amount;
  final PettyCashSource source;
  final String? description;
  final String createdBy;
  final DateTime createdAt;

  final PettyCashStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;

  PettyCashEntry({
    required this.id,
    required this.restoId,
    required this.amount,
    required this.source,
    this.description,
    required this.createdBy,
    required this.createdAt,
    this.status = PettyCashStatus.approved,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
  });

  bool get isPending => status == PettyCashStatus.pending;
  bool get isApproved => status == PettyCashStatus.approved;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        'source': source.dbValue,
        if (description != null) 'description': description,
        'created_by': createdBy,
        'status': status.dbValue,
      };

  factory PettyCashEntry.fromMap(Map<String, dynamic> map) {
    return PettyCashEntry(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      amount: (map['amount'] as num).toInt(),
      source: PettyCashSourceDb.fromDb(map['source'] as String?),
      description: map['description'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: PettyCashStatusDb.fromDb(map['status'] as String?),
      reviewedBy: map['reviewed_by'] as String?,
      reviewedAt: map['reviewed_at'] == null
          ? null
          : DateTime.parse(map['reviewed_at'] as String).toUtc(),
      reviewNote: map['review_note'] as String?,
    );
  }
}
