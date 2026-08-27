import '../models/transaction.dart';
import 'database_helper.dart';

/// Local record of Kasir/Admin sales.
///
/// Still written on every checkout — the receipt shown immediately after
/// payment is built from it, and it keeps a copy on the device even if
/// the mirror to Supabase fails. Riwayat Transaksi no longer reads from
/// here though: a shift close has to cover every till in the resto, so it
/// reads the shared `orders` table instead.
class TransactionRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> insert(PosTransaction tx) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('transactions', tx.toMap());
      for (final item in tx.items) {
        await txn.insert('transaction_items', item.toMap(tx.id));
      }
    });
  }

  /// Menempelkan nomor antrean pada transaksi yang sudah tersimpan.
  ///
  /// Nomornya datang dari server sesudah barisnya masuk, sementara
  /// transaksinya sudah lebih dulu ditulis ke penyimpanan lokal —
  /// menahan penulisan lokal sampai jaringan menjawab berarti penjualan
  /// hilang kalau jaringannya sedang mati.
  Future<void> updateNomor(String id, int nomor) async {
    final db = await _dbHelper.database;
    await db.update('transactions', {'orderNo': nomor},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PosTransaction>> getAll() async {
    final db = await _dbHelper.database;
    final txMaps = await db.query('transactions', orderBy: 'createdAt DESC');

    final result = <PosTransaction>[];
    for (final txMap in txMaps) {
      final itemMaps = await db.query(
        'transaction_items',
        where: 'transactionId = ?',
        whereArgs: [txMap['id']],
      );
      final items = itemMaps.map((m) => TransactionItem.fromMap(m)).toList();
      result.add(PosTransaction.fromMap(txMap, items));
    }
    return result;
  }

  /// Total sales for a given day (used by the daily report screen).
  Future<int> getTotalForDate(DateTime date) async {
    final db = await _dbHelper.database;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final result = await db.rawQuery(
      'SELECT SUM(total) as sum FROM transactions WHERE createdAt >= ? AND createdAt < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['sum'] as int?) ?? 0;
  }
}
