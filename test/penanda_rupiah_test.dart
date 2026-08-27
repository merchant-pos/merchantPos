import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Rp" dan "%" harus terlihat sejak kolomnya masih kosong.
///
/// Flutter menyembunyikan prefix dan suffix selama label kolomnya belum
/// mengambang — bukan dengan melepasnya dari pohon widget, melainkan
/// dengan opasitas nol. Akibatnya kolom kosong berisi petunjuk "5.000"
/// terbaca seperti kolom yang sudah berisi lima ribu, tanpa satu pun
/// tanda bahwa yang diminta rupiah.
double? _opasitas(WidgetTester tester, String teks) {
  final o = tester.widgetList<AnimatedOpacity>(
    find.ancestor(of: find.text(teks), matching: find.byType(AnimatedOpacity)),
  );
  return o.isEmpty ? null : o.first.opacity;
}

Future<void> _pump(WidgetTester tester, InputDecoration d) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: TextField(decoration: d))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tanpa label mengambang, penandanya tak terlihat', (t) async {
    await _pump(
      t,
      const InputDecoration(
          labelText: 'Nominal', prefixText: 'Rp ', hintText: '5.000'),
    );
    // Ada di pohon widget, tapi opasitasnya nol — inilah yang membuatnya
    // lolos dari pemeriksaan `find.text` yang polos.
    expect(_opasitas(t, 'Rp '), 0.0);
  });

  testWidgets('dengan label mengambang, penandanya terlihat', (t) async {
    await _pump(
      t,
      const InputDecoration(
        labelText: 'Nominal',
        prefixText: 'Rp ',
        hintText: '5.000',
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
    expect(_opasitas(t, 'Rp '), 1.0);
  });

  testWidgets('berlaku juga untuk suffix persen', (t) async {
    await _pump(
      t,
      const InputDecoration(
        labelText: 'Persen',
        suffixText: '%',
        hintText: '10',
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
    expect(_opasitas(t, '%'), 1.0);
  });
}
