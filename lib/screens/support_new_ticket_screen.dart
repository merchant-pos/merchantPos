import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/customer_profile_repository.dart';
import '../db/support_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/gambar_base64.dart';
import '../utils/photo_picker.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Formulir pengaduan baru.
class SupportNewTicketScreen extends StatefulWidget {
  final bool dariMerchant;
  final String? restoId;

  /// Judul yang sudah ditentukan — dipakai percakapan bebas, yang tidak
  /// perlu diberi judul karena memang bukan pengaduan atas satu hal
  /// tertentu. Kolom judulnya ikut disembunyikan.
  final String? subjekTetap;

  const SupportNewTicketScreen({
    super.key,
    this.dariMerchant = false,
    this.restoId,
    this.subjekTetap,
  });

  @override
  State<SupportNewTicketScreen> createState() => _SupportNewTicketScreenState();
}

class _SupportNewTicketScreenState extends State<SupportNewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = SupportRepository();
  final _judul = TextEditingController();
  final _isi = TextEditingController();

  String? _foto;
  bool _menyimpan = false;

  @override
  void dispose() {
    _judul.dispose();
    _isi.dispose();
    super.dispose();
  }

  Future<void> _tambahFoto() async {
    final file = await pickProofPhoto(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (!mounted) return;
    setState(() => _foto = base64Encode(bytes));
  }

  Future<void> _kirim() async {
    // Diperiksa di sini, bukan diserahkan ke tombolnya.
    //
    // `onPressed: _menyimpan ? null : _kirim` baru berlaku setelah
    // layarnya digambar ulang. Dua ketukan cepat sama-sama masuk lebih
    // dulu, dan yang terkirim dua pengaduan — masing-masing membawa
    // salinan fotonya sendiri.
    if (_menyimpan) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _menyimpan = true);
    try {
      final auth = context.read<AuthProvider>();
      final email = auth.user?.email;
      // Nama pegawai sudah ada di sesi; nama pelanggan diambil dari
      // profilnya. Tanpa nama, daftar di sisi Merchant-POS Admin cuma berisi
      // deretan alamat surel — dan yang menjawabnya tidak tahu sedang
      // bicara dengan siapa.
      var nama = auth.employeeName;
      if ((nama == null || nama.trim().isEmpty) && email != null) {
        try {
          final profil = await CustomerProfileRepository().getOnce(email);
          nama = profil?.name;
        } catch (_) {
          // Tanpa nama pun pengaduannya tetap harus terkirim.
        }
      }

      final tiket = await _repo.buat(
        subject: widget.subjekTetap ?? _judul.text,
        body: _isi.text,
        dariMerchant: widget.dariMerchant,
        restoId: widget.restoId,
        nama: (nama ?? '').trim().isEmpty ? null : nama!.trim(),
        photoBase64: _foto,
      );
      if (!mounted) return;
      Navigator.pop(context, tiket.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      showAppToast(context, 'Gagal mengirim: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
          title: Text(widget.subjekTetap == null
              ? 'Pengaduan Baru'
              : 'Chat Merchant-POS Admin')),
      body: Form(
        key: _formKey,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Text(
                widget.subjekTetap == null
                    ? 'Ceritakan kendalanya sejelas mungkin. Makin jelas, '
                        'makin cepat bisa dibantu.'
                    : 'Tulis pertanyaanmu. Balasannya masuk ke sini juga, '
                        'dan HP-mu berbunyi kalau sudah dijawab.',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
              const SizedBox(height: 18),
              if (widget.subjekTetap == null)
                TextFormField(
                controller: _judul,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: InputDecoration(
                  label: requiredLabel('Judul Pengaduan'),
                  hintText: 'Contoh: QRIS tidak muncul di kasir',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _isi,
                maxLines: 6,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  label: requiredLabel(widget.subjekTetap == null
                      ? 'Ceritakan keluhannya'
                      : 'Pesanmu'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 6),
              const Text('Foto (opsional)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              if (_foto == null)
                OutlinedButton.icon(
                  onPressed: _tambahFoto,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Lampirkan Foto'),
                )
              else
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(byteGambar(_foto!),
                          width: 88, height: 88, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => setState(() => _foto = null),
                      icon: const Icon(Icons.close, size: 17),
                      label: const Text('Hapus'),
                    ),
                  ],
                ),
              const SizedBox(height: 26),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _menyimpan ? null : _kirim,
                  child: _menyimpan
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.subjekTetap == null
                          ? 'Kirim Pengaduan'
                          : 'Kirim Pesan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
