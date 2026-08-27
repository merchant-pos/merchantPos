import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Batal tidak boleh berdiri di atas tombol yang justru didatangi
/// orangnya.
///
/// Baris `actions` milik AlertDialog melipat jadi kolom begitu kedua
/// labelnya tidak muat berdampingan — dan saat melipat, urutannya
/// mengikuti daftar. Di layar sempit, atau di popup web yang lebarnya
/// dibatasi, itu menaruh Batal di atas Simpan. [DialogActions] menyusun
/// keduanya sendiri supaya urutannya tetap disengaja di lebar berapa
/// pun.
void main() {
  final berkas = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('dialog_actions.dart'));

  test('tidak ada dialog yang menyusun Batal sendiri di baris actions', () {
    final nakal = <String>[];

    for (final f in berkas) {
      final isi = f.readAsStringSync();
      for (final m in RegExp(r'actions: \[').allMatches(isi)) {
        // Isi blok actions-nya saja, sampai penutupnya.
        final sisa = isi.substring(m.end);
        final tutup = sisa.indexOf('\n      ],');
        final blok = tutup < 0 ? sisa.substring(0, 400) : sisa.substring(0, tutup);

        final adaBatal = blok.contains("Text('Batal')");
        if (!adaBatal) continue;

        // Batal sendirian itu dialog pemberitahuan, bukan pilihan —
        // tidak ada yang bisa terbalik urutannya.
        final jumlahTombol = RegExp(r'(TextButton|FilledButton|OutlinedButton)\(')
            .allMatches(blok)
            .length;
        if (jumlahTombol < 2) continue;

        final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        nakal.add('${f.path}:$baris');
      }
    }

    expect(nakal, isEmpty,
        reason: 'pakai DialogActions supaya Batal tetap di bawah: '
            '${nakal.join(', ')}');
  });

  // Warna tombol adalah bahasa yang sudah dipakai seluruh aplikasi
  // untuk membedakan tindakan biasa dari yang merusak. Tombol simpan
  // berwarna lain membuat satu dialog tampak beda jenis dari semua
  // dialog lainnya — dan warna bagian (hijau untuk penarikan, ungu
  // untuk petty cash) sudah punya tempatnya sendiri di ikon dan kotak
  // keterangan.
  test('tombol utama memakai warna tema, kecuali yang merusak', () {
    final nakal = <String>[];
    for (final f in berkas) {
      final isi = f.readAsStringSync();
      for (final m
          in RegExp(r'FilledButton\.styleFrom\(backgroundColor: ([^)]+)\)')
              .allMatches(isi)) {
        final warna = m.group(1)!;
        if (warna.contains('red')) continue;
        final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        nakal.add('${f.path}:$baris ($warna)');
      }
    }
    expect(nakal, isEmpty, reason: nakal.join(', '));
  });
}
