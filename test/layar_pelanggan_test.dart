import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/db/customer_display_repository.dart';

/// Layar pelanggan di meja kasir.
void main() {
  final sql = File('supabase/customer_display.sql').readAsStringSync();
  final layar =
      File('lib/screens/customer_display_screen.dart').readAsStringSync();
  final qris = File('lib/screens/payment_qris_screen.dart').readAsStringSync();

  group('bentuk tampilannya', () {
    test('terbaca dari baris database', () {
      final t = TampilanLayar.fromMap({
        'status': 'awaiting',
        'amount': 75000,
        'qr_string': '000201...',
        'label': 'Meja 4',
      });
      expect(t.status, StatusLayar.menunggu);
      expect(t.amount, 75000);
      expect(t.adaQr, isTrue);
    });

    test('baris kosong berarti menganggur, bukan galat', () {
      expect(const TampilanLayar().status, StatusLayar.menganggur);
      expect(const TampilanLayar().adaQr, isFalse);
    });

    test('status tak dikenal jatuh ke menganggur', () {
      // Layar depan yang menampilkan pesan galat ke pelanggan lebih
      // buruk daripada layar yang diam.
      expect(TampilanLayar.fromMap({'status': 'entah'}).status,
          StatusLayar.menganggur);
    });
  });

  group('apa yang disimpan', () {
    test('membawa isinya, bukan penunjuk ke pesanan', () {
      // Di alur kasir, pesanannya baru dibuat sesudah pembayaran
      // dikonfirmasi — saat QR-nya tampil belum ada baris pesanan.
      expect(sql, contains('qr_string text'));
      expect(sql, contains('amount bigint'));
      expect(sql, isNot(contains('order_id uuid references orders')));
    });

    test('satu baris per merchant, ditimpa bukan ditumpuk', () {
      // Dua kasir yang menekan Bayar bersamaan tidak boleh meninggalkan
      // dua baris.
      expect(sql, contains('resto_id text primary key'));
      expect(sql, contains('on conflict (resto_id) do update'));
    });

    test('tidak terbuka untuk umum', () {
      // Isi QR-nya bisa dipindai orang lain sebelum pelanggannya sempat.
      expect(sql, contains('is_resto_employee(resto_id'));
      expect(sql, isNot(contains('using (true)')));
    });

    test('yang menulis dibatasi perannya', () {
      expect(sql, contains('Tidak berwenang atas layar merchant ini'));
    });

    test('perubahannya disiarkan seketika', () {
      // Tidak ada yang memuat ulang layar yang menghadap pelanggan.
      expect(sql, contains('alter publication supabase_realtime add table customer_displays'));
    });
  });

  group('di layar kasir', () {
    test('dinyalakan saat QR siap', () {
      expect(qris, contains('unawaited(_tampilkanDiLayarDepan())'));
    });

    test('dinyalakan walau tagihannya gagal dibuat', () {
      // Nominalnya tetap perlu dibaca, dan tanpa QR layarnya menyuruh
      // membayar di kasir — jalan keluar saat QRIS bermasalah.
      expect(qris.indexOf('unawaited(_tampilkanDiLayarDepan())'),
          lessThan(qris.indexOf('if (charge == null) return;')));
    });

    test('dipadamkan saat layarnya ditutup', () {
      // Tanpa ini tagihan orang sebelumnya tetap terpampang beserta
      // QR-nya.
      final blok = qris.substring(qris.indexOf('void dispose()'));
      expect(blok.substring(0, 400), contains('_padamkanLayarDepan()'));
    });

    test('restoId dibaca saat dibuka, bukan saat ditutup', () {
      // Di dispose, context sudah tidak boleh dipakai membaca provider.
      final blok = qris.substring(qris.indexOf('void initState()'));
      expect(blok.substring(0, 300), contains('_restoId = context.read<AuthProvider>().restoId;'));
    });

    test('menyatakan lunas sebelum layar kasirnya ditutup', () {
      final blok = qris.substring(qris.indexOf('void _confirm()'));
      expect(blok.indexOf('.lunas('), lessThan(blok.indexOf('Navigator.of(context).pop(true)')));
    });

    test('kegagalannya tidak menghalangi pembayaran', () {
      // Kasir yang tidak bisa menyelesaikan transaksi karena perangkat
      // kedua mati adalah kerugian yang jauh lebih besar.
      expect(qris, contains('} catch (_) {}'));
    });
  });

  group('layar depannya', () {
    test('menganggur diisi promo, bukan dibiarkan kosong', () {
      expect(layar, contains('PromoBannerCarousel(restoId: restoId)'));
    });

    test('nominalnya paling besar di layar', () {
      expect(layar, contains('fontSize: 44'));
    });

    test('tanpa QR tetap memberi arahan', () {
      expect(layar, contains("'Silakan bayar di kasir'"));
    });

    test('layar penuh, tanpa bilah status', () {
      expect(layar, contains('SystemUiMode.immersiveSticky'));
      expect(layar, contains('SystemUiMode.edgeToEdge'));
    });

    test('tersedia untuk kasir, admin, dan owner', () {
      for (final f in [
        'lib/screens/kasir_home_screen.dart',
        'lib/screens/admin_home_screen.dart',
        'lib/screens/owner_home_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('CustomerDisplayScreen()'),
            reason: f);
      }
    });
  });
}
