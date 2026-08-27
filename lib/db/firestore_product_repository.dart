import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../utils/foto_menu_bertahan.dart';

/// Mirrors the local product catalog into Supabase's `products` table so
/// the customer self-order app (a different device/install, no shared
/// local SQLite) can browse the same products and stock in real time.
///
/// Every row carries a `resto_id` so multiple restaurants can share this
/// same table without seeing each other's products.
///
/// The employee app remains the source of truth for writes — this is a
/// best-effort mirror, called after every local product/stock change.
///
/// (Class name kept as `FirestoreProductRepository` from the original
/// Firebase implementation to avoid touching every call site during the
/// Supabase migration — it's Postgres-backed now.)
class FirestoreProductRepository {
  final _client = Supabase.instance.client;

  Future<void> upsert(Product product, String restoId) async {
    await _client.from('products').upsert({
      ...product.toMap(),
      'resto_id': restoId,
    });
  }

  Future<void> delete(String id) async {
    await _client.from('products').delete().eq('id', id);
  }

  /// Menu resto ini, terus diperbarui.
  ///
  /// Baris yang datang lewat realtime tidak selalu membawa
  /// `photo_base64` yang utuh — dan itu paling sering terjadi tepat
  /// setelah sebuah pesanan masuk, karena stok menu yang dipesan
  /// dikurangi dan barisnya terkirim ulang. Yang terlihat pemesan: foto
  /// menu yang barusan dia pesan mendadak hilang.
  ///
  /// Karena itu foto yang mendadak hilang tidak langsung dipercaya.
  /// Barisnya ditanyakan ulang lewat REST — yang selalu utuh — dan foto
  /// lama dipasang sementara sambil menunggu jawabannya. Kalau server
  /// memang bilang fotonya sudah tidak ada, barulah ia dilepas: merchant
  /// berhak menghapus foto menunya, dan menolak mengakui penghapusan itu
  /// sama salahnya dengan menghilangkan fotonya sendiri.
  Stream<List<Product>> watchAll(String restoId) {
    final ingatan = IngatanFotoMenu();

    return _client
        .from('products')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        // Menaik, dan disebut tegas — aliran realtime bawaannya
        // menurun, jadi tanpa ini menunya berurut dari Z ke A.
        .order('name', ascending: true)
        .asyncMap((rows) async {
          var items = rows.map((r) => Product.fromMap(r)).toList();

          final curiga = ingatan.curiga(items);
          if (curiga.isNotEmpty) {
            items = ingatan.pulihkan(items, curiga);
            try {
              final ulang = await _client
                  .from('products')
                  .select()
                  .inFilter('id', curiga);
              final utuh = {
                for (final r in ulang)
                  r['id'].toString(): r['photo_base64'] as String?,
              };
              items = [
                for (final p in items)
                  if (utuh.containsKey(p.id))
                    p.copyWith(photoBase64: utuh[p.id])
                  else
                    p,
              ];
              for (final e in utuh.entries) {
                if (e.value == null) ingatan.lupakan(e.key);
              }
            } catch (_) {
              // Gagal menanyakan ulang berarti foto lama yang dipakai.
              // Menu berfoto basi jauh lebih berguna daripada menu
              // tanpa foto.
            }
          }

          ingatan.catat(items);
          return items;
        });
  }

  Future<List<Product>> getAllOnce(String restoId) async {
    final rows = await _client.from('products').select().eq('resto_id', restoId);
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  /// Atomically decrements stock for each item in a customer order (via
  /// the `decrement_stock` Postgres function — see supabase/functions.sql)
  /// so two simultaneous orders can't oversell the same product.
  Future<void> decrementStockForOrder(Map<String, int> productIdToQuantity) async {
    for (final entry in productIdToQuantity.entries) {
      await _client.rpc('decrement_stock', params: {'p_id': entry.key, 'qty': entry.value});
    }
  }
}
