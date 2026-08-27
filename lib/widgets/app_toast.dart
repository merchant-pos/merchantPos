import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../utils/lebar_web.dart';


/// Pesan singkat yang selalu tampil di depan, termasuk saat ada dialog
/// terbuka.
///
/// SnackBar bawaan hidup di lapisan Scaffold, sedangkan dialog berada di
/// lapisan overlay di atasnya — jadi pesan galat yang muncul saat form
/// dalam dialog gagal disimpan tertutup oleh dialognya sendiri. Orang
/// menekan Simpan, tidak terjadi apa-apa yang terlihat, dan tidak ada
/// petunjuk kenapa.
///
/// Ini menggambar pesannya sebagai entri overlay pada navigator akar,
/// yang selalu berada di atas dialog mana pun.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Menampilkan [message]. Pesan baru menggantikan yang lama alih-alih
  /// menumpuk — dua pesan bertumpuk hampir selalu berarti yang kedua
  /// menutupi yang pertama.
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    _dismiss();

    final entry = OverlayEntry(
      builder: (overlayContext) => _ToastView(
        message: message,
        isError: isError,
        bottomInset: MediaQuery.of(overlayContext).viewInsets.bottom,
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, _dismiss);
  }

  /// Pegangan yang tetap sah setelah `await`.
  ///
  /// Sebagian alur menampilkan pesannya setelah pekerjaan panjang, dan
  /// pada saat itu context aslinya bisa sudah tidak terpasang. Menangkap
  /// overlay-nya lebih dulu menghindari itu — pola yang sama dengan
  /// menangkap ScaffoldMessenger sebelum await.
  static AppToastHandle of(BuildContext context) =>
      AppToastHandle(Navigator.of(context, rootNavigator: true).overlay);

  static void _showOn(OverlayState? overlay, String message, bool isError) {
    if (overlay == null || !overlay.mounted) return;
    _dismiss();
    final entry = OverlayEntry(
      builder: (overlayContext) => _ToastView(
        message: message,
        isError: isError,
        bottomInset: MediaQuery.of(overlayContext).viewInsets.bottom,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

/// Pegangan toast yang bisa dibawa melewati `await`.
class AppToastHandle {
  final OverlayState? _overlay;

  const AppToastHandle(this._overlay);

  void show(String message, {bool isError = false}) =>
      AppToast._showOn(_overlay, message, isError);
}

/// Jalan pintas supaya pemanggilnya sependek `showSnackBar` dulu.
void showAppToast(BuildContext context, String message, {bool isError = false}) =>
    AppToast.show(context, message, isError: isError);

class _ToastView extends StatefulWidget {
  final String message;
  final bool isError;
  final double bottomInset;

  const _ToastView({
    required this.message,
    required this.isError,
    required this.bottomInset,
  });

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isError ? const Color(0xFFB42318) : const Color(0xFF1F2033);

    return Positioned(
      left: 16,
      right: 16,
      // Naik di atas papan ketik: pesan yang muncul persis di balik
      // keyboard sama saja dengan tidak muncul.
      bottom: 24 + widget.bottomInset,
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
          // Di layar lebar pesannya dibatasi dan ditaruh di tengah.
          //
          // Membentang dari tepi ke tepi jendela 1900 piksel, satu
          // kalimat pendek jadi pita setipis garis yang isinya menempel
          // di ujung kiri — jauh dari tempat mata orangnya berada.
          child: Align(
            alignment: kIsWeb ? Alignment.bottomCenter : Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: kIsWeb ? kLebarDialogWeb : double.infinity),
              child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    widget.isError ? Icons.error_outline : Icons.info_outline,
                    color: Colors.white,
                    size: 19,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
            ),
          ),
        ),
      ),
    );
  }
}
