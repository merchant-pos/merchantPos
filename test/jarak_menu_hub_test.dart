import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Jarak antar tombol di layar hub harus seragam.
///
/// Celah 24 di antara barisan yang semuanya berjarak 12 terbaca seperti
/// ada sesuatu yang gagal dimuat di situ — dan itu persis yang terjadi
/// saat sebuah tile dibuang tapi kedua SizedBox pengapitnya tertinggal.
void main() {
  test('tidak ada celah ganda di layar hub mana pun', () {
    final ganda = RegExp(
      r'const SizedBox\(height: 12\),\s*(?://[^\n]*\n\s*)*const SizedBox\(height: 12\),',
    );

    final temuan = <String>[];
    for (final f in Directory('lib/screens').listSync()) {
      if (f is! File || !f.path.endsWith('_home_screen.dart')) continue;
      final isi = f.readAsStringSync();
      for (final m in ganda.allMatches(isi)) {
        final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        temuan.add('${f.path}:$baris');
      }
    }

    expect(temuan, isEmpty,
        reason: 'celah dobel bikin satu tombol terlihat terpisah sendiri');
  });

  /// Kebalikannya, dan sama-sama terlihat: tombol tanpa jarak sama
  /// sekali di antara tetangga yang berjarak.
  ///
  /// Beranda Owner memberi jaraknya sendiri lewat SizedBox, tidak
  /// seperti beranda peran lain yang menyerahkannya ke HubMenuLayout.
  /// Tombol baru yang ditambahkan tanpa SizedBox akan menempel pada
  /// tetangganya, dan terbaca seperti bagian dari tombol di bawahnya.
  test('di beranda Owner, tiap tombol dipisahkan jaraknya', () {
    final isi = File('lib/screens/owner_home_screen.dart').readAsStringSync();
    // Hanya berlaku untuk yang berada di daftar teratas — yang di dalam
    // `tiles: () => [` memang menempel satu sama lain dengan sengaja.
    //
    // Beranda ini memakai ListView polos, bukan HubMenuLayout seperti
    // peran lain. Itu justru alasan jaraknya harus ditulis tangan.
    final atas = isi.substring(
        isi.indexOf('ListView('), isi.indexOf('HubGroupTile('));
    expect(atas, contains('const SizedBox(height: 12)'),
        reason: 'tombol pertama tidak dipisahkan dari kelompok di bawahnya');
  });
}
