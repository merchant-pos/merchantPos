import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/announcement_repository.dart';
import '../providers/auth_provider.dart';
import '../screens/inbox_screen.dart';
import 'count_badge.dart';

/// Kotak masuk untuk layar yang tidak berbentuk daftar menu.
///
/// Dapur bekerja di layar bertab, bukan hub berisi kartu, jadi
/// [InboxTile] tidak ada tempatnya di sana. Padahal justru dapur yang
/// paling jarang membuka layar lain — kalau pengumumannya cuma bisa
/// dijangkau lewat hub, orang dapur tidak akan pernah membacanya.
///
/// Angkanya dimuat sekali saat layarnya dibuka dan dihitung ulang
/// sepulang dari kotak masuknya. Memantaunya terus-menerus berarti satu
/// koneksi realtime lagi hanya demi sebuah titik merah.
class InboxIconButton extends StatefulWidget {
  const InboxIconButton({super.key});

  @override
  State<InboxIconButton> createState() => _InboxIconButtonState();
}

class _InboxIconButtonState extends State<InboxIconButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final auth = context.read<AuthProvider>();
    final email = auth.user?.email;
    if (email == null) return;
    try {
      final items =
          await AnnouncementRepository().inboxFor(email, restoId: auth.restoId);
      if (!mounted) return;
      setState(() => _unread = items.where((i) => !i.read).length);
    } catch (_) {
      // Luring — biarkan tanpa angka. Menampilkan galat untuk sesuatu
      // sesepele penanda jumlah hanya akan menghalangi pekerjaan yang
      // sedang berjalan di layar ini.
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unread > 0 ? 'Kotak Masuk ($_unread belum dibaca)' : 'Kotak Masuk',
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const InboxScreen()),
        );
        await _loadUnread();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.inbox_outlined),
          if (_unread > 0)
            Positioned(
              top: -6,
              right: -8,
              child: CountBadge(count: _unread, fontSize: 9),
            ),
        ],
      ),
    );
  }
}
