import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/announcement_repository.dart';
import '../models/announcement.dart';

/// Memberi tahu bahwa ada versi MerchantPOS yang lebih baru.
///
/// Ditujukan untuk orang yang memesan tanpa akun: mereka tidak punya
/// kotak masuk, jadi tanpa ini tidak ada satu pun jalan pemberitahuan
/// sampai ke mereka — padahal justru merekalah yang paling jarang
/// memperbarui aplikasinya.
///
/// Tidak menampilkan apa pun kalau versinya sudah paling baru, atau kalau
/// pengumumannya belum bisa diambil.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  Announcement? _update;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final latest = await AnnouncementRepository().latest();
      if (latest?.version == null) return;

      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      // Hanya ditampilkan kalau versi yang diumumkan benar-benar lebih
      // baru. Membandingkannya sebagai teks akan salah persis di kasus
      // yang sering terjadi — "1.9.0" terbaca lebih besar dari "1.10.0".
      if (compareVersions(latest!.version!, info.version) > 0) {
        setState(() => _update = latest);
      }
    } catch (_) {
      // Offline, atau pengumumannya belum ada — diam saja.
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    if (update == null || _dismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.system_update, size: 20, color: Color(0xFFB45309)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MerchantPOS ${update.version} sudah tersedia',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF92400E)),
                ),
                const SizedBox(height: 2),
                Text(
                  update.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
                if (update.downloadUrl != null && update.downloadUrl!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Unduh Sekarang'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(update.downloadUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 17),
            color: const Color(0xFF92400E),
            tooltip: 'Tutup',
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
