import 'faq_screen.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/merchantpos_logo.dart';

/// "Tentang Merchant-POS" — what the app is and what each role can do with
/// it. Reached from the small info icon on the role-choice screen, so
/// someone handed the app for the first time can work out what it's for
/// without having to log in as anything.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = 'Versi ${info.version} (${info.buildNumber})');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Tentang Merchant-POS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                const MerchantPosLogo(size: 72),
                const SizedBox(height: 14),
                const Text(
                  'Merchant-POS',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: MerchantPosTheme.brandDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Order Cepat, Merchant Hebat',
                  style: TextStyle(
                    color: MerchantPosTheme.brand,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (_version.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_version,
                      style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _WebsiteLink(),
          const SizedBox(height: 14),
          _Section(
            title: 'Apa itu Merchant-POS?',
            child: Text(
              'Merchant-POS adalah aplikasi kasir sekaligus pemesanan mandiri untuk '
              'restoran, kafe, dan warung. Satu aplikasi dipakai bersama oleh '
              'pemilik, karyawan, dan pelanggan — masing-masing masuk dengan '
              'akun sendiri dan langsung diarahkan ke tampilan sesuai perannya.\n\n'
              'Pelanggan bisa memesan sendiri dari mejanya dengan scan QR, '
              'kasir tetap bisa melayani pesanan langsung, dapur melihat semua '
              'pesanan masuk secara real-time, dan bagian keuangan mendapat '
              'catatan yang rapi dari setiap transaksi tanpa input ulang.',
              style: TextStyle(fontSize: 13.5, height: 1.55, color: MerchantPosTheme.mutedOf(context)),
            ),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Untuk Pelanggan',
            child: _Features([
              (Icons.qr_code_scanner, 'Scan QR di meja', 'Langsung lihat menu merchant tanpa install apa pun'),
              (Icons.storefront_outlined, 'Pilih merchant', 'Pesan dari daftar merchant walau tidak sedang di tempat'),
              (Icons.restaurant_menu, 'Dine In / Take Away', 'Pilih makan di tempat atau dibungkus saat checkout'),
              (Icons.tune, 'Level & catatan', 'Atur tingkat pedas, ukuran, atau catatan khusus per item'),
              (Icons.timelapse, 'Lacak pesanan', 'Pantau pesanan dari dimasak sampai siap diambil'),
              (Icons.receipt_long_outlined, 'Struk digital', 'Simpan struk ke galeri atau kirim ke email'),
              (Icons.history, 'Riwayat pesanan', 'Tetap tersimpan walau memesan tanpa login'),
              (Icons.confirmation_number_outlined, 'Voucher Merchant-POS', 'Tebus kode voucher dan pakai di merchant mana pun yang berlaku'),
              (Icons.pin_outlined, 'Nomor pesanan', 'Nomor antrean harian, muncul sejak pesanan dibuat'),
              (Icons.near_me_outlined, 'Merchant terdekat', 'Daftar tempat dalam radius 5 km berikut fasilitasnya'),
            ]),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Untuk Merchant',
            child: _Features([
              (Icons.point_of_sale_outlined, 'Kasir', 'Input pesanan, hitung total, terima Tunai/QRIS/Transfer'),
              (Icons.inventory_2_outlined, 'Kelola produk', 'Foto, harga, stok, kategori, dan varian produk'),
              (Icons.soup_kitchen_outlined, 'Layar dapur', 'Pesanan masuk real-time, dari Baru sampai Selesai'),
              (Icons.qr_code_2_outlined, 'Generator QR meja', 'Buat dan cetak QR untuk tiap nomor meja'),
              (Icons.list_alt_outlined, 'Pesanan masuk', 'Rekap harian, dikelompokkan Dine In dan Take Away'),
              (Icons.storefront_outlined, 'Multi merchant', 'Satu akun pusat mengelola banyak cabang'),
              (Icons.tv_outlined, 'Layar pelanggan', 'Perangkat kedua menghadap pelanggan, QR dan totalnya tampil di sana'),
              (Icons.search, 'Cari menu', 'Temukan satu item tanpa menggulir seluruh kategori'),
              (Icons.local_offer_outlined, 'Diskon & bundling', 'Potongan per menu, minimal qty, sampai paket beli-2'),
              (Icons.add_circle_outline, 'Topping & level', 'Tambahan berbayar dan varian, masing-masing dengan harganya'),
              (Icons.photo_size_select_actual_outlined, 'Banner promo', 'Tampil di halaman menu pelanggan, lengkap dengan masa berlakunya'),
              (Icons.chair_outlined, 'Fasilitas tempat', 'AC, Smoking Area, Live Music — tampil saat pelanggan memilih'),
            ]),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Untuk Keuangan',
            child: _Features([
              (Icons.trending_up, 'Pemasukan', 'Rekap harian dengan rincian per metode pembayaran'),
              (Icons.account_balance_wallet_outlined, 'Saldo & Petty Cash', 'Pantau saldo penghasilan dan kas kecil'),
              (Icons.trending_down, 'Pengeluaran', 'Catat biaya lengkap dengan foto bukti nota'),
              (Icons.numbers, 'Mapping GL Account', 'Hubungkan tiap transaksi ke nomor akun akuntansi'),
              (Icons.menu_book_outlined, 'Jurnal GL', 'Catatan otomatis setiap pergerakan uang, bisa diekspor'),
              (Icons.picture_as_pdf_outlined, 'Laporan PDF', 'Laporan transaksi siap cetak seperti rekening koran'),
              (Icons.savings_outlined, 'Setoran modal', 'Uang masuk dari luar penjualan, tercatat di akunnya sendiri'),
              (Icons.receipt_long_outlined, 'Tagihan langganan', 'Bayar lewat Virtual Account, invoice PDF-nya bisa diunduh'),
              (Icons.sync_alt, 'Pencairan gateway', 'Catat dana QRIS yang masuk rekening berikut potongannya'),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => bukaWhatsAppMerchantPOS(context),
              icon: const Icon(Icons.chat, size: 18, color: Color(0xFF25D366)),
              label: const Text('Chat Merchant-POS Admin di WhatsApp'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Color(0xFF25D366)),
                foregroundColor: const Color(0xFF25D366),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => bukaEmailMerchantPOS(context),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text(kEmailMerchantPOS),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Butuh bantuan? Hubungi Merchant-POS Admin lewat WhatsApp atau '
              'surel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
            ),
          ),
          // Ruang untuk tombol mengambang di bawah — tanpa ini baris
          // terakhirnya selalu tertutup.
          const SizedBox(height: 72),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FaqScreen()),
        ),
        icon: const Icon(Icons.help_outline),
        label: const Text('FAQ'),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: MerchantPosTheme.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Tautan ke situs Merchant-POS.
///
/// Ditaruh di layar ini karena inilah satu-satunya halaman yang bisa
/// dibuka sebelum login — yang membukanya sering justru orang yang
/// belum punya akun dan sedang menimbang, dan yang dia butuhkan
/// berikutnya ada di situsnya: cara berlangganan, dan berkas
/// pemasangnya.
class _WebsiteLink extends StatelessWidget {
  static const _url = 'https://bujejuki-spec.github.io/Merchant-POS-LandingPage/';

  const _WebsiteLink();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MerchantPosTheme.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => launchUrl(
          Uri.parse(_url),
          // Di browser, bukan di dalam aplikasi: halamannya memuat
          // tautan unduhan APK, dan tampilan web di dalam aplikasi
          // menangani unduhan berkas dengan cara yang berbeda-beda di
          // tiap HP — sebagian diam saja.
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: MerchantPosTheme.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.language, size: 18, color: MerchantPosTheme.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Situs Merchant-POS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      'bujejuki-spec.github.io/Merchant-POS-LandingPage',
                      style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new, size: 17, color: MerchantPosTheme.mutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Features extends StatelessWidget {
  final List<(IconData, String, String)> items;

  const _Features(this.items);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (icon, title, desc) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: MerchantPosTheme.brand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: MerchantPosTheme.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(desc,
                          style: TextStyle(
                              fontSize: 12, height: 1.35, color: MerchantPosTheme.mutedOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
