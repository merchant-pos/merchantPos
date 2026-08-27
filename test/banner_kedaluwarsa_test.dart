import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/promo_banner.dart';

/// Banner yang berhenti tayang tidak boleh hilang dari pengelolanya,
/// dan tidak boleh tetap tampil ke pelanggan.
void main() {
  final repo = File('lib/db/promo_banner_repository.dart').readAsStringSync();
  final layar = File('lib/screens/promo_banner_screen.dart').readAsStringSync();

  PromoBanner buat({
    bool active = true,
    DateTime? mulai,
    DateTime? selesai,
  }) =>
      PromoBanner(
        id: 'b1',
        restoId: 'r1',
        imageBase64: 'x',
        active: active,
        createdAt: DateTime(2026, 8, 1),
        startsOn: mulai,
        endsOn: selesai,
      );

  group('aturannya', () {
    final kemarin = DateTime.now().subtract(const Duration(days: 1));
    final besok = DateTime.now().add(const Duration(days: 1));

    test('yang saklarnya mati tidak tayang', () {
      expect(buat(active: false).isLive(), isFalse);
    });

    test('yang tanggalnya sudah lewat tidak tayang walau saklarnya nyala', () {
      // Inilah yang dulu tetap tampil ke pelanggan.
      final b = buat(selesai: kemarin);
      expect(b.active, isTrue);
      expect(b.isLive(), isFalse);
    });

    test('yang belum mulai juga belum tayang', () {
      expect(buat(mulai: besok).isLive(), isFalse);
    });

    test('yang tanpa batas tanggal tetap tayang', () {
      expect(buat().isLive(), isTrue);
    });
  });

  group('layar admin dan owner', () {
    test('mengambil seluruhnya tanpa saringan', () {
      // Banner yang menghilang sendiri dari layar pengelolanya adalah
      // banner yang tidak bisa dihapus.
      final blok = repo.substring(
          repo.indexOf('Future<List<PromoBanner>> getForResto'),
          repo.indexOf('Future<List<PromoBanner>> activeForResto'));
      expect(blok, isNot(contains('.where((b) => b.isLive())')));
      expect(blok, isNot(contains(".eq('active'")));
    });

    test('menandai sebabnya, bukan cuma "tidak tampil"', () {
      expect(layar, contains("'SUDAH LEWAT'"));
      expect(layar, contains("'BELUM MULAI'"));
      expect(layar, contains("'TIDAK TAMPIL'"));
      expect(layar, contains('if (!banner.isLive())'));
    });

    test('hitungannya memakai yang benar-benar tayang', () {
      expect(layar, contains('_banners.where((b) => b.isLive()).length'));
    });

    test('menghapusnya tetap bisa', () {
      expect(repo, contains('Future<void> delete(String id)'));
    });
  });

  group('layar pelanggan', () {
    test('menyaring saklar sekaligus masa berlakunya', () {
      // Promo yang sudah berakhir tapi masih terpampang adalah janji
      // yang akan ditagih di kasir.
      final blok = repo.substring(
          repo.indexOf('Future<List<PromoBanner>> activeForResto'));
      expect(blok, contains(".eq('active', true)"));
      expect(blok, contains('.where((b) => b.isLive())'));
    });

    test('carouselnya memang memakai yang tersaring', () {
      final carousel =
          File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();
      expect(carousel, contains('activeForResto(widget.restoId)'));
    });
  });
}
