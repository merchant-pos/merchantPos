import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/level_group_provider.dart';

/// Menyiapkan Kategori dan Level sebelum layarnya ditampilkan.
///
/// [CategoryManagementScreen] dan [LevelManagementScreen] ditulis
/// sebagai tab di dalam Kelola Produk, dan sampai sekarang selalu
/// dibuka dari sana — induknyalah yang menyetel `restoId` lalu memuat
/// datanya. Dipasang sendirian di sidebar web, keduanya berdiri tanpa
/// induk itu.
///
/// Yang terjadi tanpa penyiap ini tidak terlihat seperti kerusakan, dan
/// itu bagian buruknya: daftarnya cuma kosong, seolah resto ini memang
/// belum punya kategori. Menambah kategori pun diam-diam tidak
/// tersimpan, karena penyimpanannya berhenti sendiri saat `restoId`
/// masih null.
///
/// Sekalian memberi judul di atasnya. Keduanya ditulis tanpa AppBar
/// karena sebagai tab, judulnya dipegang layar induknya. Berdiri
/// sendiri di sidebar, layarnya jadi satu-satunya yang tidak menyebut
/// dirinya sendiri — dan yang membukanya harus menoleh ke sidebar
/// untuk memastikan sedang melihat apa.
class KatalogSiap extends StatefulWidget {
  final Widget child;
  final String judul;

  const KatalogSiap({super.key, required this.child, required this.judul});

  @override
  State<KatalogSiap> createState() => _KatalogSiapState();
}

class _KatalogSiapState extends State<KatalogSiap> {
  String? _dimuatUntuk;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final restoId = context.watch<AuthProvider>().restoId;
    // Berpindah cabang harus memuat ulang. Tanpa perbandingan ini,
    // daftar cabang pertama akan bertahan di layar sesudah pindah.
    if (restoId == _dimuatUntuk) return;
    _dimuatUntuk = restoId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat(restoId));
  }

  Future<void> _muat(String? restoId) async {
    final categories = context.read<CategoryProvider>();
    categories.restoId = restoId;
    await categories.load();
    if (!mounted || restoId == null) return;
    await context.read<LevelGroupProvider>().load(restoId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.judul)),
      body: widget.child,
    );
  }
}
