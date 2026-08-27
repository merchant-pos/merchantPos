import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/restaurant_repository.dart';
import '../db/support_repository.dart';
import '../services/push_service.dart';
import '../models/support_ticket.dart';
import '../theme.dart';
import '../utils/gambar_base64.dart';
import '../utils/id_time.dart';
import '../utils/photo_picker.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/penampil_foto.dart';

/// Percakapan satu tiket.
///
/// Satu layar untuk kedua sisi. Menyalinnya jadi dua — satu untuk
/// pelapor, satu untuk Merchant-POS Admin — berarti dua tempat yang harus
/// selalu sepakat soal bentuk gelembung, urutan pesan, dan kapan
/// tombolnya boleh ditekan. Yang kedua akan tertinggal saat yang pertama
/// diperbaiki, dan yang menemukannya adalah orang yang sedang mengadu.
class SupportChatScreen extends StatefulWidget {
  final String ticketId;

  /// Layar ini dibuka oleh Merchant-POS Admin, bukan oleh pelapornya.
  final bool sebagaiAdmin;

  /// Nama yang disematkan pada pesan yang dikirim dari layar ini.
  final String? namaSaya;

  const SupportChatScreen({
    super.key,
    required this.ticketId,
    this.sebagaiAdmin = false,
    this.namaSaya,
  });

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _repo = SupportRepository();
  final _teks = TextEditingController();
  final _gulir = ScrollController();

  StreamSubscription<List<SupportMessage>>? _pesanSub;
  StreamSubscription<SupportTicket?>? _tiketSub;

  List<SupportMessage> _pesan = const [];
  SupportTicket? _tiket;
  String? _namaMerchant;
  bool _mengirim = false;
  String? _foto;

  static final _jam = DateFormat('HH:mm', 'id_ID');
  static final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

  @override
  void initState() {
    super.initState();
    // Selama layar ini terbuka, notifikasi untuk percakapan yang sama
    // tidak ditampilkan — pesannya sudah muncul di sini detik itu juga.
    PushService.tiketSupportTerbuka = widget.ticketId;
    _pesanSub = _repo.pesan(widget.ticketId).listen((p) {
      if (!mounted) return;
      setState(() => _pesan = p);
      _keBawah();
      // Dibaca begitu terlihat, bukan saat layarnya dibuka. Pesan yang
      // datang selagi layarnya terbuka juga sudah terbaca — menandainya
      // sekali di awal saja menyisakan penanda merah yang tidak pernah
      // hilang sampai layarnya dibuka ulang.
      _repo.tandaiDibaca(widget.ticketId);
    });
    _tiketSub = _repo.pantau(widget.ticketId).listen((t) {
      if (!mounted || t == null) return;
      setState(() => _tiket = t);
      _muatMerchant(t);
    });
  }

  @override
  void dispose() {
    if (PushService.tiketSupportTerbuka == widget.ticketId) {
      PushService.tiketSupportTerbuka = null;
    }
    _pesanSub?.cancel();
    _tiketSub?.cancel();
    _teks.dispose();
    _gulir.dispose();
    super.dispose();
  }

  /// Nama merchant pelapor, hanya untuk sisi Merchant-POS Admin.
  ///
  /// Diambil sekali. Pelapornya tidak berpindah merchant di tengah
  /// percakapan, dan mengambilnya tiap kali tiketnya bergerak berarti
  /// satu permintaan tiap pesan masuk.
  Future<void> _muatMerchant(SupportTicket t) async {
    if (!widget.sebagaiAdmin || t.restoId == null || _namaMerchant != null) {
      return;
    }
    try {
      final m = await RestaurantRepository().getOnce(t.restoId!);
      if (!mounted || m == null) return;
      setState(() => _namaMerchant = m.name);
    } catch (_) {
      // Tanpa namanya, yang tampil tetap "Merchant" — cukup untuk tahu
      // ini bukan keluhan pelanggan.
    }
  }

  void _keBawah() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_gulir.hasClients) return;
      _gulir.jumpTo(_gulir.position.maxScrollExtent);
    });
  }

  Future<void> _kirim() async {
    // Penjaga yang sama seperti di formulir pengaduan: tombol yang
    // dimatikan lewat setState belum mati pada ketukan kedua yang cepat.
    if (_mengirim) return;
    final isi = _teks.text.trim();
    if (isi.isEmpty && _foto == null) return;
    setState(() => _mengirim = true);
    try {
      await _repo.kirim(
        ticketId: widget.ticketId,
        body: isi.isEmpty ? '(foto)' : isi,
        sebagaiAdmin: widget.sebagaiAdmin,
        nama: widget.namaSaya,
        photoBase64: _foto,
      );
      if (!mounted) return;
      setState(() {
        _teks.clear();
        _foto = null;
      });
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, _pesanGalat(e), isError: true);
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  Future<void> _tambahFoto() async {
    final file = await pickProofPhoto(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (!mounted) return;
    setState(() => _foto = base64Encode(bytes));
  }

  String _pesanGalat(Object e) {
    final teks = e.toString();
    final i = teks.indexOf('message: ');
    if (i < 0) return teks;
    final sisa = teks.substring(i + 9);
    final akhir = sisa.indexOf(', code:');
    return akhir > 0 ? sisa.substring(0, akhir) : sisa;
  }

  Future<void> _ubahStatus(SupportStatus status) async {
    try {
      await _repo.ubahStatus(widget.ticketId, status);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, _pesanGalat(e), isError: true);
    }
  }

  Future<void> _tutup() async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tutup pengaduan?'),
        content: const Text(
          'Percakapannya tetap bisa dibaca, tapi tidak bisa dibalas lagi. '
          'Kalau masalahnya muncul lagi, buat pengaduan baru.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Tutup Pengaduan',
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (ya != true) return;
    await _ubahStatus(SupportStatus.closed);
  }

  @override
  Widget build(BuildContext context) {
    final t = _tiket;
    final terbuka = t?.terbuka ?? true;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t?.subject ?? 'Merchant-POS Support',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15.5)),
            if (t != null)
              Text(
                widget.sebagaiAdmin
                    ? (t.chatBebas
                        ? '${t.namaTampil} • ${t.asalTampil(_namaMerchant)}'
                        : '${t.namaTampil} • ${t.asalTampil(_namaMerchant)} • '
                            '${kSupportStatusLabel[t.status]}')
                    : (t.chatBebas ? 'Chat' : kSupportStatusLabel[t.status]!),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          // Chat bebas tidak punya tahapan dan tidak pernah "selesai".
          // Memberinya tombol status dan tombol tutup membuat orang yang
          // cuma bertanya merasa sedang mengurus perkara.
          if (t != null && widget.sebagaiAdmin && !t.chatBebas)
            PopupMenuButton<SupportStatus>(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Ubah status',
              onSelected: _ubahStatus,
              itemBuilder: (_) => [
                for (final s in SupportStatus.values)
                  PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(Icons.circle,
                            size: 10, color: kSupportStatusWarna[s]),
                        const SizedBox(width: 8),
                        Text(kSupportStatusLabel[s]!),
                      ],
                    ),
                  ),
              ],
            ),
          if (t != null && terbuka && !t.chatBebas)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: 'Tutup pengaduan',
              onPressed: _tutup,
            ),
        ],
      ),
      body: Column(
        children: [
          if (t != null && !t.chatBebas) _KepalaStatus(tiket: t),
          Expanded(
            child: _pesan.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _gulir,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _pesan.length,
                    itemBuilder: (context, i) {
                      final m = _pesan[i];
                      final sebelumnya = i == 0 ? null : _pesan[i - 1];
                      final hariBaru = sebelumnya == null ||
                          !_hariSama(sebelumnya.createdAt, m.createdAt);
                      return Column(
                        children: [
                          if (hariBaru)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                _tanggal.format(m.createdAt.toWib()),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: MerchantPosTheme.mutedOf(context)),
                              ),
                            ),
                          _Gelembung(
                            pesan: m,
                            milikSaya: m.fromAdmin == widget.sebagaiAdmin,
                            jam: _jam.format(m.createdAt.toWib()),
                            // Nama penjawabnya disebut, bukan cuma
                            // "Merchant-POS". Yang mengadu berhak tahu
                            // sedang bicara dengan siapa — dan yang
                            // menjawab jadi ikut bertanggung jawab atas
                            // kalimatnya.
                            pengirim: m.fromAdmin
                                ? _labelAdmin(m)
                                : (widget.sebagaiAdmin
                                    ? (_tiket?.namaTampil ?? '')
                                    : null),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (terbuka)
            _KolomKirim(
              controller: _teks,
              foto: _foto,
              mengirim: _mengirim,
              onFoto: _tambahFoto,
              onHapusFoto: () => setState(() => _foto = null),
              onKirim: _kirim,
            )
          else if (t != null && !t.chatBebas)
            _Ditutup(tiket: t),
        ],
      ),
    );
  }

  static String _labelAdmin(SupportMessage m) {
    final n = (m.senderName ?? '').trim();
    return n.isEmpty ? 'Merchant-POS Admin' : 'Merchant-POS Admin - $n';
  }

  static bool _hariSama(DateTime a, DateTime b) {
    final x = a.toWib();
    final y = b.toWib();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _KepalaStatus extends StatelessWidget {
  final SupportTicket tiket;

  const _KepalaStatus({required this.tiket});

  @override
  Widget build(BuildContext context) {
    final warna = kSupportStatusWarna[tiket.status]!;
    return Container(
      width: double.infinity,
      color: warna.withOpacity(0.10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 9, color: warna),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              switch (tiket.status) {
                SupportStatus.open =>
                  'Pengaduan sudah masuk. Merchant-POS Admin akan menanggapinya.',
                SupportStatus.onProgress => 'Sedang ditangani Merchant-POS Admin.',
                SupportStatus.confirmCustomer =>
                  'Menunggu tanggapanmu. Tanpa jawaban dalam 24 jam, '
                      'pengaduan ini ditutup sendiri.',
                SupportStatus.closed => tiket.autoClosed
                    ? 'Ditutup otomatis karena tidak ada tanggapan.'
                    : 'Pengaduan sudah ditutup.',
              },
              style: TextStyle(
                  fontSize: 11.5, color: MerchantPosTheme.textOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gelembung extends StatelessWidget {
  final SupportMessage pesan;
  final bool milikSaya;
  final String jam;

  /// Nama pengirimnya, kalau perlu disebut. Null berarti tidak.
  final String? pengirim;

  const _Gelembung({
    required this.pesan,
    required this.milikSaya,
    required this.jam,
    this.pengirim,
  });

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);

    // Pesan sistem berdiri di tengah, tanpa gelembung. Ia bukan ucapan
    // siapa-siapa — menampilkannya sebagai gelembung admin membuat
    // orang membalas kalimat yang tidak pernah diketik manusia.
    if (pesan.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MerchantPosTheme.softFillOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(pesan.body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: muted)),
          ),
        ),
      );
    }

    final warna = milikSaya
        ? MerchantPosTheme.brandOf(context)
        : MerchantPosTheme.surfaceOf(context);
    final teks = milikSaya ? Colors.white : MerchantPosTheme.textOf(context);

    return Align(
      alignment: milikSaya ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: warna,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(milikSaya ? 14 : 3),
              bottomRight: Radius.circular(milikSaya ? 3 : 14),
            ),
            border: milikSaya
                ? null
                : Border.all(color: MerchantPosTheme.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!milikSaya && (pengirim ?? '').isNotEmpty) ...[
                Text(pengirim!,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: MerchantPosTheme.brandOf(context))),
                const SizedBox(height: 3),
              ],
              if (pesan.photoBase64 != null) ...[
                GestureDetector(
                  onTap: () => lihatFoto(context, [pesan.photoBase64!]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.memory(byteGambar(pesan.photoBase64!),
                        width: 200, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 7),
              ],
              Text(pesan.body,
                  style: TextStyle(fontSize: 13.5, height: 1.35, color: teks)),
              const SizedBox(height: 3),
              Text(jam,
                  style: TextStyle(
                      fontSize: 10,
                      color: milikSaya ? Colors.white70 : muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _KolomKirim extends StatelessWidget {
  final TextEditingController controller;
  final String? foto;
  final bool mengirim;
  final VoidCallback onFoto;
  final VoidCallback onHapusFoto;
  final VoidCallback onKirim;

  const _KolomKirim({
    required this.controller,
    required this.foto,
    required this.mengirim,
    required this.onFoto,
    required this.onHapusFoto,
    required this.onKirim,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: MerchantPosTheme.surfaceOf(context),
          border: Border(
              top: BorderSide(color: MerchantPosTheme.borderOf(context))),
        ),
        child: Column(
          children: [
            if (foto != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(byteGambar(foto!),
                          width: 54, height: 54, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Foto siap dikirim',
                          style: TextStyle(
                              fontSize: 12,
                              color: MerchantPosTheme.mutedOf(context))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: onHapusFoto,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  tooltip: 'Lampirkan foto',
                  onPressed: mengirim ? null : onFoto,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Tulis pesan…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: mengirim ? null : onKirim,
                  icon: mengirim
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Ditutup extends StatelessWidget {
  final SupportTicket? tiket;

  const _Ditutup({required this.tiket});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        color: MerchantPosTheme.softFillOf(context),
        child: Text(
          tiket?.autoClosed == true
              ? 'Ditutup otomatis karena tidak ada tanggapan selama 24 jam. '
                  'Buat pengaduan baru kalau masalahnya belum selesai.'
              : 'Pengaduan sudah ditutup. Buat pengaduan baru kalau '
                  'masalahnya muncul lagi.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
        ),
      ),
    );
  }
}
