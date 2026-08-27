import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../providers/app_prefs_provider.dart';
import '../theme.dart';

/// Fitur bahasa disembunyikan dulu.
///
/// Mekanismenya jalan, tapi terjemahannya baru menutup sekitar 90 dari
/// ~1.400 kalimat di aplikasi ini. Tombol yang menjanjikan bahasa
/// Inggris lalu menyodorkan layar yang tetap berbahasa Indonesia lebih
/// buruk daripada tidak ada tombolnya: yang menekannya menyimpulkan
/// aplikasinya rusak, bukan bahwa fiturnya belum selesai.
///
/// Dikembalikan ke true saat terjemahannya sudah utuh. Kodenya sengaja
/// tidak dibuang — yang tersisa cuma mengisi kamusnya.
const kLanguageSwitcherEnabled = false;

/// Pemilih bahasa berbendera, dipakai di halaman awal dan di Pengaturan.
///
/// Benderanya emoji, bukan berkas gambar: ikut mengikuti bentuk yang
/// dikenali sistem operasinya, tidak menambah aset yang harus dirawat,
/// dan tidak pernah menjadi kotak kosong saat gagal dimuat.
///
/// Indonesia lebih dulu karena itu bahasa mayoritas pemakainya —
/// urutan pilihan adalah pernyataan tentang siapa yang diutamakan.
class LanguageToggle extends StatelessWidget {
  /// Ringkas untuk halaman awal, melebar untuk layar Pengaturan.
  final bool compact;

  const LanguageToggle({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (!kLanguageSwitcherEnabled) return const SizedBox.shrink();
    final prefs = context.watch<AppPrefsProvider>();

    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: 'id',
          label: Text(compact ? '🇮🇩 ID' : '🇮🇩  Indonesia'),
        ),
        ButtonSegment(
          value: 'en',
          label: Text(compact ? '🇬🇧 EN' : '🇬🇧  English'),
        ),
      ],
      selected: {prefs.locale.languageCode},
      onSelectionChanged: (v) => prefs.setLocale(Locale(v.first)),
      style: compact
          ? ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10),
              ),
            )
          : null,
    );
  }
}

/// Pemilih tema: Terang, Gelap, atau ikut setelan HP.
///
/// "Ikuti HP" ada dan menjadi bawaannya karena sebagian besar orang
/// sudah menentukan pilihannya sekali di tingkat sistem — termasuk yang
/// menjadwalkannya berganti sendiri saat malam. Memaksa mereka memilih
/// lagi di sini berarti aplikasi ini yang menyendiri saat semua
/// aplikasi lain di HP-nya berubah.
class ThemeToggle extends StatelessWidget {
  /// Dipanggil setelah temanya berganti.
  ///
  /// Dipakai dialog Tampilan untuk menutup dirinya sendiri. Tanpa itu
  /// dialognya tetap menutupi layar yang barusan berganti warna, dan
  /// yang terlihat cuma sebagian kecil di pinggirnya — cukup untuk
  /// mengira temanya belum sepenuhnya berubah.
  final VoidCallback? onChanged;

  const ThemeToggle({super.key, this.onChanged});

  static const _pilihan = [
    (ThemeMode.light, Icons.light_mode_outlined, 'Terang'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Gelap'),
    (ThemeMode.system, Icons.brightness_auto_outlined, 'Ikuti HP'),
  ];

  /// Di web hanya Terang dan Gelap.
  ///
  /// "Ikuti HP" masuk akal di ponsel, tempat orang sudah menentukan
  /// pilihannya sekali di tingkat sistem dan sering menjadwalkannya
  /// berganti sendiri saat malam. Di peramban yang dibuka di antara
  /// jendela kerja lain, yang diikuti bukan lagi keputusan yang pernah
  /// diambil orangnya — dan konsol yang berganti warna sendiri di
  /// tengah jam kerja lebih mengganggu daripada membantu.
  static List<(ThemeMode, IconData, String)> get _pilihanDipakai =>
      kIsWeb ? _pilihan.sublist(0, 2) : _pilihan;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<AppPrefsProvider>();
    // Setelan lama bisa saja masih "Ikuti HP" — dibaca sebagai tema yang
    // sedang benar-benar tampil, supaya tidak ada tombol yang menyala.
    final terpilih = kIsWeb && prefs.themeMode == ThemeMode.system
        ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light)
        : prefs.themeMode;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sempit berarti ikonnya saja.
        //
        // Dipaksa muat, tulisannya patah jadi dua baris di tengah
        // tombol — "Ikut / i / HP" — dan yang tersisa bukan lagi
        // pilihan yang bisa dibaca sekilas, melainkan tiga kotak berisi
        // potongan kata. Ikonnya sendiri sudah jelas: matahari, bulan,
        // dan huruf A yang otomatis.
        final sempit = constraints.maxWidth < 300;

        return SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: [
            for (final (mode, ikon, nama) in _pilihanDipakai)
              ButtonSegment(
                value: mode,
                icon: Icon(ikon, size: sempit ? 19 : 17),
                label: sempit ? null : Text(context.tr(nama)),
                // Namanya tidak hilang, cuma pindah ke tekan-tahan —
                // dan tetap terbaca pembaca layar.
                tooltip: context.tr(nama),
              ),
          ],
          selected: {terpilih},
          onSelectionChanged: (v) {
            prefs.setThemeMode(v.first);
            onChanged?.call();
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }
}

/// Blok Bahasa + Tampilan untuk layar Pengaturan.
class LanguageThemeSection extends StatelessWidget {
  final VoidCallback? onThemeChanged;

  const LanguageThemeSection({super.key, this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    // Ditaruh di tengah, bukan rata kiri.
    //
    // Pilihannya cuma satu baris tombol, dan rata kiri menyisakan ruang
    // kosong menganggur di kanan — barisnya terlihat seperti separuh
    // jadi. Judul "Tampilan" di atasnya juga sudah diulang oleh judul
    // bagiannya di layar Pengaturan, jadi dibuang.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (kLanguageSwitcherEnabled) ...[
          Text(context.tr('Bahasa'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          const LanguageToggle(),
          const SizedBox(height: 18),
        ],
        ThemeToggle(onChanged: onThemeChanged),
        const SizedBox(height: 8),
        Text(
          'Berlaku di perangkat ini saja.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
        ),
      ],
    );
  }
}

/// Tombol bilah atas yang membuka pilihan bahasa dan tema.
///
/// Untuk hub yang tidak punya menu Pengaturan sendiri — kasir, dapur,
/// super admin, dan halaman pelanggan. Tanpa ini, satu-satunya cara
/// mereka mengganti bahasa setelah masuk adalah keluar akun dulu, dan
/// itu bukan harga yang pantas untuk mengubah tampilan.
class AppearanceIconButton extends StatelessWidget {
  const AppearanceIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.brightness_6_outlined),
      tooltip: context.tr('Tampilan'),
      onPressed: () => showAppearanceDialog(context),
    );
  }
}

Future<void> showAppearanceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(dialogContext.tr('Tampilan'),
          style: const TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: LanguageThemeSection(
          // Ditutup begitu temanya dipilih: yang menekan tombolnya
          // sedang ingin melihat hasilnya, bukan melihat dialognya.
          onThemeChanged: () => Navigator.pop(dialogContext),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.tr('Tutup')),
        ),
      ],
    ),
  );
}
