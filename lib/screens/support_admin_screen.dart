import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../db/support_repository.dart';
import '../models/support_ticket.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../widgets/responsive.dart';
import 'support_chat_screen.dart';

/// Customer Service — Merchant-POS Admin.
///
/// Daftar percakapan, bukan daftar tiket. Bentuknya sengaja mengikuti
/// aplikasi pesan yang sudah dipakai semua orang: nama di kiri, cuplikan
/// pesan terakhir di bawahnya, waktu di kanan, titik merah untuk yang
/// belum dibaca. Yang menjawab keluhan sepanjang hari tidak sedang
/// mempelajari aplikasi baru — dia sedang membalas orang.
class SupportAdminScreen extends StatefulWidget {
  const SupportAdminScreen({super.key});

  @override
  State<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends State<SupportAdminScreen>
    with SingleTickerProviderStateMixin {
  /// Dua urusan yang berbeda, dan dipisah karena memang berbeda.
  ///
  /// Pengaduan punya tahapan, menuntut keputusan, dan bisa selesai. Chat
  /// cuma percakapan. Menaruhnya di satu daftar membuat yang menuntut
  /// jawaban tenggelam di bawah yang sekadar bertanya.
  late final TabController _tab = TabController(length: 2, vsync: this);

  final _repo = SupportRepository();
  StreamSubscription<List<SupportTicket>>? _sub;

  List<SupportTicket> _semua = const [];

  /// Nama merchant per id, untuk menyebut pengaduan ini dari mana.
  ///
  /// Diambil sekali di awal, bukan per baris. Daftar ini bisa berisi
  /// puluhan percakapan, dan satu permintaan per baris berarti puluhan
  /// permintaan tiap kali layarnya dibuka.
  Map<String, String> _namaMerchant = const {};

  bool _memuat = true;
  Object? _galat;

  /// Menyembunyikan yang sudah selesai.
  ///
  /// Bawaannya menyala. Daftar yang memuat seluruh tiket sejak hari
  /// pertama akan didominasi percakapan yang tidak menuntut apa-apa, dan
  /// yang menuntut jawaban tenggelam di bawahnya.
  bool _sembunyikanTutup = true;

  final _cari = TextEditingController();

  @override
  void initState() {
    super.initState();
    _muatMerchant();
    _sub = _repo.semua().listen(
      (t) {
        if (!mounted) return;
        setState(() {
          _semua = t;
          _memuat = false;
          _galat = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _galat = e;
          _memuat = false;
        });
      },
    );
  }

  Future<void> _muatMerchant() async {
    try {
      final semua = await RestaurantRepository().getAll(includeDeleted: true);
      if (!mounted) return;
      setState(() => _namaMerchant = {for (final m in semua) m.id: m.name});
    } catch (_) {
      // Tanpa namanya, yang tampil tetap "Merchant" — cukup untuk tahu
      // ini bukan keluhan pelanggan.
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _sub?.cancel();
    _cari.dispose();
    super.dispose();
  }

  List<SupportTicket> _daftar({required bool chat}) {
    final q = _cari.text.trim().toLowerCase();
    return [
      for (final t in _semua)
        if (t.chatBebas == chat &&
            // Chat tidak pernah ditutup, jadi saringannya tidak berlaku
            // di sana.
            (chat || !_sembunyikanTutup || t.terbuka) &&
            (q.isEmpty ||
                t.subject.toLowerCase().contains(q) ||
                t.namaTampil.toLowerCase().contains(q) ||
                t.reporterEmail.toLowerCase().contains(q)))
          t,
    ];
  }

  int _belumDibacaDi({required bool chat}) => SupportRepository.belumDibaca(
        [for (final t in _semua) if (t.chatBebas == chat) t],
        sebagaiAdmin: true,
      );

  int get _belumDibaca =>
      SupportRepository.belumDibaca(_semua, sebagaiAdmin: true);

  /// Angka di judul tab. Kosong kalau tidak ada yang menunggu — tab yang
  /// selalu berangka membuat angkanya berhenti berarti apa-apa.
  String _penanda({required bool chat}) {
    final n = _belumDibacaDi(chat: chat);
    return n == 0 ? '' : ' ($n)';
  }

  Widget _daftarTiket({required bool chat, String? nama}) {
    final muted = MerchantPosTheme.mutedOf(context);
    final daftar = _daftar(chat: chat);

    if (daftar.isEmpty) {
      return Center(
        child: Text(
          _cari.text.trim().isNotEmpty
              ? 'Tidak ada yang cocok.'
              : chat
                  ? 'Belum ada chat masuk.'
                  : 'Belum ada pengaduan masuk.',
          style: TextStyle(color: muted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: daftar.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, indent: 74, color: MerchantPosTheme.borderOf(context)),
      itemBuilder: (context, i) => _BarisChat(
        tiket: daftar[i],
        asal: daftar[i].asalTampil(_namaMerchant[daftar[i].restoId]),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SupportChatScreen(
              ticketId: daftar[i].id,
              sebagaiAdmin: true,
              namaSaya: nama,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nama = context.read<AuthProvider>().employeeName;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Customer Service', style: TextStyle(fontSize: 16)),
            Text(
              _belumDibaca == 0
                  ? '${_semua.where((t) => t.terbuka).length} pengaduan terbuka'
                  : '$_belumDibaca belum dibaca',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_sembunyikanTutup
                ? Icons.filter_alt
                : Icons.filter_alt_off_outlined),
            tooltip: _sembunyikanTutup
                ? 'Tampilkan yang sudah ditutup'
                : 'Sembunyikan yang sudah ditutup',
            onPressed: () =>
                setState(() => _sembunyikanTutup = !_sembunyikanTutup),
          ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Gagal memuat percakapan.\n$_galat',
                        textAlign: TextAlign.center),
                  ),
                )
              : ResponsiveCenter(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                        child: TextField(
                          controller: _cari,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 19),
                            hintText: 'Cari nama, email, atau judul',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(11)),
                          ),
                        ),
                      ),
                      TabBar(
                        controller: _tab,
                        tabs: [
                          Tab(text: 'Pengaduan${_penanda(chat: false)}'),
                          Tab(text: 'Chat${_penanda(chat: true)}'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            _daftarTiket(chat: false, nama: nama),
                            _daftarTiket(chat: true, nama: nama),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _BarisChat extends StatelessWidget {
  final SupportTicket tiket;

  /// "Customer" atau "Merchant · MerchantPos Resto".
  final String asal;

  final VoidCallback onTap;

  const _BarisChat({
    required this.tiket,
    required this.asal,
    required this.onTap,
  });

  /// Waktu ala aplikasi pesan: jam untuk hari ini, tanggal untuk yang
  /// lebih lama. Tanggal penuh pada percakapan yang barusan masuk
  /// membuat semuanya terlihat sama tuanya.
  static String _waktu(DateTime w) {
    final t = w.toWib();
    final kini = DateTime.now().toWib();
    final hariIni =
        t.year == kini.year && t.month == kini.month && t.day == kini.day;
    return hariIni
        ? DateFormat('HH:mm', 'id_ID').format(t)
        : DateFormat('d MMM', 'id_ID').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    final baru = tiket.belumDibaca(sebagaiAdmin: true);
    final warna = tiket.chatBebas
        ? MerchantPosTheme.brandOf(context)
        : kSupportStatusWarna[tiket.status]!;
    final waktu = tiket.lastMessageAt ?? tiket.createdAt;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: warna.withOpacity(0.16),
        child: Text(
          tiket.namaTampil.characters.first.toUpperCase(),
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 17, color: warna),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              tiket.namaTampil,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: baru ? FontWeight.bold : FontWeight.w600),
            ),
          ),
          Text(_waktu(waktu),
              style: TextStyle(
                  fontSize: 11,
                  color: baru ? Colors.red : muted,
                  fontWeight: baru ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (tiket.dariMerchant
                          ? const Color(0xFF0D9488)
                          : const Color(0xFF0EA5E9))
                      .withOpacity(0.14),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  asal,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: tiket.dariMerchant
                        ? const Color(0xFF166534)
                        : const Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tiket.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (tiket.lastMessageFromAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.reply, size: 12, color: muted),
                ),
              Expanded(
                child: Text(
                  tiket.lastMessageBody ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: baru ? MerchantPosTheme.textOf(context) : muted,
                    fontWeight: baru ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Chat tidak punya tahapan — lencana statusnya dilepas,
              // bukan diisi "Open" selamanya.
              if (!tiket.chatBebas)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: warna.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    kSupportStatusLabel[tiket.status]!,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: warna),
                  ),
                ),
              if (baru)
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
