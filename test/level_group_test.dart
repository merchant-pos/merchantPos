import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/level_option.dart';

void main() {
  group('LevelGroupRegistry', () {
    test('sebelum dimuat, isinya lima kelompok bawaan', () {
      // Penting justru saat jaringannya mati: dropdown yang kosong
      // membuat pesanan pedas tidak bisa dibedakan dari yang tidak.
      expect(LevelGroupRegistry.optionsOf('Level Pedas'), contains('Extra Pedas'));
    });

    test('daftar merchant menggantikan bawaannya', () {
      LevelGroupRegistry.replaceAll(const [
        LevelGroup(id: '1', name: 'Kematangan', options: ['Medium', 'Well Done']),
      ]);

      expect(LevelGroupRegistry.names, contains('Kematangan'));
      expect(LevelGroupRegistry.optionsOf('Kematangan'), ['Medium', 'Well Done']);
      // Kelompok bawaan yang tidak dipakai resto ini ikut hilang dari
      // daftar pilihannya — itulah gunanya bisa disusun sendiri.
      expect(LevelGroupRegistry.names, isNot(contains('Level Es')));
    });

    test('daftar kosong tidak mengosongkan registri', () {
      // Gagal memuat mengembalikan daftar kosong. Menerapkannya berarti
      // seluruh pilihan level lenyap dari layar pesan gara-gara satu
      // permintaan jaringan yang gagal.
      LevelGroupRegistry.replaceAll(const [
        LevelGroup(id: '1', name: 'Ukuran', options: ['S', 'L']),
      ]);
      LevelGroupRegistry.replaceAll(const []);

      expect(LevelGroupRegistry.optionsOf('Ukuran'), ['S', 'L']);
    });

    test('kelompok yang sudah dihapus tidak melempar galat', () {
      // Produk lama bisa saja masih menyandang nama kelompok yang
      // barusan dihapus restonya.
      expect(LevelGroupRegistry.optionsOf('Kelompok Antah Berantah'), isEmpty);
      expect(LevelGroupRegistry.firstOptionOf('Kelompok Antah Berantah'), isNull);
    });

    test('serialisasi bolak-balik mempertahankan urutan pilihannya', () {
      const group = LevelGroup(
        id: 'x',
        name: 'Jenis Susu',
        options: ['Full Cream', 'Oat', 'Almond'],
      );

      final ulang = LevelGroup.fromMap(group.toMap('merchant-1'));

      expect(ulang.name, 'Jenis Susu');
      expect(ulang.options, ['Full Cream', 'Oat', 'Almond']);
    });
  });
}
