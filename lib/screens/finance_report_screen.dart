import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../db/expense_repository.dart';
import '../db/order_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/customer_order.dart';
import '../models/expense.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../utils/id_time.dart';
import '../widgets/responsive.dart';

/// One line in the combined ledger — either a credit (income, from a
/// paid order) or a debit (an expense), used to render both the
/// on-screen preview and the exported PDF in a classic bank-statement
/// layout: date, description, debit, credit, running balance.
class _LedgerEntry {
  final DateTime date;
  final String description;
  final int debit; // 0 if this entry is income
  final int credit; // 0 if this entry is an expense
  late int runningBalance; // filled in after sorting

  _LedgerEntry({
    required this.date,
    required this.description,
    this.debit = 0,
    this.credit = 0,
  });
}

/// Finance's exportable transaction report — every paid order (credit)
/// and expense (debit) in a chosen date range, chronological, with a
/// running balance, styled like a bank account statement ("rekening
/// koran"). Can be printed/shared/saved as PDF via the OS share sheet.
class FinanceReportScreen extends StatefulWidget {
  const FinanceReportScreen({super.key});

  @override
  State<FinanceReportScreen> createState() => _FinanceReportScreenState();
}

class _FinanceReportScreenState extends State<FinanceReportScreen> {
  final _orderRepo = OrderRepository();
  final _expenseRepo = ExpenseRepository();
  final _restaurantRepo = RestaurantRepository();

  DateTime _start = DateTime.now().subtract(const Duration(days: 29));
  DateTime _end = DateTime.now();
  bool _loading = true;
  String _restoName = '';
  int _openingBalance = 0;
  List<_LedgerEntry> _entries = [];

  String get _restoId => context.read<AuthProvider>().restoId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  Future<void> _load() async {
    setState(() => _loading = true);
    final restoId = _restoId;
    final results = await Future.wait([
      _restaurantRepo.getOnce(restoId),
      _orderRepo.watchAll(restoId).first,
      _expenseRepo.getForResto(restoId),
    ]);
    if (!mounted) return;

    final resto = results[0] as Restaurant?;
    final orders = (results[1] as List<CustomerOrder>)
        .where((o) => o.paymentStatus == OrderPaymentStatus.paid)
        .toList();
    final expenses = results[2] as List<Expense>;

    final periodStart = _startOfDay(_start);
    final periodEnd = _endOfDay(_end);

    // Opening balance = net of everything that happened before the
    // period starts, same idea as a bank statement's "saldo awal".
    // Compared in WIB wall-clock time — the picked date range is a
    // calendar day in Indonesia, not the backend's raw UTC.
    var opening = 0;
    for (final o in orders) {
      if (o.createdAt.toWib().isBefore(periodStart)) opening += o.total;
    }
    for (final e in expenses) {
      if (e.createdAt.toWib().isBefore(periodStart)) opening -= e.amount;
    }

    final entries = <_LedgerEntry>[];
    for (final o in orders) {
      final wib = o.createdAt.toWib();
      if (!wib.isBefore(periodStart) && !wib.isAfter(periodEnd)) {
        entries.add(_LedgerEntry(
          date: wib,
          description:
              'Pemasukan — #${o.id.substring(0, 8).toUpperCase()} (${o.items.length} item)',
          credit: o.total,
        ));
      }
    }
    for (final e in expenses) {
      final wib = e.createdAt.toWib();
      if (!wib.isBefore(periodStart) && !wib.isAfter(periodEnd)) {
        entries.add(_LedgerEntry(
          date: wib,
          description: e.description,
          debit: e.amount,
        ));
      }
    }
    entries.sort((a, b) => a.date.compareTo(b.date));

    var running = opening;
    for (final entry in entries) {
      running += entry.credit - entry.debit;
      entry.runningBalance = running;
    }

    setState(() {
      _restoName = resto?.name ?? restoId;
      _openingBalance = opening;
      _entries = entries;
      _loading = false;
    });
  }

  int get _closingBalance => _entries.isEmpty ? _openingBalance : _entries.last.runningBalance;
  int get _totalCredit => _entries.fold(0, (sum, e) => sum + e.credit);
  int get _totalDebit => _entries.fold(0, (sum, e) => sum + e.debit);

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (range == null) return;
    setState(() {
      _start = range.start;
      _end = range.end;
    });
    _load();
  }

  Future<void> _exportPdf() async {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd/MM/yy HH:mm', 'id_ID');
    final periodFmt = DateFormat('dd MMM yyyy', 'id_ID');
    // The pdf package's default base-14 font (Helvetica) doesn't have
    // glyphs for characters like "—" or "•" — they render as tofu boxes.
    // Loading a full Unicode font fixes that for any text (including
    // free-typed expense descriptions), not just the ones we control.
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Merchant-POS — Laporan Transaksi',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(_restoName, style: const pw.TextStyle(fontSize: 13)),
            pw.Text('Periode: ${periodFmt.format(_start)} — ${periodFmt.format(_end)}',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.SizedBox(height: 10),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount} • Dicetak ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Saldo Awal: ${currency.format(_openingBalance)}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Saldo Akhir: ${currency.format(_closingBalance)}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(3.4),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell('Tanggal', bold: true),
                  _pdfCell('Keterangan', bold: true),
                  _pdfCell('Debit', bold: true, align: pw.TextAlign.right),
                  _pdfCell('Kredit', bold: true, align: pw.TextAlign.right),
                  _pdfCell('Saldo', bold: true, align: pw.TextAlign.right),
                ],
              ),
              for (final e in _entries)
                pw.TableRow(children: [
                  _pdfCell(dateFmt.format(e.date)),
                  _pdfCell(e.description),
                  _pdfCell(e.debit > 0 ? currency.format(e.debit) : '-', align: pw.TextAlign.right),
                  _pdfCell(e.credit > 0 ? currency.format(e.credit) : '-', align: pw.TextAlign.right),
                  _pdfCell(currency.format(e.runningBalance), align: pw.TextAlign.right),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total Kredit: ${currency.format(_totalCredit)}   ',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Total Debit: ${currency.format(_totalDebit)}',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM, HH:mm', 'id_ID');
    final periodFmt = DateFormat('dd MMM yyyy', 'id_ID');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Pilih periode',
            onPressed: _pickRange,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _exportPdf,
        icon: const Icon(Icons.print_outlined),
        label: const Text('Cetak / Export'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, kFabSafeBottom),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${periodFmt.format(_start)} — ${periodFmt.format(_end)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _StatColumn(label: 'Saldo Awal', value: currency.format(_openingBalance)),
                          _StatColumn(label: 'Saldo Akhir', value: currency.format(_closingBalance)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _entries.isEmpty
                      ? const Center(child: Text('Tidak ada transaksi di periode ini.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            final isCredit = e.credit > 0;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                              title: Text(e.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(dateFmt.format(e.date)),
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isCredit
                                        ? '+ ${currency.format(e.credit)}'
                                        : '- ${currency.format(e.debit)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isCredit ? Colors.green.shade700 : Colors.red.shade700,
                                    ),
                                  ),
                                  Text('Saldo: ${currency.format(e.runningBalance)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;

  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

pw.Widget _pdfCell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}
