import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/level_option.dart';

/// Kelompok level milik satu resto — dibaca semua orang, disusun admin.
///
/// Hanya di Supabase, tanpa salinan lokal seperti produk dan kategori.
/// Daftarnya pendek, jarang berubah, dan tidak pernah jadi jalur yang
/// dipakai berulang saat sedang sibuk melayani: dibaca sekali saat layar
/// menunya dibuka, lalu diam di [LevelGroupRegistry].
class LevelGroupProvider extends ChangeNotifier {
  final _client = Supabase.instance.client;
  final _uuid = const Uuid();

  String? restoId;

  List<LevelGroup> _groups = [];
  List<LevelGroup> get groups => _groups;

  bool loading = false;
  String? error;

  Future<void> load([String? id]) async {
    restoId = id ?? restoId;
    if (restoId == null) return;

    loading = true;
    notifyListeners();
    try {
      final rows = await _client
          .from('level_groups')
          .select()
          .eq('resto_id', restoId!)
          .order('sort_order');
      _groups = rows.map((r) => LevelGroup.fromMap(r)).toList();
      LevelGroupRegistry.replaceAll(_groups);
      error = null;
    } catch (e) {
      // Luring, atau tabelnya belum dimigrasi. Registrinya tetap berisi
      // lima kelompok bawaan, jadi pemesanan tidak ikut berhenti.
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> save({
    String? id,
    required String name,
    required List<String> options,
  }) async {
    if (restoId == null) return;
    await _client.from('level_groups').upsert({
      'id': id ?? _uuid.v4(),
      'resto_id': restoId,
      'name': name,
      'options': options,
      'sort_order': id == null ? _groups.length : null,
    }..removeWhere((_, v) => v == null));
    await load();
  }

  Future<void> delete(String id) async {
    await _client.from('level_groups').delete().eq('id', id);
    await load();
  }
}

/// Memuat kelompok level sekali untuk sebuah resto, tanpa Provider.
///
/// Untuk layar pelanggan dan kasir, yang cuma perlu membacanya. Gagal
/// memuat sengaja diabaikan: registrinya tetap berisi bawaan.
Future<void> primeLevelGroups(String restoId) async {
  try {
    final rows = await Supabase.instance.client
        .from('level_groups')
        .select()
        .eq('resto_id', restoId)
        .order('sort_order');
    LevelGroupRegistry.replaceAll(
      rows.map((r) => LevelGroup.fromMap(r)).toList(),
    );
  } catch (_) {
    // Biarkan bawaannya yang dipakai.
  }
}
