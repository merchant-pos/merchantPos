import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/theme.dart';

/// Tema aplikasi memberi tombol `minimumSize: Size.fromHeight(50)`, dan
/// `Size.fromHeight` berarti lebar **double.infinity**.
///
/// Di layar biasa itu yang diinginkan: tombol selebar layar. Tapi di
/// dalam `Row`, anak yang tidak fleksibel diukur dengan lebar tak
/// terbatas lebih dulu — tombolnya mengambil semuanya dan `Expanded` di
/// sebelahnya kebagian nol. Di debug itu melempar "forces an infinite
/// width"; di rilis pemeriksaannya dimatikan, jadi yang tersisa cuma
/// kolom isian yang menyusut jadi garis tipis, tanpa satu pun galat.
void main() {
  testWidgets('tombol berlebar tetap menyisakan ruang untuk isiannya',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: MerchantPosTheme.light(),
      home: Scaffold(
        body: Row(
          children: [
            const Expanded(child: TextField(key: Key('isian'))),
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(104, 46),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () {},
                child: const Text('Tebus'),
              ),
            ),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(
        tester.getSize(find.byKey(const Key('isian'))).width, greaterThan(200));
  });

  test('kolom kode voucher menyebut lebar tombolnya', () {
    // Penjaga sumber, bukan tampilan: yang menghapus baris `width:` ini
    // tidak akan melihat apa pun rusak sampai layarnya dibuka di rilis.
    final layar =
        File('lib/screens/my_vouchers_screen.dart').readAsStringSync();
    expect(layar, contains('width: 104,\n                          height: 46,'));
    expect(layar, contains('minimumSize: const Size(104, 46),'));
  });
}
