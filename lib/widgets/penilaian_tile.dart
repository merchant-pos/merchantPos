import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../providers/auth_provider.dart';
import '../screens/merchant_info_screen.dart';
import 'hub_menu_tile.dart';

/// Pintu ke penilaian pelanggan, untuk pegawai merchant.
///
/// Satu widget dipakai semua peran. Menyalinnya ke lima beranda berarti
/// lima tempat yang harus diingat berbarengan tiap kali cara membukanya
/// berubah — dan yang kelima selalu ketinggalan.
///
/// MerchantPOS Admin tidak memakainya: tempatnya bukan miliknya, dan daftar
/// keluhan yang tidak bisa dia tindaklanjuti cuma menumpuk.
/// Membuka layar penilaian untuk merchant tempat orang ini bekerja.
///
/// Dipisah dari widget tile-nya supaya layar yang tidak berbentuk
/// daftar menu — layar dapur, misalnya — bisa memakainya lewat ikon.
Future<void> bukaPenilaian(BuildContext context) async {
  final restoId = context.read<AuthProvider>().restoId;
  if (restoId == null) return;
  final m = await RestaurantRepository().getOnce(restoId);
  if (!context.mounted || m == null) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MerchantInfoScreen(
      merchant: m,
      // Yang menilai tempatnya sendiri bukan penilaian.
      bolehMenilai: false,
    ),
  ));
}

class PenilaianTile extends StatelessWidget {
  const PenilaianTile({super.key});

  @override
  Widget build(BuildContext context) {
    return HubMenuTile(
      icon: Icons.star_outline,
      title: 'Penilaian Pelanggan',
      subtitle: 'Bintang, komentar, dan foto dari pelanggan',
      color: const Color(0xFFF59E0B),
      onTap: () => bukaPenilaian(context),
    );
  }
}
