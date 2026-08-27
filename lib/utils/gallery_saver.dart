import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import '../widgets/app_toast.dart';

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
  String failurePrefix = 'Gagal menyimpan',
}) async {
  final toast = AppToast.of(context);

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

/// Menaruh satu PNG di album Merchant-POS. Melempar kalau gagal — pemanggilnya
/// yang memutuskan cara melaporkannya.
Future<void> putPngInGallery(Uint8List bytes) =>
    Gal.putImageBytes(bytes, album: 'Merchant-POS');
