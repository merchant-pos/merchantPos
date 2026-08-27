import 'dart:convert';

import 'opening_hours.dart';
import 'order_type.dart';

/// Hardcoded restaurant category options, roughly matching the
/// taxonomy used by GoFood/GrabFood/ShopeeFood-style apps in Indonesia.
const kRestaurantCategories = [
  'Makanan Berat',
  'Cepat Saji',
  'Kopi & Kafe',
  'Teh & Minuman',
  'Dessert & Kue',
  'Bakery & Roti',
  'Snack & Cemilan',
  'Seafood',
  'Ayam & Bebek',
  'Mie & Bakmi',
  'Sate & Bakar-bakaran',
  'Bubur & Soto',
  'Masakan Padang',
  'Masakan Sunda',
  'Masakan Jawa',
  'Chinese Food',
  'Japanese Food',
  'Korean Food',
  'Western Food',
  'Vegetarian & Vegan',
  'Warung/Kaki Lima',
  'Restoran Keluarga',
  'Fine Dining',
];

class Restaurant {
  final String id;
  final String name;
  final String address;
  final String? category;
  final bool active;

  /// Dihapus dari daftar, tapi datanya tetap ada.
  ///
  /// Penghapusan sungguhan akan membawa serta seluruh isi restonya —
  /// hampir semua tabel menggantung padanya dengan `on delete cascade`,
  /// termasuk jurnal GL. Itu bukan yang dimaksud orang saat menghapus
  /// resto dari daftar.
  final bool isDeleted;
  final DateTime? deletedAt;

  /// Contact number printed on the receipt. Optional.
  final String? phone;

  /// Tax and service rates as percentages — 11 means 11%. Menu prices
  /// are shown tax-inclusive, so these are what the receipt unwinds the
  /// displayed price with. Zero means the charge doesn't apply.
  /// Titik lokasi resto, dipakai customer untuk membukanya di peta.
  /// Null berarti belum diatur — tombol petanya tidak ditampilkan.
  final double? latitude;
  final double? longitude;

  final double ppnPercent;
  final double servicePercent;

  /// Cara makan yang dilayani resto ini.
  ///
  /// Tidak semua resto melayani keduanya: gerai di food court dan
  /// cloud kitchen tidak punya meja sama sekali, sementara beberapa
  /// restoran memang tidak membungkus. Selama pilihannya selalu
  /// ditawarkan, pesanan yang tidak bisa dilayani tetap masuk — dan
  /// yang menolaknya jadi orang, di depan pelanggan yang sudah
  /// membayar.
  ///
  /// Keduanya bernilai true untuk resto yang sudah ada. Menonaktifkan
  /// salah satunya adalah keputusan yang harus diambil sengaja, bukan
  /// akibat kolom baru yang belum diisi.
  final bool dineInEnabled;
  final bool takeAwayEnabled;

  /// Fasilitas yang tersedia di tempat ini — AC, Smoking Area, Live
  /// Music, dan seterusnya.
  ///
  /// Daftar bebas, bukan pilihan tetap: tiap tempat punya hal yang
  /// belum terpikirkan siapa pun saat daftarnya dibuat, dan daftar yang
  /// menghambat pemiliknya menggambarkan tempatnya sendiri lebih buruk
  /// daripada daftar yang sesekali salah ketik.
  final List<String> facilities;

  /// Jam buka per hari. Kosong berarti belum diisi — bukan berarti
  /// tutup selamanya, jadi layarnya tidak boleh menyimpulkan apa pun
  /// dari daftar yang kosong.
  final OpeningHours openingHours;

  /// Optional store logo, base64-encoded. Shared between Super Admin and
  /// Admin — whoever uploads it, either can replace or clear it.
  final String? logoBase64;

  Restaurant({
    required this.id,
    this.facilities = const [],
    this.openingHours = OpeningHours.kosong,
    required this.name,
    required this.address,
    this.category,
    this.active = true,
    this.isDeleted = false,
    this.deletedAt,
    this.logoBase64,
    this.phone,
    this.latitude,
    this.longitude,
    this.ppnPercent = 0,
    this.servicePercent = 0,
    this.dineInEnabled = true,
    this.takeAwayEnabled = true,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        if (category != null) 'category': category,
        'active': active,
        // Always sent, even when null — an omitted key leaves the old
        // logo in place, making removal impossible.
        'logo_base64': logoBase64,
        // Always sent so clearing it actually clears it.
        'phone': phone,
        // Selalu dikirim supaya menghapus titik lokasi benar-benar
        // menghapusnya — kunci yang dilewatkan pada upsert akan
        // mempertahankan nilai lama.
        'latitude': latitude,
        'longitude': longitude,
        'ppn_percent': ppnPercent,
        'service_percent': servicePercent,
        'dine_in_enabled': dineInEnabled,
        'take_away_enabled': takeAwayEnabled,
        'facilities': facilities,
        'opening_hours': openingHours.toJson(),
      };

  static List<String> _facilities(Object? raw) {
    if (raw is List) {
      return [
        for (final f in raw)
          if (f.toString().trim().isNotEmpty) f.toString().trim(),
      ];
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) return _facilities(d);
      } catch (_) {
        // Kolom lama yang isinya bukan JSON tidak boleh menjatuhkan
        // seluruh baris restonya.
      }
    }
    return const [];
  }

  factory Restaurant.fromMap(String id, Map<String, dynamic> map) {
    return Restaurant(
      id: id,
      name: map['name'] as String? ?? 'Merchant',
      // Dua bentuk dibaca: List dari Postgres, dan teks JSON dari
      // sqflite. Kolom yang sama sampai dalam bentuk berbeda tergantung
      // dari mana barisnya datang.
      facilities: _facilities(map['facilities']),
      openingHours: OpeningHours.fromRaw(map['opening_hours']),
      address: map['address'] as String? ?? '',
      category: map['category'] as String?,
      active: map['active'] as bool? ?? true,
      isDeleted: map['is_deleted'] as bool? ?? false,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'].toString()).toLocal(),
      logoBase64: map['logo_base64'] as String?,
      phone: map['phone'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      ppnPercent: (map['ppn_percent'] as num?)?.toDouble() ?? 0,
      servicePercent: (map['service_percent'] as num?)?.toDouble() ?? 0,
      dineInEnabled: map['dine_in_enabled'] as bool? ?? true,
      takeAwayEnabled: map['take_away_enabled'] as bool? ?? true,
    );
  }

  bool get hasLocation => latitude != null && longitude != null;

  /// Cara makan yang boleh dipilih saat checkout.
  ///
  /// Tidak pernah kosong. Resto yang keduanya dimatikan — entah salah
  /// pencet atau data yang belum lengkap — akan membuat layar checkout
  /// tanpa satu pun pilihan yang bisa ditekan, dan tidak ada pesanan
  /// yang bisa dibuat sama sekali. Dine In yang dipaksakan jauh lebih
  /// ringan akibatnya daripada resto yang berhenti berjualan.
  List<OrderType> get orderTypes {
    return [
      if (dineInEnabled || !takeAwayEnabled) OrderType.dineIn,
      if (takeAwayEnabled) OrderType.takeAway,
    ];
  }
}
