import 'package:flutter/material.dart';

import '../theme.dart';

import 'count_badge.dart';

/// A colorful menu row used on "hub" home screens (Super Admin, Finance)
/// — an icon in a soft gradient badge, title/subtitle, and a chevron.
/// Nicer than a plain ListTile-in-a-Card, and each entry can carry its
/// own accent color so the menu doesn't read as one flat block.
class HubMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  /// Jumlah hal yang menunggu di balik menu ini. Nol atau null berarti
  /// tidak ada penanda sama sekali — bulatan berisi "0" justru menarik
  /// perhatian ke tempat yang tidak perlu didatangi.
  final int badgeCount;

  const HubMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Penandanya menempel di ikon, bukan di ujung kanan baris.
              // Di ujung kanan ia akan berbaris rapi dengan tanda panah
              // milik setiap kartu dan larut jadi satu kolom seragam; di
              // sini ia justru memotong bentuk yang sudah dikenal mata.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, Color.lerp(color, Colors.black, 0.18)!],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -5,
                      right: -6,
                      child: CountBadge(count: badgeCount),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: MerchantPosTheme.mutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A soft gradient hero header used at the top of hub home screens —
/// shows the app mark, the employee's name in large text, and a smaller
/// "Role • email" line underneath it.
class HubHeader extends StatelessWidget {
  final Widget logo;
  final String title;
  final String? subtitle;
  final Color colorA;
  final Color colorB;

  /// Ditampilkan di bawah subtitle. Dipakai pemilih resto, yang hanya
  /// muncul untuk akun pemegang lebih dari satu cabang.
  final Widget? trailing;

  const HubHeader({
    super.key,
    required this.logo,
    required this.title,
    required this.colorA,
    required this.colorB,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorA, colorB],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logo,
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5),
            ),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
