import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/widgets/responsive.dart';

void main() {
  group('ResponsiveCenter', () {
    testWidgets('di bottomNavigationBar tingginya mengikuti isinya', (tester) async {
      // Inilah bug yang membuat layar QR Meja tampak kosong sama sekali
      // di perangkat: pembungkus yang melebar ke seluruh ruang membuat
      // bilah bawah setinggi layar penuh, dan badan layarnya tersisa nol.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(child: ColoredBox(color: Colors.blue)),
            bottomNavigationBar: ResponsiveCenter(
              child: SizedBox(height: 60, child: Container(color: Colors.red)),
            ),
          ),
        ),
      );

      final bar = tester.getSize(find.byType(ResponsiveCenter));
      expect(bar.height, 60);
    });

    testWidgets('badan layar tetap terisi penuh', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveCenter(
              child: ListView(children: const [Text('baris')]),
            ),
          ),
        ),
      );

      final screen = tester.getSize(find.byType(Scaffold));
      final body = tester.getSize(find.byType(ResponsiveCenter));
      expect(body.height, screen.height);
      expect(find.text('baris'), findsOneWidget);
    });

    testWidgets('lebarnya dibatasi di layar lebar', (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveCenter(
              maxWidth: 840,
              child: Container(color: Colors.green),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Container)).width, 840);
    });

    testWidgets('di layar sempit isinya memakai lebar penuh', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveCenter(child: Container(color: Colors.green)),
          ),
        ),
      );

      final screen = tester.getSize(find.byType(Scaffold));
      expect(tester.getSize(find.byType(Container)).width, screen.width);
    });
  });
}
