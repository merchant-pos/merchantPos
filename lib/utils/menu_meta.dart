import '../db/discount_repository.dart';
import '../db/product_review_repository.dart';
import '../models/discount.dart';
import '../models/product_review.dart';

/// Dua hal yang menempel pada menu tapi tidak tersimpan di menunya:
/// promo yang sedang berlaku, dan bintang berikut angka terjualnya.
///
/// Dikumpulkan di satu tempat karena dua layar yang berbeda — kasir dan
/// HP pelanggan — menampilkan kartu menu yang sama persis. Menyalin cara
/// memuatnya ke keduanya berarti dua tempat yang harus selalu sepakat,
/// dan yang satu akan tertinggal saat yang lain diperbaiki.
class MenuMeta {
  /// Promo yang sedang berlaku, dikelompokkan per menu yang dikenainya.
  ///
  /// Bukan sekadar daftar id yang kena promo. Labelnya memang cuma
  /// butuh tahu "kena atau tidak", tapi yang mengetuk menunya berhak
  /// tahu promonya apa — dan menyimpan hanya id berarti harus memanggil
  /// server lagi justru pada saat orangnya sedang menunggu.
  final Map<String, List<Discount>> diskon;

  final Map<String, ProductStats> stats;

  const MenuMeta({this.diskon = const {}, this.stats = const {}});

  static const kosong = MenuMeta();

  Set<String> get diskonProductIds => diskon.keys.toSet();

  List<Discount> diskonUntuk(String productId) => diskon[productId] ?? const [];
}

/// Memuat keduanya. Gagal berarti kosong, bukan galat yang dilempar ke
/// layar: label dan bintang adalah tambahan, dan menu yang menolak
/// tampil karena angka terjualnya tidak bisa dihitung jauh lebih buruk
/// daripada menu tanpa angka.
Future<MenuMeta> muatMenuMeta(String restoId) async {
  final hasil = await Future.wait([
    _diskon(restoId),
    _stats(restoId),
  ]);
  return MenuMeta(
    diskon: hasil[0] as Map<String, List<Discount>>,
    stats: hasil[1] as Map<String, ProductStats>,
  );
}

Future<Map<String, List<Discount>>> _diskon(String restoId) async {
  try {
    final live = await DiscountRepository().liveForResto(restoId);
    final map = <String, List<Discount>>{};
    for (final d in live) {
      if (d.basis != DiscountBasis.products) continue;
      // Satu promo bisa mengenai beberapa menu sekaligus — itulah cara
      // bundling dinyatakan — jadi promo yang sama sengaja muncul di
      // beberapa kunci.
      for (final i in d.items) {
        map.putIfAbsent(i.productId, () => []).add(d);
      }
    }
    return map;
  } catch (_) {
    return const {};
  }
}

Future<Map<String, ProductStats>> _stats(String restoId) async {
  try {
    return await ProductReviewRepository().statistik(restoId);
  } catch (_) {
    return const {};
  }
}
