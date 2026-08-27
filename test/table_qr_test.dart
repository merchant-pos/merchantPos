import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/utils/table_qr_image.dart';

void main() {
  group('tableLabels', () {
    test('jumlah yang diisi menghasilkan sebanyak itu QR', () {
      // Inilah maksud fitur borongannya: "mejaku ada sepuluh" → sepuluh
      // QR, bernomor 1 sampai 10.
      expect(tableLabels(count: 10), hasLength(10));
      expect(tableLabels(count: 10).first, '1');
      expect(tableLabels(count: 10).last, '10');
    });

    test('nomornya polos, tanpa nol di depan', () {
      // Nomor ini tersimpan di dalam QR dan muncul di layar dapur, jadi
      // harus sama persis dengan yang diketik orang di mode satu meja.
      // "07" dan "7" adalah dua meja berbeda di mata siapa pun yang
      // membacanya.
      expect(tableLabels(count: 12), contains('7'));
      expect(tableLabels(count: 12), isNot(contains('07')));
    });

    test('awalan menempel di depan nomornya', () {
      expect(tableLabels(prefix: 'A', count: 3), ['A1', 'A2', 'A3']);
    });

    test('satu meja tetap sah', () {
      expect(tableLabels(count: 1), ['1']);
    });

    test('jumlah nol atau negatif tidak menghasilkan apa-apa', () {
      expect(tableLabels(count: 0), isEmpty);
      expect(tableLabels(count: -3), isEmpty);
    });

    test('tepat sebatas maksimum masih boleh, lewat satu ditolak', () {
      expect(tableLabels(count: kMaxTableBatch), hasLength(kMaxTableBatch));
      expect(tableLabels(count: kMaxTableBatch + 1), isEmpty);
    });
  });

  group('TableQrCard.fileName', () {
    test('pembuatan satuan tanpa nomor urut', () {
      const card = TableQrCard(restoName: 'Merchant', table: '7', payload: 'x');
      expect(card.fileName, 'qr-meja-7.png');
    });

    test('pembuatan borongan diberi nomor urut berimbuhan nol', () {
      // Galeri mengurutkan nama berkas sebagai teks. Tanpa nol di depan,
      // meja 10 nyempil di antara 1 dan 2 — dan yang memasangnya di meja
      // harus membaca satu per satu.
      const card = TableQrCard(
        restoName: 'Merchant',
        table: '7',
        payload: 'x',
        sequence: 7,
      );
      expect(card.fileName, 'qr-meja-007-7.png');
    });

    test('urutan berkas mengikuti urutan mejanya', () {
      final names = [
        for (var i = 1; i <= 12; i++)
          TableQrCard(
            restoName: 'Merchant',
            table: '$i',
            payload: 'x',
            sequence: i,
          ).fileName,
      ];
      final sorted = [...names]..sort();
      // Inilah yang dijaga nomor urutnya: diurutkan sebagai teks pun,
      // meja 2 tetap datang sebelum meja 10.
      expect(sorted, names);
    });

    test('karakter yang tidak aman untuk nama berkas diganti', () {
      // Nomor meja bebas diketik, jadi "VIP/2" bisa saja masuk — dan
      // garis miring di situ akan dibaca sebagai pemisah folder.
      const card = TableQrCard(restoName: 'Merchant', table: 'VIP/2', payload: 'x');
      expect(card.fileName, 'qr-meja-VIP-2.png');
    });
  });
}
