/// Aturan isian yang berlaku sama di seluruh aplikasi.
///
/// Dikumpulkan di satu tempat, bukan ditulis ulang di tiap layar: batas
/// yang berbeda-beda antar layar adalah cara termudah membuat data yang
/// sama tersimpan dalam dua bentuk — nomor HP yang lolos di layar admin
/// tapi ditolak di layar profil, misalnya.
///
/// Tiap aturan dipasang dua lapis: formatter menahan karakter yang tidak
/// diizinkan saat diketik, validator memeriksa lagi saat disimpan. Yang
/// pertama menjaga orang tidak sempat salah, yang kedua menangkap isian
/// yang masuk lewat tempel (paste) atau papan ketik yang tidak menghormati
/// formatter.
library;

import 'package:flutter/services.dart';

const kNameMaxLength = 40;
const kPhoneMaxLength = 15;
const kEmailMaxLength = 25;
const kNipMaxLength = 15;

/// Huruf, angka, spasi, dan tanda baca yang wajar dipakai pada nama
/// ("Warung 88", "Bpk. Andi", "Kopi & Roti"). Emoji dan simbol lain
/// tidak termasuk — itulah yang dijaga di sini.
final _nameAllowed = RegExp(r"[A-Za-z0-9 .,'()&/-]");

/// Nama orang, resto, bank, dan sejenisnya.
List<TextInputFormatter> get nameFormatters => [
      FilteringTextInputFormatter.allow(_nameAllowed),
      LengthLimitingTextInputFormatter(kNameMaxLength),
    ];

/// [label] dipakai di pesan galatnya, mis. "Nama resto".
String? validateName(String? value, {required String label, bool required = true}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return required ? '$label wajib diisi' : null;
  if (text.length > kNameMaxLength) return '$label maksimal $kNameMaxLength karakter';
  if (!text.split('').every(_nameAllowed.hasMatch)) {
    return '$label hanya boleh huruf, angka, dan tanda baca biasa';
  }
  return null;
}

/// Nomor telepon: angka saja.
///
/// Tanda "+" sengaja tidak diizinkan — nomor Indonesia ditulis mulai 0
/// atau 62, dan mengizinkan "+" berarti nomor yang sama tersimpan dalam
/// dua bentuk yang tidak bisa dicocokkan satu sama lain.
List<TextInputFormatter> get phoneFormatters => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(kPhoneMaxLength),
    ];

String? validatePhone(String? value, {bool required = true, String label = 'Nomor HP'}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return required ? '$label wajib diisi' : null;
  if (!RegExp(r'^\d+$').hasMatch(text)) return '$label hanya boleh angka';
  if (text.length > kPhoneMaxLength) return '$label maksimal $kPhoneMaxLength angka';
  if (text.length < 8) return '$label terlalu pendek';
  return null;
}

/// NIP: angka saja, seperti nomor telepon tapi tanpa batas bawah — tiap
/// resto punya penomorannya sendiri.
List<TextInputFormatter> get nipFormatters => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(kNipMaxLength),
    ];

String? validateNip(String? value, {bool required = false}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return required ? 'NIP wajib diisi' : null;
  if (!RegExp(r'^\d+$').hasMatch(text)) return 'NIP hanya boleh angka';
  if (text.length > kNipMaxLength) return 'NIP maksimal $kNipMaxLength angka';
  return null;
}

/// Alamat email untuk akun karyawan.
///
/// Hanya Gmail yang diterima, karena satu-satunya cara masuk ke aplikasi
/// ini adalah Login dengan Google. Alamat selain Gmail akan tersimpan
/// rapi di tabel karyawan lalu gagal login tanpa penjelasan apa pun —
/// jenis kesalahan yang paling lama dicari penyebabnya.
final _emailAllowed = RegExp(r'[A-Za-z0-9@._-]');

List<TextInputFormatter> get emailFormatters => [
      FilteringTextInputFormatter.allow(_emailAllowed),
      LengthLimitingTextInputFormatter(kEmailMaxLength),
    ];

String? validateGmail(String? value, {bool required = true}) {
  final text = (value ?? '').trim().toLowerCase();
  if (text.isEmpty) return required ? 'Email wajib diisi' : null;
  if (text.length > kEmailMaxLength) return 'Email maksimal $kEmailMaxLength karakter';
  if (!text.endsWith('@gmail.com')) return 'Harus alamat @gmail.com';

  final local = text.substring(0, text.length - '@gmail.com'.length);
  if (local.isEmpty) return 'Alamat email belum lengkap';
  if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(local)) {
    return 'Email hanya boleh huruf, angka, titik, dan garis bawah';
  }
  return null;
}

/// Tarif persen (PPN, biaya service).
///
/// Menerima "11", "11.1", "12.50" — dan menolak bentuk setengah jadi
/// seperti "11." atau "." yang lolos begitu saja kalau hanya mengandalkan
/// double.tryParse, karena Dart membaca "11." sebagai 11.
List<TextInputFormatter> get rateFormatters => [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      LengthLimitingTextInputFormatter(6),
    ];

String? validateRate(String? value, {String label = 'Tarif'}) {
  final text = (value ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null; // kosong berarti 0, dan itu sah

  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)) {
    return '$label harus angka, mis. 11 atau 12.50';
  }

  final parsed = double.parse(text);
  if (parsed < 0 || parsed > 100) return '$label harus antara 0 dan 100';
  return null;
}

/// Nomor rekening: angka saja, lebih panjang dari nomor telepon.
List<TextInputFormatter> get accountNumberFormatters => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(20),
    ];

String? validateAccountNumber(String? value, {bool required = true}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return required ? 'Nomor rekening wajib diisi' : null;
  if (!RegExp(r'^\d+$').hasMatch(text)) return 'Nomor rekening hanya boleh angka';
  if (text.length > 20) return 'Nomor rekening maksimal 20 angka';
  return null;
}
