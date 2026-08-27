import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/announcement_repository.dart';
import '../providers/auth_provider.dart';
import '../screens/customer_inbox_screen.dart';
import '../screens/inbox_screen.dart';
import 'hub_menu_tile.dart';

/// Pintu masuk kotak pesan di setiap hub, lengkap dengan jumlah pesan
/// yang belum dibaca.
///
/// Angkanya dimuat sekali saat hub dibuka. Memantaunya terus-menerus
/// berarti satu koneksi realtime lagi hanya demi sebuah titik merah —
/// mahal untuk sesuatu yang isinya berubah beberapa kali sebulan.
class InboxTile extends StatefulWidget {
  /// Kotak masuk pelanggan, bukan karyawan.
  ///
  /// Isinya lahir dari aturan yang berbeda: pelanggan tidak punya
  /// "resto sendiri", yang dia punya adalah daftar resto yang pernah
  /// dia datangi. Memakai kotak masuk karyawan untuknya berarti promo
  /// resto tidak pernah muncul — yang sampai cuma kabar versi baru.
  final bool forCustomer;

  const InboxTile({super.key, this.forCustomer = false});

  @override
  State<InboxTile> createState() => _InboxTileState();
}

class _InboxTileState extends State<InboxTile> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final auth = context.read<AuthProvider>();
    final email = auth.user?.email;
    if (email == null && !widget.forCustomer) return;
    // Daftar restonya diambil sebelum menunggu apa pun: sesudah baris
    // async pertama, context-nya mungkin sudah tidak terpasang lagi.
    final restoIds =
        widget.forCustomer ? await customerRestoIds(context) : const <String>{};
    if (!mounted) return;
    try {
      final items = widget.forCustomer
          ? await AnnouncementRepository()
              .customerInbox(email: email, restoIds: restoIds)
          : await AnnouncementRepository()
              .inboxFor(email!, restoId: auth.restoId);
      if (!mounted) return;
      setState(() => _unread = items.where((i) => !i.read).length);
    } catch (_) {
      // Offline — biarkan tanpa angka, jangan menampilkan galat untuk
      // sesuatu sesepele penanda jumlah.
    }
  }

  @override
  Widget build(BuildContext context) {
    return HubMenuTile(
      icon: Icons.inbox_outlined,
      title: 'Kotak Masuk',
      subtitle: _unread > 0
          ? '$_unread pesan belum dibaca'
          : widget.forCustomer
              ? 'Promo merchant & info versi terbaru'
              : 'Pengumuman & info versi terbaru MerchantPOS',
      color: const Color(0xFF0EA5E9),
      // Angkanya pindah dari judul ke penanda merah. Sebagai tulisan
      // "(3 baru)" ia terbaca sebagai bagian dari nama menunya dan ikut
      // luput bersama seluruh baris; sebagai bulatan merah ia satu-
      // satunya benda berwarna itu di layar.
      badgeCount: _unread,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => widget.forCustomer
                ? const CustomerInboxScreen()
                : const InboxScreen(),
          ),
        );
        _loadUnread();
      },
    );
  }
}
