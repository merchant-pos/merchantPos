import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/widgets/dialog_actions.dart';

/// Tombol Batal dulu menutup dialog dengan nilai `false`.
///
/// Pada showDialog<bool> itu tidak kelihatan salah. Pada
/// showDialog<String> — dan pada dialog yang mengembalikan angka atau
/// record — Navigator melempar "type 'bool' is not a subtype of type
/// 'String?'", dialognya tidak jadi tertutup, dan yang menekan Batal
/// terjebak di depan galat yang tidak menyebut tombol Batal sama sekali.
Future<Object?> bukaDialog<T extends Object>(
  WidgetTester tester,
  T nilaiKonfirmasi,
) async {
  Object? hasil = #belum;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          hasil = await showDialog<T>(
            context: context,
            builder: (c) => AlertDialog(
              actions: [
                DialogActions(
                  confirmLabel: 'OK',
                  onConfirm: () => Navigator.pop(c, nilaiKonfirmasi),
                ),
              ],
            ),
          );
        },
        child: const Text('buka'),
      ),
    ),
  ));
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Batal'));
  await tester.pumpAndSettle();
  return hasil;
}

void main() {
  testWidgets('Batal menutup dialog bertipe String tanpa galat',
      (tester) async {
    expect(await bukaDialog<String>(tester, 'ya'), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Batal menutup dialog bertipe int tanpa galat', (tester) async {
    expect(await bukaDialog<int>(tester, 7), isNull);
    expect(tester.takeException(), isNull);
  });

  // Yang memeriksa hasilnya dengan `== true` tidak terpengaruh: null
  // maupun false sama-sama bukan true.
  testWidgets('Batal pada dialog bertipe bool tetap bukan true',
      (tester) async {
    final hasil = await bukaDialog<bool>(tester, true);
    expect(hasil == true, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tombol utamanya tetap mengembalikan nilainya', (tester) async {
    Object? hasil;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            hasil = await showDialog<String>(
              context: context,
              builder: (c) => AlertDialog(
                actions: [
                  DialogActions(
                    confirmLabel: 'Simpan',
                    onConfirm: () => Navigator.pop(c, 'tersimpan'),
                  ),
                ],
              ),
            );
          },
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(hasil, 'tersimpan');
  });
}
