import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'gallery_saver.dart';
import '../widgets/app_toast.dart';

/// Saves the payment QR a customer is looking at as a PNG in their photo
/// gallery, so they can pay from their banking app — which means leaving
/// Merchant-POS, and losing sight of the code — or come back to it later.
///
/// Ordering without a cashier is exactly when this matters: there's
/// nobody holding a terminal to show the code again.
///
/// The QR is drawn onto a PDF page and rasterised rather than screenshot
/// from the widget tree, so the saved image is sharp at any zoom and
/// carries the merchant/amount/order context around it instead of just a
/// bare square.
Future<bool> saveQrisToGallery(
  BuildContext context, {
  required String qrData,
  required String merchantName,
  required int amount,
  required String orderId,
}) async {
  final Uint8List bytes;
  try {
    bytes = await _renderQrisPng(
      qrData: qrData,
      merchantName: merchantName,
      amount: amount,
      orderId: orderId,
    );
  } catch (e) {
    if (!context.mounted) return false;
    showAppToast(context, 'Gagal membuat gambar QR: $e', isError: true);
    return false;
  }

  if (!context.mounted) return false;
  return savePngToGallery(
    context,
    bytes,
    successMessage: 'QR pembayaran tersimpan di galeri (album Merchant-POS).',
    namaBerkas: 'QR Pembayaran Merchant-POS.png',
    failurePrefix: 'Gagal menyimpan QR',
  );
}

Future<Uint8List> _renderQrisPng({
  required String qrData,
  required String merchantName,
  required int amount,
  required String orderId,
}) async {
  final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();

  // Portrait card, roughly phone-screenshot shaped so it sits naturally
  // among the customer's other photos.
  const pageFormat = PdfPageFormat(360, 520, marginAll: 20);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        // Without this the rasterised PNG has a transparent background,
        // which the gallery shows as black — hiding the QR itself, since
        // its modules are black too.
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: PdfColors.white),
        ),
      ),
      build: (context) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
          borderRadius: pw.BorderRadius.circular(14),
        ),
        padding: const pw.EdgeInsets.all(20),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text('Merchant-POS',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('QR Pembayaran',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
            pw.Text(merchantName,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 4),
            pw.Text(currency.format(amount),
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: qrData,
              width: 200,
              height: 200,
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(16),
              ),
              child: pw.Text('Pesanan #${orderId.substring(0, 8).toUpperCase()}',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text(dateFmt.format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
    ),
  );

  final raster = await Printing.raster(await doc.save(), pages: [0], dpi: 220).first;
  return raster.toPng();
}
