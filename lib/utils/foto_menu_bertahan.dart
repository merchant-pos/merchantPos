import '../models/product.dart';

/// Menjaga foto menu tidak lenyap gara-gara satu pembaruan stok.
///
/// Daftar menu pelanggan mendengarkan perubahan baris `products` secara
/// realtime. Begitu ada pesanan masuk, stok menu yang dipesan dikurangi,
/// dan barisnya terkirim ulang lewat jalur itu — tapi baris yang datang
/// lewat realtime tidak selalu membawa `photo_base64` yang utuh. Yang
/// terlihat pemesan: foto menu yang barusan dia pesan mendadak hilang,
/// berganti gambar sendok garpu, sementara menu yang tidak dipesan tetap
/// berfoto.
///
/// Yang hilang bukan datanya — baris di basis data tetap utuh. Yang
/// hilang cuma salinan di layar, dan hanya sampai aplikasinya dimuat
/// ulang. Tapi yang melihatnya tidak tahu itu, dan menu tanpa foto
/// adalah menu yang tidak jadi dipesan.
class IngatanFotoMenu {
  final Map<String, String> _foto = {};

  /// Menu yang tadinya berfoto lalu datang tanpa foto.
  ///
  /// Dikembalikan supaya pemanggilnya bisa menanyakan ulang baris itu ke
  /// server. Sengaja tidak langsung memakai foto lama: merchant memang
  /// boleh menghapus foto menunya, dan menolak mengakui penghapusan itu
  /// sama salahnya dengan menghilangkan fotonya sendiri.
  List<String> curiga(List<Product> menu) => [
        for (final p in menu)
          if (p.photoBase64 == null && _foto.containsKey(p.id)) p.id,
      ];

  /// Memasang kembali foto yang diketahui, untuk id yang disebut.
  ///
  /// Dipakai selagi menunggu jawaban server — lebih baik menampilkan
  /// foto yang mungkin sedikit basi daripada kotak kosong yang pasti
  /// salah.
  List<Product> pulihkan(List<Product> menu, Iterable<String> ids) {
    final perlu = ids.toSet();
    return [
      for (final p in menu)
        if (perlu.contains(p.id) && _foto[p.id] != null)
          p.copyWith(photoBase64: _foto[p.id])
        else
          p,
    ];
  }

  /// Mencatat foto yang benar-benar ada, dan melupakan yang sudah
  /// dipastikan tidak ada lagi.
  void catat(List<Product> menu) {
    for (final p in menu) {
      final foto = p.photoBase64;
      if (foto != null && foto.isNotEmpty) {
        _foto[p.id] = foto;
      }
    }
  }

  /// Melupakan foto sebuah menu — dipakai saat server sendiri yang
  /// memastikan fotonya sudah dihapus.
  void lupakan(String productId) => _foto.remove(productId);

  bool punya(String productId) => _foto.containsKey(productId);
}
