import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:merchant_pos/utils/tautan_meja.dart';

/// Web pelanggan hanya untuk yang tidak masuk akun.
///
/// Ia dibuka dari kamera bawaan HP tanpa memasang apa pun, dan gunanya
/// satu: memesan dari meja yang barusan dipindai.
void main() {
  group('isi QR meja', () {
    test('berbentuk tautan, bukan teks biasa', () {
      final t = tautanMeja('resto-1', 'A01');
      expect(t, startsWith('https://'));
      final u = Uri.parse(t);
      expect(u.queryParameters['resto'], 'resto-1');
      expect(u.queryParameters['meja'], 'A01');
    });

    test('nomor meja yang berspasi dan bersimbol tetap utuh', () {
      final t = tautanMeja('resto satu', 'VIP-2 / B');
      final baca = bacaTautanMeja(t);
      expect(baca?.restoId, 'resto satu');
      expect(baca?.meja, 'VIP-2 / B');
    });

    // Stiker yang sudah tertempel tidak ikut berubah saat aplikasinya
    // diperbarui, dan merchant yang mencetaknya tahun lalu tidak punya
    // alasan mencetak ulang.
    test('bentuk lama tetap diterima', () {
      final baca = bacaTautanMeja('RESTO:abc|TABLE:12');
      expect(baca?.restoId, 'abc');
      expect(baca?.meja, '12');
    });

    test('yang bukan QR meja ditolak, bukan diterima setengah', () {
      expect(bacaTautanMeja('halo'), isNull);
      expect(bacaTautanMeja('https://contoh.com/'), isNull);
      // Resto tanpa meja bukan sesi meja: yang membukanya akan berdiri
      // di menu tanpa satu pun cara memberi tahu pesanannya untuk siapa.
      expect(bacaTautanMeja('https://contoh.com/?resto=abc'), isNull);
      expect(bacaTautanMeja('https://contoh.com/?meja=1'), isNull);
    });
  });

  group('pintu masuknya', () {
    final root = File('lib/screens/root_screen.dart').readAsStringSync();

    // Kameranyalah yang mengantar orangnya ke sini; tidak ada kamera
    // yang perlu dibuka aplikasi ini.
    test('meja dibaca dari alamat halaman di web', () {
      expect(root, contains('bacaTautanMeja(Uri.base.toString())'));
      expect(root, contains('if (!kIsWeb) return;'));
    });

    // Sesi baru berarti pesanan yang sedang berjalan ditinggalkan di
    // sesi lama, dan yang menunggu makanannya kehilangan jejaknya.
    test('memuat ulang halaman tidak memulai sesi baru', () {
      expect(root, contains('session.restoId == meja.restoId'));
      expect(root, contains('session.tableNumber == meja.meja'));
    });
  });

  group('yang tidak diberikan di web pelanggan', () {
    // Tombol kembali mengakhiri sesi restonya lalu membangun layar ini
    // jadi pemilih merchant. Di web pemilih itu tidak ada — yang
    // tersisa cuma halaman masuk merchant, dan satu-satunya jalan
    // kembali ke mejanya adalah memindai ulang QR yang barangkali
    // sudah tidak ada di depannya.
    test('tidak ada tombol kembali saat datang dari QR meja', () {
      final beranda =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(beranda,
          contains('final tanpaKembali = kIsWeb && session.enteredViaQr;'));
      expect(beranda, contains('leading: tanpaKembali'));
      // Tombol kembali milik sistem — sapuan di tepi layar, tombol
      // kembali peramban — lewat jalur yang sama dan harus ikut diam.
      expect(beranda, contains('if (!didPop && !tanpaKembali)'));
      // Tanpa ini Scaffold memasang panah kembalinya sendiri begitu
      // leading dibiarkan null.
      expect(beranda, contains('automaticallyImplyLeading: false'));
    });

    test('tidak ada pintu login', () {
      final beranda =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(beranda, contains('else if (!kIsWeb)'));
      expect(beranda, contains("tooltip: 'Login dengan Email'"));
    });

    // Berkas APK tidak bisa dipasang dari peramban.
    test('tidak menawarkan pembaruan aplikasi', () {
      final beranda =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(beranda, contains('kIsWeb ? SizedBox.shrink() : UpdateBanner()'));
    });

    // Yang di web tersimpan di peramban, bukan di HP — dan hilang
    // bersama data situs, bukan bersama HP-nya.
    test('ajakan menyimpan riwayat menyebut aplikasinya', () {
      final riwayat =
          File('lib/screens/customer_history_screen.dart').readAsStringSync();
      expect(riwayat, contains('Pasang aplikasi '));
    });
  });
}
