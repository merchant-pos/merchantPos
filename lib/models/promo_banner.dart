import '../utils/promo_period.dart';

/// Banner promo yang dipasang resto di halaman menunya.
class PromoBanner {
  final String id;
  final String restoId;

  /// Gambar banner sebagai base64 — pendekatan yang sama dengan logo
  /// resto dan foto produk.
  final String imageBase64;

  final String? title;
  final String? description;

  /// Nonaktif berarti tersimpan tapi tidak ditampilkan ke customer.
  /// Promo musiman biasanya dipakai lagi, jadi menghapusnya berarti
  /// mengunggah ulang gambar yang sama.
  final bool active;

  final int sortOrder;

  /// Masa berlaku. Sebelumnya banner hanya punya saklar aktif/nonaktif,
  /// dan itu berarti ada orang yang harus ingat mematikannya. Promo
  /// Ramadan yang masih terpasang di bulan Juli bukan sekadar salah — ia
  /// menjanjikan harga yang sudah tidak berlaku kepada orang yang sedang
  /// memesan.
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String? createdBy;
  final DateTime createdAt;

  PromoBanner({
    required this.id,
    required this.restoId,
    required this.imageBase64,
    this.title,
    this.description,
    this.active = true,
    this.sortOrder = 0,
    this.startsOn,
    this.endsOn,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'image_base64': imageBase64,
        'title': title,
        'description': description,
        'active': active,
        'sort_order': sortOrder,
        'starts_on': startsOn?.toIso8601String().split('T').first,
        'ends_on': endsOn?.toIso8601String().split('T').first,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory PromoBanner.fromMap(Map<String, dynamic> map) {
    return PromoBanner(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      imageBase64: map['image_base64'] as String,
      title: map['title'] as String?,
      description: map['description'] as String?,
      active: map['active'] != false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      startsOn: map['starts_on'] == null
          ? null
          : DateTime.parse(map['starts_on'].toString()),
      endsOn: map['ends_on'] == null
          ? null
          : DateTime.parse(map['ends_on'].toString()),
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }

  PromoPeriod get period => PromoPeriod(startsOn: startsOn, endsOn: endsOn);

  /// Layak ditampilkan ke pelanggan sekarang.
  bool isLive([DateTime? now]) => active && period.isLive(now);
}
