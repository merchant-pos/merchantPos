import 'package:flutter/material.dart';

import '../theme.dart';
import 'merchantpos_logo.dart';

/// Runs [action] behind a branded, non-dismissible loading card.
///
/// Used for signing in: between picking a Google account and landing on
/// the right screen there's a token exchange plus a role lookup, and
/// without this the app just sits on the previous screen looking frozen.
///
/// Safe to wrap around work that opens native UI first (Google's account
/// picker) — the card simply sits underneath until that closes, and is
/// still there for the part that actually takes time.
Future<T> withLoadingOverlay<T>(
  BuildContext context,
  Future<T> Function() action, {
  String message = 'Menyiapkan MerchantPOS...',
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    // Nothing else pops while this is up, and back is blocked below, so
    // the single pop in `finally` always closes exactly this dialog.
    builder: (_) => PopScope(
      canPop: false,
      child: _LoadingCard(message: message),
    ),
  );

  try {
    return await action();
  } finally {
    navigator.pop();
  }
}

class _LoadingCard extends StatelessWidget {
  final String message;

  const _LoadingCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MerchantPosTheme.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PulsingLogo(),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: MerchantPosTheme.brandDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sebentar ya...',
              style: TextStyle(fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 130,
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: Color(0xFFE5E7EB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gently breathing app mark — reads as "working" without the impatience
/// a fast spinner brings to something that can take a few seconds.
class _PulsingLogo extends StatefulWidget {
  const _PulsingLogo();

  @override
  State<_PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<_PulsingLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1.06).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const MerchantPosLogo(size: 64),
    );
  }
}
