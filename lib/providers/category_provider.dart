import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/category_repository.dart';
import '../db/category_sync_repository.dart';
import '../models/category.dart';

class CategoryProvider extends ChangeNotifier {
  final _repo = CategoryRepository();
  final _syncRepo = CategorySyncRepository();
  final _uuid = const Uuid();

  /// Set once by the Kelola Produk screen from AuthProvider.restoId,
  /// same pattern as ProductProvider.
  String? restoId;

  List<ProductCategory> _categories = [];
  List<ProductCategory> get categories => _categories;

  /// Sama seperti produk: di web tidak ada salinan lokal.
  ///
  /// Kategori yang berbeda antara HP dan web lebih buruk daripada
  /// katalog yang berbeda — produk menunjuk kategorinya lewat nama, jadi
  /// kategori yang cuma ada di satu sisi membuat produknya menggantung
  /// di sisi yang lain.
  bool get _tanpaSalinanLokal => kIsWeb;

  Future<void> load() async {
    if (_tanpaSalinanLokal) {
      if (restoId == null) {
        _categories = [];
      } else {
        _categories = await _syncRepo.getAllOnce(restoId!);
      }
      notifyListeners();
      return;
    }
    _categories = await _repo.getAll(restoId);
    notifyListeners();
  }

  Future<void> syncAllToSupabase() async {
    if (restoId == null || _tanpaSalinanLokal) return;
    for (final category in _categories) {
      _syncRepo.upsert(category, restoId!).catchError((_) {});
    }
  }

  /// Pulls down any categories that exist in Supabase but not yet in
  /// this device's local database — e.g. ones seeded directly via SQL.
  Future<void> pullNewFromSupabase() async {
    if (restoId == null || _tanpaSalinanLokal) return;
    // Kategori warisan diakui milik resto ini sekali saja — sama seperti
    // produk, supaya resto kedua tidak ikut mengklaimnya.
    await _repo.claimUnassigned(restoId!);
    try {
      final remote = await _syncRepo.getAllOnce(restoId!);
      final localIds = _categories.map((c) => c.id).toSet();
      for (final r in remote) {
        if (!localIds.contains(r.id)) {
          await _repo.insert(r, restoId);
        }
      }
      await load();
    } catch (_) {
      // Offline — nothing new to pull in.
    }
  }

  Future<void> addCategory(String name) async {
    final category = ProductCategory(id: _uuid.v4(), name: name);
    if (_tanpaSalinanLokal) {
      if (restoId == null) return;
      await _syncRepo.upsert(category, restoId!);
      await load();
      return;
    }
    await _repo.insert(category, restoId);
    if (restoId != null) {
      _syncRepo.upsert(category, restoId!).catchError((_) {});
    }
    await load();
  }

  Future<void> deleteCategory(String id) async {
    if (_tanpaSalinanLokal) {
      await _syncRepo.delete(id);
      await load();
      return;
    }
    await _repo.delete(id);
    _syncRepo.delete(id).catchError((_) {});
    await load();
  }
}
