import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tab aktif dibaca lewat DefaultTabController.of(context), dan context
/// yang dipakai harus berada DI BAWAH controller-nya.
///
/// Kelihatan sepele sampai diingat bentuk kegagalannya: galatnya terjadi
/// di dalam onPressed, jadi tidak ada layar merah dan tidak ada pesan
/// apa pun — yang terlihat cuma tombol yang ditekan lalu tidak
/// melakukan apa-apa. Persis yang dilaporkan untuk Tandai Dibaca dan
/// Hapus di kotak masuk.
void main() {
  testWidgets('context di atas DefaultTabController tidak menemukannya',
      (tester) async {
    Object? galat;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (luar) {
        return DefaultTabController(
          length: 2,
          // Sengaja memakai context dari luar — bentuk bug-nya.
          child: Builder(builder: (_) {
            try {
              DefaultTabController.of(luar).index;
            } catch (e) {
              galat = e;
            }
            return const SizedBox.shrink();
          }),
        );
      }),
    ));

    expect(galat, isNotNull,
        reason: 'kalau ini lolos, bug-nya bukan soal context lagi');
  });

  testWidgets('context di bawahnya menemukan tab yang sedang aktif',
      (tester) async {
    late int index;

    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Builder(builder: (dalam) {
          index = DefaultTabController.of(dalam).index;
          return const SizedBox.shrink();
        }),
      ),
    ));

    expect(index, 0);
  });
}
