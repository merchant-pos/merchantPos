import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/promo_banner_repository.dart';
import '../models/promo_banner.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/photo_picker.dart';
import '../utils/promo_period.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/promo_period_fields.dart';
import '../widgets/responsive.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../utils/lebar_web.dart';

/// Mengelola banner promo yang tampil di halaman menu customer.
///
/// Bannernya milik resto, bukan MerchantPOS: tiap resto memasang promonya
/// sendiri, dan customer hanya melihat banner resto yang sedang dibuka.
class PromoBannerScreen extends StatefulWidget {
  const PromoBannerScreen({super.key});

  @override
  State<PromoBannerScreen> createState() => _PromoBannerScreenState();
}

class _PromoBannerScreenState extends State<PromoBannerScreen> {
  final _repo = PromoBannerRepository();
  List<PromoBanner> _banners = [];
  bool _loading = true;
  String? _error;

  String get _restoId => context.read<AuthProvider>().restoId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.getForResto(_restoId);
      if (!mounted) return;
      setState(() {
        _banners = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addOrEdit([PromoBanner? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BannerFormDialog(
        restoId: _restoId,
        existing: existing,
        nextOrder: _banners.length,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(PromoBanner b) async {
    try {
      await _repo.setActive(b.id, !b.active);
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _delete(PromoBanner b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline, size: 38, color: Colors.red),
        title: const Text('Hapus banner?'),
        content: const Text(
          'Gambarnya ikut terhapus dan harus diunggah ulang kalau nanti dipakai '
          'lagi. Kalau hanya ingin menyembunyikannya sementara, matikan saja '
          'saklar aktifnya.',
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
    if (confirm != true) return;
    try {
      await _repo.delete(b.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  Future<void> _move(int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= _banners.length) return;

    final reordered = [..._banners];
    final item = reordered.removeAt(index);
    reordered.insert(target, item);
    setState(() => _banners = reordered);

    try {
      await _repo.reorder(reordered);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal mengurutkan: $e', isError: true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yang dihitung yang benar-benar dilihat pelanggan, bukan yang
    // saklarnya menyala. Banner yang masa berlakunya sudah lewat tetap
    // menyala saklarnya — menghitungnya sebagai tayang membuat angka di
    // layar ini menjanjikan promo yang sudah tidak ada.
    final aktif = _banners.where((b) => b.isLive()).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Banner Promo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Tambah Banner'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 40, color: MerchantPosTheme.mutedOf(context)),
                        const SizedBox(height: 12),
                        Text('Gagal memuat banner.\n$_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MerchantPosTheme.mutedOf(context))),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, kFabSafeBottom),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: MerchantPosTheme.brandTintOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: MerchantPosTheme.onBrandTintOf(context)
                                    .withOpacity(0.3)),
                          ),
                          child: Text(
                            _banners.isEmpty
                                ? 'Banner tampil di bagian atas halaman menu, tepat sebelum '
                                    'daftar produk. Pakai gambar melebar (rasio 16:9) supaya '
                                    'tidak terpotong.'
                                : '$aktif dari ${_banners.length} banner sedang tampil ke '
                                    'customer. Urutannya mengikuti daftar di bawah.',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: MerchantPosTheme.onBrandTintOf(context)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_banners.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Icon(Icons.image_outlined, size: 46, color: MerchantPosTheme.borderOf(context)),
                                const SizedBox(height: 12),
                                Text('Belum ada banner promo.',
                                    style: TextStyle(color: MerchantPosTheme.mutedOf(context))),
                              ],
                            ),
                          )
                        else
                          for (var i = 0; i < _banners.length; i++)
                            _BannerCard(
                              banner: _banners[i],
                              position: i,
                              total: _banners.length,
                              onEdit: () => _addOrEdit(_banners[i]),
                              onToggle: () => _toggleActive(_banners[i]),
                              onDelete: () => _delete(_banners[i]),
                              onUp: () => _move(i, -1),
                              onDown: () => _move(i, 1),
                            ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final PromoBanner banner;
  final int position;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onUp;
  final VoidCallback onDown;

  const _BannerCard({
    required this.banner,
    required this.position,
    required this.total,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.memory(
                  base64Decode(banner.imageBase64),
                  fit: BoxFit.cover,
                  // Gambar rusak tidak boleh menjatuhkan seluruh daftar —
                  // tanpa ini satu baris cacat mengosongkan layarnya.
                  errorBuilder: (_, __, ___) => Container(
                    color: MerchantPosTheme.softFillOf(context),
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                  ),
                ),
              ),
              // Sebabnya disebut, bukan cuma "tidak tampil".
              //
              // Banner yang saklarnya menyala tapi tanggalnya sudah
              // lewat dulu tidak bertanda apa pun — terlihat tayang
              // padahal tidak, dan pemiliknya baru tahu saat ada yang
              // menanyakan promonya di kasir.
              if (!banner.isLive())
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    alignment: Alignment.center,
                    child: Text(
                      !banner.active
                          ? 'TIDAK TAMPIL'
                          : banner.period.isExpired()
                              ? 'SUDAH LEWAT'
                              : 'BELUM MULAI',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (banner.title != null && banner.title!.isNotEmpty)
                  Text(banner.title!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                if (banner.description != null && banner.description!.isNotEmpty)
                  Text(banner.description!,
                      style: TextStyle(fontSize: 12.5, color: MerchantPosTheme.mutedOf(context))),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Urutan ${position + 1}',
                        style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      tooltip: 'Naikkan',
                      visualDensity: VisualDensity.compact,
                      onPressed: position == 0 ? null : onUp,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      tooltip: 'Turunkan',
                      visualDensity: VisualDensity.compact,
                      onPressed: position == total - 1 ? null : onDown,
                    ),
                    IconButton(
                      icon: Icon(
                        banner.active ? Icons.visibility : Icons.visibility_off,
                        size: 19,
                      ),
                      tooltip: banner.active ? 'Sembunyikan' : 'Tampilkan',
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Ubah',
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 19),
                      color: Colors.red.shade400,
                      tooltip: 'Hapus',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerFormDialog extends StatefulWidget {
  final String restoId;
  final PromoBanner? existing;
  final int nextOrder;

  const _BannerFormDialog({
    required this.restoId,
    required this.nextOrder,
    this.existing,
  });

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  late DateTime? _startsOn = widget.existing?.startsOn;
  late DateTime? _endsOn = widget.existing?.endsOn;

  final _repo = PromoBannerRepository();
  late final _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
  late final _descCtrl = TextEditingController(text: widget.existing?.description ?? '');

  File? _picked;
  late final String? _existingImage = widget.existing?.imageBase64;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await pickProofPhoto(context);
    if (file != null && mounted) setState(() => _picked = file);
  }

  Future<void> _save() async {
    if (_picked == null && _existingImage == null) {
      showAppToast(context, 'Pilih gambar bannernya dulu.');
      return;
    }

    // Diperiksa SEBELUM tombolnya berubah jadi lingkaran memuat.
    //
    // Sebelumnya urutannya terbalik: tombolnya berputar, lalu
    // pemeriksaan tanggal menolak dan keluar begitu saja — meninggalkan
    // tombol yang berputar selamanya untuk sesuatu yang tidak pernah
    // dikirim. Yang melihatnya menunggu simpanan yang tidak akan pernah
    // selesai.
    final periodError = validatePeriod(startsOn: _startsOn, endsOn: _endsOn);
    if (periodError != null) {
      showAppToast(context, periodError, isError: true);
      return;
    }

    final email = context.read<AuthProvider>().user?.email;
    setState(() => _saving = true);

    try {
      final image =
          _picked != null ? base64Encode(await _picked!.readAsBytes()) : _existingImage!;
      final banner = PromoBanner(
        id: widget.existing?.id ?? '',
        restoId: widget.restoId,
        imageBase64: image,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        active: widget.existing?.active ?? true,
        sortOrder: widget.existing?.sortOrder ?? widget.nextOrder,
        startsOn: _startsOn,
        endsOn: _endsOn,
        createdBy: widget.existing?.createdBy ?? email,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      if (widget.existing == null) {
        await _repo.create(banner);
      } else {
        await _repo.update(banner);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _picked != null
        ? Image.file(_picked!, fit: BoxFit.cover)
        : (_existingImage != null
            ? Image.memory(base64Decode(_existingImage), fit: BoxFit.cover)
            : null);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context, minimal: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'Tambah Banner' : 'Ubah Banner',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 4),
              Text('Rasio 16:9 paling pas — gambar lain akan terpotong.',
                  style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context))),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _pick,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: MerchantPosTheme.softFillOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MerchantPosTheme.borderOf(context)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: preview ??
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 34, color: MerchantPosTheme.mutedOf(context)),
                            const SizedBox(height: 6),
                            Text('Ketuk untuk pilih gambar',
                                style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context))),
                          ],
                        ),
                  ),
                ),
              ),
              if (preview != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Ganti gambar'),
                    onPressed: _pick,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Judul (opsional)', isDense: true),
                textCapitalization: TextCapitalization.words,
                inputFormatters: nameFormatters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 18),
              PromoPeriodFields(
                startsOn: _startsOn,
                endsOn: _endsOn,
                onChanged: (s, e) => setState(() {
                  _startsOn = s;
                  _endsOn = e;
                }),
              ),
              const SizedBox(height: 20),
              DialogActions(
                confirmLabel: 'Simpan',
                busy: _saving,
                onConfirm: _save,
                onCancel: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
