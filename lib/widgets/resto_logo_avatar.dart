import '../utils/gambar_base64.dart';

import 'package:flutter/material.dart';

import '../theme.dart';


/// Circular resto logo for list rows, falling back to a storefront icon
/// when none has been uploaded. Greyed out for a deactivated resto so it
/// reads the same way the rest of that row does.
class RestoLogoAvatar extends StatelessWidget {
  final String? logoBase64;
  final bool active;
  final double radius;

  const RestoLogoAvatar({
    super.key,
    required this.logoBase64,
    this.active = true,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoBase64 != null && logoBase64!.isNotEmpty;

    if (!hasLogo) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: active ? null : MerchantPosTheme.borderOf(context),
        child: Icon(Icons.storefront_outlined, size: radius),
      );
    }

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white,
      // A corrupt blob would otherwise throw during paint and blank the
      // whole list, so fall back to the icon instead.
      backgroundImage: MemoryImage(byteGambar(logoBase64!)),
      onBackgroundImageError: (_, __) {},
      child: null,
    );

    return active ? avatar : Opacity(opacity: 0.45, child: avatar);
  }
}
