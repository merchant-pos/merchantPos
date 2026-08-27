import '../models/product.dart';
import 'database_helper.dart';

class ProductRepository {
  final _dbHelper = DatabaseHelper.instance;

  /// Katalog satu resto.
  ///
  /// Baris ber-resto_id NULL ikut terbawa: itu produk yang sudah ada
  /// sebelum aplikasi mengenal banyak resto, dan pada perangkat yang
  /// bersangkutan memang hanya ada satu resto. Sekali disentuh
  /// [claimUnassigned], kepemilikannya jadi tegas.
  Future<List<Product>> getAll(String? restoId) async {
    final db = await _dbHelper.database;
    final maps = restoId == null
        ? await db.query('products', orderBy: 'name ASC')
        : await db.query(
            'products',
            where: 'resto_id = ? OR resto_id IS NULL',
            whereArgs: [restoId],
            orderBy: 'name ASC',
          );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  /// Menandai produk warisan sebagai milik resto yang sedang dibuka.
  ///
  /// Dijalankan sekali saat resto pertama kali dibuka setelah pembaruan.
  /// Setelah itu tidak ada lagi baris tanpa pemilik, sehingga resto kedua
  /// tidak akan ikut mengklaimnya.
  Future<void> claimUnassigned(String restoId) async {
    final db = await _dbHelper.database;
    await db.update('products', {'resto_id': restoId}, where: 'resto_id IS NULL');
  }

  Future<void> insert(Product product, String? restoId) async {
    final db = await _dbHelper.database;
    await db.insert('products', {...product.toMap(), 'resto_id': restoId});
  }

  Future<void> update(Product product, String? restoId) async {
    final db = await _dbHelper.database;
    await db.update(
      'products',
      {...product.toMap(), 'resto_id': restoId},
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(String id, int delta) async {
    final db = await _dbHelper.database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ? WHERE id = ?',
      [delta, id],
    );
  }

  Future<void> setStock(String id, int stock) async {
    final db = await _dbHelper.database;
    await db.update('products', {'stock': stock},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setOutOfStock(String id, bool value) async {
    final db = await _dbHelper.database;
    await db.update('products', {'out_of_stock': value ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }
}
