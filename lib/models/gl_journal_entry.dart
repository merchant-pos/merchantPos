enum JournalEntryType { debit, credit }

extension JournalEntryTypeDb on JournalEntryType {
  String get dbValue => this == JournalEntryType.debit ? 'debit' : 'credit';

  static JournalEntryType fromDb(String? value) =>
      value == 'debit' ? JournalEntryType.debit : JournalEntryType.credit;
}

/// One row of real money movement — written only by database triggers
/// (an order flipping to `paid`, or a GL-tagged expense being recorded),
/// never inserted directly by the app. See supabase/gl_journal.sql.
class GlJournalEntry {
  final String id;
  final String restoId;
  final DateTime entryDate;
  final String entryTime; // "HH:mm:ss", as stored — display-formatted by the UI
  final String glCode;

  /// Snapshotted at write time, not joined — so renaming or removing a GL
  /// account later can't rewrite what history says it was called.
  final String? glName;
  final String referenceType; // 'order' | 'expense' | 'petty_cash'
  final String referenceId;
  final int amount;
  final JournalEntryType entryType;

  /// True for rows written to undo an earlier entry (its source record
  /// was deleted). The original row is never removed — see
  /// supabase/journal_integrity.sql.
  final bool isReversal;
  final String? description;
  final DateTime createdAt;

  GlJournalEntry({
    required this.id,
    required this.restoId,
    required this.entryDate,
    required this.entryTime,
    required this.glCode,
    this.glName,
    required this.referenceType,
    required this.referenceId,
    required this.amount,
    required this.entryType,
    this.isReversal = false,
    this.description,
    required this.createdAt,
  });

  /// Signed contribution to a running balance, using standard
  /// double-entry: debit adds, credit subtracts.
  int get signedAmount => entryType == JournalEntryType.debit ? amount : -amount;

  factory GlJournalEntry.fromMap(Map<String, dynamic> map) {
    return GlJournalEntry(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      entryDate: DateTime.parse(map['entry_date'] as String),
      entryTime: map['entry_time'] as String,
      glCode: map['gl_code'] as String,
      glName: map['gl_name'] as String?,
      referenceType: map['reference_type'] as String,
      referenceId: map['reference_id'] as String,
      amount: (map['amount'] as num).toInt(),
      entryType: JournalEntryTypeDb.fromDb(map['entry_type'] as String?),
      isReversal: map['is_reversal'] as bool? ?? false,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
