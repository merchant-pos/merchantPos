import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/screens/restaurant_list_screen.dart';
import 'package:merchant_pos/theme.dart';

/// Baris fasilitas harus muat di dalam kartunya.
///
/// Chip yang tergulir keluar terlihat terpotong di tepi kartu seperti
/// tampilan yang rusak — dan tidak ada yang menyangka baris sesempit itu
/// bisa digeser, jadi sisanya tidak pernah dilihat siapa pun.
void main() {
  final sumber =
      File('lib/screens/restaurant_list_screen.dart').readAsStringSync();

  Future<void> ukur(WidgetTester tester, List<String> f, double lebar) async {
    tester.view.physicalSize = Size(lebar, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: MerchantPosTheme.dark(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: lebar,
            child: RestaurantFacilityRowForTest(nama: f),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('tidak melimpah walau namanya panjang-panjang',
      (tester) async {
    await ukur(tester, const [
      'Ramah Difabel',
      'Colokan Listrik',
      'Smoking Area',
      'Kids Friendly',
      'Live Music',
    ], 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yang tidak muat diringkas jadi +N', (tester) async {
    await ukur(tester, const [
      'Ramah Difabel',
      'Colokan Listrik',
      'Smoking Area',
      'Kids Friendly',
      'Live Music',
    ], 200);
    expect(find.textContaining('+'), findsOneWidget);
  });

  testWidgets('kalau semuanya muat, tidak ada +N', (tester) async {
    await ukur(tester, const ['AC'], 320);
    expect(find.textContaining('+'), findsNothing);
    expect(find.text('AC'), findsOneWidget);
  });

  testWidgets('selalu menampilkan minimal satu', (tester) async {
    // Baris kosong berarti fasilitasnya seolah tidak ada.
    await ukur(tester, const ['Nama Fasilitas Yang Sangat Panjang Sekali'], 90);
    expect(tester.takeException(), isNull);
    expect(find.byType(Row), findsWidgets);
  });

  group('sumbernya', () {
    test('tidak lagi memakai baris yang digeser', () {
      expect(sumber, isNot(contains('scrollDirection: Axis.horizontal')));
      expect(sumber, contains('_BarisFasilitas('));
    });

    test('ruang untuk +N disisihkan sejak awal', () {
      // Menghitungnya belakangan berarti chip terakhir sudah terlanjur
      // masuk, lalu "+N"-nya yang melimpah keluar kartu.
      expect(sumber, contains('const lebarLainnya = 42.0;'));
    });

    test('merchant tutup tidak masuk saran terdekat', () {
      // "Terdekat" adalah saran, bukan katalog.
      expect(sumber, contains('km <= _nearbyRadiusKm && !_tutup(r)'));
    });

    test('yang tutup tetap ada di daftar semua merchant', () {
      // Dibuang dari saran, bukan dari katalognya.
      final blok = sumber.substring(sumber.indexOf('List<Restaurant> get _matching'));
      expect(blok.substring(0, 900), isNot(contains('!_tutup(')));
    });
  });
}
