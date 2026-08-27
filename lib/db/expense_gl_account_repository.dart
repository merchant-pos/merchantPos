import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/expense_gl_account.dart';

class ExpenseGlAccountRepository {
  final _client = Supabase.instance.client;

  Future<List<ExpenseGlAccount>> getForResto(String restoId) async {
    final rows = await _client
        .from('expense_gl_accounts')
        .select()
        .eq('resto_id', restoId)
        .order('gl_code');
    return rows.map((r) => ExpenseGlAccount.fromMap(r)).toList();
  }

  Future<void> create(String restoId, String glCode, String glName) async {
    await _client.from('expense_gl_accounts').insert({
      'resto_id': restoId,
      'gl_code': glCode,
      'gl_name': glName,
    });
  }

  /// How many expenses are already booked against this GL code. The
  /// database refuses the delete outright (FK ON DELETE RESTRICT — see
  /// supabase/journal_integrity.sql); this just lets the UI explain why
  /// before the user commits to it, instead of surfacing a raw
  /// constraint-violation error.
  Future<int> usageCount(String restoId, String glCode) async {
    final rows = await _client
        .from('expenses')
        .select('id')
        .eq('resto_id', restoId)
        .eq('gl_code', glCode);
    return rows.length;
  }

  Future<void> delete(String id) async {
    await _client.from('expense_gl_accounts').delete().eq('id', id);
  }
}
