import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:merchant_pos/utils/apk_updater.dart';

void main() {
  group('downloadErrorMessage', () {
    test('galat jaringan jadi satu kalimat, bukan jejak teknis', () {
      // Bentuk aslinya persis seperti ini — dan inilah yang dulu
      // ditampilkan utuh ke layar HP orang.
      final asli = ClientException(
        'Connection closed while receiving data',
        Uri.parse('https://objects.githubusercontent.com/Merchant-POS.apk'),
      );

      final pesan = downloadErrorMessage(asli);

      expect(pesan, 'Unduhan gagal karena masalah koneksi.');
      expect(pesan, isNot(contains('Exception')));
      expect(pesan, isNot(contains('http')));
    });

    test('putusnya socket dianggap masalah koneksi juga', () {
      expect(
        downloadErrorMessage(const SocketException('Connection reset by peer')),
        contains('masalah koneksi'),
      );
    });

    test('penyimpanan penuh dibedakan dari koneksi', () {
      expect(
        downloadErrorMessage(const FileSystemException('No space left')),
        contains('penyimpanan'),
      );
    });

    test('galat tak dikenal pun tidak pernah membocorkan isinya', () {
      final pesan = downloadErrorMessage(
        StateError('Bad state: stream sudah ditutup di dalam _download()'),
      );

      expect(pesan, 'Unduhan gagal. Coba lagi sebentar lagi.');
      expect(pesan, isNot(contains('_download')));
    });

    test('semua pesannya cukup pendek untuk dibaca sekali lihat', () {
      final semua = [
        downloadErrorMessage(const SocketException('x')),
        downloadErrorMessage(const FileSystemException('x')),
        downloadErrorMessage(StateError('x')),
      ];
      for (final pesan in semua) {
        expect(pesan.length, lessThan(70), reason: pesan);
      }
    });
  });
}
