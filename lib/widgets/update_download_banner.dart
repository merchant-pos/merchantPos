import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/app_updater.dart';
import '../services/notification_router.dart';
import '../theme.dart';

/// Penanda mengambang untuk unduhan pembaruan yang sedang berjalan.
///
/// Membungkus seluruh isi aplikasi, bukan ditaruh di satu layar: unduhan
/// 80 MB bukan sesuatu yang ditunggui orang sambil menatap layar. Dia
/// akan pindah melihat pesanan masuk, membuka kasir, atau mengunci
/// HP-nya — dan tanpa penanda yang ikut ke mana-mana, tidak ada cara
/// mengetahui unduhannya masih hidup atau sudah selesai.
///
/// Diketuk membuka kembali rincian unduhannya, berikut tombol batal.
class UpdateDownloadBanner extends StatelessWidget {
  final Widget child;

  const UpdateDownloadBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Pembaruan APK tidak berlaku di web — halamannya sudah selalu
    // versi terbaru begitu dimuat ulang.
    if (kIsWeb) return child;

    return Stack(
      children: [
        child,
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: AppUpdater.instance,
              builder: (context, _) {
                final updater = AppUpdater.instance;
                if (!updater.downloading &&
                    !updater.paused &&
                    updater.error == null &&
                    updater.notice == null) {
                  return const SizedBox.shrink();
                }
                return _Pill(updater: updater);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final AppUpdater updater;

  const _Pill({required this.updater});

  @override
  Widget build(BuildContext context) {
    final failed = !updater.downloading && updater.error != null;
    final paused = !updater.downloading && updater.paused;
    final notice = !updater.downloading && !paused && updater.error == null
        ? updater.notice
        : null;
    final percent = updater.percent;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: failed
            ? Colors.red.shade700
            : notice != null
                ? MerchantPosTheme.mutedOf(context)
                : MerchantPosTheme.brandDark,
        borderRadius: BorderRadius.circular(24),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          // Pembatalan tidak membuka apa pun kalau diketuk. Tidak ada
          // rincian yang perlu dibaca — yang terjadi sudah tertulis
          // seluruhnya di kalimat itu sendiri.
          onTap: notice != null ? null : () => showUpdateDownloadDialog(context),
          // Sasaran ketuknya diperbesar sedikit ke bawah. Pil ini duduk
          // persis di atas bilah gestur Android, dan tepi yang mepet
          // membuat sebagian ketukan diambil sistem.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed)
                  const Icon(Icons.error_outline, color: Colors.white, size: 18)
                else if (paused)
                  const Icon(Icons.pause_circle_outline,
                      color: Colors.white, size: 18)
                else if (notice != null)
                  const Icon(Icons.cancel_outlined, color: Colors.white, size: 18)
                else
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                      // Nilainya dipasang begitu diketahui, jadi
                      // lingkarannya benar-benar menggambarkan kemajuan
                      // alih-alih berputar tanpa arti.
                      value: updater.progress,
                    ),
                  ),
                const SizedBox(width: 10),
                Text(
                  failed
                      ? 'Unduhan gagal — ketuk untuk lihat'
                      : paused
                          ? 'Unduhan dijeda${percent == null ? '' : ' $percent%'}'
                              ' — ketuk untuk lanjut'
                          : notice ??
                              (percent == null
                                  ? 'Mengunduh pembaruan…'
                                  : 'Mengunduh pembaruan $percent%'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rincian unduhan: kemajuan, galat, dan tombol batal.
///
/// Dipakai dua tempat — penanda mengambang dan tombol di dalam
/// pengumumannya — supaya keduanya menampilkan hal yang sama persis.
Future<void> showUpdateDownloadDialog(BuildContext context) {
  // Konteks Navigator diambil dari kunci global, bukan dari yang
  // dioper.
  //
  // Penanda mengambangnya hidup di `builder` MaterialApp — DI ATAS
  // Navigator, supaya ia tetap terlihat di rute mana pun. Akibatnya
  // konteksnya sendiri tidak punya Navigator di atasnya, dan showDialog
  // dari sana melempar "Navigator operation requested with a context
  // that does not include a Navigator". Di rilis, galat itu tidak
  // menampilkan apa pun — pilnya cuma terlihat tidak bisa diketuk.
  final nav = navigatorKey.currentContext ?? context;
  return showDialog<void>(
    context: nav,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Unduh Pembaruan', style: TextStyle(fontSize: 17)),
      content: AnimatedBuilder(
        animation: AppUpdater.instance,
        builder: (context, _) {
          final updater = AppUpdater.instance;

          if (updater.error != null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 34),
                const SizedBox(height: 10),
                Text(updater.error!, textAlign: TextAlign.center),
              ],
            );
          }

          if (!updater.downloading && !updater.paused) {
            return const Text(
              'Unduhan sudah selesai. Layar pemasang akan terbuka sendiri; '
              'kalau tidak, buka berkasnya dari notifikasi unduhan.',
              textAlign: TextAlign.center,
            );
          }

          final percent = updater.percent;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                percent == null
                    ? (updater.paused ? 'Dijeda' : 'Mengunduh…')
                    : '${updater.paused ? 'Dijeda pada' : 'Mengunduh'} '
                        '$percent%',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: updater.progress, minHeight: 6),
              ),
              const SizedBox(height: 12),
              Text(
                updater.paused
                    ? 'Yang sudah turun tetap tersimpan. Melanjutkan '
                        'meneruskan dari titik ini, bukan mengulang dari '
                        'nol.'
                    : 'Berkasnya sekitar 80 MB. Unduhan tetap berjalan '
                        'walau layar ini ditutup.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
            ],
          );
        },
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        AnimatedBuilder(
          animation: AppUpdater.instance,
          builder: (context, _) {
            final updater = AppUpdater.instance;
            final berjalan = updater.downloading;
            final dijeda = updater.paused && !berjalan;

            return Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                if (berjalan)
                  TextButton.icon(
                    onPressed: updater.pause,
                    icon: const Icon(Icons.pause, size: 17),
                    label: const Text('Jeda'),
                  ),
                if (dijeda)
                  TextButton.icon(
                    onPressed: updater.resume,
                    icon: const Icon(Icons.play_arrow, size: 17),
                    label: const Text('Lanjutkan'),
                  ),
                if (berjalan || dijeda)
                  TextButton(
                    onPressed: () {
                      updater.cancel();
                      Navigator.pop(dialogContext);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Batalkan'),
                  ),
                if (updater.error != null)
                  TextButton(
                    onPressed: () {
                      updater.clearError();
                      updater.retry();
                    },
                    child: const Text('Coba Lagi'),
                  ),
                // Selalu "Tutup" — ia menyebut apa yang terjadi pada
                // kotaknya, dan tidak lagi rancu sejak Jeda ada. Dulu
                // tombolnya berbunyi "Lanjutkan" selagi unduhan jalan,
                // dan sekarang kata itu sudah punya arti lain: benar
                // benar melanjutkan yang dijeda.
                TextButton(
                  onPressed: () {
                    if (!berjalan && !dijeda) updater.clearError();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
