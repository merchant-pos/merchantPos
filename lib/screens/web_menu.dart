import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/support_repository.dart';
import '../models/billing.dart';
import '../providers/auth_provider.dart';
import 'billing_discount_screen.dart';
import 'billing_screen.dart';
import 'cash_deposit_screen.dart';
import 'cashier_shift_screen.dart';
import 'category_management_screen.dart';
import 'discount_screen.dart';
import 'employee_management_screen.dart';
import 'employee_orders_screen.dart';
import 'finance_balance_screen.dart';
import 'finance_gateway_settlement_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_income_screen.dart';
import 'finance_journal_screen.dart';
import 'finance_report_screen.dart';
import 'inbox_screen.dart';
import 'katalog_siap.dart';
import 'level_management_screen.dart';
import 'market_report_screen.dart';
import 'merchant_report_screen.dart';
import 'pending_payment_screen.dart';
import 'product_list_screen.dart';
import 'payment_info_screen.dart';
import 'promo_banner_screen.dart';
import 'publish_announcement_screen.dart';
import 'restaurant_info_screen.dart';
import 'restaurant_manage_list_screen.dart';
import 'settings_screen.dart';
import 'super_admin_billing_screen.dart';
import 'super_admin_finance_screen.dart';
import 'support_admin_screen.dart';
import 'table_qr_generator_screen.dart';
import 'transaction_history_screen.dart';
import 'voucher_screen.dart';

/// Satu tujuan di sidebar web.
class MenuWeb {
  final IconData ikon;
  final String judul;
  final Widget Function() layar;

  /// Judul kelompok di atasnya. Null berarti menyambung kelompok
  /// sebelumnya.
  final String? kelompok;

  /// Berapa hal yang menunggu dibaca di balik menu ini.
  ///
  /// Angkanya ditempel di sidebar. Tanpa ini, tanda "1 belum dibaca"
  /// hanya terlihat sesudah menunya dibuka — padahal justru itu yang
  /// seharusnya membuat orang membukanya.
  ///
  /// Aliran, bukan sekali hitung. Angka yang diperbarui berkala selalu
  /// tertinggal sebanyak selang waktunya, dan yang menunggu jawaban
  /// membaca keterlambatan itu sebagai "harus muat ulang dulu".
  final Stream<int> Function()? belumDibaca;

  const MenuWeb({
    required this.ikon,
    required this.judul,
    required this.layar,
    this.kelompok,
    this.belumDibaca,
  });
}

/// Percakapan yang menunggu jawaban Merchant-POS Admin.
///
/// Dihitung dari aliran tiket yang sama dengan yang dipakai layar
/// Customer Service — bukan permintaan terpisah. Dua sumber untuk satu
/// angka akan berbeda cepat atau lambat, dan yang berbeda dengan isi
/// layarnya sendiri adalah yang lebih membingungkan.
Stream<int> _supportBelumDibaca() => SupportRepository().semua().map(
      (tiket) => SupportRepository.belumDibaca(tiket, sebagaiAdmin: true),
    );

/// Pembukuan Merchant-POS sendiri, bukan pembukuan merchant — ketiganya
/// selalu menunjuk resto semu 'merchantpos'.
Widget _saldoMerchantPOS() => const FinanceBalanceScreen(restoId: kPlatformRestoId);
Widget _mappingMerchantPOS() =>
    const FinanceGlMappingScreen(restoId: kPlatformRestoId);
Widget _jurnalMerchantPOS() => const FinanceJournalScreen(restoId: kPlatformRestoId);

/// Tagihan langganan butuh tahu cabang mana yang sedang dibuka.
Widget _tagihan() => Builder(builder: (context) {
      final restoId = context.watch<AuthProvider>().restoId;
      if (restoId == null) {
        return const Scaffold(
          body: Center(child: Text('Pilih merchant dulu.')),
        );
      }
      return BillingScreen(restoId: restoId);
    });

/// Kategori dan Level berdiri sendiri di sidebar, tanpa induk Kelola
/// Produk yang biasanya memuatkan datanya lebih dulu.
Widget _kategori() => const KatalogSiap(
      judul: 'Kategori',
      child: CategoryManagementScreen(),
    );
Widget _level() => const KatalogSiap(
      judul: 'Level',
      child: LevelManagementScreen(),
    );

/// Menu sidebar untuk tiap peran yang punya versi web.
///
/// Ditulis sebagai daftar datar, bukan disalin dari beranda ponselnya.
/// Beranda ponsel menumpuk menunya di balik kelompok karena layarnya
/// sempit — di layar lebar tumpukan itu justru menyembunyikan hal yang
/// muat ditampilkan seluruhnya.
///
/// Kasir dan Chef sengaja tidak ada. Keduanya bekerja sambil berdiri, di
/// depan antrean, dengan satu tangan memegang perangkat — dan tidak ada
/// satu pun bagian pekerjaannya yang lebih mudah dengan tetikus.
List<MenuWeb> menuWebUntuk(AuthProvider auth) {
  if (auth.isSuperAdmin) return _superAdmin;
  if (auth.isOwner) return _owner;
  if (auth.isAdmin) return _admin;
  if (auth.isFinance) return _finance;
  return const [];
}

/// Pintasan ke seluruh menu, sebagai halaman pertama.
///
/// Sidebar sudah memuat semuanya, jadi ini bukan satu-satunya jalan ke
/// mana pun — dan memang bukan itu gunanya. Yang baru masuk menghadapi
/// dua puluh baris teks sempit di kiri layar dan ruang kosong yang
/// jauh lebih luas di sebelahnya; halaman ini memakai ruang itu untuk
/// menunjukkan apa saja yang ada, dengan ukuran yang bisa dibaca
/// sekilas.
///
/// Layarnya dirakit kerangka web, bukan di sini: menekan kartunya harus
/// memindahkan pilihan di sidebar, dan yang memegang pilihan itu
/// kerangkanya.
const menuBerandaWeb = MenuWeb(
  ikon: Icons.home_outlined,
  judul: 'Beranda',
  layar: _berandaKosong,
);

Widget _berandaKosong() => const SizedBox.shrink();

/// Peran ini punya versi webnya sendiri.
bool punyaVersiWeb(AuthProvider auth) => menuWebUntuk(auth).isNotEmpty;

const _superAdmin = <MenuWeb>[
  MenuWeb(
    kelompok: 'Merchant',
    ikon: Icons.storefront_outlined,
    judul: 'List Merchant',
    layar: RestaurantManageListScreen.new,
  ),
  MenuWeb(
    ikon: Icons.badge_outlined,
    judul: 'Kelola Karyawan',
    layar: EmployeeManagementScreen.new,
  ),
  MenuWeb(
    kelompok: 'Keuangan',
    ikon: Icons.receipt_long_outlined,
    judul: 'Billing Merchant',
    layar: SuperAdminBillingScreen.new,
  ),
  // Isi hub Finance Merchant-POS dibongkar ke sidebar.
  //
  // Hub bertingkat masuk akal di ponsel: layarnya sempit, jadi tujuh
  // tujuan disembunyikan di balik satu kartu. Di sidebar yang memang
  // memuat semuanya, kartu itu berubah jadi ketukan tambahan menuju
  // daftar yang seharusnya sudah terlihat sejak awal — dan tujuh
  // tujuan itu jadi satu-satunya bagian aplikasi yang tidak bisa
  // dicapai langsung dari kiri layar.
  MenuWeb(
    ikon: Icons.history,
    judul: 'Riwayat Langganan',
    layar: BillingHistoryScreen.new,
  ),
  MenuWeb(
    ikon: Icons.local_offer_outlined,
    judul: 'Diskon Langganan',
    layar: BillingDiscountScreen.new,
  ),
  MenuWeb(
    ikon: Icons.card_giftcard,
    judul: 'Voucher Pelanggan',
    layar: VoucherScreen.new,
  ),
  MenuWeb(
    kelompok: 'Pembukuan Merchant-POS',
    ikon: Icons.account_balance_wallet_outlined,
    judul: 'Saldo & Pengeluaran',
    layar: _saldoMerchantPOS,
  ),
  MenuWeb(
    ikon: Icons.numbers,
    judul: 'Mapping GL Account',
    layar: _mappingMerchantPOS,
  ),
  MenuWeb(
    ikon: Icons.menu_book_outlined,
    judul: 'Jurnal GL Merchant-POS',
    layar: _jurnalMerchantPOS,
  ),
  MenuWeb(
    ikon: Icons.travel_explore,
    judul: 'Jurnal GL Semua Merchant',
    layar: AllRestoJournalScreen.new,
  ),
  MenuWeb(
    kelompok: 'Pelanggan',
    ikon: Icons.support_agent,
    judul: 'Customer Service',
    layar: SupportAdminScreen.new,
    belumDibaca: _supportBelumDibaca,
  ),
  MenuWeb(
    ikon: Icons.insights_outlined,
    judul: 'Analisa Pasar',
    layar: MarketReportScreen.new,
  ),
  MenuWeb(
    ikon: Icons.campaign_outlined,
    judul: 'Kirim Pengumuman',
    layar: PublishAnnouncementScreen.new,
  ),
  MenuWeb(
    ikon: Icons.inbox_outlined,
    judul: 'Kotak Masuk',
    layar: InboxScreen.new,
  ),
];

const _owner = <MenuWeb>[
  MenuWeb(
    kelompok: 'Penjualan',
    ikon: Icons.point_of_sale,
    judul: 'Shift Kasir',
    layar: CashierShiftScreen.new,
  ),
  MenuWeb(
    ikon: Icons.list_alt,
    judul: 'Pesanan Masuk',
    layar: EmployeeOrdersScreen.new,
  ),
  MenuWeb(
    ikon: Icons.hourglass_bottom,
    judul: 'Pending Payment',
    layar: PendingPaymentScreen.new,
  ),
  MenuWeb(
    ikon: Icons.history,
    judul: 'Riwayat Kasir',
    layar: TransactionHistoryScreen.new,
  ),
  MenuWeb(
    ikon: Icons.insights_outlined,
    judul: 'Laporan Penjualan',
    layar: MerchantReportScreen.new,
  ),
  MenuWeb(
    kelompok: 'Keuangan',
    ikon: Icons.trending_up,
    judul: 'Pemasukan',
    layar: FinanceIncomeScreen.new,
  ),
  MenuWeb(
    ikon: Icons.account_balance_wallet_outlined,
    judul: 'Saldo & Pengeluaran',
    layar: FinanceBalanceScreen.new,
  ),
  MenuWeb(
    ikon: Icons.account_balance_outlined,
    judul: 'Setor Saldo Cash',
    layar: CashDepositScreen.new,
  ),
  MenuWeb(
    ikon: Icons.numbers,
    judul: 'Mapping GL Account',
    layar: FinanceGlMappingScreen.new,
  ),
  MenuWeb(
    ikon: Icons.menu_book_outlined,
    judul: 'Jurnal GL',
    layar: FinanceJournalScreen.new,
  ),
  MenuWeb(
    ikon: Icons.picture_as_pdf_outlined,
    judul: 'Laporan Transaksi',
    layar: FinanceReportScreen.new,
  ),
  MenuWeb(
    ikon: Icons.sync_alt,
    judul: 'Pencairan Gateway',
    layar: FinanceGatewaySettlementScreen.new,
  ),
  MenuWeb(
    ikon: Icons.receipt_long_outlined,
    judul: 'Tagihan Langganan',
    layar: _tagihan,
  ),
  MenuWeb(
    kelompok: 'Pengelolaan',
    ikon: Icons.inventory_2_outlined,
    judul: 'Kelola Produk',
    layar: ProductListScreen.new,
  ),
  MenuWeb(
    ikon: Icons.category_outlined,
    judul: 'Kategori',
    layar: _kategori,
  ),
  MenuWeb(
    ikon: Icons.tune,
    judul: 'Level',
    layar: _level,
  ),
  MenuWeb(
    ikon: Icons.local_offer_outlined,
    judul: 'Diskon',
    layar: DiscountScreen.new,
  ),
  MenuWeb(
    ikon: Icons.image_outlined,
    judul: 'Banner Promo',
    layar: PromoBannerScreen.new,
  ),
  MenuWeb(
    kelompok: 'Pengaturan',
    ikon: Icons.storefront_outlined,
    judul: 'Info Merchant',
    layar: RestaurantInfoScreen.new,
  ),
  MenuWeb(
    ikon: Icons.qr_code_2,
    judul: 'QR Meja',
    layar: TableQrGeneratorScreen.new,
  ),
  // Owner memegang rekeningnya sendiri, jadi ia boleh mengubahnya.
  MenuWeb(
    ikon: Icons.payments_outlined,
    judul: 'Info Pembayaran',
    layar: SettingsScreen.new,
  ),
  MenuWeb(
    ikon: Icons.campaign_outlined,
    judul: 'Kirim Pengumuman',
    layar: PublishAnnouncementScreen.new,
  ),
  MenuWeb(
    ikon: Icons.inbox_outlined,
    judul: 'Kotak Masuk',
    layar: InboxScreen.new,
  ),
];

const _admin = <MenuWeb>[
  MenuWeb(
    kelompok: 'Penjualan',
    ikon: Icons.point_of_sale,
    judul: 'Shift Kasir',
    layar: CashierShiftScreen.new,
  ),
  MenuWeb(
    ikon: Icons.list_alt,
    judul: 'Pesanan Masuk',
    layar: EmployeeOrdersScreen.new,
  ),
  MenuWeb(
    ikon: Icons.hourglass_bottom,
    judul: 'Pending Payment',
    layar: PendingPaymentScreen.new,
  ),
  MenuWeb(
    ikon: Icons.history,
    judul: 'Riwayat Kasir',
    layar: TransactionHistoryScreen.new,
  ),
  MenuWeb(
    ikon: Icons.insights_outlined,
    judul: 'Laporan Penjualan',
    layar: MerchantReportScreen.new,
  ),
  MenuWeb(
    kelompok: 'Keuangan',
    ikon: Icons.account_balance_wallet_outlined,
    judul: 'Saldo & Pengeluaran',
    layar: FinanceBalanceScreen.new,
  ),
  MenuWeb(
    ikon: Icons.account_balance_outlined,
    judul: 'Setor Saldo Cash',
    layar: CashDepositScreen.new,
  ),
  MenuWeb(
    kelompok: 'Pengelolaan',
    ikon: Icons.inventory_2_outlined,
    judul: 'Kelola Produk',
    layar: ProductListScreen.new,
  ),
  MenuWeb(
    ikon: Icons.category_outlined,
    judul: 'Kategori',
    layar: _kategori,
  ),
  MenuWeb(
    ikon: Icons.tune,
    judul: 'Level',
    layar: _level,
  ),
  MenuWeb(
    ikon: Icons.local_offer_outlined,
    judul: 'Diskon',
    layar: DiscountScreen.new,
  ),
  MenuWeb(
    ikon: Icons.image_outlined,
    judul: 'Banner Promo',
    layar: PromoBannerScreen.new,
  ),
  MenuWeb(
    kelompok: 'Pengaturan',
    ikon: Icons.storefront_outlined,
    judul: 'Info Merchant',
    layar: RestaurantInfoScreen.new,
  ),
  MenuWeb(
    ikon: Icons.qr_code_2,
    judul: 'QR Meja',
    layar: TableQrGeneratorScreen.new,
  ),
  // Baca-saja, sama seperti di HP. Rekening tujuan dan ID merchant
  // menentukan ke mana uang merchant mengalir; yang boleh mengubahnya
  // adalah yang menanggung akibatnya kalau salah.
  MenuWeb(
    ikon: Icons.payments_outlined,
    judul: 'Info Pembayaran',
    layar: PaymentInfoScreen.new,
  ),
  MenuWeb(
    ikon: Icons.campaign_outlined,
    judul: 'Kirim Pengumuman',
    layar: PublishAnnouncementScreen.new,
  ),
  MenuWeb(
    ikon: Icons.inbox_outlined,
    judul: 'Kotak Masuk',
    layar: InboxScreen.new,
  ),
];

const _finance = <MenuWeb>[
  MenuWeb(
    kelompok: 'Pemasukan & Saldo',
    ikon: Icons.trending_up,
    judul: 'Pemasukan',
    layar: FinanceIncomeScreen.new,
  ),
  MenuWeb(
    ikon: Icons.account_balance_wallet_outlined,
    judul: 'Saldo & Pengeluaran',
    layar: FinanceBalanceScreen.new,
  ),
  MenuWeb(
    ikon: Icons.account_balance_outlined,
    judul: 'Setor Saldo Cash',
    layar: CashDepositScreen.new,
  ),
  MenuWeb(
    ikon: Icons.point_of_sale,
    judul: 'Shift Kasir',
    layar: CashierShiftScreen.new,
  ),
  MenuWeb(
    kelompok: 'Pembukuan',
    ikon: Icons.numbers,
    judul: 'Mapping GL Account',
    layar: FinanceGlMappingScreen.new,
  ),
  MenuWeb(
    ikon: Icons.menu_book_outlined,
    judul: 'Jurnal GL',
    layar: FinanceJournalScreen.new,
  ),
  MenuWeb(
    ikon: Icons.picture_as_pdf_outlined,
    judul: 'Laporan Transaksi',
    layar: FinanceReportScreen.new,
  ),
  MenuWeb(
    ikon: Icons.sync_alt,
    judul: 'Pencairan Gateway',
    layar: FinanceGatewaySettlementScreen.new,
  ),
  MenuWeb(
    kelompok: 'Langganan & Pengaturan',
    ikon: Icons.receipt_long_outlined,
    judul: 'Tagihan Langganan',
    layar: _tagihan,
  ),
  MenuWeb(
    ikon: Icons.payments_outlined,
    judul: 'Pengaturan Pembayaran',
    layar: SettingsScreen.new,
  ),
  MenuWeb(
    ikon: Icons.inbox_outlined,
    judul: 'Kotak Masuk',
    layar: InboxScreen.new,
  ),
];
