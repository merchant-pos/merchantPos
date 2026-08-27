/// Ringkasan penjualan satu merchant dalam sebuah rentang tanggal.
class RingkasanPenjualan {
  final int jumlahPesanan;
  final int omzet;
  final int rataTransaksi;
  final int menuTerjual;

  const RingkasanPenjualan({
    this.jumlahPesanan = 0,
    this.omzet = 0,
    this.rataTransaksi = 0,
    this.menuTerjual = 0,
  });

  bool get kosong => jumlahPesanan == 0;

  factory RingkasanPenjualan.fromMap(Map<String, dynamic> map) =>
      RingkasanPenjualan(
        jumlahPesanan: (map['orders_count'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
        rataTransaksi: (map['rata_transaksi'] as num?)?.toInt() ?? 0,
        menuTerjual: (map['menu_terjual'] as num?)?.toInt() ?? 0,
      );
}

/// Satu baris peringkat menu.
class PenjualanMenu {
  final String productId;

  /// Nama saat dipesan, bukan nama sekarang. Menu yang sudah dihapus
  /// tetap punya sejarah penjualan.
  final String nama;

  final int qty;
  final int omzet;

  const PenjualanMenu({
    required this.productId,
    required this.nama,
    required this.qty,
    required this.omzet,
  });

  factory PenjualanMenu.fromMap(Map<String, dynamic> map) => PenjualanMenu(
        productId: map['product_id']?.toString() ?? '',
        nama: map['product_name']?.toString() ?? 'Menu sudah dihapus',
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
      );
}

/// Menu yang tidak terjual sama sekali sepanjang rentangnya.
class MenuTidakLaku {
  final String productId;
  final String nama;
  final String kategori;
  final int harga;

  const MenuTidakLaku({
    required this.productId,
    required this.nama,
    required this.kategori,
    required this.harga,
  });

  factory MenuTidakLaku.fromMap(Map<String, dynamic> map) => MenuTidakLaku(
        productId: map['product_id']?.toString() ?? '',
        nama: map['product_name']?.toString() ?? '',
        kategori: map['category']?.toString() ?? '',
        harga: (map['price'] as num?)?.toInt() ?? 0,
      );
}

/// Satu jam dalam sehari, berikut ramainya.
class JamRamai {
  final int jam;
  final int jumlahPesanan;
  final int omzet;

  const JamRamai({
    required this.jam,
    required this.jumlahPesanan,
    required this.omzet,
  });

  /// "14:00"
  String get label => '${jam.toString().padLeft(2, '0')}:00';

  factory JamRamai.fromMap(Map<String, dynamic> map) => JamRamai(
        jam: (map['jam'] as num?)?.toInt() ?? 0,
        jumlahPesanan: (map['orders_count'] as num?)?.toInt() ?? 0,
        omzet: (map['omzet'] as num?)?.toInt() ?? 0,
      );
}
