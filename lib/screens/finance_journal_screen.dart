import '../models/billing.dart';
import '../utils/saldo_jurnal.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../db/gl_account_repository.dart';
import '../db/gl_journal_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/gl_account.dart';
import '../models/gl_journal_entry.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../widgets/responsive.dart';

const _referenceTypeLabels = {
  'order': 'Pesanan',
  'expense': 'Pengeluaran',
  'petty_cash': 'Petty Cash',
};

/// Read-only view of every real money movement — orders that got paid,
/// expenses (with the balance that funded them), and Petty Cash top-ups —
/// written automatically by database triggers, grouped by date. Nothing
/// here is editable: this is an audit trail, not a data-entry screen.
///
/// Deleting the underlying record doesn't erase its rows; it appends a
/// reversal instead (shown greyed out with a "Pembatalan" tag), so the
/// history stays honest about what happened and when.
class FinanceJournalScreen extends StatefulWidget {
  /// Resto yang dibukukan. Kosong berarti resto tempat orangnya bekerja.
  ///
  /// Diisi hanya oleh menu Finance Super Admin, yang membukukan Merchant-POS
  /// sendiri — penyewa platform yang memakai mesin pembukuan yang sama
  /// persis dengan resto.
  final String? restoId;

  const FinanceJournalScreen({super.key, this.restoId});

  @override
  State<FinanceJournalScreen> createState() => _FinanceJournalScreenState();
}

class _FinanceJournalScreenState extends State<FinanceJournalScreen> {
  final _repo = GlJournalRepository();
  final _glRepo = GlAccountRepository();
  final _restoRepo = RestaurantRepository();
  List<GlJournalEntry> _entries = [];
  GlAccount? _totalBalanceGl;
  String _restoName = '';
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final restoId = widget.restoId ?? context.read<AuthProvider>().restoId!;
      final results = await Future.wait([
        _repo.getForResto(restoId),
        _glRepo.getForResto(restoId),
        _restoRepo.getOnce(restoId),
      ]);
      if (!mounted) return;
      final glAccounts = results[1] as List<GlAccount>;
      final resto = results[2] as Restaurant?;
      setState(() {
        _entries = results[0] as List<GlJournalEntry>;
        _totalBalanceGl = glAccounts
            .where((g) => g.paymentMethod == 'total_balance' && g.glCode.isNotEmpty)
            .firstOrNull;
        _restoName = resto?.name ?? restoId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  /// A reversal is written with the same (reference_type, reference_id,
  /// gl_code) as the row it undoes — that triple is what pairs the two up.
  String _pairKey(GlJournalEntry e) => '${e.referenceType}|${e.referenceId}|${e.glCode}';

  Set<String> get _cancelledKeys =>
      _entries.where((e) => e.isReversal).map(_pairKey).toSet();

  /// Rows that still count toward the totals: neither a cancellation nor
  /// the entry one cancelled.
  ///
  /// Summing every row instead made a cancellation *raise* both totals —
  /// the original debit/credit stayed in, and the contra entry added its
  /// mirror on top — so undoing a Rp 100.000 expense pushed Total Debit
  /// and Total Kredit up by Rp 100.000 each rather than clearing it.
  /// Both rows stay visible in the list below for audit; they just stop
  /// contributing here.
  List<GlJournalEntry> get _effectiveEntries {
    final cancelled = _cancelledKeys;
    return _entries
        .where((e) => !e.isReversal && !cancelled.contains(_pairKey(e)))
        .toList();
  }

  int get _cancelledCount => _entries.where((e) => e.isReversal).length;

  int get _totalDebit => _effectiveEntries
      .where((e) => e.entryType == JournalEntryType.debit)
      .fold(0, (sum, e) => sum + e.amount);

  int get _totalCredit => _effectiveEntries
      .where((e) => e.entryType == JournalEntryType.credit)
      .fold(0, (sum, e) => sum + e.amount);

  /// The balance this journal implies — derived the same way Saldo &
  /// Pengeluaran derives it, so the two screens agree.
  ///
  /// Debit and credit totals are *gross movement*, not balance. Moving
  /// income into Petty Cash books a debit and a credit of the same
  /// amount, and paying an expense books its funding leg too, so those
  /// totals climb well past the money actually on hand — which made this
  /// card look like it was reporting a much larger balance than it was.
  int get _saldoTotal {
    // Pembukuan Merchant-POS dihitung dari pergerakan akun GL Total Saldo,
    // bukan dari daftar jenis transaksi. Daftar semacam itu harus
    // ditambahi tiap kali ada fitur baru yang memindahkan uang — dan
    // saat voucher terbit, jenisnya belum ada di daftar sehingga
    // seluruh pergerakannya tidak terhitung sama sekali.
    final kodeTotal = _totalBalanceGl?.glCode;
    if (widget.restoId == kPlatformRestoId && kodeTotal != null) {
      return saldoPlatform(_entries, kodeTotal);
    }

    final effective = _effectiveEntries;

    // Pendapatan datang dari dua sumber, tergantung siapa yang
    // dibukukan: penjualan resto ('order') dan biaya langganan yang
    // dibayar resto ke Merchant-POS ('billing'). Menyebut 'order' saja
    // membuat pembukuan Merchant-POS berbunyi Rp 0 selamanya — seluruh
    // pendapatannya memang tidak pernah berasal dari pesanan.
    const sumberPemasukan = {'order', 'billing'};

    // Yang mengurangi: pengeluaran, dan diskon langganan.
    //
    // `order_discount` sengaja TIDAK ikut. Kedua sisi mencatat diskon
    // dengan cara yang berbeda, dan itu menentukan mana yang boleh
    // dikurangi di sini:
    //
    //   pesanan resto  → `orders.total` sudah BERSIH sesudah potongan,
    //                    jadi kreditnya sudah dikurangi. Menguranginya
    //                    lagi di sini menghitung potongan yang sama dua
    //                    kali, dan tiap resto berdiskon akan terlihat
    //                    lebih miskin daripada isi lacinya.
    //
    //   langganan      → dikredit sebesar HARGA DAFTAR, potongannya
    //                    berdiri sebagai debit tersendiri. Di sini
    //                    justru harus dikurangi.
    const sumberPengurang = {'expense', 'billing_discount'};

    final income = effective
        .where((e) =>
            sumberPemasukan.contains(e.referenceType) &&
            e.entryType == JournalEntryType.credit)
        .fold(0, (sum, e) => sum + e.amount);

    final expenses = effective
        .where((e) =>
            sumberPengurang.contains(e.referenceType) &&
            e.entryType == JournalEntryType.debit)
        .fold(0, (sum, e) => sum + e.amount);

    // Pemindahan antar kantong sendiri membukukan dua kaki sekaligus —
    // satu keluar, satu masuk — jadi bersihnya nol dan tidak menambah
    // saldo. Top up manual hanya punya satu kaki: itu modal dari luar,
    // dan memang menaikkan saldo.
    //
    // Dikenali dari jumlah kakinya, bukan dari arahnya. Bergantung pada
    // "ada debit tanpa kredit" membuat perhitungan ini ikut salah begitu
    // arah jurnalnya diperbaiki — dan itu sudah pernah terjadi.
    final legsByRef = <String, List<GlJournalEntry>>{};
    for (final e in effective.where((e) => e.referenceType == 'petty_cash')) {
      legsByRef.putIfAbsent(e.referenceId, () => []).add(e);
    }

    var manualTopUps = 0;
    for (final legs in legsByRef.values) {
      final hasIn = legs.any((e) => e.entryType == JournalEntryType.credit);
      final hasOut = legs.any((e) => e.entryType == JournalEntryType.debit);
      if (hasIn && hasOut) continue; // pindah kantong, bersihnya nol
      for (final leg in legs) {
        manualTopUps +=
            leg.entryType == JournalEntryType.credit ? leg.amount : -leg.amount;
      }
    }

    return income - expenses + manualTopUps;
  }

  /// Same date grouping as the on-screen list, rendered as a
  /// print/share-able PDF via the OS sheet. Each day gets its own header
  /// row and a per-day debit/credit subtotal, so the export reads like a
  /// proper ledger rather than one flat dump.
  Future<void> _exportPdf() async {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dayFmt = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');
    // The pdf package's base-14 font has no glyphs for "—" or "•", which
    // show up in GL names and descriptions — load a full Unicode face.
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final groups = _groupByDay();
    final cancelledKeys = _cancelledKeys;
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Merchant-POS — Jurnal GL',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(_restoName, style: const pw.TextStyle(fontSize: 13)),
            if (_totalBalanceGl != null)
              pw.Text('GL Total Saldo: ${_totalBalanceGl!.glCode} — ${_totalBalanceGl!.glName}',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.SizedBox(height: 10),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount} • '
            'Dicetak ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Saldo Total: ${currency.format(_saldoTotal)}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('Debit: ${currency.format(_totalDebit)}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Kredit: ${currency.format(_totalCredit)}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text(
                    _cancelledCount > 0
                        ? '${_entries.length} baris ($_cancelledCount dibatalkan)'
                        : '${_entries.length} baris',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          if (groups.isEmpty)
            pw.Text('Belum ada pergerakan tercatat.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))
          else
            for (final group in groups) ...[
              pw.SizedBox(height: 6),
              pw.Text(dayFmt.format(group.day),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.1),
                  1: const pw.FlexColumnWidth(3.2),
                  2: const pw.FlexColumnWidth(3.0),
                  3: const pw.FlexColumnWidth(1.8),
                  4: const pw.FlexColumnWidth(1.8),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _pdfCell('Jam', bold: true),
                      _pdfCell('GL Account', bold: true),
                      _pdfCell('Keterangan', bold: true),
                      _pdfCell('Debit', bold: true, align: pw.TextAlign.right),
                      _pdfCell('Kredit', bold: true, align: pw.TextAlign.right),
                    ],
                  ),
                  for (final e in group.entries)
                    pw.TableRow(children: [
                      _pdfCell(e.entryTime.substring(0, 5)),
                      _pdfCell(e.glName == null || e.glName!.isEmpty
                          ? e.glCode
                          : '${e.glCode} — ${e.glName}'),
                      _pdfCell(
                        '${_referenceTypeLabels[e.referenceType] ?? e.referenceType} '
                        '#${e.referenceId.substring(0, 8).toUpperCase()}'
                        '${e.isReversal ? ' [PEMBATALAN]' : ''}'
                        '${!e.isReversal && cancelledKeys.contains(_pairKey(e)) ? ' [DIBATALKAN]' : ''}'
                        '${e.description != null && e.description!.isNotEmpty ? '\n${e.description}' : ''}',
                      ),
                      _pdfCell(
                          e.entryType == JournalEntryType.debit ? currency.format(e.amount) : '-',
                          align: pw.TextAlign.right),
                      _pdfCell(
                          e.entryType == JournalEntryType.credit ? currency.format(e.amount) : '-',
                          align: pw.TextAlign.right),
                    ]),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _pdfCell(''),
                      _pdfCell(''),
                      _pdfCell('Subtotal', bold: true, align: pw.TextAlign.right),
                      _pdfCell(currency.format(group.totalDebit),
                          bold: true, align: pw.TextAlign.right),
                      _pdfCell(currency.format(group.totalCredit),
                          bold: true, align: pw.TextAlign.right),
                    ],
                  ),
                ],
              ),
            ],
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  List<_DayGroup> _groupByDay() {
    final cancelled = _cancelledKeys;
    bool stillCounts(GlJournalEntry e) =>
        !e.isReversal && !cancelled.contains(_pairKey(e));

    final byDay = <DateTime, List<GlJournalEntry>>{};
    for (final e in _entries) {
      final day = DateTime(e.entryDate.year, e.entryDate.month, e.entryDate.day);
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days
        .map((d) => _DayGroup(d, byDay[d]!, byDay[d]!.where(stillCounts).toList()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final cancelledKeys = _cancelledKeys;

    return Scaffold(
      appBar: AppBar(title: const Text('Jurnal GL')),
      floatingActionButton: (_loading || _loadError != null || _entries.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Cetak / Export'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text('Gagal memuat data:\n$_loadError', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    // Extra bottom room so the export FAB doesn't sit on
                    // top of the last journal row.
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, kFabSafeBottom),
                    children: [
                      _TotalBalanceCard(
                        glAccount: _totalBalanceGl,
                        saldoTotal: _saldoTotal,
                        totalDebit: _totalDebit,
                        totalCredit: _totalCredit,
                        cancelledCount: _cancelledCount,
                        entryCount: _entries.length,
                        currency: currency,
                      ),
                      const SizedBox(height: 20),
                      if (_entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Belum ada pergerakan tercatat.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._groupByDay().map((group) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              initiallyExpanded: false,
                              title: Text(
                                  DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(group.day),
                                  style:
                                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              childrenPadding: const EdgeInsets.only(bottom: 4),
                              children: group.entries
                                  .map((e) => _JournalRow(
                                        entry: e,
                                        currency: currency,
                                        cancelled: !e.isReversal &&
                                            cancelledKeys.contains(_pairKey(e)),
                                      ))
                                  .toList(),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _TotalBalanceCard extends StatelessWidget {
  final GlAccount? glAccount;
  final int saldoTotal;
  final int totalDebit;
  final int totalCredit;
  final int entryCount;
  final int cancelledCount;
  final NumberFormat currency;

  const _TotalBalanceCard({
    required this.glAccount,
    required this.saldoTotal,
    required this.totalDebit,
    required this.totalCredit,
    required this.entryCount,
    required this.cancelledCount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final gl = glAccount;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_outlined, color: Colors.white.withOpacity(0.85), size: 18),
                const SizedBox(width: 6),
                Text('GL Total Saldo',
                    style: TextStyle(color: Colors.white.withOpacity(0.85))),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              gl == null ? 'Belum diatur di Mapping GL Account' : '${gl.glCode} — ${gl.glName}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(gl == null ? 0.7 : 0.9),
              ),
            ),
            const SizedBox(height: 14),
            // The headline figure has to be the balance, not the movement
            // totals — those read far higher and made this screen look
            // like it disagreed with Saldo & Pengeluaran.
            Text('Saldo Total',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              currency.format(saldoTotal),
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Divider(height: 24, color: Colors.white.withOpacity(0.3)),
            Text('Pergerakan (bukan saldo)',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Debit', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                Text(currency.format(totalDebit),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Kredit', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                Text(currency.format(totalCredit),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              cancelledCount > 0
                  ? '$entryCount baris jurnal • $cancelledCount pembatalan tidak dihitung'
                  : '$entryCount baris jurnal tercatat',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalRow extends StatelessWidget {
  final GlJournalEntry entry;
  final NumberFormat currency;

  /// True for an original that a later reversal cancelled out. Struck
  /// through so it's obvious at a glance which rows the totals ignore.
  final bool cancelled;

  const _JournalRow({
    required this.entry,
    required this.currency,
    this.cancelled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDebit = entry.entryType == JournalEntryType.debit;
    // Reversals are bookkeeping corrections, not new activity — muted so
    // they don't read as real movement at a glance.
    final color = entry.isReversal || cancelled
        ? Colors.grey
        : (isDebit ? const Color(0xFFEF4444) : const Color(0xFF10B981));
    final refLabel = _referenceTypeLabels[entry.referenceType] ?? entry.referenceType;

    return ListTile(
      dense: true,
      leading: Icon(
        entry.isReversal
            ? Icons.undo
            : (isDebit ? Icons.arrow_upward : Icons.arrow_downward),
        color: color,
        size: 18,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.glName == null || entry.glName!.isEmpty
                  ? 'GL ${entry.glCode}'
                  : '${entry.glCode} — ${entry.glName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.isReversal) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: MerchantPosTheme.softFillOf(context),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Pembatalan',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${entry.entryTime.substring(0, 5)} • ${isDebit ? 'Debit' : 'Kredit'} • '
        '$refLabel #${entry.referenceId.substring(0, 8).toUpperCase()}'
        '${entry.description != null && entry.description!.isNotEmpty ? '\n${entry.description}' : ''}',
      ),
      isThreeLine: entry.description != null && entry.description!.isNotEmpty,
      trailing: Text(
        currency.format(entry.amount),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          decoration: cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _DayGroup {
  final DateTime day;

  /// Everything booked that day, cancellations included — the list shows
  /// them all.
  final List<GlJournalEntry> entries;

  /// Subtotals count only entries that still stand, matching the header
  /// totals. Counting the cancelled ones here would make a day's figures
  /// climb every time something was undone.
  final int totalDebit;
  final int totalCredit;

  _DayGroup(this.day, this.entries, List<GlJournalEntry> effective)
      : totalDebit = effective
            .where((e) => e.entryType == JournalEntryType.debit)
            .fold(0, (sum, e) => sum + e.amount),
        totalCredit = effective
            .where((e) => e.entryType == JournalEntryType.credit)
            .fold(0, (sum, e) => sum + e.amount);
}

pw.Widget _pdfCell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}
