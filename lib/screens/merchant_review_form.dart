import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/customer_profile_repository.dart';
import '../db/merchant_review_repository.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/gambar_base64.dart';
import '../utils/photo_picker.dart';
import '../widgets/app_toast.dart';

/// Formulir penilaian merchant.
///
/// Membuka penilaian yang sudah pernah ditulis orang ini kalau ada —
/// yang berubah pikiran mengubah tulisannya, bukan menambah yang kedua.
class MerchantReviewForm extends StatefulWidget {
  final Restaurant merchant;

  const MerchantReviewForm({super.key, required this.merchant});

  @override
  State<MerchantReviewForm> createState() => _MerchantReviewFormState();
}

class _MerchantReviewFormState extends State<MerchantReviewForm> {
  final _repo = MerchantReviewRepository();
  final _komentar = TextEditingController();

  int _bintang = 0;
  final List<String> _foto = [];
  bool _memuat = true;
  bool _menyimpan = false;

  /// Paling banyak tiga.
  ///
  /// Bukan batas teknis — foto disimpan sebagai base64 di barisnya
  /// sendiri, dan sepuluh foto membuat satu ulasan lebih berat daripada
  /// seluruh daftar menunya.
  static const _maksFoto = 3;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _komentar.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      final punya = await _repo.mine(widget.merchant.id);
      if (!mounted) return;
      setState(() {
        if (punya != null) {
          _bintang = punya.rating;
          _komentar.text = punya.comment ?? '';
          _foto
            ..clear()
            ..addAll(punya.photos);
        }
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuat = false);
    }
  }

  Future<void> _tambahFoto() async {
    if (_foto.length >= _maksFoto) return;
    final file = await pickProofPhoto(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (!mounted) return;
    setState(() => _foto.add(base64Encode(bytes)));
  }

  Future<void> _simpan() async {
    if (_bintang == 0) {
      AppToast.show(context, 'Pilih bintangnya dulu.', isError: true);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      final auth = context.read<AuthProvider>();
      final email = auth.user?.email;
      // Namanya diambil dari profil, dan disalin saat menilai — ulasan
      // yang tiba-tiba berganti penulis adalah ulasan yang tidak bisa
      // dipercaya.
      final profil = email == null
          ? null
          : await CustomerProfileRepository().getOnce(email);
      final nama = (profil?.name.isNotEmpty ?? false)
          ? profil!.name
          : (email?.split('@').first ?? 'Pelanggan');

      await _repo.simpan(
        restoId: widget.merchant.id,
        customerName: nama,
        rating: _bintang,
        comment: _komentar.text,
        photos: _foto,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      AppToast.show(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: Text('Nilai ${widget.merchant.name}')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          iconSize: 38,
                          onPressed: () => setState(() => _bintang = i),
                          icon: Icon(
                            _bintang >= i ? Icons.star : Icons.star_border,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    switch (_bintang) {
                      1 => 'Mengecewakan',
                      2 => 'Kurang',
                      3 => 'Lumayan',
                      4 => 'Bagus',
                      5 => 'Sangat bagus',
                      _ => 'Ketuk bintangnya',
                    },
                    style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _komentar,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: 'Komentar (opsional)',
                    hintText: 'Ceritakan pengalamanmu di sini',
                    hintStyle: TextStyle(
                      color: MerchantPosTheme.mutedOf(context).withOpacity(0.7),
                      fontWeight: FontWeight.normal,
                    ),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Foto (opsional, maksimal $_maksFoto)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _foto.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.memory(byteGambar(_foto[i]),
                                width: 88, height: 88, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    setState(() => _foto.removeAt(i)),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.close,
                                      color: Colors.white, size: 15),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_foto.length < _maksFoto)
                      InkWell(
                        onTap: _tambahFoto,
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border:
                                Border.all(color: MerchantPosTheme.borderOf(context)),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined,
                              size: 22),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _menyimpan ? null : _simpan,
                    child: _menyimpan
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Simpan Penilaian'),
                  ),
                ),
              ],
            ),
    );
  }
}
