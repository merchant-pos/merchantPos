import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../db/announcement_repository.dart';
import '../models/announcement.dart';
import '../db/restaurant_repository.dart';
import '../providers/auth_provider.dart';
import '../utils/photo_picker.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';
import '../widgets/required_label.dart';

/// Menerbitkan pengumuman ke kotak masuk.
///
/// Dua jenis, dan yang boleh mengirimnya berbeda:
///
/// - **Update Aplikasi** — hanya Super Admin. Isinya menyangkut APK yang
///   dia sendiri terbitkan, dan admin resto tidak punya cara mengetahui
///   versi mana yang sebenarnya sudah rilis.
/// - **General** — Super Admin (ke semua resto) dan Admin (ke restonya
///   sendiri). Ini yang dipakai untuk promo, jadi boleh berisi gambar.
///
/// Batasnya juga ditegakkan RLS. Tab yang disembunyikan di sini cuma
/// menghalangi orang yang memakai aplikasinya.
class PublishAnnouncementScreen extends StatelessWidget {
  const PublishAnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canPublishUpdate = auth.isSuperAdmin;

    if (!canPublishUpdate) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kirim Pengumuman')),
        body: const _AnnouncementForm(category: AnnouncementCategory.general),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kirim Pengumuman'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Update Aplikasi'),
              Tab(text: 'General'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AnnouncementForm(category: AnnouncementCategory.update),
            _AnnouncementForm(category: AnnouncementCategory.general),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementForm extends StatefulWidget {
  final AnnouncementCategory category;

  const _AnnouncementForm({required this.category});

  @override
  State<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends State<_AnnouncementForm>
    with AutomaticKeepAliveClientMixin {
  static const _downloadUrl =
      'https://github.com/bujejuki-spec/Merchant-POS-LandingPage/releases/latest/download/Merchant-POS.apk';

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _urlCtrl = TextEditingController(text: _downloadUrl);
  String? _imageBase64;
  bool _saving = false;

  /// Nama resto yang sedang dibuka, untuk disebut di keterangannya.
  ///
  /// Namanya, bukan Resto ID-nya. Admin yang memegang dua cabang perlu
  /// tahu pengumumannya akan mendarat di mana, dan yang dia kenali
  /// adalah "MerchantPos Resto Dago" — bukan deretan huruf yang tidak pernah
  /// dia lihat di layar mana pun.
  String? _restoName;

  bool get _isUpdate => widget.category == AnnouncementCategory.update;

  // Isian yang sudah diketik tidak boleh hilang saat berpindah tab lalu
  // kembali — mengetik ulang seluruh pengumuman gara-gara melirik tab
  // sebelah adalah cara tercepat membuat orang enggan memakainya.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRestoName();
    if (!_isUpdate) return;
    // Versi yang terpasang di HP ini dipakai sebagai isian awal: yang
    // menerbitkan pengumuman biasanya baru saja memasang APK barunya.
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _versionCtrl.text = info.version;
        _titleCtrl.text = 'Merchant-POS ${info.version} sudah tersedia';
        _bodyCtrl.text = 'Versi baru Merchant-POS sudah bisa diunduh. '
            'Perbarui aplikasimu untuk mendapat perbaikan dan fitur terbaru.';
      });
    });
  }

  Future<void> _loadRestoName() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted) return;
      setState(() => _restoName = resto?.name);
    } catch (_) {
      // Luring — keterangannya cukup menyebut "resto yang sedang kamu
      // buka" tanpa namanya.
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _versionCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await pickProofPhoto(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (!mounted) return;
    setState(() => _imageBase64 = base64Encode(bytes));
  }

  /// Sasaran pengumuman. Hanya berlaku untuk pengumuman umum dari
  /// resto — kabar versi baru dan pengumuman Super Admin selalu untuk
  /// semua orang.
  AnnouncementAudience _audience = AnnouncementAudience.all;

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final toast = AppToast.of(context);
    final navigator = Navigator.of(context);

    // Pengumuman umum dari Super Admin berlaku untuk semua resto, jadi
    // restonya sengaja dikosongkan. Dari Admin, selalu terikat restonya
    // sendiri — dan RLS menolak kalau bukan.
    final restoId = auth.isSuperAdmin ? null : auth.restoId;
    if (!_isUpdate && restoId == null && !auth.isSuperAdmin) {
      toast.show('Akun ini belum punya Merchant ID.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await AnnouncementRepository().publish(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        category: widget.category,
        version: _isUpdate && _versionCtrl.text.trim().isNotEmpty
            ? _versionCtrl.text.trim()
            : null,
        downloadUrl:
            _isUpdate && _urlCtrl.text.trim().isNotEmpty ? _urlCtrl.text.trim() : null,
        restoId: _isUpdate ? null : restoId,
        imageBase64: _isUpdate ? null : _imageBase64,
        audience: restoId == null ? AnnouncementAudience.all : _audience,
        createdBy: auth.user?.email ?? 'Merchant-POS',
      );
      toast.show(restoId == null
          ? 'Pengumuman terkirim ke semua kotak masuk.'
          : 'Pengumuman terkirim ke '
              '${kAnnouncementAudienceHints[_audience]!.toLowerCase()}.');
      navigator.pop();
    } catch (e) {
      toast.show('Gagal mengirim: $e', isError: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthProvider>();
    final toEveryone = _isUpdate || auth.isSuperAdmin;

    return ResponsiveCenter(
      maxWidth: 640,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Warnanya dari tema, bukan ditulis mati.
            //
            // Sebelumnya biru tua 0xFF075985 — dipilih untuk latar
            // pastel di tema terang, dan nyaris lenyap begitu latarnya
            // jadi gelap. Kalimat di sini menjelaskan siapa yang akan
            // menerima pengumumannya; yang tidak terbaca membuat orang
            // menekan Kirim tanpa tahu ke mana perginya.
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: MerchantPosTheme.tintOf(context, Colors.lightBlue),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: MerchantPosTheme.onTintOf(context, Colors.lightBlue)
                        .withOpacity(0.35)),
              ),
              child: Text(
                _isUpdate
                    ? 'Pemberitahuan versi baru. Muncul di tab "Update Aplikasi" '
                        'pada kotak masuk semua pengguna, dan sebagai banner di '
                        'layar awal untuk yang memesan tanpa akun.'
                    : toEveryone
                        ? 'Pengumuman umum ke seluruh merchant. Muncul di tab '
                            '"General" pada kotak masuk semua pengguna yang login.'
                        : 'Pengumuman umum untuk '
                            '${_restoName ?? 'merchant yang sedang kamu buka'}. '
                            'Masuk ke tab "General" di kotak masuk, berikut '
                            'notifikasinya. Merchant lain tidak menerimanya.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: MerchantPosTheme.onTintOf(context, Colors.lightBlue)),
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _titleCtrl,
              decoration: InputDecoration(label: requiredLabel('Judul')),
              maxLength: 80,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bodyCtrl,
              decoration: InputDecoration(label: requiredLabel('Isi Pesan')),
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 14),
            // Sasarannya dipilih tegas, tanpa bawaan yang tersembunyi.
            //
            // Promo dan pengumuman internal punya pembaca yang berbeda.
            // Jadwal shift yang ikut terkirim ke pelanggan bukan cuma
            // tidak berguna — sebagian memang tidak pantas dibaca
            // mereka, dan yang mengirimnya baru tahu setelah terkirim.
            if (!_isUpdate && !toEveryone) ...[
              const Text('Dikirim ke',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<AnnouncementAudience>(
                segments: [
                  for (final a in AnnouncementAudience.values)
                    ButtonSegment(
                      value: a,
                      label: Text(kAnnouncementAudienceLabels[a]!),
                    ),
                ],
                selected: {_audience},
                onSelectionChanged: (v) => setState(() => _audience = v.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle:
                      WidgetStateProperty.all(const TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kAnnouncementAudienceHints[_audience]!,
                style: TextStyle(
                    fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              const SizedBox(height: 16),
            ],
            if (_isUpdate) ...[
              TextFormField(
                controller: _versionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Versi (mis. 1.32.0)',
                  helperText: 'Dipakai untuk tahu apakah aplikasi pengguna sudah tertinggal',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'Link Unduh'),
              ),
            ] else ...[
              const Text('Gambar Promo (opsional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              if (_imageBase64 == null)
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Pilih Gambar'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        base64Decode(_imageBase64!),
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _imageBase64 = null),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.campaign_outlined),
                label: const Text('Kirim Pengumuman'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _saving ? null : _publish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
