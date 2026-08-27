import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/services/app_updater.dart';
import 'package:merchant_pos/services/notification_router.dart';
import 'package:merchant_pos/widgets/update_download_banner.dart';

/// Disusun persis seperti `main.dart`: penanda mengambangnya hidup di
/// `builder` MaterialApp — DI ATAS Navigator.
///
/// Itu bukan detail. Konteks di sana tidak punya Navigator di atasnya,
/// dan `showDialog` dari sana melempar "Navigator operation requested
/// with a context that does not include a Navigator". Di rilis, galat
/// itu tidak menampilkan apa pun: pilnya cuma terlihat tidak bisa
/// diketuk.
///
/// Tes yang membungkusnya dengan `home:` — di dalam Navigator — akan
/// lulus dan tidak membuktikan apa-apa. Pernah terjadi.
Widget aplikasi() => MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) =>
          UpdateDownloadBanner(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: SizedBox.expand()),
    );

void main() {
  testWidgets('pil unduhan gagal membuka rinciannya', (tester) async {
    AppUpdater.instance.setUjiGagal('Jaringan terputus.');
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Unduhan gagal'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Unduh Pembaruan'), findsOneWidget);
  });

  testWidgets('rinciannya menawarkan Coba Lagi dan Tutup saat gagal',
      (tester) async {
    AppUpdater.instance.setUjiGagal('Jaringan terputus.');
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Unduhan gagal'));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    expect(find.text('Tutup'), findsOneWidget);
    // Tidak ada yang bisa dijeda atau dibatalkan pada unduhan yang sudah
    // berhenti.
    expect(find.text('Jeda'), findsNothing);
    expect(find.text('Batalkan'), findsNothing);
  });

  testWidgets('unduhan berjalan menawarkan Jeda, Batalkan, dan Tutup',
      (tester) async {
    AppUpdater.instance.setUjiBerjalan(0.27);
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();

    expect(find.textContaining('Mengunduh pembaruan 27%'), findsOneWidget);
    await tester.tap(find.textContaining('Mengunduh pembaruan'));
    await tester.pumpAndSettle();

    expect(find.text('Jeda'), findsOneWidget);
    expect(find.text('Batalkan'), findsOneWidget);
    expect(find.text('Tutup'), findsOneWidget);
  });

  testWidgets('yang dijeda menawarkan Lanjutkan, dan angkanya tidak hangus',
      (tester) async {
    AppUpdater.instance.setUjiDijeda(0.27);
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();

    // Angkanya tetap terlihat — yang kembali ke nol membuat orang
    // mengira unduhannya hangus.
    expect(find.textContaining('27%'), findsOneWidget);
    await tester.tap(find.textContaining('Unduhan dijeda'));
    await tester.pumpAndSettle();

    expect(find.text('Lanjutkan'), findsOneWidget);
    expect(find.text('Batalkan'), findsOneWidget);
    expect(find.text('Tutup'), findsOneWidget);
    expect(find.text('Jeda'), findsNothing);
  });

  tearDown(() => AppUpdater.instance.resetUji());
}
