import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `order()` pada aliran realtime bawaannya MENURUN.
///
/// Itu kebalikan dari `select().order()`, yang bawaannya menaik. Menulis
/// `.order('created_at')` saja pada sebuah stream membuat yang terbaru
/// berada di paling atas — dan pada percakapan, itu berarti seluruh
/// obrolan terbaca terbalik.
///
/// Karena bawaannya berlawanan dengan yang diduga, urutannya harus
/// selalu disebut tegas. Yang lupa menyebutnya tidak menemukan galat apa
/// pun — cuma daftar yang terbalik, dan itu bisa bertahan lama.
void main() {
  test('setiap aliran menyebut arah urutannya sendiri', () {
    final temuan = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final isi = f.readAsStringSync();

      // Hanya rantai yang benar-benar berawal dari `.stream(` — sampai
      // titik koma yang menutupnya. Memeriksa seluruh berkas akan ikut
      // menjaring `select().order()` biasa, yang bawaannya justru sudah
      // benar.
      for (final m in '.stream(primaryKey'.allMatches(isi)) {
        final akhir = isi.indexOf(';', m.start);
        final rantai = isi.substring(m.start, akhir < 0 ? isi.length : akhir);

        // Baris komentar dibuang: penjelasan tentang jebakan ini justru
        // menyebut `.order('created_at')` apa adanya sebagai contoh.
        final perintah = rantai
            .split('\n')
            .where((b) => !b.trimLeft().startsWith('//'))
            .join('\n');

        for (final o in RegExp(r'\.order\([^)]*\)').allMatches(perintah)) {
          if (o.group(0)!.contains('ascending')) continue;
          final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
          temuan.add('${f.path}:$baris → ${o.group(0)}');
        }
      }
    }

    expect(temuan, isEmpty,
        reason: 'aliran realtime mengurutkan menurun kalau tidak disebut — '
            'tulis ascending-nya');
  });
}
