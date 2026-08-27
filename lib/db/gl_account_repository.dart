import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gl_account.dart';

class GlAccountRepository {
  final _client = Supabase.instance.client;

  Future<List<GlAccount>> getForResto(String restoId) async {
    final rows = await _client.from('gl_accounts').select().eq('resto_id', restoId);
    return rows.map((r) => GlAccount.fromMap(r)).toList();
  }

  Future<void> upsert(GlAccount account) async {
    await _client.from('gl_accounts').upsert(account.toMap());
  }
}
