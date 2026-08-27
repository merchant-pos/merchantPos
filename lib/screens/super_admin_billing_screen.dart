import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/billing_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/billing.dart';
import '../models/restaurant.dart';
import '../theme.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';
import '../widgets/dialog_actions.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Billing seluruh resto — hanya Super Admin.
///
/// Dua tab yang sengaja dipisah karena dua pekerjaan yang berbeda
/// waktunya: menetapkan harga dilakukan sekali saat resto bergabung,
/// memverifikasi pembayaran dilakukan tiap bulan.
class SuperAdminBillingScreen extends StatefulWidget {
  const SuperAdminBillingScreen({super.key});

  @override
  State<SuperAdminBillingScreen> createState() =>
      _SuperAdminBillingScreenState();
}

class _SuperAdminBillingScreenState extends State<SuperAdminBillingScreen> {
  final _repo = BillingRepository();
  final _restoRepo = RestaurantRepository();

  List<Restaurant> _resto = const [];
  Map<String, RestoBilling> _setelan = const {};
  List<BillingInvoice> _tagihan = const [];
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final resto = await _restoRepo.getAll();
      final setelan = await _repo.allSettings();
      final tagihan = await _repo.allInvoices();
      if (!mounted) return;
      setState(() {
        _resto = resto;
        _setelan = setelan;
        _tagihan = tagihan;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _terbitkanSekarang() async {
    try {
      final n = await _repo.generateNow();
      if (!mounted) return;
      showAppToast(
          context, n == 0 ? 'Tidak ada tagihan baru.' : '$n tagihan terbit.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _atur(Restaurant resto) async {
    final hasil = await showDialog<RestoBilling>(
      context: context,
      builder: (_) => _DialogSetelan(
        resto: resto,
        awal: _setelan[resto.id] ?? RestoBilling(restoId: resto.id),
      ),
    );
    if (hasil == null || !mounted) return;
    try {
      await _repo.saveSettings(hasil);
      if (!mounted) return;
      showAppToast(context, 'Setelan langganan ${resto.name} tersimpan.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  Future<void> _segarkan(BillingInvoice inv) async {
    try {
      final baru = await _repo.refreshInvoice(inv.id);
      if (!mounted) return;
      showAppToast(
        context,
        baru == inv.amount
            ? 'Nominalnya sudah sesuai.'
            : 'Diperbarui jadi ${_rupiah.format(baru)}.',
      );
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _putuskan(BillingInvoice inv, bool terima) async {
    String? alasan;
    if (!terima) {
      alasan = await showDialog<String>(
        context: context,
        builder: (_) => const _DialogTolak(),
      );
      if (alasan == null) return;
    }
    try {
      await _repo.review(inv.id, accept: terima, reason: alasan);
      if (!mounted) return;
      showAppToast(context,
          terima ? 'Tagihan ${inv.id} lunas.' : 'Bukti ${inv.id} ditolak.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menunggu =
        _tagihan.where((t) => t.status == InvoiceStatus.review).length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: MerchantPosTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Billing Merchant'),
          actions: [
            IconButton(
              tooltip: 'Terbitkan tagihan sekarang',
              icon: const Icon(Icons.playlist_add_outlined),
              onPressed: _terbitkanSekarang,
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Paket & Harga'),
              Tab(text: menunggu > 0 ? 'Tagihan ($menunggu)' : 'Tagihan'),
            ],
          ),
        ),
        body: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Gagal memuat: $_galat',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: MerchantPosTheme.mutedOf(context))),
                    ),
                  )
                : TabBarView(
                    children: [_tabPaket(), _tabTagihan()],
                  ),
      ),
    );
  }

  Widget _tabPaket() => RefreshIndicator(
        onRefresh: _muat,
        child: ResponsiveCenter(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            itemCount: _resto.length,
            itemBuilder: (_, i) {
              final r = _resto[i];
              final s = _setelan[r.id] ?? RestoBilling(restoId: r.id);
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  color: MerchantPosTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: MerchantPosTheme.borderOf(context)),
                ),
                child: ListTile(
                  title: Text(r.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    s.gratis || !s.active
                        ? (s.active ? 'Gratis' : 'Langganan dimatikan')
                        : '${_rupiah.format(s.monthlyPrice)} / bulan · '
                            'tiap tanggal ${s.billingDay} · '
                            'tenggang ${s.graceDays} hari',
                    style: TextStyle(
                        fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 19),
                  onTap: () => _atur(r),
                ),
              );
            },
          ),
        ),
      );

  Widget _tabTagihan() {
    if (_tagihan.isEmpty) {
      return Center(
        child: Text('Belum ada tagihan terbit.',
            style: TextStyle(color: MerchantPosTheme.mutedOf(context))),
      );
    }
    return RefreshIndicator(
      onRefresh: _muat,
      child: ResponsiveCenter(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          itemCount: _tagihan.length,
          itemBuilder: (_, i) => _KartuTagihanAdmin(
            invoice: _tagihan[i],
            onTerima: () => _putuskan(_tagihan[i], true),
            onTolak: () => _putuskan(_tagihan[i], false),
            onSegarkan: () => _segarkan(_tagihan[i]),
          ),
        ),
      ),
    );
  }
}

class _KartuTagihanAdmin extends StatelessWidget {
  final BillingInvoice invoice;
  final VoidCallback onTerima;
  final VoidCallback onTolak;
  final VoidCallback onSegarkan;

  const _KartuTagihanAdmin({
    required this.invoice,
    required this.onTerima,
    required this.onTolak,
    required this.onSegarkan,
  });

  @override
  Widget build(BuildContext context) {
    final (warna, label) = switch (invoice.status) {
      InvoiceStatus.paid => (Colors.green, 'Lunas'),
      InvoiceStatus.waived => (Colors.blueGrey, 'Dibebaskan'),
      InvoiceStatus.review => (Colors.orange, 'Perlu Diperiksa'),
      InvoiceStatus.unpaid => (Colors.red, 'Belum Dibayar'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: invoice.status == InvoiceStatus.review
              ? Colors.orange
              : MerchantPosTheme.borderOf(context),
          width: invoice.status == InvoiceStatus.review ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(invoice.restoName ?? invoice.restoId,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: warna.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: warna)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_rupiah.format(invoice.amount)} · ${invoice.id}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (invoice.status == InvoiceStatus.unpaid)
                IconButton(
                  tooltip: 'Hitung ulang mengikuti diskon',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: onSegarkan,
                ),
            ],
          ),
          if (invoice.discountAmount > 0)
            Text(
              'Harga ${_rupiah.format(invoice.grossAmount ?? invoice.amount)} · '
              '${invoice.discountName ?? 'Diskon'} '
              '−${_rupiah.format(invoice.discountAmount)}',
              style: const TextStyle(fontSize: 11.5, color: Colors.green),
            ),
          Text(
            'Jatuh tempo ${_tanggal.format(invoice.dueDate)}',
            style:
                TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
          ),
          if (invoice.paidNote != null && invoice.paidNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Catatan: ${invoice.paidNote}',
                  style: TextStyle(
                      fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
            ),
          if (invoice.confirmedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Diputuskan ${invoice.confirmedBy}',
                  style: TextStyle(
                      fontSize: 11, color: MerchantPosTheme.mutedOf(context))),
            ),
          if (invoice.hasProof) ...[
            const SizedBox(height: 9),
            GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.memory(base64Decode(invoice.proofBase64!)),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(invoice.proofBase64!),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          if (invoice.status == InvoiceStatus.review) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onTerima,
                    icon: const Icon(Icons.check, size: 17),
                    label: const Text('Terima'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTolak,
                    icon: const Icon(Icons.close, size: 17, color: Colors.red),
                    label: const Text('Tolak',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DialogSetelan extends StatefulWidget {
  final Restaurant resto;
  final RestoBilling awal;

  const _DialogSetelan({required this.resto, required this.awal});

  @override
  State<_DialogSetelan> createState() => _DialogSetelanState();
}

class _DialogSetelanState extends State<_DialogSetelan> {
  late final _harga = TextEditingController(
    text: widget.awal.monthlyPrice == 0
        ? ''
        : formatRupiahInput(widget.awal.monthlyPrice),
  );
  late final _tenggang =
      TextEditingController(text: '${widget.awal.graceDays}');
  late int _tanggalTagih = widget.awal.billingDay;
  late bool _aktif = widget.awal.active;

  @override
  void dispose() {
    _harga.dispose();
    _tenggang.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Langganan ${widget.resto.name}',
          style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _harga,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              decoration: InputDecoration(
                label: requiredLabel('Biaya per Bulan'),
                prefixText: 'Rp ',
                helperText: 'Kosong atau 0 berarti gratis — tidak pernah '
                    'ditagih dan tidak pernah terkunci.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
            // Tanggal 29–31 boleh dipilih, dan di bulan yang lebih
            // pendek jatuh di hari terakhirnya — 31 jadi 30 di April,
            // 28 di Februari biasa, 29 di Februari kabisat.
            //
            // Dulu daftarnya berhenti di 28 supaya artinya sama di
            // bulan mana pun. Itu menghindari pertanyaannya dengan cara
            // melarang resto memilih tanggal tagihnya sendiri; resto
            // yang siklus kasnya di akhir bulan terpaksa menagih di
            // tanggal yang bukan tanggalnya.
            DropdownButtonFormField<int>(
              value: _tanggalTagih,
              decoration: const InputDecoration(
                labelText: 'Tanggal Tagihan',
                helperText: 'Tiap bulan pada tanggal ini. Tanggal 29–31 '
                    'jatuh di hari terakhir bulan yang lebih pendek.',
                // Tiga, bukan dua. Popup di web lebih sempit daripada
                // layar HP tempat angka ini dipilih, dan kalimat yang
                // terpotong di tengah kata justru kalimat yang
                // menjelaskan kenapa tanggal 31 boleh dipilih.
                helperMaxLines: 3,
              ),
              items: [
                for (var d = 1; d <= 31; d++)
                  DropdownMenuItem(
                    value: d,
                    child: Text(d > 28 ? 'Tanggal $d (atau akhir bulan)'
                        : 'Tanggal $d'),
                  ),
              ],
              onChanged: (v) => setState(() => _tanggalTagih = v ?? 1),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tenggang,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Tenggang (hari)',
                helperText: 'Merchant terkunci setelah lewat tenggang ini',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _aktif,
              title: const Text('Langganan aktif',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                _aktif
                    ? 'Ditagih tiap bulan'
                    : 'Tidak ditagih dan tidak pernah terkunci',
                style: TextStyle(
                    fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              onChanged: (v) => setState(() => _aktif = v),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // DialogActions, bukan dua tombol berjajar.
        //
        // Baris `actions` milik AlertDialog melipat jadi kolom begitu
        // labelnya tidak muat — dan saat melipat, urutannya mengikuti
        // daftar, jadi Batal berdiri di atas hal yang justru
        // didatangi orangnya.
        DialogActions(
          confirmLabel: 'Simpan',
          onConfirm: () => Navigator.pop(
            context,
            widget.awal.copyWith(
              monthlyPrice: parseRupiah(_harga.text) ?? 0,
              billingDay: _tanggalTagih,
              graceDays: (int.tryParse(_tenggang.text.trim()) ?? 1).clamp(0, 30),
              active: _aktif,
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogTolak extends StatefulWidget {
  const _DialogTolak();

  @override
  State<_DialogTolak> createState() => _DialogTolakState();
}

class _DialogTolakState extends State<_DialogTolak> {
  final _alasan = TextEditingController();

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tolak Bukti Bayar', style: TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alasannya dibaca merchant. Tanpa alasan, yang ditolak tidak tahu '
            'apa yang harus diperbaiki — dan akan mengirim bukti yang sama '
            'lagi.',
            style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _alasan,
            autofocus: true,
            decoration: InputDecoration(
              label: requiredLabel('Alasan'),
              hintText: 'Contoh: nominal tidak sesuai',
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Tolak',
          destructive: true,
          onConfirm: () {
            final t = _alasan.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, t);
          },
        ),
      ],
    );
  }
}
