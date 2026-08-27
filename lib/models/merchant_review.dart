import 'dart:convert';

/// Penilaian seorang pelanggan atas sebuah merchant.
class MerchantReview {
  final String id;
  final String restoId;
  final String customerEmail;

  /// Disalin saat menilai, tidak dibaca ulang dari profilnya.
  ///
  /// Profil bisa berganti nama besok; ulasan yang tiba-tiba berganti
  /// penulis adalah ulasan yang tidak bisa dipercaya.
  final String customerName;

  final int rating;
  final String? comment;
  final List<String> photos;
  final DateTime createdAt;

  const MerchantReview({
    required this.id,
    required this.restoId,
    required this.customerEmail,
    required this.customerName,
    required this.rating,
    this.comment,
    this.photos = const [],
    required this.createdAt,
  });

  bool get punyaKomentar => comment != null && comment!.trim().isNotEmpty;
  bool get punyaFoto => photos.isNotEmpty;

  static List<String> _photos(Object? raw) {
    if (raw is List) {
      return [
        for (final p in raw)
          if (p.toString().trim().isNotEmpty) p.toString(),
      ];
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) return _photos(d);
      } catch (_) {
        // Baris yang isinya bukan JSON tidak boleh menjatuhkan seluruh
        // daftar ulasannya.
      }
    }
    return const [];
  }

  factory MerchantReview.fromMap(Map<String, dynamic> map) => MerchantReview(
        id: map['id'].toString(),
        restoId: map['resto_id'] as String,
        customerEmail: map['customer_email'] as String? ?? '',
        customerName: map['customer_name'] as String? ?? 'Pelanggan',
        rating: (map['rating'] as num?)?.toInt() ?? 0,
        comment: map['comment'] as String?,
        photos: _photos(map['photos']),
        createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
      );
}

/// Ringkasan bintang sebuah merchant.
class RatingRingkas {
  final double rata;
  final int jumlah;

  const RatingRingkas({this.rata = 0, this.jumlah = 0});

  bool get adaPenilaian => jumlah > 0;

  /// "4,5" — koma, bukan titik.
  String get teks => rata.toStringAsFixed(1).replaceAll('.', ',');
}
