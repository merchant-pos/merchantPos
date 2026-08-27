import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bahasa dan tema aplikasi — pilihan perangkat, bukan pilihan akun.
///
/// Disimpan di HP-nya, bukan di profil pengguna di server. Dua alasan:
/// pelanggan tamu tidak punya akun sama sekali, dan pilihannya harus
/// sudah berlaku di layar pertama — sebelum ada yang login, sebelum ada
/// panggilan jaringan apa pun. Setelan yang baru bisa dibaca setelah
/// masuk akun berarti layar pembuka selalu tampil dalam bahasa yang
/// salah untuk sebagian orang.
///
/// Karena itu pula tombolnya tetap ada di halaman awal: setelah keluar
/// akun, tidak ada lagi menu Pengaturan yang bisa dibuka.
class AppPrefsProvider extends ChangeNotifier {
  static const _localeKey = 'app_locale';
  static const _themeKey = 'app_theme_mode';

  Locale _locale = const Locale('id');
  ThemeMode _themeMode = ThemeMode.system;

  /// Sudah dibaca dari penyimpanan. Sebelum ini, jangan menggambar
  /// apa pun yang bergantung pada bahasanya — satu kedipan dari bahasa
  /// bawaan ke bahasa pilihannya terlihat seperti aplikasi yang salah
  /// memuat.
  bool loaded = false;

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;

  bool get isEnglish => _locale.languageCode == 'en';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString(_localeKey);
      if (lang != null) _locale = Locale(lang);
      final theme = prefs.getString(_themeKey);
      _themeMode = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Penyimpanan tidak terbaca — pakai bawaannya. Bahasa Indonesia
      // dan tema mengikuti HP adalah tebakan yang benar untuk hampir
      // semua pemakainya.
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale value) async {
    if (value.languageCode == _locale.languageCode) return;
    _locale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, value.languageCode);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeKey,
      switch (value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }
}
