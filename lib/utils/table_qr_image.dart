import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/app_toast.dart';
import 'gallery_saver.dart';

/// Satu meja: yang dibutuhkan untuk menggambar satu kartu QR.
class TableQrCard {
  final String restoName;
  final String table;
  final String payload;

  /// Nomor urutnya dalam sekali pembuatan borongan, mulai dari 1.
  ///
  /// Dipakai hanya untuk mengurutkan berkasnya di galeri. Null untuk
  /// pembuatan satuan, yang tidak punya urutan apa pun.
  final int? sequence;

  /// Tulisan-tulisan di kartunya. Nilai bawaannya adalah kartu meja,
  /// yang jadi satu-satunya pemakai kartu ini sampai kasir ikut
  /// mencetakkan QR pembayaran.
  final String kicker; // di bawah tulisan Merchant-POS
  final String caption; // di bawah nama resto, di dalam kartu putih
  final String badgePrefix; // sebelum [table] di lencana amber
  final String footer; // di bawah kartu putih

  const TableQrCard({
    required this.restoName,
    required this.table,
    required this.payload,
    this.sequence,
    this.kicker = 'PESAN SENDIRI DARI MEJA',
    this.caption = 'Scan untuk pesan dari meja ini',
    this.badgePrefix = 'MEJA ',
    this.footer = 'Arahkan kamera HP ke kode di atas',
  });

  /// Kartu QRIS yang dicetak kasir lalu diserahkan ke pelanggan.
  ///
  /// Bingkainya sengaja sama persis dengan kartu meja. Pelanggan yang
  /// menerima kertas ini sudah pernah melihat kartu yang berdiri di
  /// mejanya, dan bentuk yang sama adalah cara tercepat meyakinkannya
  /// bahwa kertas ini memang dari restonya — bukan tempelan QR asing
  /// yang belakangan sering jadi berita.
  ///
  /// [amount] ditulis apa adanya, sudah diformat rupiah oleh pemanggil.
  const TableQrCard.payment({
    required this.restoName,
    required String amount,
    required this.payload,
  })  : table = amount,
        sequence = null,
        kicker = 'BAYAR DENGAN QRIS',
        caption = 'Scan pakai aplikasi bank atau e-wallet',
        badgePrefix = '',
        footer = 'Tunjukkan bukti bayarnya ke kasir';

  /// Nama berkas yang tetap enak dibaca di galeri dan di share sheet.
  ///
  /// Nomor urutnya diberi nol di depan, bukan nomor mejanya. Galeri
  /// mengurutkan nama berkas sebagai teks, jadi tanpa itu meja 10
  /// nyempil di antara 1 dan 2 dan yang memasangnya harus membaca satu
  /// per satu. Yang tidak boleh ikut berubah adalah nomor meja di dalam
  /// QR-nya — itu yang dibaca pemindai dan muncul di layar dapur.
  String get fileName {
    final safe = table.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final order = sequence == null ? '' : '${sequence!.toString().padLeft(3, '0')}-';
    return 'qr-meja-$order$safe.png';
  }
}

/// Batas jumlah meja yang boleh dibuat sekali jalan.
///
/// Bukan batas teknis: 500 kartu berarti 500 rasterisasi dan 500 gambar
/// di galeri, yang hampir pasti bukan yang dimaksud orangnya waktu salah
/// ketik nol satu kali kebanyakan.
const kMaxTableBatch = 100;

/// Nomor meja 1 sampai [count].
///
/// Satu isian, bukan rentang dari–sampai: yang diketahui pemilik resto
/// adalah "mejanya ada sepuluh", bukan "dari nomor satu sampai nomor
/// sepuluh". Rentang memaksanya menerjemahkan dulu apa yang sudah dia
/// tahu jadi dua angka, dan menyediakan dua kolom yang bisa diisi
/// terbalik.
///
/// Nomornya polos — "7", bukan "07". Nomor inilah yang tersimpan di
/// dalam QR dan muncul di layar dapur, jadi harus sama persis dengan
/// yang diketik orang di mode satu meja. Urutan berkasnya di galeri
/// dijaga lewat nama berkasnya (lihat [TableQrCard.fileName]), bukan
/// dengan mengubah nomor mejanya.
///
/// Jumlah yang tidak masuk akal mengembalikan daftar kosong, dan itulah
/// yang mematikan tombol-tombolnya di layar.
List<String> tableLabels({String prefix = '', required int count}) {
  if (count < 1 || count > kMaxTableBatch) return const [];
  return [for (var i = 1; i <= count; i++) '$prefix$i'];
}

const _brand = PdfColor.fromInt(0xFF4F46E5);
const _brandDark = PdfColor.fromInt(0xFF3730A3);
const _accent = PdfColor.fromInt(0xFFF59E0B);

/// Ukuran kartunya dalam titik PDF. Perbandingannya sengaja mendekati
/// tent card 10x13 cm yang biasa dicetak lalu ditaruh berdiri di meja.
const _cardWidth = 384.0;
const _cardHeight = 512.0;

/// Menyimpan satu kartu QR ke galeri.
Future<bool> saveTableQrToGallery(BuildContext context, TableQrCard card) async {
  final Uint8List bytes;
  try {
    bytes = await renderTableQrPng(card);
  } catch (e) {
    if (!context.mounted) return false;
    showAppToast(context, 'Gagal membuat QR: $e', isError: true);
    return false;
  }

  if (!context.mounted) return false;
  return savePngToGallery(
    context,
    bytes,
    successMessage: 'QR Meja ${card.table} tersimpan di galeri (album Merchant-POS).',
    namaBerkas: 'QR Meja ${namaBerkasAman(card.table)}.png',
    failurePrefix: 'Gagal menyimpan QR',
  );
}

/// Menyimpan sekumpulan kartu QR sekaligus.
///
/// Izin galerinya diminta sekali di depan, bukan per kartu — 40 meja
/// berarti 40 permintaan izin kalau tiap kartu mengurus dirinya sendiri.
///
/// [onProgress] dipanggil tiap satu kartu selesai supaya layarnya bisa
/// menunjukkan hitungannya; menyimpan 40 gambar makan waktu belasan
/// detik, dan tanpa angka yang bergerak orang akan mengira aplikasinya
/// menggantung.
///
/// Mengembalikan jumlah yang benar-benar tersimpan. Kartu yang gagal
/// tidak menghentikan sisanya: lebih baik 39 meja terpasang QR daripada
/// batal semua gara-gara satu.
Future<int> saveTableQrBatchToGallery(
  BuildContext context,
  List<TableQrCard> cards, {
  void Function(int done)? onProgress,
}) async {
  final toast = AppToast.of(context);

  if (!await ensureGalleryAccess(context)) return 0;

  var saved = 0;
  final failed = <String>[];
  for (final card in cards) {
    try {
      await putPngInGallery(
        await renderTableQrPng(card),
        namaBerkas: 'QR Meja ${namaBerkasAman(card.table)}.png',
      );
      saved++;
    } catch (_) {
      failed.add(card.table);
    }
    onProgress?.call(saved + failed.length);
  }

  if (failed.isEmpty) {
    toast.show('$saved QR Meja tersimpan di galeri (album Merchant-POS).');
  } else {
    toast.show(
      '$saved tersimpan, ${failed.length} gagal (meja ${failed.take(5).join(', ')}'
      '${failed.length > 5 ? ', ...' : ''}).',
      isError: true,
    );
  }
  return saved;
}

/// Mengirim kartu-kartunya ke dialog cetak — satu meja satu halaman.
Future<void> printTableQrs(
  BuildContext context,
  List<TableQrCard> cards, {
  String? name,
}) async {
  try {
    final doc = await _buildDoc(cards);
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: name ??
          (cards.length == 1 ? 'qr-meja-${cards.first.table}' : 'qr-meja-semua'),
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(context, 'Gagal mencetak QR: $e', isError: true);
  }
}

/// Membagikan kartunya lewat share sheet (WhatsApp, Drive, dan lainnya).
Future<void> shareTableQrs(BuildContext context, List<TableQrCard> cards) async {
  try {
    final files = <XFile>[];
    for (final card in cards) {
      files.add(XFile.fromData(
        await renderTableQrPng(card),
        mimeType: 'image/png',
        name: card.fileName,
      ));
    }
    await Share.shareXFiles(
      files,
      text: cards.length == 1
          ? 'QR Meja ${cards.first.table} — ${cards.first.restoName}'
          : 'QR Meja ${cards.first.restoName} (${cards.length} meja)',
    );
  } catch (e) {
    if (!context.mounted) return;
    showAppToast(context, 'Gagal membagikan QR: $e', isError: true);
  }
}

/// Menggambar satu kartu jadi PNG.
///
/// Lewat PDF yang dirasterkan, bukan tangkapan layar widget-nya: kartu
/// yang tersimpan harus utuh dan sama besar untuk semua meja, sementara
/// tangkapan layar ikut ukuran dan kerapatan piksel HP yang kebetulan
/// dipakai — dan kartu di halaman gulir bisa terpotong.
Future<Uint8List> renderTableQrPng(TableQrCard card) async {
  final doc = await _buildDoc([card]);
  // 200 dpi: cukup rapat supaya QR-nya tetap terbaca pemindai walau
  // gambarnya dicetak ulang dari galeri.
  final raster = await Printing.raster(await doc.save(), pages: [0], dpi: 200).first;
  return raster.toPng();
}

Future<pw.Document> _buildDoc(List<TableQrCard> cards) async {
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/icon/kaata_icon.png')).buffer.asUint8List(),
  );

  final doc = pw.Document();
  for (final card in cards) {
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(_cardWidth, _cardHeight, marginAll: 0),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (context) => _card(card, logo),
      ),
    );
  }
  return doc;
}

pw.Widget _card(TableQrCard card, pw.MemoryImage logo) {
  return pw.Container(
    width: _cardWidth,
    height: _cardHeight,
    decoration: const pw.BoxDecoration(
      gradient: pw.LinearGradient(
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
        colors: [_brand, _brandDark],
      ),
    ),
    child: pw.Stack(
      children: [
        // Siku amber di keempat pojok. Sekadar garis lurus di dalam
        // bidang ungu akan terbaca sebagai bingkai kedua yang menyempit;
        // siku terputus di tengah sisi justru membingkai isinya tanpa
        // mengecilkan ruang QR-nya.
        ..._corners(),
        pw.Padding(
          padding: const pw.EdgeInsets.all(26),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(logo, width: 22, height: 22),
                  pw.SizedBox(width: 7),
                  pw.Text(
                    'Merchant-POS',
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                card.kicker,
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: _accent,
                  letterSpacing: 1.8,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Expanded(child: _innerCard(card)),
              pw.SizedBox(height: 12),
              pw.Text(
                card.footer,
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _innerCard(TableQrCard card) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(20),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          card.restoName,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          card.caption,
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 14),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: card.payload,
          width: 196,
          height: 196,
          // Warna mereknya, bukan hitam. Kontrasnya terhadap putih masih
          // jauh di atas ambang yang dibutuhkan pemindai.
          color: _brandDark,
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 7),
          decoration: pw.BoxDecoration(
            color: _accent,
            borderRadius: pw.BorderRadius.circular(22),
          ),
          child: pw.Text(
            '${card.badgePrefix}${card.table}',
            style: pw.TextStyle(
              fontSize: 19,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Empat siku amber, satu di tiap pojok kartu.
List<pw.Widget> _corners() {
  const inset = 12.0;
  const arm = 34.0;
  const thick = 3.0;

  pw.Widget bar(double w, double h) => pw.Container(
        width: w,
        height: h,
        decoration: pw.BoxDecoration(
          color: _accent,
          borderRadius: pw.BorderRadius.circular(thick / 2),
        ),
      );

  return [
    // Kiri atas
    pw.Positioned(left: inset, top: inset, child: bar(arm, thick)),
    pw.Positioned(left: inset, top: inset, child: bar(thick, arm)),
    // Kanan atas
    pw.Positioned(right: inset, top: inset, child: bar(arm, thick)),
    pw.Positioned(right: inset, top: inset, child: bar(thick, arm)),
    // Kiri bawah
    pw.Positioned(left: inset, bottom: inset, child: bar(arm, thick)),
    pw.Positioned(left: inset, bottom: inset, child: bar(thick, arm)),
    // Kanan bawah
    pw.Positioned(right: inset, bottom: inset, child: bar(arm, thick)),
    pw.Positioned(right: inset, bottom: inset, child: bar(thick, arm)),
  ];
}
