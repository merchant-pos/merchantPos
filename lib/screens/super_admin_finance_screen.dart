import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/billing_repository.dart';
import '../db/gl_journal_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/billing.dart';
import '../models/gl_journal_entry.dart';
import '../theme.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/responsive.dart';
import 'billing_discount_screen.dart';
import 'voucher_screen.dart';
import 'finance_balance_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_journal_screen.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Keuangan Merchant-POS sendiri — bukan keuangan resto.
///
/// Seluruh isinya memakai mesin pembukuan yang sama persis dengan resto,
/// hanya dengan penyewa yang berbeda: Merchant-POS punya barisnya sendiri di
/// tabel restaurants, ditandai `is_platform`. Itulah kenapa layar Saldo,
/// Mapping GL, dan Jurnal di bawah bisa dipakai apa adanya.
///
/// Yang **tidak** ada di sini: Setor Saldo Cash. Menyetor tunai ke
/// rekening sendiri adalah pekerjaan resto yang uangnya menumpuk di
/// laci; Merchant-POS tidak punya laci.
class SuperAdminFinanceScreen extends StatelessWidget {
  const SuperAdminFinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Finance Merchant-POS')),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('PENDAPATAN',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: MerchantPosTheme.mutedOf(context))),
            const SizedBox(height: 10),
            HubMenuTile(
              icon: Icons.receipt_long_outlined,
              title: 'Riwayat Langganan',
              subtitle: 'Tagihan yang sudah dibayar merchant, per bulan',
              color: const Color(0xFF10B981),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BillingHistoryScreen(),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.local_offer_outlined,
              title: 'Diskon Langganan',
              subtitle: 'Potongan harga untuk merchant tertentu',
              color: const Color(0xFF6366F1),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BillingDiscountScreen(),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.confirmation_number_outlined,
              title: 'Voucher Pelanggan',
              subtitle: 'Promo Merchant-POS — ditanggung dari saldo sendiri',
              color: const Color(0xFFF59E0B),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const VoucherScreen(),
              )),
            ),
            const SizedBox(height: 22),
            Text('PEMBUKUAN KAATAGO',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: MerchantPosTheme.mutedOf(context))),
            const SizedBox(height: 10),
            HubMenuTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Saldo & Pengeluaran',
              subtitle: 'Petty cash dan pengeluaran Merchant-POS',
              color: const Color(0xFF0EA5E9),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FinanceBalanceScreen(restoId: kPlatformRestoId),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.tag,
              title: 'Mapping GL Account',
              subtitle: 'Nomor akun pendapatan, diskon, dan pengeluaran',
              color: const Color(0xFF8B5CF6),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FinanceGlMappingScreen(restoId: kPlatformRestoId),
              )),
            ),
            const SizedBox(height: 12),
            HubMenuTile(
              icon: Icons.menu_book_outlined,
              title: 'Jurnal GL Merchant-POS',
              subtitle: 'Pergerakan uang di pembukuan Merchant-POS',
              color: const Color(0xFF14B8A6),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const FinanceJournalScreen(restoId: kPlatformRestoId),
              )),
            ),
            const SizedBox(height: 22),
            Text('SELURUH RESTO',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: MerchantPosTheme.mutedOf(context))),
            const SizedBox(height: 10),
            HubMenuTile(
              icon: Icons.travel_explore_outlined,
              title: 'Jurnal GL Semua Merchant',
              subtitle: 'Pembukuan merchant klien, hanya untuk dilihat',
              color: const Color(0xFF64748B),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AllRestoJournalScreen(),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

/// Riwayat tagihan langganan yang sudah dibayar.
class BillingHistoryScreen extends StatefulWidget {
  const BillingHistoryScreen({super.key});

  @override
  State<BillingHistoryScreen> createState() => _BillingHistoryScreenState();
}

class _BillingHistoryScreenState extends State<BillingHistoryScreen> {
  final _repo = BillingRepository();
  List<BillingInvoice> _items = const [];
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
      final items = await _repo.paidInvoices();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(0, (a, b) => a + b.amount);
    final diskon = _items.fold<int>(0, (a, b) => a + b.discountAmount);

    // Dikelompokkan per bulan pembayaran. Yang ingin diketahui dari
    // layar ini hampir selalu "bulan ini masuk berapa", bukan urutan
    // tagihan satu per satu.
    final perBulan = <String, List<BillingInvoice>>{};
    for (final i in _items) {
      final k = DateFormat('MMMM yyyy', 'id_ID')
          .format(i.confirmedAt ?? i.dueDate);
      perBulan.putIfAbsent(k, () => []).add(i);
    }

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Riwayat Langganan')),
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
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFF10B981),
                              Color(0xFF047857),
                            ]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Diterima',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12.5)),
                              const SizedBox(height: 6),
                              Text(_rupiah.format(total),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(
                                '${_items.length} tagihan'
                                '${diskon > 0 ? ' · diskon ${_rupiah.format(diskon)}' : ''}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: Text('Belum ada tagihan yang dibayar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: MerchantPosTheme.mutedOf(context))),
                          ),
                        for (final entry in perBulan.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 6),
                            child: Row(
                              children: [
                                Text(entry.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const Spacer(),
                                Text(
                                  _rupiah.format(entry.value
                                      .fold<int>(0, (a, b) => a + b.amount)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          for (final i in entry.value) _BarisTagihan(invoice: i),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _BarisTagihan extends StatelessWidget {
  final BillingInvoice invoice;
  const _BarisTagihan({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final lewatMesin = invoice.paidVia == 'xendit_va';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.restoName ?? invoice.restoId,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(
                  '${invoice.id} · '
                  '${_tanggal.format(invoice.confirmedAt ?? invoice.dueDate)}',
                  style: TextStyle(
                      fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                ),
                if (invoice.discountAmount > 0)
                  Text(
                    '${invoice.discountName ?? 'Diskon'} '
                    '−${_rupiah.format(invoice.discountAmount)}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.orange),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_rupiah.format(invoice.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(height: 2),
              // Yang dibedakan adalah bagaimana tagihannya dinyatakan
              // lunas, bukan cara transfernya — dan itu perlu ditulis
              // utuh. "manual" sendirian tidak memberi tahu siapa pun
              // apa yang terjadi; yang membacanya enam bulan lagi akan
              // menebak, dan menebak soal uang selalu mahal.
              Text(
                lewatMesin ? 'Lunas via VA' : 'Dikonfirmasi manual',
                style: TextStyle(
                  fontSize: 10.5,
                  color: lewatMesin
                      ? Colors.green
                      : MerchantPosTheme.mutedOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Jurnal GL seluruh resto — hanya untuk dilihat.
///
/// Tidak ada satu pun tombol yang mengubah isinya, dan itu bukan
/// kelalaian: tiap baris jurnal ditulis pemicu yang mengikuti kejadian
/// nyata di pesanan dan pengeluaran. Tangan yang bisa menulis langsung
/// ke sini adalah tangan yang bisa membuat pembukuan berbeda dari yang
/// benar-benar terjadi — dan itu berlaku untuk Super Admin persis
/// seperti untuk yang lain.
class AllRestoJournalScreen extends StatefulWidget {
  const AllRestoJournalScreen({super.key});

  @override
  State<AllRestoJournalScreen> createState() => _AllRestoJournalScreenState();
}

class _AllRestoJournalScreenState extends State<AllRestoJournalScreen> {
  final _repo = GlJournalRepository();
  final _restoRepo = RestaurantRepository();

  List<GlJournalEntry> _semua = const [];
  Map<String, String> _namaResto = const {};
  String? _saring;

  /// Tanggal yang sedang terbuka. Diisi saat memuat dengan tanggal
  /// terbaru saja — hari itu yang hampir selalu dicari, dan membuka
  /// semuanya menenggelamkannya di bawah berminggu-minggu sebelumnya.
  final Set<DateTime> _dibuka = {};
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
      final entries = await _repo.getAll();
      final resto = await _restoRepo.getAll(includeDeleted: true);
      if (!mounted) return;
      setState(() {
        _semua = entries;
        // Merchant-POS tidak ikut: layar ini khusus pembukuan resto klien.
        // Pembukuan sendiri punya layarnya sendiri di menu di atas.
        _namaResto = {for (final r in resto) r.id: r.name};
        _dibuka
          ..clear()
          ..addAll(entries.isEmpty ? const [] : [_hari(entries.first.entryDate)]);
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

  static DateTime _hari(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Pembalikan ditulis dengan (reference_type, reference_id, gl_code)
  /// yang sama dengan baris yang dibatalkannya — tiga itu yang
  /// memasangkan keduanya.
  String _kunciPasangan(GlJournalEntry e) =>
      '${e.referenceType}|${e.referenceId}|${e.glCode}';

  /// Baris yang masih ikut dihitung: bukan pembatalan, dan bukan baris
  /// yang dibatalkan.
  ///
  /// Menjumlahkan semuanya membuat pembatalan justru MENAIKKAN kedua
  /// totalnya — baris aslinya tetap masuk, lalu baris kebalikannya
  /// menambah cerminnya di atas itu. Aturannya sama persis dengan
  /// Jurnal GL per resto; kalau di sini berbeda, dua layar yang membaca
  /// data sama akan menyebut angka berbeda, dan yang membacanya tidak
  /// punya cara tahu mana yang benar.
  List<GlJournalEntry> _berlaku(List<GlJournalEntry> dari) {
    final dibatalkan = dari
        .where((e) => e.isReversal)
        .map(_kunciPasangan)
        .toSet();
    return dari
        .where((e) => !e.isReversal && !dibatalkan.contains(_kunciPasangan(e)))
        .toList();
  }

  Future<void> _pilihResto() async {
    final punyaJurnal = _semua.map((e) => e.restoId).toSet();
    final pilihan = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Saring per Merchant',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.clear_all),
                    title: const Text('Semua merchant'),
                    trailing: _saring == null
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    // Nilai sentinel, bukan null. PopupMenuButton dan
                    // showModalBottomSheet sama-sama membaca null sebagai
                    // "dibatalkan" — pilihan yang mengembalikan null tidak
                    // pernah sampai ke pemanggilnya, dan tombol "Semua
                    // resto" terlihat rusak.
                    onTap: () => Navigator.pop(context, '*'),
                  ),
                  const Divider(height: 1),
                  for (final e in _namaResto.entries)
                    ListTile(
                      leading: Icon(
                        e.key == kPlatformRestoId
                            ? Icons.workspace_premium_outlined
                            : Icons.storefront_outlined,
                        size: 20,
                      ),
                      title: Text(e.value),
                      // Resto tanpa satu baris pun disebut apa adanya,
                      // supaya "kosong" tidak terbaca sebagai saringan
                      // yang rusak.
                      subtitle: punyaJurnal.contains(e.key)
                          ? null
                          : const Text('Belum ada jurnal',
                              style: TextStyle(fontSize: 11)),
                      trailing: _saring == e.key
                          ? const Icon(Icons.check, size: 18)
                          : null,
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pilihan == null) return;
    setState(() => _saring = pilihan == '*' ? null : pilihan);
  }

  @override
  Widget build(BuildContext context) {
    final tampil = _saring == null
        ? _semua
        : _semua.where((e) => e.restoId == _saring).toList();
    final berlaku = _berlaku(tampil);
    final pembatalan = tampil.where((e) => e.isReversal).length;

    final debit = berlaku
        .where((e) => e.entryType == JournalEntryType.debit)
        .fold<int>(0, (a, b) => a + b.amount);
    final kredit = berlaku
        .where((e) => e.entryType == JournalEntryType.credit)
        .fold<int>(0, (a, b) => a + b.amount);

    // Dikelompokkan per tanggal, dan bisa dilipat. Tanpa itu, layar ini
    // adalah satu daftar panjang tanpa batas yang bisa dipakai mata
    // untuk berhenti.
    final perTanggal = <DateTime, List<GlJournalEntry>>{};
    for (final e in tampil) {
      perTanggal.putIfAbsent(_hari(e.entryDate), () => []).add(e);
    }
    final tanggal = perTanggal.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Jurnal GL Semua Merchant'),
        // Ikon saring di pojok kanan atas tidak ditampilkan di web.
        //
        // Saringan yang sama sudah berdiri sebagai pita di bawah judul,
        // menyebutkan merchant yang sedang berlaku dan bisa diketuk.
        // Dua pintu ke satu saringan membuat yang satu tampak
        // melakukan hal lain — dan yang berupa ikon tanpa label
        // adalah yang lebih sulit ditebak isinya.
        actions: kIsWeb
            ? null
            : [
                IconButton(
                  tooltip: 'Saring per merchant',
                  icon: const Icon(Icons.filter_list),
                  onPressed: _memuat ? null : _pilihResto,
                ),
              ],
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      color: MerchantPosTheme.surfaceOf(context),
                      child: ResponsiveCenter(
                        child: Column(
                          children: [
                            // Saringan yang sedang berlaku ditulis di
                            // layar, bukan cuma tersimpan di kepala orang
                            // yang menekannya. Angka yang lebih kecil
                            // daripada yang diingat selalu jadi kecurigaan
                            // lebih dulu, bukan saringan yang terlupa.
                            _PitaSaringan(
                              nama: _saring == null
                                  ? 'Semua merchant'
                                  : _namaResto[_saring] ?? _saring!,
                              menyaring: _saring != null,
                              onUbah: _pilihResto,
                              onHapus:
                                  _saring == null ? null : () => setState(() => _saring = null),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _Angka(
                                      label: 'Total Debit',
                                      nilai: debit,
                                      warna: Colors.red),
                                ),
                                Expanded(
                                  child: _Angka(
                                      label: 'Total Kredit',
                                      nilai: kredit,
                                      warna: Colors.green),
                                ),
                                Expanded(
                                  child: _Angka(
                                      label: 'Baris',
                                      nilai: berlaku.length,
                                      warna: MerchantPosTheme.mutedOf(context),
                                      rupiah: false),
                                ),
                              ],
                            ),
                            if (pembatalan > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '$pembatalan pembatalan tidak dihitung',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: MerchantPosTheme.mutedOf(context)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: tampil.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(30),
                                child: Text(
                                  _saring == null
                                      ? 'Belum ada jurnal.'
                                      : '${_namaResto[_saring] ?? _saring} belum '
                                          'punya jurnal.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: MerchantPosTheme.mutedOf(context)),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _muat,
                              // Tanpa pembatas lebar, sama seperti
                              // Jurnal GL Merchant-POS di sebelahnya.
                              //
                              // Daftarnya bukan bacaan mengalir yang
                              // barisnya perlu dipendekkan supaya
                              // nyaman dibaca — tiap barisnya kartu
                              // bertumpu pada nomor akun di kiri dan
                              // nominal di kanan, dan justru jarak
                              // itulah yang membuat keduanya terbaca
                              // sebagai sepasang.
                              child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 12, 14, 28),
                                  itemCount: tanggal.length,
                                  itemBuilder: (_, i) {
                                    final hari = tanggal[i];
                                    return _KelompokTanggal(
                                      tanggal: hari,
                                      entries: perTanggal[hari]!,
                                      namaResto: _namaResto,
                                      terbuka: _dibuka.contains(hari),
                                      onToggle: () => setState(() {
                                        _dibuka.contains(hari)
                                            ? _dibuka.remove(hari)
                                            : _dibuka.add(hari);
                                      }),
                                    );
                                  },
                                ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _PitaSaringan extends StatelessWidget {
  final String nama;
  final bool menyaring;
  final VoidCallback onUbah;
  final VoidCallback? onHapus;

  const _PitaSaringan({
    required this.nama,
    required this.menyaring,
    required this.onUbah,
    this.onHapus,
  });

  @override
  Widget build(BuildContext context) {
    final warna = menyaring
        ? MerchantPosTheme.brandOf(context)
        : MerchantPosTheme.mutedOf(context);
    return InkWell(
      onTap: onUbah,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
        decoration: BoxDecoration(
          color: warna.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: warna.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(menyaring ? Icons.storefront_outlined : Icons.all_inclusive,
                size: 15, color: warna),
            const SizedBox(width: 7),
            Flexible(
              child: Text(nama,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: warna)),
            ),
            const SizedBox(width: 4),
            if (onHapus != null)
              GestureDetector(
                onTap: onHapus,
                child: Icon(Icons.close, size: 15, color: warna),
              )
            else
              Icon(Icons.expand_more, size: 16, color: warna),
          ],
        ),
      ),
    );
  }
}

class _KelompokTanggal extends StatelessWidget {
  final DateTime tanggal;
  final List<GlJournalEntry> entries;
  final Map<String, String> namaResto;
  final bool terbuka;
  final VoidCallback onToggle;

  const _KelompokTanggal({
    required this.tanggal,
    required this.entries,
    required this.namaResto,
    required this.terbuka,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hari = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(tanggal);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(hari,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13.5)),
                  ),
                  Text('${entries.length} baris',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: MerchantPosTheme.mutedOf(context))),
                  const SizedBox(width: 6),
                  Icon(terbuka ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: MerchantPosTheme.brandOf(context)),
                ],
              ),
            ),
          ),
          if (terbuka)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 8),
              child: Column(
                children: [
                  for (final e in entries)
                    _BarisJurnal(
                      entry: e,
                      namaResto: namaResto[e.restoId] ?? e.restoId,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final int nilai;
  final Color warna;
  final bool rupiah;

  const _Angka({
    required this.label,
    required this.nilai,
    required this.warna,
    this.rupiah = true,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: MerchantPosTheme.mutedOf(context))),
          const SizedBox(height: 3),
          Text(rupiah ? _rupiah.format(nilai) : '$nilai',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: warna)),
        ],
      );
}

class _BarisJurnal extends StatelessWidget {
  final GlJournalEntry entry;
  final String namaResto;

  const _BarisJurnal({required this.entry, required this.namaResto});

  @override
  Widget build(BuildContext context) {
    final masuk = entry.entryType == JournalEntryType.credit;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      child: Row(
        children: [
          Icon(masuk ? Icons.south_west : Icons.north_east,
              size: 17, color: masuk ? Colors.green : Colors.red),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('${entry.glCode} — ${entry.glName ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12.5)),
                    ),
                    // Barisnya tetap ditampilkan walau tidak ikut
                    // dihitung. Menyembunyikannya berarti jejak auditnya
                    // hilang justru pada kejadian yang paling perlu
                    // ditelusuri.
                    if (entry.isReversal)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('PEMBATALAN',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$namaResto · ${_tanggal.format(entry.entryDate)} '
                  '${entry.entryTime.substring(0, 5)}',
                  style: TextStyle(
                      fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
                ),
                if (entry.description != null)
                  Text(entry.description!,
                      style: TextStyle(
                          fontSize: 11,
                          color: MerchantPosTheme.mutedOf(context))),
              ],
            ),
          ),
          Text(
            _rupiah.format(entry.amount),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: masuk ? Colors.green : Colors.red),
          ),
        ],
      ),
    );
  }
}
