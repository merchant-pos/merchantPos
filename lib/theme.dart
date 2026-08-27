import 'package:flutter/material.dart';

/// Merchant-POS's shared visual identity — one place that shapes how every
/// screen looks (colors, AppBar, cards, buttons, inputs) so the app
/// reads as a single cohesive product instead of default-Material white.
class MerchantPosTheme {
  MerchantPosTheme._();

  // Hijau, bukan indigo warisan salinan.
  //
  // Nilainya dipilih supaya tulisan putih di atasnya lolos kontras
  // 4.5:1 — tombol utama aplikasi ini selalu berisi teks putih, dan
  // hijau yang lebih terang terlihat lebih segar di layar desainer
  // lalu tidak terbaca di layar kasir yang menghadap jendela.
  static const brand = Color(0xFF047857); // emerald 700
  static const brandDark = Color(0xFF065F46); // emerald 800

  /// Amber tetap. Ia menandai hal yang perlu diperhatikan — dan
  /// aksen yang bertetangga dengan warna mereknya sendiri berhenti
  /// menandai apa pun.
  static const accent = Color(0xFFF59E0B);

  /// Latar terang dengan semburat hijau tipis, bukan putih pucat.
  static const backgroundTint = Color(0xFFF2F7F4);

  // ── Warna gelap ────────────────────────────────────────────────────
  //
  // Bukan hitam pekat. Layar OLED memang paling hemat pada hitam murni,
  // tapi kartu putih-abu di atas hitam murni menghasilkan kontras yang
  // memedihkan di ruangan gelap — dan aplikasi ini justru paling sering
  // dibuka di jam tutup, saat lampu resto sudah setengah dimatikan.
  static const darkBackground = Color(0xFF14151C);
  static const darkSurface = Color(0xFF1E202A);
  static const darkSurfaceHigh = Color(0xFF272A36);
  static const darkBorder = Color(0xFF343846);

  /// Ungu mereknya dinaikkan terangnya untuk latar gelap.
  ///
  /// Warna yang sama persis di atas latar gelap jatuh di bawah ambang
  /// keterbacaan — tulisan ungu tua di atas abu tua nyaris tidak
  /// terbaca. Yang dijaga bukan kode heksanya, tapi jarak kontrasnya.
  static const brandOnDark = Color(0xFF8B85F0);

  /// Warna latar kartu yang benar untuk tema yang sedang dipakai.
  ///
  /// Dipakai layar yang menulis `Colors.white` langsung sebagai latar
  /// kartunya. Di tema gelap putih murni bukan sekadar salah rasa — ia
  /// membuat tulisan hitamnya hilang begitu tema teksnya ikut menjadi
  /// terang.
  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurface
          : Colors.white;

  /// Latar lembut untuk blok di dalam kartu (pengganti Colors.grey.shade100).
  static Color softFillOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurfaceHigh
          : const Color(0xFFF5F5F5);

  /// Garis pemisah dan bingkai tipis.
  static Color borderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBorder
          : const Color(0xFFE0E0E0);

  /// Teks penjelas — yang di tema terang ditulis Colors.grey.shade600.
  static Color mutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9BA1B0)
          : const Color(0xFF757575);

  /// Latar halaman. Menggantikan [backgroundTint] yang dipasang langsung
  /// sebagai `backgroundColor` Scaffold di belasan layar.
  ///
  /// Nilai tetap itu menang atas `scaffoldBackgroundColor` milik tema —
  /// hasilnya di mode gelap adalah halaman berlatar lavender terang
  /// dengan kartu-kartu gelap di atasnya, persis kebalikan dari yang
  /// dimaksud.
  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBackground
          : backgroundTint;

  /// Latar kolom isian yang sedang tidak bisa disunting.
  ///
  /// Abu terang menandakan "terkunci" di tema terang. Di tema gelap ia
  /// jadi balok putih menyilaukan, dan teks terangnya lenyap di
  /// dalamnya.
  static Color disabledFillOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2D39)
          : const Color(0xFFEEEEEE);

  /// Latar lembut berwarna — pengganti Colors.X.shade50/shade100.
  ///
  /// Warna pastel itu dipilih untuk menampung tulisan gelap. Di tema
  /// gelap ia jadi pita terang yang menelan tulisan terangnya sendiri;
  /// yang dibutuhkan justru kebalikannya — warna yang sama, tapi gelap.
  static Color tintOf(BuildContext context, MaterialColor base) =>
      Theme.of(context).brightness == Brightness.dark
          ? Color.alphaBlend(base.withOpacity(0.16), darkSurface)
          : base.shade50;

  /// Warna tulisan di atas [tintOf].
  static Color onTintOf(BuildContext context, MaterialColor base) =>
      Theme.of(context).brightness == Brightness.dark
          ? base.shade200
          : base.shade700;

  /// Latar kotak keterangan berwarna merek, dan warna tulisan di
  /// atasnya.
  ///
  /// [brandDark] dipilih untuk latar pastel di tema terang. Di tema
  /// gelap latarnya jadi nyaris hitam, dan biru tua di atasnya tidak
  /// terbaca sama sekali — kotak keterangan yang justru dipasang
  /// karena isinya penting dibaca.
  static Color brandTintOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Color.alphaBlend(brand.withOpacity(0.16), darkSurface)
          : brand.withOpacity(0.07);

  static Color onBrandTintOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFC7D2FE)
          : brandDark;

  /// Warna teks utama. Menggantikan Colors.black87 yang ditulis
  /// langsung di layar — hitam di atas latar gelap tidak terbaca sama
  /// sekali.
  static Color textOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE7E9EF)
          : Colors.black87;

  /// Ungu merek yang aman dibaca di tema yang sedang dipakai.
  static Color brandOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? brandOnDark : brand;

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: brand,
      secondary: accent,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundTint,
      fontFamily: 'Roboto',

      appBarTheme: const AppBarTheme(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      tabBarTheme: const TabBarTheme(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        labelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),

      cardTheme: CardTheme(
        elevation: 1.5,
        shadowColor: Colors.black.withOpacity(0.08),
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand,
          side: const BorderSide(color: brand, width: 1.4),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: brand.withOpacity(0.08),
        labelStyle: const TextStyle(color: brandDark, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
      ),

      dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: brandDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Tema gelap.
  ///
  /// Disusun ulang, bukan sekadar membalik ThemeData.dark(): bilah atas
  /// tetap memakai ungu mereknya di tema terang, dan mempertahankan itu
  /// di tema gelap menghasilkan balok ungu terang yang menyala sendirian
  /// di layar yang seluruhnya redup. Di sini bilah atasnya ikut gelap,
  /// dan yang menjaga identitasnya adalah tombol serta sorotannya.
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
    ).copyWith(
      primary: brandOnDark,
      secondary: accent,
      surface: darkSurface,
      onSurface: const Color(0xFFE7E9EF),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkBackground,
      fontFamily: 'Roboto',

      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Color(0xFFE7E9EF),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFFE7E9EF),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Color(0xFFE7E9EF)),
      ),

      tabBarTheme: const TabBarTheme(
        labelColor: brandOnDark,
        unselectedLabelColor: Color(0xFF9BA1B0),
        indicatorColor: brandOnDark,
        labelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),

      cardTheme: CardTheme(
        elevation: 0,
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder),
        ),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandOnDark,
          // Teks gelap di atas ungu terang, bukan putih: ungu yang sudah
          // dinaikkan terangnya tidak lagi punya jarak yang cukup dari
          // putih.
          foregroundColor: const Color(0xFF14151C),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandOnDark,
          side: const BorderSide(color: brandOnDark, width: 1.4),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandOnDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brandOnDark, width: 1.6),
        ),
      ),

      dialogTheme: DialogTheme(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),

      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFFE7E9EF),
        iconColor: Color(0xFF9BA1B0),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: brandOnDark.withOpacity(0.16),
        labelStyle: const TextStyle(
            color: brandOnDark, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandOnDark,
        foregroundColor: Color(0xFF14151C),
      ),

      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceHigh,
        contentTextStyle: const TextStyle(color: Color(0xFFE7E9EF)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
