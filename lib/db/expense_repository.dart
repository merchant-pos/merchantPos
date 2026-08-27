import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/expense.dart';

class ExpenseRepository {
  final _client = Supabase.instance.client;

  Future<List<Expense>> getForResto(String restoId) async {
    final rows = await _client
        .from('expenses')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<void> create(Expense expense) async {
    await _client.from('expenses').insert(expense.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('expenses').delete().eq('id', id);
  }
}
