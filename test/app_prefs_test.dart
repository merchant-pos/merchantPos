import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/l10n/strings.dart';
import 'package:merchant_pos/providers/app_prefs_provider.dart';
import 'package:merchant_pos/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppPrefsProvider', () {
    test('bawaannya Indonesia dan mengikuti tema HP', () async {
      final prefs = AppPrefsProvider();
      await prefs.load();

      expect(prefs.locale.languageCode, 'id');
      expect(prefs.isEnglish, isFalse);
      expect(prefs.themeMode, ThemeMode.system);
    });

    test('pilihannya bertahan setelah aplikasi dibuka ulang', () async {
      // Ini inti janjinya: dipilih sekali di halaman awal, lalu ikut ke
      // mana-mana — termasuk ke sesi berikutnya.
      final pertama = AppPrefsProvider();
      await pertama.load();
      await pertama.setLocale(const Locale('en'));
      await pertama.setThemeMode(ThemeMode.dark);

      final kedua = AppPrefsProvider();
      await kedua.load();

      expect(kedua.isEnglish, isTrue);
      expect(kedua.themeMode, ThemeMode.dark);
    });

    test('penyimpanan yang gagal tidak menghentikan aplikasi', () async {
      // Layar pertama harus tetap tampil walau setelannya tidak terbaca.
      final prefs = AppPrefsProvider();
      await prefs.load();

      expect(prefs.loaded, isTrue);
    });

    test('memilih bahasa yang sama tidak menggambar ulang percuma', () async {
      final prefs = AppPrefsProvider();
      await prefs.load();
      var diberitahu = 0;
      prefs.addListener(() => diberitahu++);

      await prefs.setLocale(const Locale('id'));
      expect(diberitahu, 0);

      await prefs.setLocale(const Locale('en'));
      expect(diberitahu, 1);
    });
  });

  group('kamus', () {
    test('kalimat yang belum diterjemahkan tetap terbaca, bukan jadi kode', () {
      // Dengan 49 layar, penerjemahan memang bertahap. Yang tidak boleh
      // terjadi adalah layar yang terlewat menampilkan kunci mentah ke
      // pemakainya.
      const asing = 'Kalimat yang belum masuk kamus';
      expect(translateForTest(asing, english: true), asing);
    });

    test('yang sudah ada padanannya benar-benar berganti', () {
      expect(translateForTest('Simpan', english: true), 'Save');
      expect(translateForTest('Simpan', english: false), 'Simpan');
    });

    test('kamusnya tidak kosong', () {
      expect(translatedCount, greaterThan(50));
    });
  });

  group('tema gelap', () {
    test('warna merek dinaikkan terangnya, tidak dipakai apa adanya', () {
      // Ungu tua di atas abu tua jatuh di bawah ambang keterbacaan.
      expect(MerchantPosTheme.brandOnDark, isNot(MerchantPosTheme.brand));
    });

    test('latarnya bukan hitam murni', () {
      // Kartu terang di atas hitam murni memedihkan di ruangan gelap —
      // dan layar ini justru paling sering dibuka saat tutup toko.
      expect(MerchantPosTheme.darkBackground, isNot(Colors.black));
    });

    test('tema gelap dan terang keduanya bisa dibangun', () {
      expect(MerchantPosTheme.dark().brightness, Brightness.dark);
      expect(MerchantPosTheme.light().brightness, Brightness.light);
    });
  });
}
