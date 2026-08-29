import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gal/gal.dart';
import '../widgets/app_toast.dart';
import 'unduh_web.dart';

/// Drops [bytes] (a PNG) into the device's photo gallery, under a
/// "Merchant-POS" album, handling the permission prompt Android 9 and below
/// still need.
///
/// Returns true only if the image actually landed. Failures — including
/// a refused permission — are reported through [context] rather than
/// thrown, since every caller here is a "save this for me" button where
/// a snackbar is the whole error handling anyone wants.
Future<bool> savePngToGallery(
  BuildContext context,
  Uint8List bytes, {
  required String successMessage,
  required String namaBerkas,
  String failurePrefix = 'Gagal menyimpan',
}) async {
  final toast = AppToast.of(context);

  // Di web tidak ada galeri, dan tidak ada izin yang bisa diminta untuk
  // menulis ke sana. Sebelumnya jalur ini tetap menanyakan izin galeri
  // lewat Gal — yang di web menjawab dengan galat, lalu tombolnya
  // berhenti sebagai pesan "gagal memeriksa izin galeri" pada perangkat
  // yang memang tidak punya galeri sama sekali.
  if (kIsWeb) {
    try {
      unduhPngWeb(bytes, namaBerkas);
      toast.show('$namaBerkas diunduh.');
      return true;
    } catch (e) {
      toast.show('$failurePrefix: $e', isError: true);
      return false;
    }
  }

  if (!await ensureGalleryAccess(context)) return false;

  try {
    await putPngInGallery(bytes);
    toast.show(successMessage);
    return true;
  } catch (e) {
    toast.show('$failurePrefix: $e');
    return false;
  }
}

/// Memastikan aplikasi boleh menulis ke galeri, meminta izinnya kalau
/// belum.
///
/// Dipisah dari [savePngToGallery] supaya penyimpanan berjumlah banyak
/// bisa meminta izinnya sekali di depan: kalau tiap gambar mengurus
/// dirinya sendiri, menyimpan 40 QR meja berarti 40 kali pemeriksaan
/// izin yang jawabannya sudah pasti sama.
Future<bool> ensureGalleryAccess(BuildContext context) async {
  // Tidak ada yang perlu diizinkan di web — unduhan tidak menyentuh
  // galeri mana pun.
  if (kIsWeb) return true;

  final toast = AppToast.of(context);
  try {
    if (await Gal.hasAccess()) return true;
    if (await Gal.requestAccess()) return true;
    toast.show('Izin galeri ditolak, gambar tidak bisa disimpan.', isError: true);
    return false;
  } catch (e) {
    toast.show('Gagal memeriksa izin galeri: $e', isError: true);
    return false;
  }
}

/// Menaruh satu PNG di album Merchant-POS, atau mengunduhnya di web.
/// Melempar kalau gagal — pemanggilnya yang memutuskan cara
/// melaporkannya.
Future<void> putPngInGallery(Uint8List bytes, {String? namaBerkas}) async {
  if (kIsWeb) {
    unduhPngWeb(bytes, namaBerkas ?? 'Merchant-POS.png');
    return;
  }
  await Gal.putImageBytes(bytes, album: 'Merchant-POS');
}

/// Menjadikan teks aman sebagai nama berkas unduhan.
///
/// Nomor meja bebas bentuk — "VIP-2", "A/01", "Meja 3 (pojok)" — dan
/// garis miring di dalamnya membuat peramban memperlakukannya sebagai
/// folder, lalu unduhannya mendarat entah di mana.
String namaBerkasAman(String teks) {
  final bersih = teks
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '-')
      // Dirapatkan lalu dipangkas ujungnya. Tanpa ini "///" berubah jadi
      // "---" — bukan kosong, jadi lolos dari penjaga di bawah, dan
      // berkasnya terunduh bernama tiga setrip.
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-\s]+|[-\s]+$'), '');
  return bersih.isEmpty ? 'Merchant-POS' : bersih;
}
