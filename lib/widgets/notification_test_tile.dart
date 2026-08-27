import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

import '../services/notification_service.dart';
import '../services/push_service.dart';
import 'hub_menu_tile.dart';
import 'app_toast.dart';

/// Menjalankan tes notifikasi dan menampilkan hasilnya.
///
/// Dipisah dari widgetnya supaya layar yang tidak berbentuk daftar menu
/// — layar dapur, misalnya — bisa memanggilnya dari ikon di app bar.
Future<void> showNotificationTest(BuildContext context) async {
  final toast = AppToast.of(context);
  final navigator = Navigator.of(context);
  // Dibaca sebelum menunggu apa pun: sesudah await, context-nya mungkin
  // sudah tidak menempel di pohon widget lagi.
  final auth = context.read<AuthProvider>();
  toast.show('Mengirim notifikasi tes…');

  // Apa pun yang terjadi, harus ada jawabannya. Sebelumnya galat dari
  // dalam plugin melompati seluruh sisa fungsi ini, jadi menekan Tes
  // Notifikasi benar-benar tidak menghasilkan apa-apa — tidak berhasil,
  // tidak juga memberi tahu kenapa.
  //
  // Batas waktunya ada karena permintaan izin bisa menggantung tanpa
  // pernah kembali di sebagian perangkat; menggantung selamanya terlihat
  // persis sama dengan tidak melakukan apa pun.
  String message;
  try {
    message = await NotificationService.instance
        .sendTest()
        .timeout(const Duration(seconds: 12));
  } on TimeoutException {
    message = 'Tidak ada jawaban dari sistem notifikasi dalam 12 detik. '
        'Coba buka Setelan HP > Aplikasi > MerchantPOS > Notifikasi dan pastikan '
        'izinnya menyala.';
  } catch (e) {
    message = 'Notifikasi gagal dijalankan: $e';
  }

  // Keadaan push dilaporkan berbarengan. Keduanya sama-sama "notifikasi"
  // bagi yang memakainya, tapi jalannya berbeda: yang satu dibangkitkan
  // aplikasinya sendiri dan hanya hidup selama aplikasinya terbuka, yang
  // satu lagi datang dari server dan tetap sampai walau tertutup.
  // Melaporkan yang pertama saja membuat "sudah dites, bunyi" terasa
  // seperti jaminan yang tidak pernah diberikan.
  // Sekalian mencoba mendaftarkan ulang. Layar tes adalah satu-satunya
  // tempat orang datang saat notifikasinya tidak bunyi, jadi di sinilah
  // percobaan ulang paling mungkin berguna — daripada menunggu
  // aplikasinya dibuka ulang entah kapan.
  final push = PushService.instance;
  await push.register(
    email: auth.user?.email,
    restoId: auth.restoId,
    role: auth.role?.dbValue,
  );

  final String pushLine;
  if (push.lastError != null) {
    pushLine = '\n\nPush BELUM aktif.\n${push.lastError}';
  } else if (push.tokenPreview != null) {
    pushLine = '\n\nPush aktif — perangkat ini terdaftar (${push.tokenPreview}), '
        'jadi notifikasi tetap masuk walau aplikasi ditutup.';
  } else {
    pushLine = '\n\nPush BELUM aktif. Notifikasi hanya masuk selama '
        'aplikasi masih terbuka.';
  }
  message = '$message$pushLine';

  if (!navigator.mounted) return;

  showDialog<void>(
    context: navigator.context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        message.startsWith('Notifikasi terkirim')
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        size: 38,
        color: message.startsWith('Notifikasi terkirim')
            ? const Color(0xFF10B981)
            : Colors.orange,
      ),
      title: const Text('Tes Notifikasi'),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Mengirim satu notifikasi contoh, lalu melaporkan hasilnya.
///
/// Notifikasi bisa gagal karena banyak hal di luar kendali aplikasi —
/// izin ditolak, channel-nya dibisukan pemakainya, mode fokus menyala.
/// Semuanya terlihat sama dari dalam: tidak ada apa-apa yang muncul.
/// Tanpa cara mengujinya, "notifikasi tidak jalan" tidak bisa dibedakan
/// dari "memang belum ada pesanan baru".
class NotificationTestTile extends StatefulWidget {
  const NotificationTestTile({super.key});

  @override
  State<NotificationTestTile> createState() => _NotificationTestTileState();
}

class _NotificationTestTileState extends State<NotificationTestTile> {
  bool _sending = false;

  Future<void> _test() async {
    setState(() => _sending = true);
    await showNotificationTest(context);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return HubMenuTile(
      icon: _sending ? Icons.hourglass_top : Icons.notifications_active_outlined,
      title: 'Tes Notifikasi',
      subtitle: 'Pastikan bunyi & banner notifikasi aktif',
      color: const Color(0xFFF59E0B),
      onTap: _sending ? () {} : _test,
    );
  }
}
