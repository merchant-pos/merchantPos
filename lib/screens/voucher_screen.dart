import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/restaurant_repository.dart';
import '../db/voucher_repository.dart';
import '../models/restaurant.dart';
import '../models/voucher.dart';
import '../theme.dart';
import '../utils/photo_picker.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';
import '../widgets/dialog_actions.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Voucher Merchant-POS — hanya Super Admin.
///
/// Menerbitkan voucher bukan sekadar membuat aturan potongan: dananya
/// benar-benar berpindah dari saldo bebas Merchant-POS ke kantong voucher,
/// dan baru kembali kalau vouchernya hangus. Karena itu layar ini
/// menampilkan nominalnya, bukan cuma nama dan kodenya.
class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Yang masih hidup: belum kedaluwarsa.
  ///
  /// Yang ditutup manual tetap di sini — ia bisa dibuka lagi, dan
  /// memindahkannya ke tab riwayat berarti menyembunyikan sesuatu yang
  /// masih bisa diubah.
  List<Voucher> get _aktif =>
      [for (final v in _items) if (!v.kedaluwarsa) v];

  List<Voucher> get _lampau =>
      [for (final v in _items) if (v.kedaluwarsa) v];

  final _repo = VoucherRepository();
  final _restoRepo = RestaurantRepository();

  List<Voucher> _items = const [];
  List<Restaurant> _resto = const [];
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
      final items = await _repo.all();
      final resto = await _restoRepo.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _resto = resto;
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

  Future<void> _tutupBuka(Voucher v) async {
    try {
      await _repo.setActive(v.id, !v.active);
      if (!mounted) return;
      _muat();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal: $e', isError: true);
    }
  }

  Future<void> _hapus(Voucher v) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Hapus voucher ini?'),
        content: Text(
          'Batch ${v.code} akan dibuang dan '
          '${_rupiah.format(v.totalAmount)} kembali ke saldo Merchant-POS. '
          'Pengumumannya di kotak masuk pelanggan ikut dicabut.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(d, true),
            onCancel: () => Navigator.pop(d, false),
          ),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      await _repo.delete(v.id);
      if (!mounted) return;
      AppToast.show(context, 'Voucher ${v.code} dihapus.');
      _muat();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, _pesanGalat(e), isError: true);
    }
  }

  /// Alasan penolakan dari server dibiarkan apa adanya.
  ///
  /// Server menolak dengan kalimat yang sudah menjelaskan sebabnya —
  /// "Sudah ada 3 pelanggan yang menebus". Menggantinya dengan "gagal
  /// menghapus" membuang satu-satunya keterangan yang berguna.
  String _pesanGalat(Object e) {
    final teks = '$e';
    final m = RegExp(r'message: ([^,}]+)').firstMatch(teks);
    return m?.group(1)?.trim() ?? teks;
  }

  Future<void> _lihatPenebus(Voucher v) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PenebusScreen(voucher: v)),
    );
  }

  Future<void> _terbitkan() async {
    final hasil = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _FormBatch(resto: _resto),
    ));
    if (hasil == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final menggantung =
        _items.fold<int>(0, (s, v) => s + v.nilaiTertebus);

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Voucher Pelanggan'),
        // Dipisah supaya yang berjalan tidak tenggelam di bawah tumpukan
        // yang sudah lewat. Batch menumpuk terus dan tidak pernah
        // menyusut — dan yang dicari hampir selalu yang masih hidup.
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: 'Berjalan (${_aktif.length})'),
            Tab(text: 'Kedaluwarsa (${_lampau.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _terbitkan,
        icon: const Icon(Icons.add),
        label: const Text('Terbitkan Voucher'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Gagal memuat: $_galat',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MerchantPosTheme.mutedOf(context))),
                  ),
                )
              : TabBarView(
                  controller: _tab,
                  children: [
                    _daftar(_aktif, menggantung: menggantung, aktif: true),
                    _daftar(_lampau, menggantung: menggantung, aktif: false),
                  ],
                ),
    );
  }

  Widget _daftar(
    List<Voucher> items, {
    required int menggantung,
    required bool aktif,
  }) {
    return RefreshIndicator(
                  onRefresh: _muat,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
                      children: [
                        // Kartu ringkasannya hanya di tab yang berjalan:
                        // yang menggantung selalu berasal dari voucher
                        // yang belum hangus, jadi mengulangnya di tab
                        // riwayat cuma menimbulkan pertanyaan.
                        if (aktif && _items.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFF59E0B),
                                Color(0xFFB45309),
                              ]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Menggantung di tangan pelanggan',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(_rupiah.format(menggantung),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text(
                                  'Sudah ditebus, belum dipakai. Kembali ke '
                                  'saldo kalau sampai hangus.',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(30),
                            child: Text(
                              aktif
                                  ? 'Belum ada voucher yang berjalan.'
                                  : 'Belum ada voucher yang kedaluwarsa.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: MerchantPosTheme.mutedOf(context)),
                            ),
                          ),
                        for (final v in items)
                          _Kartu(
                            voucher: v,
                            resto: _resto,
                            onToggle: () => _tutupBuka(v),
                            onHapus: () => _hapus(v),
                            onPenebus: () => _lihatPenebus(v),
                          ),
                      ],
                    ),
                  ),
                );
  }
}

class _Kartu extends StatelessWidget {
  final Voucher voucher;
  final List<Restaurant> resto;
  final VoidCallback onToggle;
  final VoidCallback onHapus;
  final VoidCallback onPenebus;

  const _Kartu({
    required this.voucher,
    required this.resto,
    required this.onToggle,
    required this.onHapus,
    required this.onPenebus,
  });

  @override
  Widget build(BuildContext context) {
    final nama = {for (final r in resto) r.id: r.name};
    final (label, warna) = voucher.kedaluwarsa
        ? ('Kedaluwarsa', Colors.grey)
        : !voucher.active
            ? ('Ditutup', Colors.grey)
            : voucher.habis
                ? ('Habis ditebus', Colors.orange)
                : ('Berjalan', Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (voucher.punyaBanner) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.memory(
                  base64Decode(voucher.bannerBase64!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: MerchantPosTheme.brandOf(context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(voucher.code,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: MerchantPosTheme.brandOf(context))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(voucher.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: warna.withOpacity(0.13),
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
          Text(
            '${_rupiah.format(voucher.amount)} × ${voucher.quantity} = '
            '${_rupiah.format(voucher.totalAmount)}',
            style:
                TextStyle(fontSize: 13, color: MerchantPosTheme.brandOf(context)),
          ),
          const SizedBox(height: 3),
          Text(
            'Ditebus ${voucher.claimed}/${voucher.quantity} · '
            'berlaku sampai ${_tanggal.format(voucher.expiresOn)}',
            style:
                TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
          ),
          Text(
            [
              voucher.berlakuDiSemuaResto
                  ? 'Semua merchant'
                  : voucher.restoIds.map((id) => nama[id] ?? id).join(', '),
              if (voucher.minPurchase > 0)
                'min belanja ${_rupiah.format(voucher.minPurchase)}',
              if (voucher.newCustomersOnly) 'khusus pengguna baru',
            ].join(' · '),
            style:
                TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
          ),
          if (voucher.settledAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sisa yang tidak ditebus sudah kembali ke saldo.',
                style: TextStyle(
                    fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: onPenebus,
                icon: const Icon(Icons.group_outlined, size: 16),
                label: Text('Penebus (${voucher.claimed})',
                    style: const TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              const Spacer(),
              // Menyalakannya untuk batch yang masih berjalan cuma
              // memindahkan penolakannya dari mata ke server — dan
              // tombol yang selalu menolak lebih membingungkan
              // daripada tombol yang jelas mati.
              if (voucher.bisaDihapus)
                TextButton(
                  onPressed: onHapus,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Hapus'),
                ),
              TextButton(
                onPressed: voucher.kedaluwarsa ? null : onToggle,
                child: Text(voucher.active ? 'Tutup' : 'Buka lagi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormBatch extends StatefulWidget {
  final List<Restaurant> resto;

  const _FormBatch({required this.resto});

  @override
  State<_FormBatch> createState() => _FormBatchState();
}

class _FormBatchState extends State<_FormBatch> {
  final _formKey = GlobalKey<FormState>();
  final _repo = VoucherRepository();

  final _kode = TextEditingController();
  final _nama = TextEditingController();
  final _total = TextEditingController();
  final _jumlah = TextEditingController(text: '10');
  final _minBelanja = TextEditingController();
  final Set<String> _sasaran = {};
  final _cariResto = TextEditingController();
  String? _banner;
  bool _khususBaru = false;
  DateTime? _kedaluwarsa;
  bool _menyimpan = false;

  /// Resto yang cocok dengan kata kunci pencarian.
  ///
  /// Yang tersaring keluar tetap terpilih kalau sudah dicentang —
  /// mengetik pencarian bukan pernyataan bahwa yang tidak muncul tidak
  /// jadi dipakai.
  List<Restaurant> get _restoTampil {
    final q = _cariResto.text.trim().toLowerCase();
    if (q.isEmpty) return widget.resto;
    return [
      for (final r in widget.resto)
        if (r.name.toLowerCase().contains(q)) r,
    ];
  }

  /// Semua yang sedang tampil sudah tercentang.
  bool get _semuaTampilTerpilih =>
      _restoTampil.isNotEmpty &&
      _restoTampil.every((r) => _sasaran.contains(r.id));

  /// Mencentang atau melepas seluruh yang sedang tampil.
  ///
  /// Terbatas pada yang tampil, bukan seluruh daftar: kalau pencarian
  /// sedang menyaring, "pilih semua" yang diam-diam ikut mencentang
  /// resto yang tidak terlihat adalah voucher yang berlaku di tempat
  /// yang tidak pernah dimaksud.
  void _pilihSemuaTampil() {
    setState(() {
      final tampil = _restoTampil.map((r) => r.id);
      if (_semuaTampilTerpilih) {
        _sasaran.removeAll(tampil);
      } else {
        _sasaran.addAll(tampil);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_kode, _nama, _total, _jumlah, _minBelanja, _cariResto]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _nilaiPer {
    final total = parseRupiah(_total.text) ?? 0;
    final n = int.tryParse(_jumlah.text.trim()) ?? 0;
    if (total <= 0 || n <= 0) return 0;
    return total ~/ n;
  }

  /// Sisa pembagian yang tidak pernah jadi voucher.
  ///
  /// Ditampilkan, bukan dibulatkan diam-diam: yang mengetik Rp 1.000.000
  /// untuk 3 voucher berhak tahu bahwa Rp 1 tidak ikut keluar.
  int get _sisa {
    final total = parseRupiah(_total.text) ?? 0;
    final n = int.tryParse(_jumlah.text.trim()) ?? 0;
    if (total <= 0 || n <= 0) return 0;
    return total - (_nilaiPer * n);
  }

  Future<void> _pilihBanner() async {
    final file = await pickProofPhoto(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (!mounted) return;
    setState(() => _banner = base64Encode(bytes));
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kedaluwarsa == null) {
      AppToast.show(context, 'Pilih tanggal kedaluwarsanya.', isError: true);
      return;
    }

    setState(() => _menyimpan = true);
    try {
      await _repo.generate(
        code: _kode.text.trim().toUpperCase(),
        name: _nama.text.trim(),
        totalAmount: parseRupiah(_total.text) ?? 0,
        quantity: int.tryParse(_jumlah.text.trim()) ?? 0,
        expiresOn: _kedaluwarsa!,
        minPurchase: parseRupiah(_minBelanja.text) ?? 0,
        restoIds: _sasaran.toList(),
        banner: _banner,
        newCustomersOnly: _khususBaru,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      final pesan = '$e'.contains('vouchers_code_key')
          ? 'Kode ini sudah dipakai voucher lain.'
          : 'Gagal menerbitkan: $e';
      AppToast.show(context, pesan, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Terbitkan Voucher')),
      body: Form(
        key: _formKey,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              TextFormField(
                controller: _kode,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  TextInputFormatter.withFunction((lama, baru) =>
                      baru.copyWith(text: baru.text.toUpperCase())),
                ],
                decoration: InputDecoration(
                  label: requiredLabel('Kode Voucher'),
                  hintText: 'HEMAT100',
                  helperText: 'Satu kode untuk seluruh batch — ini yang '
                      'diumumkan ke pelanggan',
                  helperMaxLines: 2,
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Minimal 3 karakter'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nama,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: requiredLabel('Nama Voucher'),
                  hintText: 'Promo Pengguna Baru',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 18),
              const Text('Alokasi Dana',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Dananya keluar dari saldo Merchant-POS saat diterbitkan, dan '
                'kembali lagi kalau tidak ditebus sampai kedaluwarsa.',
                style:
                    TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _total,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: InputDecoration(
                        label: requiredLabel('Total Dana'),
                        prefixText: 'Rp ',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => (parseRupiah(v ?? '') ?? 0) <= 0
                          ? 'Harus lebih dari 0'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _jumlah,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        label: requiredLabel('Jadi berapa'),
                        suffixText: 'voucher',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          (int.tryParse((v ?? '').trim()) ?? 0) <= 0
                              ? 'Minimal 1'
                              : null,
                    ),
                  ),
                ],
              ),
              if (_nilaiPer > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MerchantPosTheme.brandOf(context).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiap voucher bernilai ${_rupiah.format(_nilaiPer)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: MerchantPosTheme.brandOf(context)),
                      ),
                      if (_sisa > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Sisa ${_rupiah.format(_sisa)} tidak ikut '
                            'diterbitkan dan tetap di saldo.',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: MerchantPosTheme.mutedOf(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _minBelanja,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Minimal belanja',
                  prefixText: 'Rp ',
                  helperText: 'Kosong = tanpa minimum',
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final besok = DateTime.now().add(const Duration(days: 1));
                  final pilih = await showDatePicker(
                    context: context,
                    initialDate: _kedaluwarsa ?? besok,
                    firstDate: besok,
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (pilih != null) setState(() => _kedaluwarsa = pilih);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    label: requiredLabel('Kedaluwarsa'),
                    helperText: 'Minimal besok. Voucher yang belum dipakai '
                        'hangus dan dananya kembali ke saldo.',
                    helperMaxLines: 2,
                  ),
                  child: Text(
                    _kedaluwarsa == null
                        ? 'Pilih tanggal'
                        : _tanggal.format(_kedaluwarsa!),
                    style: TextStyle(
                      color: _kedaluwarsa == null
                          ? MerchantPosTheme.mutedOf(context)
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Berlaku di Merchant',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Text(
                    _sasaran.isEmpty
                        ? 'Semua merchant'
                        : '${_sasaran.length} dipilih',
                    style: TextStyle(
                        fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Kosong berarti semua resto, dan itu tidak sama dengan
              // mencentang semuanya satu per satu: daftar yang
              // dicentang membeku pada resto yang ada hari ini, resto
              // yang bergabung bulan depan tidak ikut.
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _cariResto,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Cari merchant',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _cariResto.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () => setState(
                                      () => _cariResto.clear()),
                                ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        _restoTampil.isEmpty ? null : _pilihSemuaTampil,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(
                      _semuaTampilTerpilih ? 'Lepas semua' : 'Pilih semua',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  border: Border.all(color: MerchantPosTheme.borderOf(context)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (_restoTampil.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(
                            'Tidak ada merchant bernama itu',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: MerchantPosTheme.mutedOf(context)),
                          ),
                        ),
                      ),
                    for (final r in _restoTampil)
                      CheckboxListTile(
                        dense: true,
                        value: _sasaran.contains(r.id),
                        title:
                            Text(r.name, style: const TextStyle(fontSize: 13.5)),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sasaran.add(r.id);
                          } else {
                            _sasaran.remove(r.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _khususBaru,
                onChanged: (v) => setState(() => _khususBaru = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Khusus pengguna baru',
                    style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  'Hanya bisa ditebus yang belum pernah memesan lewat '
                  'Merchant-POS, di merchant mana pun.',
                  style: TextStyle(
                      fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Banner 16:9 (opsional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Ikut tampil di Kotak Masuk pelanggan bersama kabar '
                'vouchernya.',
                style: TextStyle(
                    fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              const SizedBox(height: 8),
              if (_banner == null)
                OutlinedButton.icon(
                  onPressed: _pilihBanner,
                  icon: const Icon(Icons.add_photo_alternate_outlined,
                      size: 18),
                  label: const Text('Pilih Gambar'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      // Dipotong ke 16:9 di sini juga, supaya yang
                      // terlihat sekarang sama dengan yang nanti
                      // muncul di kotak masuk — pratinjau yang berbeda
                      // dari hasilnya bukan pratinjau.
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.memory(
                          base64Decode(_banner!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _banner = null),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _menyimpan ? null : _simpan,
                  child: _menyimpan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_nilaiPer > 0
                          ? 'Terbitkan ${_rupiah.format(_nilaiPer * (int.tryParse(_jumlah.text.trim()) ?? 0))}'
                          : 'Terbitkan'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Setelah terbit, umumkan kodenya ke pelanggan lewat Kirim '
                'Pengumuman supaya mereka bisa menebusnya.',
                style:
                    TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Siapa saja yang sudah menebus sebuah batch, dan sampai mana
/// vouchernya.
///
/// Yang ditanya Super Admin biasanya bukan "berapa yang menebus" —
/// angka itu sudah ada di kartunya — melainkan berapa yang benar-benar
/// dipakai. Selisih antara keduanya adalah uang yang masih menggantung
/// dan bisa kembali sendiri kalau sampai hangus.
class _PenebusScreen extends StatefulWidget {
  final Voucher voucher;

  const _PenebusScreen({required this.voucher});

  @override
  State<_PenebusScreen> createState() => _PenebusScreenState();
}

class _PenebusScreenState extends State<_PenebusScreen> {
  final _repo = VoucherRepository();
  List<VoucherClaim> _items = const [];
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final rows = await _repo.claimsOf(widget.voucher.id);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _memuat = false);
      AppToast.show(context, 'Gagal memuat penebus: $e', isError: true);
    }
  }

  /// Kedaluwarsa ditentukan tanggalnya, bukan hanya status tersimpan.
  ///
  /// Penjadwal berjalan sekali sehari; di antara dua jalannya ada
  /// voucher yang statusnya masih `claimed` padahal tanggalnya sudah
  /// lewat. Menampilkannya sebagai "Siap Dipakai" berarti layar ini
  /// menjanjikan sesuatu yang akan ditolak kasir.
  (String, Color) _status(VoucherClaim c) {
    if (c.status == VoucherClaimStatus.used) {
      return ('Sudah dipakai', Colors.green);
    }
    if (c.status == VoucherClaimStatus.expired || c.kedaluwarsa) {
      return ('Hangus', Colors.grey);
    }
    return ('Belum dipakai', Colors.orange);
  }

  @override
  Widget build(BuildContext context) {
    final dipakai =
        _items.where((c) => c.status == VoucherClaimStatus.used).length;
    final hangus = _items
        .where((c) => c.status == VoucherClaimStatus.expired || c.kedaluwarsa)
        .length;
    final menggantung = _items.length - dipakai - hangus;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: Text('Penebus ${widget.voucher.code}')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    Row(
                      children: [
                        _Angka(
                            label: 'Dipakai',
                            nilai: '$dipakai',
                            warna: Colors.green),
                        const SizedBox(width: 8),
                        _Angka(
                            label: 'Menggantung',
                            nilai: '$menggantung',
                            warna: Colors.orange),
                        const SizedBox(width: 8),
                        _Angka(
                            label: 'Hangus',
                            nilai: '$hangus',
                            warna: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          'Belum ada yang menebus voucher ini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                        ),
                      ),
                    for (final c in _items)
                      Builder(builder: (_) {
                        final (label, warna) = _status(c);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: MerchantPosTheme.surfaceOf(context),
                            borderRadius: BorderRadius.circular(11),
                            border:
                                Border.all(color: MerchantPosTheme.borderOf(context)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(c.customerLabel,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ditebus ${_tanggal.format(c.createdAt)}'
                                      '${c.usedAt == null ? '' : ' · dipakai ${_tanggal.format(c.usedAt!)}'}',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: MerchantPosTheme.mutedOf(context)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: warna.withOpacity(0.13),
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
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final String nilai;
  final Color warna;

  const _Angka({required this.label, required this.nilai, required this.warna});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: warna.withOpacity(0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            children: [
              Text(nilai,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: warna)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: MerchantPosTheme.mutedOf(context))),
            ],
          ),
        ),
      );
}
