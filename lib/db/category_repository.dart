import '../models/category.dart';
import 'database_helper.dart';

/// Local (offline-first) storage for product categories — same pattern
/// as ProductRepository. Categories are managed once (Kelola Produk >
/// Kategori tab) and picked from a dropdown when adding/editing a
/// product, instead of being free-typed each time.
class CategoryRepository {
  final _dbHelper = DatabaseHelper.instance;

  /// Kategori milik satu resto. Baris tanpa pemilik ikut terbawa — itu
  /// kategori yang dibuat sebelum aplikasi mengenal banyak resto.
  Future<List<ProductCategory>> getAll(String? restoId) async {
    final db = await _dbHelper.database;
    final maps = restoId == null
        ? await db.query('categories', orderBy: 'name ASC')
        : await db.query(
            'categories',
            where: 'resto_id = ? OR resto_id IS NULL',
            whereArgs: [restoId],
            orderBy: 'name ASC',
          );
    return maps.map((m) => ProductCategory.fromMap(m)).toList();
  }

  Future<void> claimUnassigned(String restoId) async {
    final db = await _dbHelper.database;
    await db.update('categories', {'resto_id': restoId}, where: 'resto_id IS NULL');
  }

  Future<void> insert(ProductCategory category, String? restoId) async {
    final db = await _dbHelper.database;
    await db.insert('categories', {...category.toMap(), 'resto_id': restoId});
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
