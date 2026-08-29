import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt_data.dart';
import 'gallery_saver.dart';
import '../widgets/app_toast.dart';

/// Renders [data] as a receipt-roll shaped PNG and drops it in the photo
/// gallery under a "Merchant-POS" album.
///
/// Goes via a PDF page rasterised by `printing` rather than screenshotting
/// the widget tree: the on-screen receipt lives inside a scroll view, so a
/// RepaintBoundary capture would silently cut off every item below the
/// fold on a long order. Laying it out on a tall page instead means the
/// saved image always holds the whole thing.
///
/// Returns true when the image reached the gallery. Any failure is
/// reported to the user through [context] and returns false.
Future<bool> saveReceiptToGallery(BuildContext context, ReceiptData data) async {
  final Uint8List bytes;
  try {
    bytes = await _renderReceiptPng(data);
  } catch (e) {
    if (!context.mounted) return false;
    showAppToast(context, 'Gagal membuat struk: $e', isError: true);
    return false;
  }

  if (!context.mounted) return false;
  return savePngToGallery(
    context,
    bytes,
    successMessage: 'Struk tersimpan di galeri (album Merchant-POS).',
    namaBerkas: 'Struk Merchant-POS.png',
    failurePrefix: 'Gagal menyimpan struk',
  );
}

/// Hands the receipt image to the OS share sheet, so it can go out via
/// WhatsApp, Telegram, Gmail — whatever the phone has.
///
/// Replaces the old "email me this receipt" flow: that queued a row for a
/// Supabase Edge Function and a mail provider that were never deployed,
/// so it reported success while nothing was ever sent. Sharing needs no
/// backend at all and reaches the apps people actually use.
Future<void> shareReceipt(BuildContext context, ReceiptData data) async {
  try {
    final bytes = await _renderReceiptPng(data);
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'image/png', name: 'struk-${data.reference}.png')],
      text: 'Struk ${data.restoName} — ${data.reference}',
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(context, 'Gagal membagikan struk: $e', isError: true);
  }
}

/// Sends the receipt to the Android print dialog, which covers both a
/// real printer and "save as PDF".
///
/// This is the Kasir/Admin path: at the counter a receipt is something
/// you hand over, not something you file in your own photo gallery.
Future<void> printReceipt(BuildContext context, ReceiptData data) async {
  try {
    // Sized to the content before printing. The draft page is
    // deliberately over-tall so nothing overflows, but a printer scales
    // the whole page onto the sheet — so an 80mm x 2400pt draft lands on
    // A4 as a postage stamp in the corner. Measuring first and reissuing
    // at the real height makes the receipt fill the paper.
    final doc = await _buildReceiptDoc(data, pageHeight: await _measureContentHeight(data));
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'struk-${data.reference}',
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(context, 'Gagal mencetak struk: $e', isError: true);
  }
}

Future<Uint8List> _renderReceiptPng(ReceiptData data) async {
  final doc = await _buildReceiptDoc(data);
  // Rasterise at a high enough dpi that the text stays crisp when the
  // saved image is zoomed in the gallery.
  final raster = await Printing.raster(await doc.save(), pages: [0], dpi: 220).first;
  return _trimBlankTail(raster);
}

/// Height in PDF points of the inked part of the receipt.
///
/// Rasterised at 72dpi so one pixel is one point, which makes the row
/// index the answer directly.
Future<double> _measureContentHeight(ReceiptData data) async {
  final draft = await _buildReceiptDoc(data);
  final raster = await Printing.raster(await draft.save(), pages: [0], dpi: 72).first;
  final lastInked = _lastInkedRow(raster);
  if (lastInked < 0) return _draftPageHeight;
  // Bottom margin to match the page's own, so the last line isn't flush
  // against the cut.
  return lastInked + 8 * PdfPageFormat.mm;
}

Future<pw.Document> _buildReceiptDoc(ReceiptData data, {double? pageHeight}) async {
  final currency = NumberFormat.decimalPattern('id_ID');
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  final monoFont = await PdfGoogleFonts.robotoMonoRegular();

  final kaataIcon = pw.MemoryImage(
    (await rootBundle.load('assets/icon/kaata_icon.png')).buffer.asUint8List(),
  );
  final restoLogo = data.restoLogoBase64 != null && data.restoLogoBase64!.isNotEmpty
      ? pw.MemoryImage(base64Decode(data.restoLogoBase64!))
      : null;

  // 80mm-wide roll. Without an explicit height it falls back to a page
  // tall enough that even a long order can't overflow.
  final pageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    pageHeight ?? _draftPageHeight,
    marginAll: 8 * PdfPageFormat.mm,
  );

  pw.Widget rule() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Divider(height: 0, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey500),
      );

  pw.Widget kv(String label, String value, {bool soft = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: monoFont, fontSize: 9, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(
                  font: monoFont, fontSize: 9, color: soft ? PdfColors.grey700 : PdfColors.black)),
        ],
      );

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        // A PDF page has no paper of its own: rasterised straight to PNG
        // it comes out with a transparent background, which the gallery
        // renders as black — turning every black-inked line invisible and
        // leaving only the grey ones readable. Painting the sheet white
        // makes the saved image match the on-screen receipt.
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: PdfColors.white),
        ),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Center(
            child: pw.Container(
              width: 46,
              height: 46,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: PdfColors.grey400),
                image: restoLogo == null
                    ? null
                    : pw.DecorationImage(image: restoLogo, fit: pw.BoxFit.cover),
              ),
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Center(
            child: pw.Text(data.restoName,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('powered by',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(width: 3),
              pw.Image(kaataIcon, width: 11, height: 11),
              pw.SizedBox(width: 3),
              pw.Text('Merchant-POS',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
          if (data.restoAddress != null && data.restoAddress!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(data.restoAddress!,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ),
          ],
          if (data.restoPhone != null && data.restoPhone!.trim().isNotEmpty)
            pw.Center(
              child: pw.Text(data.restoPhone!,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ),
          rule(),
          for (final (label, value) in data.headerRows) kv(label, value),
          rule(),
          for (final line in data.lines) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(line.name, style: pw.TextStyle(font: monoFont, fontSize: 9)),
                ),
                pw.SizedBox(width: 8),
                pw.Text(currency.format(line.subtotal),
                    style: pw.TextStyle(font: monoFont, fontSize: 9)),
              ],
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8, bottom: 5),
              child: pw.Text(
                '${line.quantity} x ${currency.format(line.unitPrice)}'
                '${line.note != null && line.note!.isNotEmpty ? ' · ${line.note}' : ''}',
                style: pw.TextStyle(font: monoFont, fontSize: 7.5, color: PdfColors.grey700),
              ),
            ),
          ],
          rule(),
          kv('Subtotal', currency.format(data.subtotal), soft: true),
          if ((data.serviceAmount ?? 0) > 0)
            kv('Biaya Service', currency.format(data.serviceAmount!), soft: true),
          if ((data.ppnAmount ?? 0) > 0) kv('PPN', currency.format(data.ppnAmount!), soft: true),
          kv('${data.itemCount} item', '', soft: true),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 7),
            child: pw.Divider(height: 0, color: PdfColors.black),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('TOTAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('Rp ${currency.format(data.total)}',
                  style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          if (data.cashReceived != null) ...[
            pw.SizedBox(height: 5),
            kv('Uang Bayar', currency.format(data.cashReceived!)),
            kv('Kembalian', currency.format(data.changeDue!)),
          ],
          rule(),
          for (final (label, value) in data.footerRows) kv(label, value),
          if (data.paid) ...[
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Center(
                child: pw.Text('PEMBAYARAN BERHASIL',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
            ),
          ],
          if (data.inclusiveNote != null) ...[
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(data.inclusiveNote!,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text('Terima kasih sudah memesan!',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ),
        ],
      ),
    ),
  );

  return doc;
}

/// Fallback page height: tall enough that no realistic order overflows.
const _draftPageHeight = 2400.0;

/// Index of the lowest row holding any ink, or -1 if the page is blank.
int _lastInkedRow(PdfRaster raster) {
  final pixels = raster.pixels;
  final width = raster.width;
  for (var y = raster.height - 1; y >= 0; y--) {
    var i = y * width * 4;
    for (var x = 0; x < width; x++, i += 4) {
      // Anything meaningfully darker than the paper counts as ink.
      if (pixels[i] < 245 || pixels[i + 1] < 245 || pixels[i + 2] < 245) return y;
    }
  }
  return -1;
}

/// Cuts the unused paper off the bottom of the rasterised page.
///
/// The page is deliberately over-tall so a long order can't overflow it,
/// which on a short receipt leaves most of the image as empty white. A
/// gallery thumbnail of that is a sliver of text above a huge blank
/// sheet, so the tail is cropped back to just past the last inked row.
Future<Uint8List> _trimBlankTail(PdfRaster raster) async {
  final lastInked = _lastInkedRow(raster);
  final width = raster.width;

  // An entirely blank render means something went wrong upstream — hand
  // back the full page rather than a zero-height image.
  if (lastInked < 0) return raster.toPng();

  final margin = (24 * raster.height / 2400).round();
  final height = (lastInked + margin).clamp(1, raster.height);

  final full = img.Image.fromBytes(
    width: width,
    height: raster.height,
    bytes: Uint8List.fromList(raster.pixels).buffer,
    numChannels: 4,
  );
  final cropped = img.copyCrop(full, x: 0, y: 0, width: width, height: height);
  return img.encodePng(cropped);
}
