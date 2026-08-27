import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category.dart';

/// Mirrors categories to Supabase (same best-effort pattern as
/// FirestoreProductRepository) so they stay consistent if the Admin
/// manages products from more than one device.
class CategorySyncRepository {
  final _client = Supabase.instance.client;

  Future<void> upsert(ProductCategory category, String restoId) async {
    await _client.from('categories').upsert({
      ...category.toMap(),
      'resto_id': restoId,
    });
  }

  Future<void> delete(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }

  Future<List<ProductCategory>> getAllOnce(String restoId) async {
    final rows = await _client.from('categories').select().eq('resto_id', restoId);
    return rows.map((r) => ProductCategory.fromMap(r)).toList();
  }
}
