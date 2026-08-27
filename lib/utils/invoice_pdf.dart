import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/billing.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggal = DateFormat('d MMMM yyyy', 'id_ID');

/// Bukti bayar langganan yang bisa disimpan dan dikirim.
///
/// Yang dicetak adalah tagihan yang **sudah lunas** — bukan surat
/// penagihan. Karena itu nomor Virtual Account tidak ikut: nomor yang
/// masih terbaca di sebuah dokumen bertuliskan "Lunas" adalah undangan
/// untuk mentransfer dua kali.
///
/// Harga daftar dan potongannya ditulis terpisah, bukan langsung
/// nettonya. Bagian keuangan resto mencocokkan angka ini dengan harga
/// yang disepakati, dan netto tanpa rinciannya membuat mereka mengira
/// harganya berubah diam-diam.
Future<void> cetakInvoiceLangganan({
  required BillingInvoice invoice,
  required String restoName,
  int listPrice = 0,
  String? discountLabel,
}) async {
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();

  // Logonya boleh gagal dimuat tanpa menjatuhkan strukmya. Bukti bayar
  // yang tidak terbit karena satu gambar tidak ada adalah kehilangan
  // yang jauh lebih besar daripada kepala surat tanpa logo.
  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/icon/merchantpos_icon.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    logo = null;
  }

  final potongan =
      listPrice > invoice.amount ? listPrice - invoice.amount : 0;

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null) ...[
                    pw.ClipRRect(
                      horizontalRadius: 7,
                      verticalRadius: 7,
                      child: pw.Image(logo, width: 34, height: 34),
                    ),
                    pw.SizedBox(width: 10),
                  ],
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Merchant-POS',
                          style: pw.TextStyle(
                              fontSize: 22, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text('Bukti Pembayaran Langganan',
                          style: const pw.TextStyle(
                              fontSize: 11, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.green400),
                ),
                child: pw.Text('LUNAS',
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green800)),
              ),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 14),
          _baris('Nomor Tagihan', invoice.id),
          _baris('Merchant', restoName),
          _baris(
              'Periode',
              '${_tanggal.format(invoice.periodStart)} — '
                  '${_tanggal.format(invoice.periodEnd)}'),
          _baris('Jatuh Tempo', _tanggal.format(invoice.dueDate)),
          if (invoice.confirmedAt != null)
            _baris('Dibayar', _tanggal.format(invoice.confirmedAt!)),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                if (listPrice > 0) ...[
                  _hitung('Harga langganan', _rupiah.format(listPrice)),
                  if (potongan > 0)
                    _hitung(discountLabel ?? 'Potongan',
                        '-${_rupiah.format(potongan)}'),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.grey400),
                  pw.SizedBox(height: 6),
                ],
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Dibayar',
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_rupiah.format(invoice.amount),
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'Dokumen ini dibuat otomatis oleh aplikasi Merchant-POS dan sah '
            'tanpa tanda tangan.',
            style:
                const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'Merchant-POS-${invoice.id}.pdf',
  );
}

pw.Widget _baris(String label, String nilai) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 10.5, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(nilai,
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );

pw.Widget _hitung(String label, String nilai) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(nilai, style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
