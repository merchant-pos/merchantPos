import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_prefs_provider.dart';

/// Kamus dua bahasa aplikasi.
///
/// Kunci-nya adalah kalimat bahasa Indonesianya sendiri, bukan kode
/// seperti `login.title`. Dua alasan, dan keduanya soal berapa lama
/// terjemahannya bertahan benar:
///
/// 1. Layar yang belum diterjemahkan tetap tampil utuh dalam bahasa
///    Indonesia. Kalau kuncinya kode, layar yang terlewat menampilkan
///    `login.title` mentah-mentah ke pemakainya — kerusakan yang jauh
///    lebih buruk daripada satu kalimat yang belum berbahasa Inggris.
///    Dengan 49 layar, penerjemahan memang bertahap, dan bentuk
///    setengah jadinya harus tetap layak dipakai.
///
/// 2. Kalimat yang diubah di layar tanpa ikut mengubah kamusnya akan
///    jatuh kembali ke bahasa Indonesia — bukan menampilkan terjemahan
///    lama yang sudah tidak cocok dengan yang di sebelahnya.
///
/// Yang tidak diterjemahkan dan tidak akan pernah: nama merek, nama
/// resto, nama menu yang diketik restonya, dan istilah yang di
/// Indonesia memang dipakai apa adanya (QRIS, Dine In, Take Away).
const Map<String, String> _en = {
  // ── Halaman awal & peran ──
  'Masuk sebagai': 'Sign in as',
  'Pelanggan': 'Customer',
  'Merchant-POS': 'Merchant-POS',
  'Pesan sendiri dari meja atau dari rumah': 'Order from your table or from home',
  'Kasir, dapur, admin, dan keuangan': 'Cashier, kitchen, admin, and finance',
  'Tentang Merchant-POS': 'About Merchant-POS',
  'Bahasa': 'Language',
  'Tema': 'Theme',
  'Terang': 'Light',
  'Gelap': 'Dark',
  'Ikuti HP': 'Follow device',
  'Tampilan': 'Appearance',

  // ── Umum ──
  'Batal': 'Cancel',
  'Batalkan': 'Cancel',
  'Simpan': 'Save',
  'Hapus': 'Delete',
  'Tutup': 'Close',
  'Edit': 'Edit',
  'Tambah': 'Add',
  'Coba Lagi': 'Try Again',
  'Selesai': 'Done',
  'Detail': 'Details',
  'Keluar': 'Sign Out',
  'Pengaturan': 'Settings',
  'Wajib diisi': 'Required',
  'Harus angka': 'Must be a number',
  'Kembali ke Keranjang': 'Back to Cart',

  // ── Menu utama ──
  'Kasir': 'Cashier',
  'Riwayat Kasir': 'Cashier History',
  'Kelola Produk': 'Manage Products',
  'Pesanan Masuk': 'Incoming Orders',
  'Pending Payment': 'Pending Payment',
  'Kotak Masuk': 'Inbox',
  'Saldo & Pengeluaran': 'Balance & Expenses',
  'Setor Saldo Cash': 'Deposit Cash',
  'Info Merchant': 'Restaurant Info',
  'Kelola Karyawan': 'Manage Staff',
  'QR Meja': 'Table QR',
  'Produk': 'Products',
  'Kategori': 'Categories',
  'Level': 'Levels',

  // ── Keranjang & pembayaran ──
  'Keranjang': 'Cart',
  'Keranjang kosong.': 'Your cart is empty.',
  'Nomor Meja': 'Table Number',
  'Nama Customer': 'Customer Name',
  'Nama Customer (opsional)': 'Customer Name (optional)',
  'Tunai': 'Cash',
  'Transfer': 'Transfer',
  'Bayar dengan QRIS': 'Pay with QRIS',
  'Menunggu pembayaran…': 'Waiting for payment…',
  'Ada menu yang sudah habis': 'Some items are sold out',
  'Makan di tempat': 'Dine In',
  'Dibungkus (Take Away)': 'Take Away',
  'Stok (opsional)': 'Stock (optional)',
  'Tandai Habis (Out of Stock)': 'Mark as Out of Stock',
  'HABIS': 'SOLD OUT',
  'Cara Makan yang Dilayani': 'Service Types Offered',

  // ── Unduhan & pengumuman ──
  'Unduh Pembaruan': 'Download Update',
  'Unduh Versi Terbaru': 'Download Latest Version',
  'Unduhan dibatalkan': 'Download cancelled',
  'Unduhan gagal karena masalah koneksi.': 'Download failed — connection problem.',
  'Unduhan gagal. Coba lagi sebentar lagi.': 'Download failed. Please try again shortly.',
  'Pengumuman': 'Announcement',
  'Update Aplikasi': 'App Update',
  'General': 'General',
};

/// Terjemahan [id] ke bahasa yang sedang dipakai.
///
/// Yang belum ada di kamus dikembalikan apa adanya — dalam bahasa
/// Indonesia. Itu keadaan yang sengaja dipilih, bukan kegagalan yang
/// diam-diam: lihat catatan di atas.
String trOf(BuildContext context, String id) {
  final english = context.watch<AppPrefsProvider>().isEnglish;
  if (!english) return id;
  return _en[id] ?? id;
}

/// Versi yang tidak ikut membangun ulang saat bahasanya berubah —
/// untuk dipakai di dalam callback, dialog, dan pesan toast.
String trIn(BuildContext context, String id) {
  final english = context.read<AppPrefsProvider>().isEnglish;
  if (!english) return id;
  return _en[id] ?? id;
}

extension AppTranslate on BuildContext {
  /// `context.tr('Simpan')`
  String tr(String id) => trOf(this, id);
}

/// Berapa banyak yang sudah punya padanan bahasa Inggris. Dipakai tes,
/// supaya kamus yang menyusut tidak lolos tanpa ketahuan.
int get translatedCount => _en.length;

/// Terjemahan tanpa BuildContext — untuk tes.
@visibleForTesting
String translateForTest(String id, {required bool english}) =>
    english ? (_en[id] ?? id) : id;
