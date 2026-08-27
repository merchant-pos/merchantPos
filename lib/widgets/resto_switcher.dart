import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';

/// Tombol pindah resto untuk akun yang memegang lebih dari satu.
///
/// Ditaruh di header layar utama, bukan disembunyikan di dalam Setelan:
/// resto mana yang sedang dibuka menentukan arti setiap angka di
/// layar-layar berikutnya, jadi ia harus terbaca sebelum orangnya mulai
/// bekerja — bukan setelah dia terlanjur salah membaca laporan cabang
/// yang keliru.
///
/// Tidak menampilkan apa pun untuk akun satu resto, karena bagi mereka
/// tidak ada yang bisa dipilih.
class RestoSwitcher extends StatefulWidget {
  const RestoSwitcher({super.key});

  @override
  State<RestoSwitcher> createState() => _RestoSwitcherState();
}

class _RestoSwitcherState extends State<RestoSwitcher> {
  final _repo = RestaurantRepository();
  Map<String, Restaurant> _restos = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = context.read<AuthProvider>().restoIds;
    try {
      final found = await Future.wait(ids.map(_repo.getOnce));
      if (!mounted) return;
      setState(() {
        _restos = {
          for (final r in found)
            if (r != null) r.id: r,
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _nameOf(String id) => _restos[id]?.name ?? id;

  Future<void> _choose() async {
    final auth = context.read<AuthProvider>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text('Pilih Merchant',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Semua data mengikuti merchant yang dipilih',
              style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
            ),
            const SizedBox(height: 10),
            for (final id in auth.restoIds)
              () {
                final aktif = id == auth.restoId;
                // Yang sedang aktif ditandai tiga kali: bulatan berisi,
                // tulisan tebal, dan latar bersemburat merek.
                //
                // Terdengar berlebihan untuk satu baris daftar, tapi
                // inilah yang menentukan seluruh data yang dilihat
                // sesudahnya milik resto yang mana. Di tema gelap,
                // warna bawaan Theme.primaryColor jatuh terlalu dekat
                // dengan latarnya — bulatannya ada, tapi tidak
                // terbaca, dan yang punya dua cabang tidak tahu sedang
                // membuka yang mana.
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: aktif
                        ? MerchantPosTheme.brandOf(context).withOpacity(0.14)
                        : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(
                      aktif
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: aktif
                          ? MerchantPosTheme.brandOf(context)
                          : MerchantPosTheme.mutedOf(context),
                    ),
                    title: Text(
                      _nameOf(id),
                      style: TextStyle(
                        fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
                        color: aktif ? MerchantPosTheme.brandOf(context) : null,
                      ),
                    ),
                    subtitle: _restos[id]?.address.isNotEmpty == true
                        ? Text(_restos[id]!.address,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: aktif
                        ? Icon(Icons.check,
                            size: 18, color: MerchantPosTheme.brandOf(context))
                        : null,
                    onTap: () => Navigator.pop(sheetContext, id),
                  ),
                );
              }(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null) await auth.switchResto(picked);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.hasMultipleRestos || auth.restoId == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _loading ? null : _choose,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_outlined, size: 15, color: Colors.white),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(
                    _loading ? 'Memuat merchant…' : _nameOf(auth.restoId!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.expand_more, size: 17, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
