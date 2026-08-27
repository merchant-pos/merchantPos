import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/theme.dart';

/// Berkas yang warnanya memang harus tetap, apa pun temanya.
const _dikecualikan = {
  'lib/theme.dart',
  'lib/widgets/receipt_view.dart', // struk: dicetak & disimpan ke galeri
  'lib/widgets/merchantpos_qr_card.dart', // kartu QR berbingkai
  'lib/utils/table_qr_image.dart', // PDF
  'lib/screens/finance_report_screen.dart', // PDF
  'lib/screens/receipt_screen.dart',
  'lib/screens/customer_receipt_screen.dart',
};

/// Menjalankan [pemeriksa] dengan context di bawah [tema].
///
/// Temanya dipasang langsung lewat Theme(), bukan lewat themeMode di
/// MaterialApp: di lingkungan tes, kecerahan sistemnya selalu terang,
/// dan menyandarkan pemeriksaan pada penyetelan tidak langsung membuat
/// tesnya menguji harness-nya sendiri alih-alih warnanya.
Future<void> _diTema(
  WidgetTester tester,
  ThemeData tema,
  void Function(BuildContext context) pemeriksa,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Theme(
      data: tema,
      child: Builder(builder: (context) {
        pemeriksa(context);
        return const SizedBox.shrink();
      }),
    ),
  ));
}

void main() {
  test('tidak ada lagi abu-abu yang ditulis langsung di layar', () {
    // Colors.grey.shadeNNN dipilih untuk latar terang. Di tema gelap ia
    // jatuh nyaris tidak terbaca — dan yang paling sering memakainya
    // justru teks penjelas, yang memang sudah kecil.
    final pelanggar = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_dikecualikan.contains(f.path)) continue;
      if (f.readAsStringSync().contains('Colors.grey.shade')) {
        pelanggar.add(f.path);
      }
    }
    expect(pelanggar, isEmpty,
        reason: 'pakai MerchantPosTheme.mutedOf / softFillOf / borderOf');
  });

  test('latar halaman tidak lagi dipaku ke warna terang', () {
    // MerchantPosTheme.backgroundTint dipasang langsung sebagai
    // backgroundColor Scaffold di belasan layar, dan nilai tetap itu
    // menang atas scaffoldBackgroundColor milik tema. Hasilnya di mode
    // gelap: halaman berlatar lavender terang dengan kartu gelap di
    // atasnya — persis kebalikan dari yang dimaksud.
    final pelanggar = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_dikecualikan.contains(f.path)) continue;
      final isi = f.readAsStringSync();
      // Warna near-putih yang ditulis langsung sebagai latar. Semuanya
      // dipilih untuk menampung tulisan gelap, dan di tema gelap
      // tulisannya berubah terang — hilang di dalam kotaknya sendiri.
      const putihSamaran = [
        'MerchantPosTheme.backgroundTint',
        '0xFFEEEEEE',
        '0xFFF7F8FC',
        '0xFFF4F5FB',
        '0xFFFAFAFA',
        '0xFFF5F5F5',
      ];
      if (putihSamaran.any(isi.contains)) {
        pelanggar.add(f.path);
      }
    }
    expect(pelanggar, isEmpty,
        reason: 'pakai MerchantPosTheme.backgroundOf / disabledFillOf');
  });

  test('warna pastel tidak ditulis langsung sebagai latar', () {
    // Colors.X.shade50 dipilih untuk menampung tulisan gelap. Di tema
    // gelap ia jadi pita terang yang menelan tulisan terangnya sendiri.
    final pelanggar = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_dikecualikan.contains(f.path)) continue;
      final isi = f.readAsStringSync();
      if (isi.contains('.shade50') || isi.contains('.shade100')) {
        pelanggar.add(f.path);
      }
    }
    expect(pelanggar, isEmpty, reason: 'pakai MerchantPosTheme.tintOf / onTintOf');
  });

  testWidgets('latar dan kartu tidak pernah tertukar terang-gelapnya',
      (tester) async {
    // Kartu harus selalu lebih terang daripada latarnya di tema gelap,
    // dan lebih terang pula di tema terang — kalau tertukar, kartunya
    // terbaca sebagai lubang alih-alih sebagai kartu.
    for (final tema in [MerchantPosTheme.light(), MerchantPosTheme.dark()]) {
      late Color latar, kartu;
      await _diTema(tester, tema, (c) {
        latar = MerchantPosTheme.backgroundOf(c);
        kartu = MerchantPosTheme.surfaceOf(c);
      });
      expect(kartu.computeLuminance(),
          greaterThanOrEqualTo(latar.computeLuminance()));
    }
  });

  testWidgets('token temanya menjawab berbeda di terang dan gelap',
      (tester) async {
    late Color terang, gelap;
    await _diTema(
        tester, MerchantPosTheme.light(), (c) => terang = MerchantPosTheme.surfaceOf(c));
    await _diTema(tester, MerchantPosTheme.dark(), (c) => gelap = MerchantPosTheme.surfaceOf(c));

    expect(terang, Colors.white);
    expect(gelap, isNot(Colors.white));
  });

  testWidgets('teks utama tidak pernah hitam di tema gelap', (tester) async {
    // Hitam di atas latar gelap bukan sekadar sulit dibaca — ia hilang.
    late Color gelap;
    await _diTema(tester, MerchantPosTheme.dark(), (c) => gelap = MerchantPosTheme.textOf(c));

    expect(gelap.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('teks redup tetap punya jarak dari latarnya', (tester) async {
    // Teks penjelas yang menyatu dengan latarnya sama saja dengan tidak
    // ditulis.
    late Color terang, gelap;
    await _diTema(tester, MerchantPosTheme.light(), (c) => terang = MerchantPosTheme.mutedOf(c));
    await _diTema(tester, MerchantPosTheme.dark(), (c) => gelap = MerchantPosTheme.mutedOf(c));

    expect(terang.computeLuminance(), lessThan(0.5));
    expect(gelap.computeLuminance(), greaterThan(0.2));
  });
}
