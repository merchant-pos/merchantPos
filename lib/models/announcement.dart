/// Jenis pengumuman.
///
/// Dipisah karena yang dicari orang berbeda: pemberitahuan versi dibuka
/// sekali lalu ditindaklanjuti, sedangkan pengumuman umum dibaca
/// sekilas. Dicampur dalam satu daftar, kabar versi baru tenggelam di
/// antara promo — dan justru itu satu-satunya pesan yang menuntut
/// tindakan.
enum AnnouncementCategory { update, general }

const kAnnouncementCategoryLabels = {
  AnnouncementCategory.update: 'Update Aplikasi',
  AnnouncementCategory.general: 'General',
};

extension AnnouncementCategoryDb on AnnouncementCategory {
  String get dbValue => name;

  static AnnouncementCategory fromDb(String? value) =>
      value == 'general' ? AnnouncementCategory.general : AnnouncementCategory.update;
}

/// Pengumuman dari Merchant-POS — pemberitahuan versi baru, atau kabar umum
/// dari resto sendiri.
///
/// Disimpan sekali, bukan disalin ke tiap penerima. Menyalin berarti
/// orang yang mendaftar besok tidak akan pernah melihat pengumuman hari
/// ini, dan setiap blast menambah ribuan baris kembar. Yang disimpan per
/// orang hanyalah keadaannya — sudah dibaca, atau sudah dihapus.
/// Siapa yang dituju sebuah pengumuman resto.
///
/// Promo dan pengumuman internal punya pembaca yang berbeda, dan
/// sebelumnya keduanya terpaksa memakai jalur yang sama. Jadwal shift
/// yang ikut terkirim ke pelanggan bukan cuma tidak berguna — sebagian
/// memang tidak pantas dibaca mereka.
enum AnnouncementAudience { employees, customers, all }

const _audienceDb = {
  AnnouncementAudience.employees: 'employees',
  AnnouncementAudience.customers: 'customers',
  AnnouncementAudience.all: 'all',
};

const kAnnouncementAudienceLabels = {
  AnnouncementAudience.employees: 'Karyawan',
  AnnouncementAudience.customers: 'Customer',
  AnnouncementAudience.all: 'Semua',
};

const kAnnouncementAudienceHints = {
  AnnouncementAudience.employees: 'Hanya karyawan merchant ini',
  AnnouncementAudience.customers: 'Hanya pelanggan merchant ini',
  AnnouncementAudience.all: 'Karyawan dan pelanggan',
};

extension AnnouncementAudienceDb on AnnouncementAudience {
  String get dbValue => _audienceDb[this]!;
}

class Announcement {
  final String id;
  final String title;
  final String body;

  /// Versi aplikasi yang diumumkan, mis. "1.32.0". Dipakai layar tamu
  /// untuk tahu apakah aplikasi yang terpasang sudah tertinggal, tanpa
  /// perlu punya akun.
  final String? version;

  final String? downloadUrl;

  final AnnouncementCategory category;

  /// Null berarti untuk semua resto — pengumuman dari Super Admin.
  /// Terisi berarti hanya untuk resto itu.
  final String? restoId;

  /// Gambar promo sebagai base64. Hanya dipakai pengumuman umum.
  final String? imageBase64;

  final DateTime createdAt;

  /// Keadaan pembacanya, hasil gabungan dengan tabel inbox_states.
  final bool read;

  /// Siapa yang dituju. Pengumuman lama — dan seluruh kabar dari Super
  /// Admin — berlaku untuk semuanya.
  final AnnouncementAudience audience;

  /// Nama resto pengirimnya, diisi saat dibaca untuk kotak masuk
  /// pelanggan.
  ///
  /// Pelanggan memesan di banyak resto, dan promo tanpa nama pengirim
  /// adalah promo yang tidak bisa dipakai: dia tidak tahu harus datang
  /// ke mana. Karyawan tidak membutuhkannya — kotak masuknya hanya
  /// berisi kabar restonya sendiri.
  final String? restoName;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.version,
    this.downloadUrl,
    this.category = AnnouncementCategory.update,
    this.restoId,
    this.imageBase64,
    required this.createdAt,
    this.read = false,
    this.restoName,
    this.audience = AnnouncementAudience.all,
  });

  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;

  /// Pengumuman ini pantas muncul di kotak masuk orang yang restonya
  /// [restoId].
  ///
  /// Yang tanpa resto berlaku untuk semua — itulah pengumuman dari Super
  /// Admin, termasuk seluruh pemberitahuan versi. Yang punya resto hanya
  /// untuk resto itu: promo cabang Dago tidak ada urusannya dengan
  /// karyawan cabang sebelah, dan kotak masuk yang penuh kabar orang
  /// lain akan berhenti dibaca.
  bool visibleTo(String? restoId) => this.restoId == null || this.restoId == restoId;

  /// Pantas muncul di kotak masuk pelanggan yang pernah memesan di
  /// [restoIds].
  ///
  /// Berbeda dari [visibleTo] yang memakai satu resto: pelanggan tidak
  /// punya "resto sendiri". Yang dia punya adalah daftar resto yang
  /// pernah dia datangi, dan resto yang sedang dia buka sekarang.
  bool visibleToCustomer(Set<String> restoIds) =>
      audience != AnnouncementAudience.employees &&
      (restoId == null || restoIds.contains(restoId));

  /// Pantas muncul di kotak masuk karyawan resto [restoId].
  bool visibleToEmployee(String? restoId) =>
      audience != AnnouncementAudience.customers && visibleTo(restoId);

  Announcement copyWith({bool? read, String? restoName}) => Announcement(
        id: id,
        title: title,
        body: body,
        version: version,
        downloadUrl: downloadUrl,
        category: category,
        restoId: restoId,
        imageBase64: imageBase64,
        createdAt: createdAt,
        read: read ?? this.read,
        restoName: restoName ?? this.restoName,
        audience: audience,
      );

  factory Announcement.fromMap(Map<String, dynamic> map, {bool read = false}) {
    return Announcement(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Pengumuman',
      body: map['body'] as String? ?? '',
      version: map['version'] as String?,
      downloadUrl: map['download_url'] as String?,
      category: AnnouncementCategoryDb.fromDb(map['category'] as String?),
      restoId: map['resto_id'] as String?,
      imageBase64: map['image_base64'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      read: read,
      audience: _audienceDb.entries
          .firstWhere((e) => e.value == map['audience'],
              orElse: () => const MapEntry(
                  AnnouncementAudience.all, 'all'))
          .key,
    );
  }
}

/// Membandingkan dua versi bergaya "1.32.0".
///
/// Perbandingan teks biasa salah di tempat yang justru sering terjadi:
/// "1.9.0" lebih besar dari "1.10.0" kalau diadu sebagai string, padahal
/// 1.10.0 yang lebih baru.
///
/// Nomor build setelah "+" diabaikan. `pubspec.yaml` menulis versi
/// sebagai "1.32.0+68", dan menghitung 68 sebagai bagian keempat akan
/// membuat "1.32.0+68" terlihat lebih baru daripada "1.32.0" — dua
/// penulisan untuk rilis yang sama persis.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('+')
      .first
      .split(RegExp(r'[^0-9]+'))
      .where((p) => p.isNotEmpty)
      .map(int.parse)
      .toList();

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
