import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Catatan rilis dan penamaan berkas APK.
void main() {
  Map<String, dynamic> jalankan(String versi) {
    final hasil = Process.runSync('python3', [
      'scripts/catatan_rilis.py',
      'docs/CATATAN-RILIS.md',
      versi,
    ]);
    expect(hasil.exitCode, 0, reason: hasil.stderr.toString());
    return jsonDecode(hasil.stdout.toString()) as Map<String, dynamic>;
  }

  /// Rincian bug tidak diumumkan.
  ///
  /// Merinci bug berarti mengumumkan ke semua orang — termasuk yang
  /// tidak berkepentingan baik — apa saja yang pernah bisa ditembus,
  /// dilewati, atau dibuat berhenti bekerja. Rinciannya tetap ada di
  /// pesan commit dan di TSD; yang dibatasi pengumumannya.
  group('pengumuman tidak merinci bug', () {
    const rangkuman = 'Perbaikan bug dan penyempurnaan tampilan';

    /// Kosakata perbaikan yang tidak punya tempat di pengumuman.
    ///
    /// Sengaja pendek dan tegas. Daftar yang panjang akan menjegal
    /// kalimat fitur yang kebetulan memakai kata biasa, lalu ditambahi
    /// pengecualian satu per satu sampai tidak menjaga apa pun lagi.
    const bocor = ['bug', 'galat', 'error', 'crash', 'gagal'];

    /// Aturannya mulai berlaku dari versi ini. Yang lebih lama sudah
    /// terlanjur diumumkan — menulis ulangnya sekarang tidak menarik
    /// kembali apa pun, dan cuma membuat catatannya berbeda dari yang
    /// benar-benar dikirim ke kotak masuk.
    bool berlaku(String versi) {
      final b = versi.split('.').map(int.parse).toList();
      return b[0] > 2 || (b[0] == 2 && b[1] >= 15);
    }

    final isi = File('docs/CATATAN-RILIS.md').readAsStringSync();

    test('aturannya tertulis di dokumennya sendiri', () {
      expect(isi, contains(rangkuman));
      expect(isi, contains('Perbaikan bug dirangkum jadi satu baris'));
    });

    test('tidak ada rincian bug di versi mana pun sejak 2.15.0', () {
      final bagian = RegExp(r'^## (\d+\.\d+\.\d+)$', multiLine: true)
          .allMatches(isi)
          .toList();
      final temuan = <String>[];

      for (var i = 0; i < bagian.length; i++) {
        final versi = bagian[i].group(1)!;
        if (!berlaku(versi)) continue;
        final akhir =
            i + 1 < bagian.length ? bagian[i + 1].start : isi.length;
        for (final baris in isi.substring(bagian[i].end, akhir).split('\n')) {
          final b = baris.trim();
          if (!b.startsWith('- ')) continue;
          if (b.contains(rangkuman)) continue;
          for (final kata in bocor) {
            if (b.toLowerCase().contains(kata)) {
              temuan.add('$versi: $b');
              break;
            }
          }
        }
      }

      expect(temuan, isEmpty,
          reason: 'rangkum jadi "$rangkuman" — rincian bugnya di commit '
              'dan TSD saja');
    });
  });

  /// Rilis untuk versi yang sudah terbit tidak boleh berjalan diam-diam.
  ///
  /// Menjalankannya ulang bukan sekadar mubazir: rilis lamanya dihapus
  /// lalu dibuat ulang, dan pengumumannya terkirim dua kali ke seluruh
  /// kotak masuk — yang menerimanya tidak punya cara tahu itu kabar yang
  /// sama. Pernah terjadi pada 2.15.0.
  group('penjaga rilis ulang', () {
    final skrip = File('scripts/release.sh').readAsStringSync();

    test('memeriksa tag yang sudah ada di GitHub', () {
      expect(skrip, contains(r'releases/tags/$TAG'));
      expect(skrip, contains('sudah ada di GitHub'));
    });

    // Delapan menit build yang berakhir dengan penolakan adalah delapan
    // menit yang tidak perlu dihabiskan.
    test('diperiksa sebelum build, bukan sesudahnya', () {
      expect(skrip.indexOf('sudah ada di GitHub'),
          lessThan(skrip.indexOf('flutter build apk')));
    });

    test('punya jalan keluar untuk yang memang disengaja', () {
      expect(skrip, contains('--ulang'));
      expect(skrip, contains('!= "--ulang"'));
    });

    test('dry run tidak ikut terhalang', () {
      final blok = skrip.substring(
          skrip.indexOf('# ── 0. Versi ini sudah pernah terbit?'),
          skrip.indexOf('# ── 1. Build'));
      expect(blok, contains(r'if ! $DRY_RUN'));
    });
  });

  group('catatan rilis', () {
    test('versi yang punya catatannya membawa poin-poinnya', () {
      final j = jalankan('1.0.0');
      expect(j['version'], '1.0.0');
      expect(j['body'], contains('Yang berubah:'));
      expect(j['body'], contains('Rilis pertama MerchantPOS'));
    });

    test('tidak membawa apa pun dari luar bagiannya', () {
      // Bagiannya dibatasi judul di atas dan judul berikutnya di bawah.
      // Tanpa batas atas, seluruh penjelasan cara menulis catatan rilis
      // — yang ditujukan ke penulisnya, bukan ke merchant — ikut
      // terkirim ke kotak masuk semua orang.
      final j = jalankan('1.0.0');
      expect(j['body'], isNot(contains('Dua aturan yang berbeda')));
      expect(j['body'], isNot(contains('Formatnya dibaca')));
    });

    test('versi tanpa catatan tetap terbit, tanpa body', () {
      // Menahan rilis karena catatannya belum ditulis menukar
      // ketidaknyamanan kecil dengan satu rilis yang gagal terbit.
      final j = jalankan('9.9.9');
      expect(j['version'], '9.9.9');
      expect(j.containsKey('body'), isFalse);
    });

    test('keluarannya JSON yang sah untuk dikirim apa adanya', () {
      final j = jalankan('1.0.0');
      expect(j['body'], isA<String>());
    });

    test('dipakai skrip rilisnya', () {
      final sh = File('scripts/release.sh').readAsStringSync();
      expect(sh, contains('scripts/catatan_rilis.py'));
      expect(sh, contains('-d "\$ANNOUNCE_BODY"'));
    });
  });

  group('nama berkas APK', () {
    final rilis = File('scripts/github_release.py').readAsStringSync();
    final sh = File('scripts/release.sh').readAsStringSync();

    test('diunggah dengan nomor versinya', () {
      // Folder unduhan berisi lima "MerchantPOS.apk (3)" tidak memberi tahu
      // siapa pun mana yang terbaru.
      expect(rilis, contains('f"MerchantPOS-{versi}.apk"'));
    });

    test('nama tetapnya ikut diunggah supaya tautan lama tidak mati', () {
      expect(rilis, contains('"MerchantPOS.apk"'));
      expect(rilis, contains('for nama in ('));
    });

    test('tautan di web menunjuk yang bernomor versi', () {
      expect(sh, contains("MerchantPOS-{version}.apk"));
      expect(sh, contains("var APK_URL"));
    });

    test('penanda tautannya diperiksa sebelum ditulis ulang', () {
      // Penanda yang hilang berarti halamannya diam-diam terus menunjuk
      // versi lama.
      expect(sh, contains("'var APK_URL'"));
    });
  });
}
