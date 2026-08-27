import 'package:flutter/material.dart';

import 'hub_menu_tile.dart';

/// Kartu menu hub yang menghitung sendiri berapa hal yang menunggu di
/// baliknya.
///
/// Angkanya dimuat sekali saat hub dibuka, lalu dimuat ulang begitu
/// orangnya kembali dari layar tujuan — persis saat angkanya paling
/// mungkin sudah berubah, karena dialah yang barusan mengubahnya.
/// Memantaunya terus-menerus berarti satu koneksi realtime lagi per
/// kartu, mahal untuk sesuatu yang cuma sebuah bulatan merah.
///
/// Kegagalan memuat sengaja tidak dilaporkan: hub yang menyambut orang
/// dengan pesan galat karena sebuah penanda gagal dihitung jauh lebih
/// buruk daripada penanda yang tidak muncul.
class BadgedHubTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  /// Menghitung isi penandanya. Nol berarti tidak ada bulatan.
  final Future<int> Function() loadCount;

  /// Layar tujuannya. Dibuat lewat fungsi, bukan diterima jadi, supaya
  /// layarnya baru dibangun saat kartunya benar-benar diketuk.
  final Widget Function() destination;

  const BadgedHubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.loadCount,
    required this.destination,
  });

  @override
  State<BadgedHubTile> createState() => _BadgedHubTileState();
}

class _BadgedHubTileState extends State<BadgedHubTile> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final count = await widget.loadCount();
      if (!mounted) return;
      setState(() => _count = count);
    } catch (_) {
      // Sedang luring, atau tabelnya belum dimigrasi. Diamkan.
    }
  }

  @override
  Widget build(BuildContext context) {
    return HubMenuTile(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      color: widget.color,
      badgeCount: _count,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => widget.destination()),
        );
        await _refresh();
      },
    );
  }
}
