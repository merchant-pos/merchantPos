/// Penilaian satu menu oleh satu pelanggan.
class ProductReview {
  final String id;
  final String restoId;
  final String productId;

  /// Pesanan yang dinilai. Null pada baris yang ditulis sebelum
  /// penilaian menempel pada pesanannya.
  final String? orderId;

  final String customerEmail;
  final String customerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  ProductReview({
    required this.id,
    required this.restoId,
    required this.productId,
    this.orderId,
    required this.customerEmail,
    required this.customerName,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory ProductReview.fromMap(Map<String, dynamic> map) => ProductReview(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        productId: map['product_id'].toString(),
        orderId: map['order_id']?.toString(),
        customerEmail: map['customer_email']?.toString() ?? '',
        customerName: map['customer_name']?.toString() ?? 'Pelanggan',
        rating: (map['rating'] as num?)?.toInt() ?? 0,
        comment: map['comment']?.toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Bintang dan angka terjual satu menu.
///
/// Keduanya dalam satu kelas karena selalu ditampilkan bersama, di baris
/// yang sama, dan diambil dari satu panggilan yang sama.
class ProductStats {
  /// Rata-rata bintang. Nol berarti belum ada yang menilai — bukan
  /// berarti nilainya buruk, dan layarnya harus membedakan keduanya.
  final double rata;

  /// Berapa orang yang menilai.
  final int jumlah;

  /// Berapa porsi yang sudah terjual, dari pesanan yang lunas saja.
  final int terjual;

  const ProductStats({this.rata = 0, this.jumlah = 0, this.terjual = 0});

  bool get adaNilai => jumlah > 0;
}
