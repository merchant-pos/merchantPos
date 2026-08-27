import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `confirmLogout` hanya bertanya — ia tidak mengeluarkan siapa pun.
///
/// Memanggilnya tanpa membaca jawabannya menghasilkan tombol yang
/// terlihat bekerja sempurna: dialognya muncul, "Keluar" bisa ditekan,
/// dialognya menutup, dan sesinya utuh seperti semula. Tidak ada galat,
/// tidak ada yang merah di layar — persis bentuk cacat yang tidak
/// ketahuan sampai ada yang mencoba benar-benar keluar.
void main() {
  final berkas = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('logout_confirm.dart'));

  test('setiap pemanggilan confirmLogout dibaca jawabannya', () {
    final lalai = <String>[];

    for (final f in berkas) {
      final isi = f.readAsStringSync();
      for (final m in RegExp(r'confirmLogout\(').allMatches(isi)) {
        final sebelum = isi.substring(
            (m.start - 30).clamp(0, m.start), m.start);
        if (!sebelum.contains('await')) {
          final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
          lalai.add('${f.path}:$baris');
        }
      }
    }

    expect(lalai, isEmpty,
        reason: 'confirmLogout dipanggil tanpa await — dialognya muncul '
            'tapi tidak ada yang keluar: ${lalai.join(', ')}');
  });

  test('sesudah dijawab ya, sesinya benar-benar dilepas', () {
    for (final f in berkas) {
      final isi = f.readAsStringSync();
      if (!isi.contains('confirmLogout(')) continue;
      expect(isi, contains('signOut()'),
          reason: '${f.path} menanyakan keluar tapi tidak pernah signOut');
    }
  });
}
