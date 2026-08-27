import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/support_repository.dart';
import '../models/support_ticket.dart';
import '../providers/auth_provider.dart';
import '../screens/support_chat_screen.dart';
import '../screens/support_new_ticket_screen.dart';
import '../theme.dart';
import '../utils/id_time.dart';

/// Tombol mengambang MerchantPOS Support.
///
/// Satu widget untuk pelanggan maupun pegawai merchant. Keduanya
/// mengadu ke tempat yang sama, dan memisahkannya jadi dua tombol
/// berarti dua alur yang harus sama-sama diingat setiap kali salah
/// satunya berubah.
///
/// Tidak tampil untuk yang belum masuk. Pengaduan tanpa akun tidak punya
/// tempat untuk dibalas — dan pengadu yang tidak pernah menerima
/// jawabannya akan mengira MerchantPOS mendiamkannya.
class SupportFab extends StatefulWidget {
  const SupportFab({super.key});

  @override
  State<SupportFab> createState() => _SupportFabState();
}

class _SupportFabState extends State<SupportFab> {
  final _repo = SupportRepository();
  List<SupportTicket> _tiket = const [];
  Timer? _pewaktu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muat());
    // Diperiksa berkala, bukan dialirkan terus-menerus.
    //
    // Aliran realtime untuk penanda di sebuah tombol berarti langganan
    // yang hidup sepanjang aplikasi terbuka, di layar mana pun. Yang
    // dijanjikan penanda ini cuma "ada balasan" — dan satu menit
    // terlambat mengetahuinya tidak merugikan siapa pun.
    _pewaktu = Timer.periodic(const Duration(minutes: 1), (_) => _muat());
  }

  @override
  void dispose() {
    _pewaktu?.cancel();
    super.dispose();
  }

  Future<void> _muat() async {
    if (!context.read<AuthProvider>().isLoggedIn) return;
    try {
      final t = await _repo.milikSaya();
      if (!mounted) return;
      setState(() => _tiket = t);
    } catch (_) {
      // Penanda yang gagal dimuat cuma berarti tidak ada penandanya.
      // Tombolnya tetap bisa ditekan, dan itu yang penting.
    }
  }

  int get _belumDibaca =>
      SupportRepository.belumDibaca(_tiket, sebagaiAdmin: false);


  /// Badan menu MerchantPOS Support — satu untuk kedua bentuknya.
  ///
  /// Lembar bawah di ponsel dan popup menempel di web menampilkan
  /// pilihan yang sama persis. Menyalinnya jadi dua berarti perubahan
  /// berikutnya hanya sampai ke salah satunya, dan yang tertinggal
  /// adalah yang lebih jarang dilihat orang yang mengubahnya.
  Widget _menuSupport(BuildContext sheetContext) {
    // Chat bebas tidak ikut dihitung sebagai pengaduan: ia tidak punya
    // status, dan pintunya sudah ada sendiri di atas.
    final pengaduan = [for (final t in _tiket) if (!t.chatBebas) t];
    final chat = [for (final t in _tiket) if (t.chatBebas) t];
    final adaRiwayat = pengaduan.isNotEmpty;
    final belumDibacaPengaduan =
        SupportRepository.belumDibaca(pengaduan, sebagaiAdmin: false);
    final belumDibacaChat =
        SupportRepository.belumDibaca(chat, sebagaiAdmin: false);

    return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('MerchantPOS Support',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Ada kendala? Ceritakan ke kami, nanti dibalas di sini juga.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: MerchantPosTheme.mutedOf(sheetContext)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: MerchantPosTheme.brand),
              title: const Text('Buat Pengaduan Baru'),
              subtitle: const Text('Tulis keluhannya, boleh pakai foto',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () => Navigator.pop(sheetContext, 'baru'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline,
                  color: MerchantPosTheme.brand),
              title: const Text('Chat MerchantPOS Admin'),
              subtitle: Text(
                belumDibacaChat > 0
                    ? 'Ada balasan baru'
                    : 'Sekadar bertanya, bukan pengaduan',
                style: const TextStyle(fontSize: 11.5),
              ),
              // Penandanya menempel pada barisnya masing-masing.
              //
              // Satu angka di tombol mengambang cuma memberi tahu "ada
              // sesuatu" — dan yang membukanya masih harus menebak yang
              // mana, lalu membuka keduanya untuk memastikan.
              trailing: _Penanda(jumlah: belumDibacaChat),
              onTap: () => Navigator.pop(sheetContext, 'chat'),
            ),
            ListTile(
              leading: Icon(Icons.receipt_long_outlined,
                  color: adaRiwayat
                      ? MerchantPosTheme.brand
                      : MerchantPosTheme.mutedOf(sheetContext)),
              title: const Text('Lihat Status Pengaduan'),
              subtitle: Text(
                adaRiwayat
                    ? '${pengaduan.length} pengaduan'
                    : 'Belum ada pengaduan',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: _Penanda(jumlah: belumDibacaPengaduan),
              onTap: adaRiwayat
                  ? () => Navigator.pop(sheetContext, 'daftar')
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ),
      );
  }

  Future<void> _buka() async {
    final auth = context.read<AuthProvider>();

    // Di web menunya muncul menempel pada tombolnya, bukan sebagai
    // panel yang naik dari dasar jendela.
    //
    // Lembar bawah dirancang untuk layar yang lebarnya segenggam: ia
    // selalu selebar jendela dan menempel di dasarnya. Di jendela 1600
    // piksel ia jadi panel raksasa di pojok kiri bawah, sejauh mungkin
    // dari tombol yang barusan ditekan — dan hubungan antara keduanya
    // hilang sama sekali.
    // if/else, bukan ternary: dalam ternary, cabang keduanya dianggap
    // berada sesudah await cabang pertama, dan context yang dipakai di
    // sana jadi terbaca melewati jeda asinkron.
    final String? pilihan;
    if (kIsWeb) {
      pilihan = await showDialog<String>(
            context: context,
            barrierColor: Colors.black.withOpacity(0.2),
            builder: (sheetContext) => Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                // Di atas tombolnya, bukan menimpanya.
                padding: const EdgeInsets.only(right: 16, bottom: 140),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Material(
                    color: MerchantPosTheme.surfaceOf(sheetContext),
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: _menuSupport(sheetContext),
                  ),
                ),
              ),
            ),
          );
    } else {
      pilihan = await showModalBottomSheet<String>(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: _menuSupport,
          );
    }

    if (pilihan == null || !mounted) return;

    // Percakapan bebas yang masih terbuka dipakai lagi, bukan dibuat
    // baru tiap kali. Chat yang melahirkan tiket baru tiap dibuka akan
    // mengubur pengaduan sungguhan di bawah puluhan percakapan berisi
    // satu sapaan.
    if (pilihan == 'chat') {
      final adaChat = await _repo.chatUmumTerbuka();
      if (!mounted) return;
      if (adaChat != null) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportChatScreen(ticketId: adaChat.id),
        ));
        await _muat();
        return;
      }
      final dibuat = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => SupportNewTicketScreen(
            dariMerchant: auth.isEmployee,
            restoId: auth.restoId,
            subjekTetap: kSubjekChatUmum,
          ),
        ),
      );
      await _muat();
      if (dibuat != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportChatScreen(ticketId: dibuat),
        ));
        await _muat();
      }
      return;
    }

    if (pilihan == 'baru') {
      final dibuat = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => SupportNewTicketScreen(
            dariMerchant: auth.isEmployee,
            restoId: auth.restoId,
          ),
        ),
      );
      await _muat();
      if (dibuat != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportChatScreen(ticketId: dibuat),
        ));
        await _muat();
      }
      return;
    }

    // Percakapan yang ditutup tidak hilang. Yang membukanya lagi
    // langsung menemukan pesan terakhirnya — bukan daftar kosong yang
    // membuatnya mengira pengaduannya tidak pernah ada.
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SupportTicketListScreen(),
    ));
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().isLoggedIn) {
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Bulat kecil, bukan tombol berlabel.
        //
        // Yang berlabel selebar setengah layar, dan di beranda yang
        // penuh ia duduk tepat di atas tombol menu terakhir. Ikon
        // pusat bantuan sudah dikenali tanpa perlu dibaca — dan
        // namanya tetap muncul begitu diketuk.
        FloatingActionButton(
          heroTag: 'merchantpos-support',
          onPressed: _buka,
          tooltip: 'MerchantPOS Support',
          mini: true,
          child: const Icon(Icons.support_agent),
        ),
        if (_belumDibaca > 0)
          Positioned(
            right: -2,
            top: -4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: MerchantPosTheme.backgroundOf(context), width: 2),
              ),
              child: Text(
                '$_belumDibaca',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

/// Titik merah berangka. Kosong berarti tidak digambar sama sekali —
/// penanda yang selalu ada berhenti berarti apa-apa.
class _Penanda extends StatelessWidget {
  final int jumlah;

  const _Penanda({required this.jumlah});

  @override
  Widget build(BuildContext context) {
    if (jumlah <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      constraints: const BoxConstraints(minWidth: 22),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$jumlah',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Daftar pengaduan milik orang yang sedang masuk.
class SupportTicketListScreen extends StatefulWidget {
  const SupportTicketListScreen({super.key});

  @override
  State<SupportTicketListScreen> createState() =>
      _SupportTicketListScreenState();
}

class _SupportTicketListScreenState extends State<SupportTicketListScreen> {
  final _repo = SupportRepository();
  List<SupportTicket> _tiket = const [];
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final t = await _repo.milikSaya();
      if (!mounted) return;
      setState(() {
        // Chat bebas tidak ditampilkan di sini. Ia percakapan biasa
        // tanpa tahapan — menaruhnya di daftar berlencana "Open" membuat
        // orang yang cuma bertanya merasa punya perkara yang belum
        // selesai.
        _tiket = [for (final x in t) if (!x.chatBebas) x];
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tgl = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
    final muted = MerchantPosTheme.mutedOf(context);

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Pengaduan Saya')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: _tiket.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(
                            child: Text('Belum ada pengaduan.',
                                style: TextStyle(color: muted)),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                      itemCount: _tiket.length,
                      itemBuilder: (context, i) {
                        final t = _tiket[i];
                        final baru = t.belumDibaca(sebagaiAdmin: false);
                        return _KartuTiket(
                          tiket: t,
                          belumDibaca: baru,
                          waktu: t.lastMessageAt == null
                              ? tgl.format(t.createdAt.toWib())
                              : tgl.format(t.lastMessageAt!.toWib()),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SupportChatScreen(ticketId: t.id),
                              ),
                            );
                            await _muat();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

class _KartuTiket extends StatelessWidget {
  final SupportTicket tiket;
  final bool belumDibaca;
  final String waktu;
  final VoidCallback onTap;

  const _KartuTiket({
    required this.tiket,
    required this.belumDibaca,
    required this.waktu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    final warna = kSupportStatusWarna[tiket.status]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tiket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13.5)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: warna.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        kSupportStatusLabel[tiket.status]!,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: warna),
                      ),
                    ),
                  ],
                ),
                if ((tiket.lastMessageBody ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tiket.lastMessageBody!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: belumDibaca
                                ? MerchantPosTheme.textOf(context)
                                : muted,
                            fontWeight: belumDibaca
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (belumDibaca)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(waktu, style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
