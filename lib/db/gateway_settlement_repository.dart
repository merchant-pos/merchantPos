import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gateway_settlement.dart';

class GatewaySettlementRepository {
  final _client = Supabase.instance.client;

  Future<List<GatewaySettlement>> getForResto(String restoId) async {
    final rows = await _client
        .from('gateway_settlements')
        .select()
        .eq('resto_id', restoId)
        .order('settled_on', ascending: false);
    return rows.map((r) => GatewaySettlement.fromMap(r)).toList();
  }

  /// Mencatat satu pencairan. Jurnalnya ditulis trigger database, bukan
  /// di sini — sama seperti seluruh pergerakan uang lainnya di Merchant-POS.
  Future<void> create(GatewaySettlement settlement) async {
    await _client.from('gateway_settlements').insert(settlement.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('gateway_settlements').delete().eq('id', id);
  }
}
