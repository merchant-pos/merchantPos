import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/providers/app_prefs_provider.dart';
import 'package:merchant_pos/theme.dart';
import 'package:merchant_pos/widgets/language_theme_toggle.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mencari tahu apakah pergantian tema benar-benar merambat ke seluruh
/// layar, atau ada bagian yang tertinggal dengan warna lama.
///
/// Laporannya: di layar dapur, bilah atas sudah berganti terang
/// sementara kartu-kartu harinya masih gelap. Dua warna dari dua tema
/// berbeda di satu layar hanya mungkin kalau ada subtree yang tidak
/// ikut dibangun ulang.
void main() {
  Widget aplikasi(ThemeMode mode, {required Widget body}) => MaterialApp(
        theme: MerchantPosTheme.light(),
        darkTheme: MerchantPosTheme.dark(),
        themeMode: mode,
        home: Scaffold(appBar: AppBar(title: const Text('x')), body: body),
      );

  testWidgets('kartu biasa ikut berganti warna', (tester) async {
    await tester.pumpWidget(aplikasi(ThemeMode.dark,
        body: const Card(child: SizedBox(height: 20))));
    final gelap = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)));

    await tester.pumpWidget(aplikasi(ThemeMode.light,
        body: const Card(child: SizedBox(height: 20))));
    // MaterialApp memakai AnimatedTheme: warnanya berpindah bertahap,
    // bukan seketika. Membacanya sebelum animasinya selesai berarti
    // membaca warna lama — dan menyimpulkan ada yang rusak padahal
    // cuma belum sampai.
    await tester.pumpAndSettle();
    final terang = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)));

    expect(gelap.color, isNot(terang.color));
  });

  testWidgets('isi di dalam TabBarView juga ikut berganti', (tester) async {
    // Tersangka utama: halaman tab yang sedang tidak terlihat dijaga
    // tetap hidup, lalu ditampilkan lagi dengan warna dari tema lama.
    Widget denganTab(ThemeMode mode) => MaterialApp(
          theme: MerchantPosTheme.light(),
          darkTheme: MerchantPosTheme.dark(),
          themeMode: mode,
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(bottom: const TabBar(tabs: [Tab(text: 'a'), Tab(text: 'b')])),
              body: const TabBarView(
                children: [
                  Card(child: SizedBox(height: 20)),
                  SizedBox.shrink(),
                ],
              ),
            ),
          ),
        );

    await tester.pumpWidget(denganTab(ThemeMode.dark));
    final gelap = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)));

    await tester.pumpWidget(denganTab(ThemeMode.light));
    await tester.pumpAndSettle();
    final terang = tester.widget<Material>(
        find.descendant(of: find.byType(Card), matching: find.byType(Material)));

    expect(gelap.color, isNot(terang.color));
  });

  Widget denganPemilih(double lebar) => MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider(
            create: (_) => AppPrefsProvider()..load(),
            child: Center(
              child: SizedBox(width: lebar, child: const ThemeToggle()),
            ),
          ),
        ),
      );

  testWidgets('sempit: hanya ikon, tanpa tulisan', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(denganPemilih(240));
    await tester.pumpAndSettle();

    expect(find.text('Terang'), findsNothing);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
  });

  testWidgets('lapang: tulisannya ikut tampil', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(denganPemilih(420));
    await tester.pumpAndSettle();

    expect(find.text('Terang'), findsOneWidget);
    expect(find.text('Ikuti HP'), findsOneWidget);
  });
}
