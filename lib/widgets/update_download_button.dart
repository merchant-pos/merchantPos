import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_updater.dart';

/// Tombol unduh versi terbaru di dalam pengumuman kotak masuk.
///
/// Mengunduh langsung di sini, bukan melempar ke browser. Yang dilempar
/// ke browser jarang selesai: orangnya berpindah aplikasi, menunggu di
/// sana, lalu harus mencari sendiri berkasnya di folder unduhan — dan
/// pembaruan yang tidak terpasang sama saja dengan pembaruan yang tidak
/// pernah dirilis.
///
/// Browser tetap disediakan sebagai jalan keluar kalau unduhannya gagal.
/// Cara lama yang merepotkan masih jauh lebih baik daripada buntu.
class UpdateDownloadButton extends StatefulWidget {
  final String url;

  const UpdateDownloadButton({super.key, required this.url});

  @override
  State<UpdateDownloadButton> createState() => _UpdateDownloadButtonState();
}

class _UpdateDownloadButtonState extends State<UpdateDownloadButton> {
  AppUpdater get _updater => AppUpdater.instance;

  // Sengaja tidak membatalkan apa pun saat dilepas. Unduhannya bukan
  // milik tombol ini; menutup pengumumannya tidak boleh menghanguskan
  // 80 MB yang sedang berjalan.

  Future<void> _start() async {
    _updater.start(widget.url);
    // Rinciannya TIDAK dibuka sendiri.
    //
    // Dulu popup Batalkan/Lanjutkan muncul begitu unduhannya dimulai,
    // dan itu salah paham soal apa yang dibutuhkan saat itu: orang yang
    // baru saja menekan Unduh sudah tahu unduhannya berjalan. Yang
    // muncul justru menghalangi layar yang sedang dia pakai, dan
    // menutupnya terasa seperti membatalkan.
    //
    // Kemajuannya tampil sebagai bulir di bawah layar, dan popupnya
    // dibuka kalau bulir itu diketuk — yaitu saat orangnya memang
    // sedang bertanya "sudah sampai mana" atau ingin menghentikannya.
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _updater,
      builder: (context, _) => _buildButton(context),
    );
  }

  Widget _buildButton(BuildContext context) {
    final busy = _updater.downloading;
    final percent = _updater.percent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(
              !busy
                  ? 'Unduh Versi Terbaru'
                  : percent == null
                      ? 'Mengunduh…'
                      : 'Mengunduh $percent%',
            ),
            onPressed: busy ? null : _start,
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 8),
          // Batangnya menyusul tombolnya, bukan menggantikannya: angka
          // persen di tombol menjawab "sudah sejauh mana", batang ini
          // menjawab "masih jalan atau menggantung".
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _updater.progress, minHeight: 5),
          ),
          const SizedBox(height: 4),
          Text(
            'Berkasnya sekitar 80 MB. Unduhan tetap berjalan walau '
            'kotak masuk ini ditutup.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
          ),
          TextButton(
            onPressed: _updater.cancel,
            child: const Text('Batalkan'),
          ),
        ] else
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(widget.url),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Unduh lewat browser',
              style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
            ),
          ),
      ],
    );
  }
}
