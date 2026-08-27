import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/utils/greeting.dart';

void main() {
  group('mealTimeFor', () {
    test('membagi hari mengikuti jam makan', () {
      expect(mealTimeFor(7), MealTime.sarapan);
      expect(mealTimeFor(12), MealTime.makanSiang);
      expect(mealTimeFor(16), MealTime.sore);
      expect(mealTimeFor(20), MealTime.makanMalam);
      expect(mealTimeFor(2), MealTime.tengahMalam);
    });

    test('menutup seluruh 24 jam tanpa celah', () {
      // Sebuah jam yang tidak masuk potongan mana pun akan membuat
      // greetingFor melempar saat diakses — dan itu terjadi di layar
      // pertama yang dilihat customer.
      for (var hour = 0; hour < 24; hour++) {
        expect(() => mealTimeFor(hour), returnsNormally, reason: 'jam $hour');
      }
    });

    test('batasnya tidak tumpang tindih di pergantian', () {
      expect(mealTimeFor(3), MealTime.tengahMalam);
      expect(mealTimeFor(4), MealTime.sarapan);
      expect(mealTimeFor(9), MealTime.sarapan);
      expect(mealTimeFor(10), MealTime.makanSiang);
      expect(mealTimeFor(14), MealTime.makanSiang);
      expect(mealTimeFor(15), MealTime.sore);
      expect(mealTimeFor(17), MealTime.sore);
      expect(mealTimeFor(18), MealTime.makanMalam);
      expect(mealTimeFor(22), MealTime.makanMalam);
      expect(mealTimeFor(23), MealTime.tengahMalam);
    });
  });

  group('greetingFor', () {
    test('selalu memberi sapaan untuk jam berapa pun', () {
      for (var hour = 0; hour < 24; hour++) {
        final text = greetingFor(DateTime(2026, 8, 12, hour));
        expect(text, isNotEmpty, reason: 'jam $hour');
      }
    });

    test('tidak berubah dalam satu hari dan jam yang sama', () {
      // Sapaannya dipilih dari tanggal, bukan acak — kalau tidak, ia akan
      // berganti setiap kali layarnya digambar ulang.
      final a = greetingFor(DateTime(2026, 8, 12, 12, 0));
      final b = greetingFor(DateTime(2026, 8, 12, 12, 59));
      expect(a, b);
    });

    test('sapaan pagi dan malam tidak sama', () {
      final pagi = greetingFor(DateTime(2026, 8, 12, 7));
      final malam = greetingFor(DateTime(2026, 8, 12, 20));
      expect(pagi, isNot(malam));
    });
  });
}
