import 'package:flutter/material.dart';

import '../models/product_badge.dart';
import '../models/product_review.dart';
import '../theme.dart';

/// Urutan kepentingannya saat tempatnya tidak cukup untuk semuanya.
///
/// Diskon lebih dulu karena ia satu-satunya yang mengubah angka yang
/// dibayar. "Rekomendasi" paling belakang karena ia pendapat, bukan
/// fakta — dan pendapat yang menutupi harga promo merugikan keduanya.
const _urutan = [
  ProductBadge.diskon,
  ProductBadge.terlaris,
  ProductBadge.baru,
  ProductBadge.rekomendasi,
];

List<ProductBadge> urutkanBadge(Iterable<ProductBadge> badges) => [
      for (final b in _urutan)
        if (badges.contains(b)) b,
    ];

/// Deretan label di atas foto menu.
///
/// Dibatasi [maks] buah. Kartu menu selebar setengah layar ponsel, dan
/// empat label sekaligus akan menutupi foto yang justru jadi alasan
/// orang berhenti menggulir.
class ProductBadgeChips extends StatelessWidget {
  final List<ProductBadge> badges;
  final int maks;
  final double fontSize;

  const ProductBadgeChips({
    super.key,
    required this.badges,
    this.maks = 2,
    this.fontSize = 8.5,
  });

  @override
  Widget build(BuildContext context) {
    final tampil = urutkanBadge(badges).take(maks).toList();
    if (tampil.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in tampil)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: kBadgeWarna[b],
                borderRadius: BorderRadius.circular(5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(kBadgeIkon[b], size: fontSize + 3, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    kBadgeLabel[b]!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Bintang dan angka terjual, satu baris.
///
/// Yang belum pernah dinilai tidak menampilkan "0.0" — angka nol di
/// sebelah bintang terbaca sebagai penilaian terburuk, padahal artinya
/// belum ada yang menilai. Yang belum pernah terjual juga tidak
/// menampilkan "0 terjual", karena itu kalimat yang merugikan menu baru
/// tanpa memberi tahu apa pun.
class ProductStatsLine extends StatelessWidget {
  final ProductStats? stats;
  final double fontSize;

  const ProductStatsLine({super.key, required this.stats, this.fontSize = 10.5});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s == null || (!s.adaNilai && s.terjual == 0)) {
      return const SizedBox.shrink();
    }
    final muted = MerchantPosTheme.mutedOf(context);

    return Row(
      children: [
        if (s.adaNilai) ...[
          Icon(Icons.star_rounded,
              size: fontSize + 3.5, color: const Color(0xFFF59E0B)),
          const SizedBox(width: 2),
          Text(
            s.rata.toStringAsFixed(1),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: MerchantPosTheme.textOf(context),
            ),
          ),
          const SizedBox(width: 3),
          Text('(${s.jumlah})',
              style: TextStyle(fontSize: fontSize - 0.5, color: muted)),
        ],
        if (s.adaNilai && s.terjual > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text('•',
                style: TextStyle(fontSize: fontSize - 0.5, color: muted)),
          ),
        if (s.terjual > 0)
          Flexible(
            child: Text(
              '${ringkasJumlah(s.terjual)} terjual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize - 0.5, color: muted),
            ),
          ),
      ],
    );
  }
}

/// 1.240 jadi "1,2rb".
///
/// Angka penuh tidak muat di kartu selebar setengah layar, dan yang
/// membacanya juga tidak sedang menghitung — ia cuma ingin tahu menu ini
/// sering dipesan atau tidak.
String ringkasJumlah(int n) {
  if (n < 1000) return '$n';
  final ribu = n / 1000;
  if (ribu < 10) {
    final satuDesimal = (n / 100).round() / 10;
    return '${satuDesimal.toStringAsFixed(1).replaceAll('.', ',')}rb';
  }
  if (n < 1000000) return '${(n / 1000).round()}rb';
  final juta = (n / 100000).round() / 10;
  return '${juta.toStringAsFixed(1).replaceAll('.', ',')}jt';
}
