import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/utils/field_rules.dart';

void main() {
  group('validateName', () {
    test('menerima nama wajar', () {
      expect(validateName('Gamal Abdul', label: 'Nama'), isNull);
      expect(validateName('Warung 88', label: 'Nama'), isNull);
      expect(validateName("Kopi & Roti", label: 'Nama'), isNull);
      expect(validateName('Bpk. Andi', label: 'Nama'), isNull);
    });

    test('menolak emoji', () {
      expect(validateName('Warung 🍜', label: 'Nama'), isNotNull);
      expect(validateName('😀', label: 'Nama'), isNotNull);
    });

    test('menolak lebih dari 40 karakter', () {
      expect(validateName('A' * 41, label: 'Nama'), contains('maksimal 40'));
      expect(validateName('A' * 40, label: 'Nama'), isNull);
    });

    test('kosong hanya ditolak kalau wajib', () {
      expect(validateName('', label: 'Nama'), isNotNull);
      expect(validateName('', label: 'Nama', required: false), isNull);
    });
  });

  group('validatePhone', () {
    test('menerima angka saja', () {
      expect(validatePhone('081234567890'), isNull);
    });

    test('menolak huruf, simbol, dan emoji', () {
      expect(validatePhone('0812-3456'), isNotNull);
      expect(validatePhone('+6281234567'), isNotNull);
      expect(validatePhone('08123📱'), isNotNull);
    });

    test('menolak lebih dari 15 angka', () {
      expect(validatePhone('1' * 16), contains('maksimal 15'));
      expect(validatePhone('1' * 15), isNull);
    });
  });

  group('validateGmail', () {
    test('menerima gmail', () {
      expect(validateGmail('gamal@gmail.com'), isNull);
    });

    test('menolak domain lain', () {
      expect(validateGmail('gamal@yahoo.com'), contains('@gmail.com'));
      expect(validateGmail('gamal@company.co.id'), isNotNull);
    });

    test('menolak lebih dari 25 karakter', () {
      // 16 huruf + @gmail.com = 26 karakter.
      expect(validateGmail('${'a' * 16}@gmail.com'), contains('maksimal 25'));
      expect(validateGmail('${'a' * 15}@gmail.com'), isNull);
    });

    test('menolak emoji dan alamat setengah jadi', () {
      expect(validateGmail('ga🙂@gmail.com'), isNotNull);
      expect(validateGmail('@gmail.com'), isNotNull);
    });
  });

  group('validateNip', () {
    test('menerima angka, menolak sisanya', () {
      expect(validateNip('12345'), isNull);
      expect(validateNip('NIP12'), isNotNull);
      expect(validateNip('1' * 16), contains('maksimal 15'));
    });

    test('boleh kosong', () {
      expect(validateNip(''), isNull);
    });
  });

  group('validateRate', () {
    test('menerima bentuk yang sah', () {
      expect(validateRate('11'), isNull);
      expect(validateRate('12.50'), isNull);
      expect(validateRate('11.1'), isNull);
      expect(validateRate('0'), isNull);
      expect(validateRate(''), isNull); // kosong = 0
    });

    test('menolak angka setengah jadi', () {
      // Inti masalahnya: double.tryParse('11.') mengembalikan 11, jadi
      // tanpa pemeriksaan bentuk, isian ini lolos begitu saja.
      expect(validateRate('11.'), isNotNull);
      expect(validateRate('.'), isNotNull);
      expect(validateRate('.5'), isNotNull);
      expect(validateRate('11..5'), isNotNull);
      expect(validateRate('11,'), isNotNull);
    });

    test('menolak di luar 0 sampai 100', () {
      expect(validateRate('101'), contains('0 dan 100'));
      expect(validateRate('100'), isNull);
    });

    test('koma diperlakukan sebagai desimal', () {
      expect(validateRate('12,50'), isNull);
    });
  });
}
