import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/announcement_repository.dart';
import '../db/guest_order_store.dart';
import '../models/announcement.dart';
import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';
import '../widgets/update_download_button.dart';

/// Resto yang kabarnya pantas sampai ke seorang pelanggan.
///
/// Yang pernah dia pesan, ditambah yang sedang dia buka. Tamu dikenali
/// lewat daftar pesanan yang tersimpan di HP-nya sendiri — satu-satunya
/// jejak yang dia punya.
///
/// Fungsi bersama, bukan milik satu layar: kartu Kotak Masuk di hub
/// menghitung yang belum dibaca, dan angkanya harus lahir dari aturan
/// yang sama persis dengan isi layarnya. Dua perhitungan terpisah akan
/// berpisah, dan yang terlihat adalah penanda merah yang menunjuk kotak
/// masuk kosong.
Future<Set<String>> customerRestoIds(BuildContext context) async {
  final ids = <String>{};
  final session = context.read<TableSessionProvider>();
  if (session.restoId != null) ids.add(session.restoId!);

  final client = Supabase.instance.client;
  final email = context.read<AuthProvider>().user?.email;
  try {
    if (email != null) {
      final rows = await client
          .from('orders')
          .select('resto_id')
          .eq('customer_label', email)
          .limit(200);
      for (final r in rows) {
        if (r['resto_id'] != null) ids.add(r['resto_id'] as String);
      }
    } else {
      final guestIds = await GuestOrderStore().ids();
      if (guestIds.isNotEmpty) {
        final rows = await client
            .from('orders')
            .select('resto_id')
            .inFilter('id', guestIds.take(50).toList());
        for (final r in rows) {
          if (r['resto_id'] != null) ids.add(r['resto_id'] as String);
        }
      }
    }
  } catch (_) {
    // Luring — cukup pakai resto yang sedang dibuka.
  }
  return ids;
}

/// Kotak masuk pelanggan.
///
/// Sebelumnya promo resto ditempelkan sebagai pita di atas daftar menu.
/// Itu berarti kabarnya cuma sampai ke orang yang kebetulan sedang
/// membuka menu resto itu — orang yang paling tidak membutuhkannya,
/// karena dia sudah ada di sana dan sedang memesan.
///
/// Di sini kabarnya menunggu di tempat yang bisa dibuka kapan saja,
/// berikut nama restonya. "Diskon 20% hari ini" tanpa nama pengirim
/// adalah kabar yang tidak bisa dipakai: dia tidak tahu harus datang ke
/// mana.
class CustomerInboxScreen extends StatefulWidget {
  const CustomerInboxScreen({super.key});

  @override
  State<CustomerInboxScreen> createState() => _CustomerInboxScreenState();
}

class _CustomerInboxScreenState extends State<CustomerInboxScreen> {
  final _repo = AnnouncementRepository();

  List<Announcement> _items = [];
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _loading = true;
  String? _error;

  /// Tamu tidak punya email, jadi tidak punya tempat menyimpan penanda
  /// sudah dibaca maupun terhapus. Menawarkan tombolnya tetap berarti
  /// menjanjikan sesuatu yang hilang begitu layarnya ditutup.
  bool get _bisaMenandai => context.read<AuthProvider>().user?.email != null;

  AnnouncementCategory _activeCategory(BuildContext context) =>
      AnnouncementCategory.values[DefaultTabController.of(context).index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = context.read<AuthProvider>().user?.email;
      final items = await _repo.customerInbox(
        email: email,
        restoIds: await customerRestoIds(context),
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _open(Announcement item) async {
    final email = context.read<AuthProvider>().user?.email;
    if (email != null && !item.read) {
      setState(() {
        _items = [
          for (final i in _items) i.id == item.id ? i.copyWith(read: true) : i,
        ];
      });
      _repo.markRead(email, item.id).catchError((_) {});
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.restoName != null)
              Text(item.restoName!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: MerchantPosTheme.brandOf(context))),
            Text(item.title, style: const TextStyle(fontSize: 17)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('d MMMM yyyy, HH:mm', 'id_ID')
                    .format(item.createdAt.toWib()),
                style: TextStyle(
                    fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              if (item.hasImage) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(item.imageBase64!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(item.body,
                  style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.downloadUrl != null && item.downloadUrl!.isNotEmpty)
                UpdateDownloadButton(url: item.downloadUrl!),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Announcement> _itemsIn(AnnouncementCategory c) =>
      _items.where((i) => i.category == c).toList();

  /// Menandai sudah dibaca — yang terpilih, atau seluruh isi tab.
  ///
  /// Sama persis dengan kotak masuk karyawan, termasuk batasnya: yang
  /// dikenai cuma tab yang sedang dibuka. Menandai tab sebelah yang
  /// tidak sedang dilihat berarti menghapus penanda yang justru dipasang
  /// orangnya untuk dirinya sendiri.
  Future<void> _markRead(AnnouncementCategory category, {bool all = false}) async {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null) return;

    final ids = (all ? _itemsIn(category) : _items.where((i) => _selected.contains(i.id)))
        .where((i) => !i.read)
        .map((i) => i.id)
        .toList();
    if (ids.isEmpty) {
      showAppToast(context, 'Tidak ada pesan yang belum dibaca.');
      return;
    }

    setState(() {
      _items = [
        for (final i in _items) ids.contains(i.id) ? i.copyWith(read: true) : i,
      ];
      _selected.clear();
      _selecting = false;
    });

    try {
      await _repo.markManyRead(email, ids);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menandai: $e', isError: true);
      _load();
    }
  }

  Future<void> _deleteSelected({
    required AnnouncementCategory category,
    bool all = false,
  }) async {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null) return;
    final ids = all
        ? _itemsIn(category).map((i) => i.id).toList()
        : _selected.toList();
    if (ids.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline, size: 38, color: Colors.red),
        title: Text(all
            ? 'Hapus semua di ${kAnnouncementCategoryLabels[category]}?'
            : 'Hapus ${ids.length} pesan?'),
        content: Text(
          all
              ? '${ids.length} pesan di tab '
                  '${kAnnouncementCategoryLabels[category]} akan hilang dari '
                  'kotak masuk kamu. Tab sebelahnya tidak ikut terhapus.'
              : 'Pesan hanya hilang dari kotak masuk kamu. Yang lain tetap '
                  'menerimanya seperti biasa.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _repo.deleteForUser(email, ids);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selecting = false;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: AnnouncementCategory.values.length,
      // Builder supaya context-nya berada di bawah controller — tanpa
      // itu, tombol yang membaca tab aktif diam saja saat ditekan.
      child: Builder(builder: _buildScaffold),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(_selecting ? '${_selected.length} dipilih' : 'Kotak Masuk'),
          actions: [
            if (_bisaMenandai && _items.isNotEmpty && !_selecting)
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: 'Pilih pesan',
                onPressed: () => setState(() => _selecting = true),
              ),
            if (_selecting) ...[
              Builder(builder: (context) {
                final diTab = _itemsIn(_activeCategory(context))
                    .map((i) => i.id)
                    .toList();
                final semuaTerpilih =
                    diTab.isNotEmpty && diTab.every(_selected.contains);
                return IconButton(
                  icon: Icon(semuaTerpilih
                      ? Icons.remove_done
                      : Icons.select_all),
                  tooltip: semuaTerpilih
                      ? 'Batal pilih semua'
                      : 'Pilih semua di tab ini',
                  // Menekannya lagi melepas semuanya — tombol yang cuma
                  // bisa satu arah memaksa orang melepas satu per satu
                  // pilihan yang tadi dibuatnya sekali ketuk.
                  onPressed: () => setState(() {
                    if (semuaTerpilih) {
                      _selected.removeAll(diTab);
                    } else {
                      _selected.addAll(diTab);
                    }
                  }),
                );
              }),
              IconButton(
                icon: const Icon(Icons.mark_email_read_outlined),
                tooltip: 'Tandai sudah dibaca',
                onPressed: _selected.isEmpty
                    ? null
                    : () => _markRead(_activeCategory(context)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Hapus terpilih',
                onPressed: _selected.isEmpty
                    ? null
                    : () => _deleteSelected(category: _activeCategory(context)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Batal',
                onPressed: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
              ),
            ],
          ],
          bottom: TabBar(
            tabs: [
              for (final c in AnnouncementCategory.values)
                Tab(text: kAnnouncementCategoryLabels[c]),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Gagal memuat: $_error',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _load, child: const Text('Coba Lagi')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      for (final c in AnnouncementCategory.values) _list(c),
                    ],
                  ),
    );
  }

  Widget _list(AnnouncementCategory category) {
    final items = _itemsIn(category);

    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                Icon(Icons.mark_email_read_outlined,
                    size: 46, color: MerchantPosTheme.borderOf(context)),
                const SizedBox(height: 12),
                Text(
                  category == AnnouncementCategory.update
                      ? 'Belum ada pemberitahuan versi baru.'
                      : 'Belum ada promo dari merchant yang pernah kamu pesan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                ),
              ],
            )
          : ResponsiveCenter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  for (final item in items) _tile(item),
                  if (_bisaMenandai && !_selecting) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (items.any((i) => !i.read))
                          TextButton.icon(
                            icon: const Icon(Icons.mark_email_read_outlined,
                                size: 18),
                            label: const Text('Tandai Semua Dibaca'),
                            onPressed: () => _markRead(category, all: true),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: const Text('Hapus Semua'),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () =>
                              _deleteSelected(category: category, all: true),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _tile(Announcement item) {
    final terpilih = _selected.contains(item.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        // Selagi memilih, mengetuk kartunya berarti mencentang — bukan
        // membuka pesannya. Membuka pesan di tengah memilih akan
        // menandainya dibaca, padahal orangnya mungkin justru hendak
        // menghapusnya.
        onTap: () => _selecting
            ? setState(() =>
                terpilih ? _selected.remove(item.id) : _selected.add(item.id))
            : _open(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: terpilih,
                    onChanged: (_) => setState(() => terpilih
                        ? _selected.remove(item.id)
                        : _selected.add(item.id)),
                  ),
                ),
              if (!item.read && !_selecting)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  decoration: BoxDecoration(
                    color: MerchantPosTheme.brandOf(context),
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nama resto di atas judulnya, bukan di bawah.
                    // Yang pertama ingin diketahui pembacanya adalah
                    // "ini dari siapa" — promo dari warung sebelah dan
                    // dari langganannya dibaca dengan cara yang berbeda.
                    if (item.restoName != null)
                      Text(
                        item.restoName!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: MerchantPosTheme.brandOf(context),
                        ),
                      ),
                    Text(
                      item.title,
                      style: TextStyle(
                        fontWeight:
                            item.read ? FontWeight.w600 : FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('d MMM yyyy, HH:mm', 'id_ID')
                          .format(item.createdAt.toWib()),
                      style: TextStyle(
                          fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
                    ),
                  ],
                ),
              ),
              if (item.hasImage) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(item.imageBase64!),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
