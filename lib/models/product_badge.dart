import 'package:flutter/material.dart';

/// Label kecil yang menempel pada sebuah menu.
///
/// Tiga di antaranya dinyatakan merchant sendiri lewat Kelola Produk.
/// Yang keempat — [diskon] — tidak pernah disimpan: ia dibaca dari promo
/// yang sedang berlaku. Menyimpannya sebagai label yang dicentang
/// berarti menu yang masih berlabel "DISKON" seminggu setelah promonya
/// habis, dan pelanggan yang merasa ditipu di meja kasir.
enum ProductBadge {
  baru,
  terlaris,
  rekomendasi,
  diskon,
}

/// Label yang boleh dipilih merchant di formulir menu.
///
/// [ProductBadge.diskon] sengaja tidak ada di sini — bukan pilihan,
/// melainkan kenyataan.
const kBadgeBisaDipilih = [
  ProductBadge.baru,
  ProductBadge.terlaris,
  ProductBadge.rekomendasi,
];

/// Nilai yang tersimpan di kolom `badges`. Bahasa Inggris karena ini
/// kunci data, bukan tulisan yang dibaca orang — dan kunci data yang
/// ikut berganti saat tulisannya diperhalus adalah data yang rusak.
const kBadgeKode = {
  ProductBadge.baru: 'new',
  ProductBadge.terlaris: 'best_seller',
  ProductBadge.rekomendasi: 'recommended',
  ProductBadge.diskon: 'discount',
};

const kBadgeLabel = {
  ProductBadge.baru: 'BARU',
  ProductBadge.terlaris: 'TERLARIS',
  ProductBadge.rekomendasi: 'REKOMENDASI',
  ProductBadge.diskon: 'DISKON',
};

/// Tulisan lengkapnya di formulir merchant, tempat singkatan justru
/// membingungkan.
const kBadgeKeterangan = {
  ProductBadge.baru: 'Menu baru',
  ProductBadge.terlaris: 'Paling laku',
  ProductBadge.rekomendasi: 'Rekomendasi merchant',
  ProductBadge.diskon: 'Sedang diskon',
};

const kBadgeWarna = {
  ProductBadge.baru: Color(0xFF16A34A),
  ProductBadge.terlaris: Color(0xFFF59E0B),
  ProductBadge.rekomendasi: Color(0xFF7C3AED),
  ProductBadge.diskon: Color(0xFFDC2626),
};

const kBadgeIkon = {
  ProductBadge.baru: Icons.fiber_new_outlined,
  ProductBadge.terlaris: Icons.local_fire_department_outlined,
  ProductBadge.rekomendasi: Icons.thumb_up_outlined,
  ProductBadge.diskon: Icons.sell_outlined,
};

/// Membaca kode yang tersimpan. Kode yang tidak dikenal diabaikan, bukan
/// dilempar sebagai galat: baris yang ditulis versi aplikasi yang lebih
/// baru tidak boleh membuat versi lama gagal menampilkan menunya sama
/// sekali.
ProductBadge? badgeDariKode(String kode) {
  for (final entry in kBadgeKode.entries) {
    if (entry.value == kode) return entry.key;
  }
  return null;
}

List<ProductBadge> badgeDariKodeList(Iterable<String> kode) => [
      for (final k in kode)
        if (badgeDariKode(k) != null) badgeDariKode(k)!,
    ];
