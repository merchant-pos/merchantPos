/// Level/varian yang bisa dipilih saat memesan — level pedas, level
/// gula, ukuran, dan seterusnya.
///
/// Dulu daftarnya berhenti di sini: lima kelompok tetap, sama untuk
/// semua resto. Itu cukup untuk warung nasi dan kedai kopi, dan langsung
/// kurang untuk yang berikutnya — tingkat kematangan steak, pilihan
/// topping, jenis susu. Resto yang butuh satu kelompok di luar lima ini
/// tidak punya jalan sama sekali selain menuliskannya di kolom catatan,
/// yang tidak terbaca sebagai pilihan oleh siapa pun.
///
/// Sekarang tiap resto menyusun daftarnya sendiri lewat Kelola Produk →
/// tab Level. Yang tertinggal di sini adalah **bibitnya**: lima
/// kelompok ini disemaikan ke tiap resto sekali lewat migrasi, supaya
/// tidak ada yang mulai dari halaman kosong dan harus mengetik "Tidak
/// Pedas, Sedang, Pedas, Extra Pedas" sebelum bisa menjual apa pun.
const Map<String, List<String>> kLevelGroups = {
  'Level Pedas': ['Tidak Pedas', 'Sedang', 'Pedas', 'Extra Pedas'],
  'Level Gula': ['Normal', 'Kurang Manis', 'Setengah Manis', 'Tanpa Gula'],
  'Level Es': ['Normal', 'Less Ice', 'No Ice'],
  'Suhu': ['Panas', 'Dingin'],
  'Ukuran': ['Regular', 'Large'],
};

/// Satu kelompok level milik sebuah resto.
class LevelGroup {
  final String id;
  final String name;
  final List<String> options;

  const LevelGroup({
    required this.id,
    required this.name,
    required this.options,
  });

  Map<String, dynamic> toMap(String restoId) => {
        'id': id,
        'resto_id': restoId,
        'name': name,
        'options': options,
      };

  factory LevelGroup.fromMap(Map<String, dynamic> map) => LevelGroup(
        id: map['id'] as String,
        name: map['name'] as String,
        options: [
          for (final o in (map['options'] as List<dynamic>? ?? const []))
            o.toString(),
        ],
      );
}

/// Kelompok level yang berlaku saat ini, dipakai bersama oleh layar
/// admin, kasir, dan pelanggan.
///
/// Sebuah registri global, bukan Provider yang harus dicari lewat
/// context. Alasannya satu: pilihan level dibaca di tempat-tempat yang
/// tidak semuanya punya jalur provider yang sama — dialog pemesanan
/// dipakai pelanggan tamu yang bahkan tidak login. Yang dibutuhkan cuma
/// pemetaan nama ke daftar pilihan, dan menyalurkannya lewat empat layar
/// hanya untuk sampai ke satu dropdown tidak membuat apa pun lebih
/// benar.
///
/// Selalu berisi [kLevelGroups] sampai daftar restonya berhasil dimuat.
/// Kalau jaringannya mati, pemesanan tetap jalan dengan lima kelompok
/// bawaan alih-alih dropdown kosong.
class LevelGroupRegistry {
  LevelGroupRegistry._();

  static Map<String, List<String>> _groups = kLevelGroups;

  /// Nama kelompok, urut sesuai yang disusun restonya.
  static Iterable<String> get names => _groups.keys;

  static Map<String, List<String>> get all => _groups;

  /// Pilihan pada sebuah kelompok.
  ///
  /// Kelompok yang tidak dikenali mengembalikan daftar kosong, bukan
  /// melempar galat. Produk bisa saja masih menyandang nama kelompok
  /// yang barusan dihapus restonya, dan itu tidak boleh membuat layar
  /// pemesanan mati total — cukup satu dropdown yang tidak muncul.
  static List<String> optionsOf(String group) =>
      _groups[group] ?? kLevelGroups[group] ?? const [];

  /// Pilihan pertama sebuah kelompok, atau null kalau kelompoknya sudah
  /// tidak ada.
  static String? firstOptionOf(String group) {
    final options = optionsOf(group);
    return options.isEmpty ? null : options.first;
  }

  static void replaceAll(List<LevelGroup> groups) {
    if (groups.isEmpty) return;
    _groups = {for (final g in groups) g.name: g.options};
  }
}
