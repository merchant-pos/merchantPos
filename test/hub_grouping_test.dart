import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/widgets/hub_group_tile.dart';
import 'package:merchant_pos/widgets/hub_menu_tile.dart';

/// Hub dengan belasan menu memaksa orang membaca seluruh daftar tiap
/// kali, karena tidak ada yang menandai di mana satu urusan berakhir.
/// Menumpuknya jadi beberapa pintu membuat halaman awalnya bisa dibaca
/// sekali lihat — asal tidak ada yang hilang di dalam pintunya.
void main() {
  const jumlahMenu = {
    'kasir': 11,
    'admin': 15,
    'finance': 13,
    'super_admin': 10,
    'owner': 22,
  };

  String isi(String peran) =>
      File('lib/screens/${peran}_home_screen.dart').readAsStringSync();

  group('menu bertumpuk di balik kelompoknya', () {
    for (final e in jumlahMenu.entries) {
      test('${e.key} memakai kelompok', () {
        expect(isi(e.key), contains('HubGroupTile('),
            reason: '${e.key} masih satu daftar panjang');
      });

      test('${e.key} tidak kehilangan menu saat ditumpuk', () {
        // Memindahkan menu ke dalam pintu adalah tempat paling mudah
        // menjatuhkan salah satunya tanpa suara — dan yang hilang tidak
        // menimbulkan galat apa pun, cuma menu yang tidak ada lagi.
        final jumlah = RegExp(
                r'^ +(HubMenuTile|BadgedHubTile|const InboxTile)',
                multiLine: true)
            .allMatches(isi(e.key))
            .length;
        expect(jumlah, e.value, reason: e.key);
      });
    }
  });

  group('yang berdiri sendiri tetap di halaman awal', () {
    test('Kotak Masuk tidak ditumpuk di dalam kelompok mana pun', () {
      // Isinya bukan satu urusan dengan menu lain — ia kabar yang datang
      // sendiri, dan penanda belum dibacanya kehilangan gunanya begitu
      // harus dicari dua ketukan ke dalam.
      for (final peran in jumlahMenu.keys) {
        final teks = isi(peran);
        if (!teks.contains('InboxTile()')) continue;
        final posisi = teks.indexOf('InboxTile()');
        final sebelum = teks.substring(0, posisi);
        // Kalau ia berada di dalam `tiles: () => [` sebuah kelompok,
        // kurung itu belum tertutup di titik ini.
        final buka = 'tiles: () => ['.allMatches(sebelum).length;
        final tutup = RegExp(r'^ {18,20}\],$', multiLine: true)
            .allMatches(sebelum)
            .length;
        expect(buka, lessThanOrEqualTo(tutup), reason: peran);
      }
    });

    test('Shift Kasir tidak ditumpuk di dalam kelompok mana pun', () {
      // Dibuka dua kali sehari pada dua saat tersibuk: awal shift ketika
      // antrean mulai, dan akhir shift ketika sudah ingin pulang. Pernah
      // ditaruh di dalam grup Keuangan, dan yang pertama mencarinya tidak
      // menemukannya sama sekali.
      for (final peran in ['kasir', 'admin', 'owner', 'finance']) {
        final teks = isi(peran);
        final posisi = teks.indexOf("title: 'Shift Kasir'");
        expect(posisi, greaterThan(0), reason: '$peran tanpa Shift Kasir');
        final sebelum = teks.substring(0, posisi);
        // Kelompok pertama belum dibuka sama sekali di titik ini.
        expect('tiles: () => ['.allMatches(sebelum), isEmpty, reason: peran);
      }
    });

    test('Keluar selalu berdiri sendiri', () {
      for (final peran in jumlahMenu.keys) {
        final teks = isi(peran);
        final posisi = teks.indexOf("title: 'Keluar'");
        expect(posisi, greaterThan(0), reason: peran);
        final sesudahKelompokTerakhir =
            teks.lastIndexOf('HubGroupTile(') < posisi;
        expect(sesudahKelompokTerakhir, isTrue, reason: peran);
      }
    });

    test('Pengaturan tidak ditumpuk', () {
      for (final peran in ['admin', 'owner']) {
        final teks = isi(peran);
        final posisi = teks.indexOf("title: 'Pengaturan'");
        if (posisi < 0) continue;
        expect(teks.lastIndexOf('HubGroupTile(') < posisi, isTrue,
            reason: peran);
      }
    });
  });

  group('penanda ikut naik ke halaman awal', () {
    test('kelompok berisi pengajuan menghitung penandanya', () {
      // Menyembunyikan menu di balik pintu juga menyembunyikan titik
      // merahnya — dan titik merah itu satu-satunya cara orang tahu ada
      // yang menunggu keputusannya tanpa membuka apa pun.
      for (final peran in ['kasir', 'admin', 'finance', 'owner']) {
        expect(isi(peran), contains('_penandaKeuangan(restoId)'),
            reason: peran);
      }
    });

    test('penandanya menjumlahkan petty cash dan setoran', () {
      final teks = isi('kasir');
      expect(teks, contains('PettyCashRepository().pendingCount(restoId)'));
      expect(teks, contains('CashDepositRepository().pendingCount(restoId)'));
    });
  });

  group('kartu kelompok', () {
    testWidgets('menyebut isinya, bukan cuma judulnya', (tester) async {
      // Pintu yang isinya harus ditebak akan dibuka satu per satu sampai
      // ketemu.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HubGroupTile(
            icon: Icons.point_of_sale_outlined,
            title: 'Penjualan',
            subtitle: 'Input pesanan, pending payment, riwayat',
            color: const Color(0xFF10B981),
            tiles: () => const [Text('isi')],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Penjualan'), findsOneWidget);
      expect(find.text('Input pesanan, pending payment, riwayat'),
          findsOneWidget);
    });

    testWidgets('diketuk membuka halaman berisi menunya', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HubGroupTile(
            icon: Icons.tune,
            title: 'Pengelolaan',
            subtitle: 'Produk dan diskon',
            color: const Color(0xFF8B5CF6),
            tiles: () => const [Text('menu di dalam')],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('menu di dalam'), findsNothing);
      await tester.tap(find.text('Pengelolaan'));
      await tester.pumpAndSettle();
      expect(find.text('menu di dalam'), findsOneWidget);
    });

    testWidgets('isinya baru dibangun saat pintunya dibuka', (tester) async {
      // Membangun seluruh isi tiap kelompok saat hub dibuka berarti
      // membayar biaya layar yang mungkin tidak pernah dilihat.
      var dibangun = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HubGroupTile(
            icon: Icons.tune,
            title: 'Keuangan',
            subtitle: 'Saldo dan setoran',
            color: const Color(0xFF6366F1),
            tiles: () {
              dibangun++;
              return const [Text('x')];
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(dibangun, 0);

      await tester.tap(find.text('Keuangan'));
      await tester.pumpAndSettle();
      expect(dibangun, 1);
    });

    testWidgets('tanpa penanda tetap kartu biasa', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HubGroupTile(
            icon: Icons.tune,
            title: 'Pengelolaan',
            subtitle: 'Produk',
            color: const Color(0xFF8B5CF6),
            tiles: () => const [Text('x')],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(HubMenuTile), findsOneWidget);
    });
  });
}
