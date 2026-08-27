import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:provider/provider.dart';

import '../models/level_option.dart';
import '../providers/level_group_provider.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';
import '../widgets/required_label.dart';

/// Tab Level di dalam Kelola Produk.
///
/// Yang disusun di sini adalah pilihan yang muncul saat memesan: level
/// pedas, ukuran, jenis susu, tingkat kematangan — apa pun yang khas di
/// resto ini. Produk lalu ditandai memakai kelompok mana lewat formulir
/// produknya.
class LevelManagementScreen extends StatelessWidget {
  const LevelManagementScreen({super.key});

  Future<void> _edit(BuildContext context, {LevelGroup? existing}) async {
    final provider = context.read<LevelGroupProvider>();
    final result = await showDialog<({String name, List<String> options})>(
      context: context,
      builder: (_) => _LevelGroupDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;

    try {
      await provider.save(
        id: existing?.id,
        name: result.name,
        options: result.options,
      );
    } catch (e) {
      if (!context.mounted) return;
      // Nama kembar ditolak database, bukan hanya oleh formulirnya:
      // dua kelompok bernama sama membuat produk yang menyandang nama
      // itu menunjuk dua tempat sekaligus.
      showAppToast(
        context,
        '$e'.contains('level_groups_resto_id_name_key')
            ? 'Sudah ada kelompok bernama "${result.name}".'
            : 'Gagal menyimpan: $e',
        isError: true,
      );
    }
  }

  Future<void> _delete(BuildContext context, LevelGroup group) async {
    final provider = context.read<LevelGroupProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline, size: 38, color: Colors.red),
        title: Text('Hapus "${group.name}"?'),
        content: const Text(
          'Produk yang memakai kelompok ini tidak ikut terhapus, tapi '
          'pilihannya tidak muncul lagi saat memesan.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await provider.delete(group.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<LevelGroupProvider>(
        builder: (context, provider, _) {
          if (provider.loading && provider.groups.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Belum ada kelompok level.\nTambah lewat tombol +.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.load,
            child: ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, kFabSafeBottom),
                children: [
                  Text(
                    'Pilihan yang muncul saat memesan. Produk ditandai '
                    'memakai kelompok mana lewat formulir produknya.',
                    style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                  ),
                  const SizedBox(height: 12),
                  for (final group in provider.groups)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(group.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final option in group.options)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: MerchantPosTheme.softFillOf(context),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(option,
                                      style: const TextStyle(fontSize: 11.5)),
                                ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Ubah',
                              onPressed: () => _edit(context, existing: group),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              tooltip: 'Hapus',
                              onPressed: () => _delete(context, group),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Formulir satu kelompok: namanya, lalu pilihan-pilihannya.
class _LevelGroupDialog extends StatefulWidget {
  final LevelGroup? existing;

  const _LevelGroupDialog({this.existing});

  @override
  State<_LevelGroupDialog> createState() => _LevelGroupDialogState();
}

class _LevelGroupDialogState extends State<_LevelGroupDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');

  /// Satu controller per pilihan, bukan satu kolom berisi teks
  /// dipisah koma. Pilihan yang mengandung koma — "Susu, Oat" — akan
  /// terbelah dua tanpa ada yang menyadarinya sampai muncul di layar
  /// dapur.
  late List<TextEditingController> _optionCtrls = [
    for (final o in widget.existing?.options ?? const [''])
      TextEditingController(text: o),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final options = [
      for (final c in _optionCtrls)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    if (name.isEmpty) {
      showAppToast(context, 'Nama kelompok wajib diisi.', isError: true);
      return;
    }
    if (options.length < 2) {
      // Kelompok berisi satu pilihan bukan pilihan — cuma dropdown yang
      // jawabannya sudah ditentukan, memaksa satu ketukan tambahan di
      // tiap pesanan tanpa menghasilkan keterangan apa pun.
      showAppToast(context, 'Isi minimal 2 pilihan.', isError: true);
      return;
    }
    if (options.toSet().length != options.length) {
      showAppToast(context, 'Ada pilihan yang kembar.', isError: true);
      return;
    }
    Navigator.pop(context, (name: name, options: options));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.existing == null ? 'Tambah Kelompok Level' : 'Ubah Kelompok Level',
        style: const TextStyle(fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: widget.existing == null,
              inputFormatters: nameFormatters,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                label: requiredLabel('Nama Kelompok'),
                hintText: 'Contoh: Level Pedas, Ukuran, Jenis Susu',
              ),
            ),
            const SizedBox(height: 16),
            requiredLabel('Pilihan'),
            const SizedBox(height: 4),
            for (var i = 0; i < _optionCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[i],
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          hintText: 'Pilihan ${i + 1}',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      tooltip: 'Hapus pilihan',
                      onPressed: _optionCtrls.length <= 2
                          ? null
                          : () => setState(() {
                                _optionCtrls.removeAt(i).dispose();
                              }),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah Pilihan'),
              onPressed: () =>
                  setState(() => _optionCtrls = [..._optionCtrls, TextEditingController()]),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          onConfirm: _submit,
          onCancel: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
