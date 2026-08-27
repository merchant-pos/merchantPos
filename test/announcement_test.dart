import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/announcement.dart';

void main() {
  group('compareVersions', () {
    test('mengurutkan angka, bukan teks', () {
      // Inti masalahnya: diadu sebagai teks, "1.9.0" terlihat lebih besar
      // daripada "1.10.0" — dan banner update tidak akan pernah muncul.
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
    });

    test('versi sama dianggap seri', () {
      expect(compareVersions('1.32.0', '1.32.0'), 0);
    });

    test('menaikkan patch, minor, dan major', () {
      expect(compareVersions('1.32.1', '1.32.0'), greaterThan(0));
      expect(compareVersions('1.33.0', '1.32.9'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('bagian yang hilang dihitung nol', () {
      expect(compareVersions('1.32', '1.32.0'), 0);
      expect(compareVersions('1.32.1', '1.32'), greaterThan(0));
    });

    test('mengabaikan imbuhan non-angka', () {
      expect(compareVersions('v1.32.0', '1.32.0'), 0);
      expect(compareVersions('1.32.0+68', '1.32.0'), 0);
    });
  });
}
