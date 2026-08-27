import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/category_provider.dart';
import '../widgets/dialog_actions.dart';
import '../utils/field_rules.dart';
import '../widgets/responsive.dart';
import '../widgets/required_label.dart';

/// Tab content (inside Kelola Produk) for managing the list of product
/// categories — added/deleted here, then picked from a dropdown on the
/// product form instead of free-typed each time.
class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});

  Future<void> _addCategory(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah Kategori'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(label: requiredLabel('Nama Kategori')),
              inputFormatters: nameFormatters,
              textCapitalization: TextCapitalization.words,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Tambah',
            onConfirm: () {
              final value = controller.text.trim();
              Navigator.pop(context, value.isEmpty ? null : value);
            },
            onCancel: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    await context.read<CategoryProvider>().addCategory(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<CategoryProvider>(
        builder: (context, provider, _) {
          final categories = provider.categories;
          if (categories.isEmpty) {
            return const Center(
              child: Text('Belum ada kategori.\nTambah dulu lewat tombol +.',
                  textAlign: TextAlign.center),
            );
          }
          // Kartu, sama seperti tab Level di sebelahnya.
          //
          // Ketiganya — Produk, Kategori, Level — adalah daftar yang
          // isinya dikelola dengan cara yang sama, dan sampai sekarang
          // hanya Level yang terlihat begitu. Di layar lebar bedanya
          // makin kentara: baris polos membentang dari tepi ke tepi
          // tanpa apa pun yang menandai di mana satu item berakhir.
          return ResponsiveCenter(
            child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, kFabSafeBottom),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final c = categories[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                title: Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Hapus kategori?'),
                        content: Text(
                            'Hapus "${c.name}"? Produk yang sudah pakai kategori ini tidak ikut terhapus.'),
                        actions: [
                          DialogActions(
                            confirmLabel: 'Hapus',
                            destructive: true,
                            onConfirm: () => Navigator.pop(context, true),
                          ),
                        ],
                        actionsAlignment: MainAxisAlignment.center,
                      ),
                    );
                    if (confirm == true) {
                      await provider.deleteCategory(c.id);
                    }
                  },
                ),
              ),
              );
            },
          ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCategory(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
