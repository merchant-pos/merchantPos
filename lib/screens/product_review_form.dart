import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/customer_profile_repository.dart';
import '../db/product_review_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';

/// Formulir penilaian satu menu, untuk satu pesanan.
///
/// Membuka penilaian yang sudah ditulis untuk pesanan ITU kalau ada.
/// Yang memesan menu yang sama di hari lain menilai lagi dari kosong —
/// masakan hari ini bukan masakan bulan lalu.
class ProductReviewForm extends StatefulWidget {
  final String restoId;

  /// Pesanan yang sedang dinilai.
  ///
  /// Penilaian menempel pada pesanannya, bukan pada menunya. Yang
  /// memesan nasi goreng untuk kedua kalinya membuka formulir kosong,
  /// bukan bintang dari pesanan sebelumnya.
  final String orderId;

  final String productId;
  final String productName;

  const ProductReviewForm({
    super.key,
    required this.restoId,
    required this.orderId,
    required this.productId,
    required this.productName,
  });

  @override
  State<ProductReviewForm> createState() => _ProductReviewFormState();
}

class _ProductReviewFormState extends State<ProductReviewForm> {
  final _repo = ProductReviewRepository();
  final _komentar = TextEditingController();

  int _bintang = 0;
  bool _memuat = true;
  bool _menyimpan = false;

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
      final punya = await _repo.mine(
          orderId: widget.orderId, productId: widget.productId);
      if (!mounted) return;
      setState(() {
        if (punya != null) {
          _bintang = punya.rating;
          _komentar.text = punya.comment ?? '';
        }
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuat = false);
    }
  }

  Future<void> _simpan() async {
    if (_bintang == 0) {
      AppToast.show(context, 'Pilih bintangnya dulu.', isError: true);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      final email = context.read<AuthProvider>().user?.email;
      final profil = email == null
          ? null
          : await CustomerProfileRepository().getOnce(email);
      final nama = (profil?.name.isNotEmpty ?? false)
          ? profil!.name
          : (email?.split('@').first ?? 'Pelanggan');

      await _repo.simpan(
        restoId: widget.restoId,
        orderId: widget.orderId,
        productId: widget.productId,
        customerName: nama,
        rating: _bintang,
        comment: _komentar.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      // Penolakan basis data juga sampai ke sini — dan yang paling
      // mungkin adalah menilai menu yang pesanannya belum lunas.
      AppToast.show(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Nilai Menu')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Text(
                    widget.productName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 14),
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
                      1 => 'Tidak enak',
                      2 => 'Kurang',
                      3 => 'Lumayan',
                      4 => 'Enak',
                      5 => 'Enak banget',
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
                    hintText: 'Gimana rasanya menurut kamu?',
                    hintStyle: TextStyle(
                      color: MerchantPosTheme.mutedOf(context).withOpacity(0.7),
                      fontWeight: FontWeight.normal,
                    ),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
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
