import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/table_qr_image.dart';
import '../widgets/merchantpos_qr_card.dart';
import '../widgets/responsive.dart';
import '../widgets/required_label.dart';
import '../utils/tautan_meja.dart';

/// Builds the QR sticker a customer scans at their table. The Resto ID is
/// taken from the logged-in employee's own account and shown read-only —
/// an Admin can only ever generate codes for their own restaurant — so
/// the only thing to fill in is the table number.
///
/// The encoded payload is a Merchant-POS web link carrying resto and table —
/// see [tautanMeja]. Bentuk lamanya `RESTO:<restoId>|TABLE:<n>`, which is exactly
/// what [ScanTableScreen]'s parser expects; changing the format here
/// would silently break scanning.
class TableQrGeneratorScreen extends StatefulWidget {
  const TableQrGeneratorScreen({super.key});

  @override
  State<TableQrGeneratorScreen> createState() => _TableQrGeneratorScreenState();
}

class _TableQrGeneratorScreenState extends State<TableQrGeneratorScreen> {
  final _tableCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _countCtrl = TextEditingController(text: '10');
  final _mulaiCtrl = TextEditingController(text: '1');
  final _restoRepo = RestaurantRepository();

  String _restoName = '';
  bool _bulkMode = false;

  /// Berapa kartu yang sudah selesai disimpan, atau null saat tidak ada
  /// penyimpanan yang berjalan.
  int? _savedSoFar;

  @override
  void initState() {
    super.initState();
    _loadRestoName();
  }

  Future<void> _loadRestoName() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await _restoRepo.getOnce(restoId);
      if (!mounted) return;
      setState(() => _restoName = resto?.name ?? restoId);
    } catch (_) {
      // Offline — the ID alone is enough to render a working QR.
      if (mounted) setState(() => _restoName = restoId);
    }
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    _prefixCtrl.dispose();
    _countCtrl.dispose();
    _mulaiCtrl.dispose();
    super.dispose();
  }

  String _payloadFor(String table, String restoId) =>
      tautanMeja(restoId, table);

  /// Daftar meja yang sedang dipilih — satu isinya di mode tunggal,
  /// serentetan di mode banyak.
  ///
  /// Kosong berarti isian layarnya belum sah, dan itu pula yang mematikan
  /// tombol-tombolnya; jadi tidak ada jalan mengekspor sesuatu yang belum
  /// bisa dilihat di layar.
  List<String> get _tables {
    if (!_bulkMode) {
      final raw = _tableCtrl.text.trim();
      return raw.isEmpty ? const [] : [raw];
    }

    final count = int.tryParse(_countCtrl.text.trim());
    if (count == null) return const [];
    return tableLabels(
      prefix: _prefixCtrl.text.trim(),
      count: count,
      mulai: _mulai,
    );
  }

  /// Nomor meja pertama. Kosong dianggap 1 — itu yang paling sering
  /// dipakai, dan memaksa mengetiknya cuma menambah satu isian wajib
  /// untuk hal yang sudah jelas.
  int get _mulai {
    final teks = _mulaiCtrl.text.trim();
    if (teks.isEmpty) return 1;
    return int.tryParse(teks) ?? 0;
  }

  /// Keterangan kenapa mode banyak belum bisa dijalankan, atau null kalau
  /// isiannya sudah sah.
  String? get _bulkProblem {
    if (!_bulkMode) return null;
    final count = int.tryParse(_countCtrl.text.trim());
    if (count == null) return 'Isi jumlah mejanya.';
    if (count < 1) return 'Jumlah meja minimal 1.';
    if (count > kMaxTableBatch) return 'Maksimal $kMaxTableBatch meja sekali buat.';
    if (_mulai < 1) return 'Nomor awal minimal 1.';
    return null;
  }

  List<TableQrCard> _cardsFor(String restoId) {
    final tables = _tables;
    return [
      for (var i = 0; i < tables.length; i++)
        TableQrCard(
          restoName: _restoName.isEmpty ? restoId : _restoName,
          table: tables[i],
          payload: _payloadFor(tables[i], restoId),
          // Urutannya hanya berarti kalau memang dibuat borongan.
          sequence: _bulkMode ? i + 1 : null,
        ),
    ];
  }

  Future<void> _save(String restoId) async {
    final cards = _cardsFor(restoId);
    if (cards.isEmpty) return;

    if (cards.length == 1) {
      await saveTableQrToGallery(context, cards.first);
      return;
    }

    // Tombolnya berubah jadi penghitung selama proses ini — itu juga yang
    // menghalangi tombolnya ditekan dua kali, karena menyimpan puluhan
    // gambar butuh belasan detik dan diam saja selama itu mengundang
    // orang menekannya lagi.
    setState(() => _savedSoFar = 0);
    try {
      await saveTableQrBatchToGallery(
        context,
        cards,
        onProgress: (done) {
          if (mounted) setState(() => _savedSoFar = done);
        },
      );
    } finally {
      if (mounted) setState(() => _savedSoFar = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restoId = context.watch<AuthProvider>().restoId;

    if (restoId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generator QR Meja')),
        body: const Center(child: Text('Akun ini belum punya Merchant ID.')),
      );
    }

    final tables = _tables;
    final busy = _savedSoFar != null;
    final restoName = _restoName.isEmpty ? restoId : _restoName;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Generator QR Meja')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ResponsiveCenter(
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: tables.isEmpty || busy ? null : () => _save(restoId),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      busy
                          ? 'Menyimpan $_savedSoFar/${tables.length}...'
                          : tables.length > 1
                              ? 'Download Semua (${tables.length})'
                              : 'Simpan ke Galeri',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: tables.isEmpty || busy
                      ? null
                      : () => shareTableQrs(context, _cardsFor(restoId)),
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Bagikan',
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: tables.isEmpty || busy
                      ? null
                      : () => printTableQrs(context, _cardsFor(restoId)),
                  icon: const Icon(Icons.print_outlined),
                  tooltip: 'Cetak',
                ),
              ],
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          children: [
            _Card(
              icon: Icons.storefront_outlined,
              color: MerchantPosTheme.brand,
              title: 'Data Merchant',
              subtitle: 'Otomatis dari akun yang sedang login',
              children: [
                // Resto ID sengaja tidak ditampilkan di sini. Itu kunci
                // internal yang tidak berarti apa-apa bagi admin, dan
                // memajangnya cuma mengundang orang menyalin lalu
                // mengetikkannya di tempat yang salah. Namanya sudah cukup
                // untuk memastikan QR ini milik resto yang benar.
                if (_restoName.isNotEmpty) ...[
                  TextFormField(
                    key: ValueKey(_restoName),
                    initialValue: _restoName,
                    // Tidak bisa diubah, tapi bukan "dinonaktifkan".
                    // `enabled: false` mewarnai isinya dengan warna
                    // disabled tema, dan di mode gelap itu membuat nama
                    // merchantnya nyaris tak terbaca — padahal justru
                    // nama itu yang dipakai memastikan QR-nya milik
                    // merchant yang benar.
                    readOnly: true,
                    canRequestFocus: false,
                    style: TextStyle(color: MerchantPosTheme.textOf(context)),
                    decoration: InputDecoration(
                      labelText: 'Nama Merchant',
                      filled: true,
                      fillColor: MerchantPosTheme.disabledFillOf(context),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _Card(
              icon: Icons.table_restaurant_outlined,
              color: MerchantPosTheme.accent,
              title: 'Nomor Meja',
              subtitle: _bulkMode
                  ? 'Buat sederet meja sekaligus'
                  : 'QR akan langsung berubah saat diketik',
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.looks_one_outlined, size: 18),
                      label: Text('Satu Meja'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.grid_view_outlined, size: 18),
                      label: Text('Banyak Meja'),
                    ),
                  ],
                  selected: {_bulkMode},
                  onSelectionChanged: busy
                      ? null
                      : (value) => setState(() => _bulkMode = value.first),
                ),
                const SizedBox(height: 14),
                if (!_bulkMode)
                  TextFormField(
                    controller: _tableCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      label: requiredLabel('Nomor Meja'),
                      hintText: 'Contoh: 7, A01, VIP-2',
                      prefixIcon: const Icon(Icons.tag),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    onChanged: (_) => setState(() {}),
                  )
                else
                  _BulkFields(
                    prefixCtrl: _prefixCtrl,
                    countCtrl: _countCtrl,
                    mulaiCtrl: _mulaiCtrl,
                    problem: _bulkProblem,
                    tables: tables,
                    onChanged: () => setState(() {}),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (tables.isEmpty)
              const _EmptyPreview()
            else ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  tables.length == 1 ? 'Pratinjau' : 'Pratinjau · ${tables.length} meja',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: MerchantPosTheme.mutedOf(context),
                  ),
                ),
              ),
              // Di mode banyak hanya meja pertama yang digambar penuh.
              // Empat puluh QR hidup sekaligus berarti empat puluh kali
              // perhitungan matriks tiap kali satu huruf awalan diketik,
              // dan yang ingin dilihat orangnya cuma "bentuknya sudah
              // benar belum" — bukan keempat puluhnya satu per satu.
              _QrPreview(
                restoName: restoName,
                table: tables.first,
                payload: _payloadFor(tables.first, restoId),
              ),
              if (tables.length > 1) ...[
                const SizedBox(height: 12),
                _TableChips(tables: tables),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BulkFields extends StatelessWidget {
  final TextEditingController prefixCtrl;
  final TextEditingController countCtrl;
  final TextEditingController mulaiCtrl;
  final String? problem;
  final List<String> tables;
  final VoidCallback onChanged;

  const _BulkFields({
    required this.prefixCtrl,
    required this.countCtrl,
    required this.mulaiCtrl,
    required this.problem,
    required this.tables,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: prefixCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Awalan (opsional)',
            hintText: 'Contoh: A, VIP-',
            prefixIcon: Icon(Icons.text_fields),
            counterText: '',
            helperText: 'Kosongkan kalau mejanya cuma bernomor. '
                'Diisi "A" jadi A1, A2, A3, …',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        // Nomor awal, bukan selalu 1.
        //
        // Merchant yang menambah lantai dua tidak mulai dari meja 1
        // lagi — dan tanpa isian ini, satu-satunya jalan adalah membuat
        // 30 QR lalu membuang 15 yang pertama.
        TextFormField(
          controller: mulaiCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 3,
          decoration: const InputDecoration(
            labelText: 'Nomor Awal',
            hintText: '1',
            prefixIcon: Icon(Icons.first_page),
            counterText: '',
            helperText: 'Kosongkan kalau mulai dari 1.',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: countCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 3,
          autofocus: true,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          decoration: InputDecoration(
            label: requiredLabel('Jumlah Meja'),
            hintText: 'Contoh: 10',
            prefixIcon: const Icon(Icons.tag),
            counterText: '',
            helperText: 'Nomornya dibuat urut mulai dari 1',
          ),
          onChanged: (_) => onChanged(),
        ),
        if (problem != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.redAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  problem!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ] else if (tables.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${tables.length} QR akan dibuat: meja ${tables.first} sampai ${tables.last}',
            style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
          ),
        ],
      ],
    );
  }
}

/// Daftar ringkas nomor meja yang ikut dibuat.
///
/// Pratinjaunya hanya menggambar meja pertama, jadi tanpa daftar ini
/// tidak ada cara memastikan rentangnya benar-benar berhenti di tempat
/// yang dimaksud sebelum puluhan gambar telanjur masuk galeri.
class _TableChips extends StatelessWidget {
  final List<String> tables;

  const _TableChips({required this.tables});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MerchantPosTheme.softFillOf(context)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final table in tables)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MerchantPosTheme.brand.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                table,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MerchantPosTheme.brandDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pratinjau kartu QR.
///
/// Bentuknya dipinjam dari [MerchantPosQrCard], widget yang sama yang dipakai
/// layar pembayaran pelanggan — jadi yang dilihat admin di sini memang
/// bentuk yang sama dengan yang dikenali pelanggan di tempat lain.
class _QrPreview extends StatelessWidget {
  final String restoName;
  final String table;
  final String payload;

  const _QrPreview({
    required this.restoName,
    required this.table,
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MerchantPosQrCard(
        data: payload,
        title: restoName,
        badge: 'MEJA $table',
        width: 300,
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MerchantPosTheme.softFillOf(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_2, size: 56, color: MerchantPosTheme.borderOf(context)),
          const SizedBox(height: 12),
          Text('Isi nomor meja untuk membuat QR',
              style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 13)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: MerchantPosTheme.softFillOf(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}
