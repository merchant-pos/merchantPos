import '../widgets/support_fab.dart';
import '../widgets/penilaian_tile.dart';
import 'billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../db/petty_cash_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/badged_hub_tile.dart';
import '../widgets/hub_group_tile.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/responsive.dart';
import '../widgets/resto_switcher.dart';
import '../widgets/merchantpos_logo.dart';
import 'cash_deposit_screen.dart';
import 'cashier_shift_screen.dart';
import 'finance_balance_screen.dart';
import 'finance_gateway_settlement_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_income_screen.dart';
import 'finance_journal_screen.dart';
import 'finance_report_screen.dart';
import 'settings_screen.dart';

/// Home screen for the 'finance' role: view resto-wide income (grouped
/// per day, broken down by payment method), view balance + record
/// expenses, and configure the GL account mapping used to book each
/// payment method's income.
class FinanceHomeScreen extends StatelessWidget {
  const FinanceHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Finance';
    final email = auth.user?.email;
    final restoId = auth.restoId;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      // Mengambang di beranda, bukan jadi satu tombol lagi di daftar.
      //
      // Yang mencarinya sedang kesulitan — dan orang yang sedang
      // kesulitan tidak menggulir daftar menu mencari jalan mengadu.
      floatingActionButton: const SupportFab(),
      // Fixed header + scrolling menu, rather than a SliverAppBar: with
      // enough entries to scroll, a collapsing app bar took the logo,
      // name and email away with it. Only the menu should move.
      body: Column(
        children: [
          HubHeader(
            logo: const MerchantPosLogo(size: 64),
            title: name,
            subtitle: email == null ? 'Finance' : 'Finance • $email',
            colorA: MerchantPosTheme.brand,
            colorB: MerchantPosTheme.brandDark,
            trailing: const RestoSwitcher(),
          ),
          Expanded(
            child: HubMenuLayout(
              tiles: [
                // Dibuka dua kali sehari pada dua saat tersibuk: awal shift
                // ketika antrean mulai, dan akhir shift ketika sudah ingin
                // pulang. Menu yang harus dicari di dalam grup pada dua saat
                // itu adalah menu yang dilewati — dan shift yang tidak pernah
                // ditutup membuat seluruh gunanya hilang.
                HubMenuTile(
                  icon: Icons.point_of_sale,
                  title: 'Shift Kasir',
                  subtitle: 'Buka shift, tutup shift, dan hitung uang laci',
                  color: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CashierShiftScreen()),
                  ),
                ),
                HubGroupTile(
                  icon: Icons.trending_up,
                  title: 'Pemasukan & Saldo',
                  subtitle: 'Pemasukan, saldo, pengeluaran, setoran',
                  color: const Color(0xFF10B981),
                  loadCount: () => _penandaKeuangan(restoId),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.trending_up,
                      title: 'Pemasukan',
                      subtitle: 'Rekap harian, breakdown Tunai/QRIS/Transfer',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FinanceIncomeScreen()),
                      ),
                    ),
                    // Penandanya menghitung pengajuan yang menunggu, bukan
                    // sekadar "ada yang baru": yang membuat Finance harus
                    // ke sini adalah keputusan yang belum dia ambil.
                    BadgedHubTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Saldo & Pengeluaran',
                      subtitle: 'Lihat saldo total, catat pengeluaran',
                      color: const Color(0xFF6366F1),
                      loadCount: () => restoId == null ? Future.value(0) : PettyCashRepository().pendingCount(restoId),
                      destination: () => const FinanceBalanceScreen(),
                    ),
                    BadgedHubTile(
                      icon: Icons.account_balance_outlined,
                      title: 'Setor Saldo Cash',
                      subtitle: 'Riwayat setoran tunai berikut buktinya',
                      color: const Color(0xFF0EA5E9),
                      loadCount: () => restoId == null ? Future.value(0) : CashDepositRepository().pendingCount(restoId),
                      destination: () => const CashDepositScreen(),
                    ),
                  ],
                ),
                HubGroupTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Pembukuan',
                  subtitle: 'Mapping GL, jurnal, laporan, pencairan gateway',
                  color: const Color(0xFF14B8A6),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.numbers,
                      title: 'Mapping GL Account',
                      subtitle: 'Nomor akun untuk pemasukan & pengeluaran',
                      color: const Color(0xFFF59E0B),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FinanceGlMappingScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.menu_book_outlined,
                      title: 'Jurnal GL',
                      subtitle: 'Audit trail semua pergerakan uang per GL account',
                      color: const Color(0xFF14B8A6),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FinanceJournalScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Laporan Transaksi',
                      subtitle: 'Export/cetak laporan seperti rekening koran',
                      color: const Color(0xFF0EA5E9),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FinanceReportScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.credit_card_outlined,
                      title: 'Pencairan Gateway',
                      subtitle: 'Catat dana QRIS yang masuk rekening & potongannya',
                      color: const Color(0xFFEC4899),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const FinanceGatewaySettlementScreen()),
                      ),
                    ),
                  ],
                ),
                // Berdiri sendiri, bukan di dalam Pembukuan: ini
                // satu-satunya uang yang keluar dari resto ke MerchantPOS,
                // dan yang membayarnya memang bagian Finance.
                HubMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Tagihan Langganan',
                  subtitle: 'Biaya bulanan MerchantPOS & bukti pembayaran',
                  color: const Color(0xFF6366F1),
                  onTap: () {
                    final restoId = context.read<AuthProvider>().restoId;
                    if (restoId == null) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BillingScreen(restoId: restoId),
                    ));
                  },
                ),
                HubMenuTile(
                    icon: Icons.payments_outlined,
                    title: 'Pengaturan Pembayaran',
                    subtitle: 'Atur QRIS & rekening bank merchant',
                    color: const Color(0xFFEC4899),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                const PenilaianTile(),
                const InboxTile(),
                HubMenuTile(
                    icon: Icons.brightness_6_outlined,
                    title: 'Tampilan',
                    subtitle: 'Mode terang, gelap, atau ikut setelan HP',
                    color: const Color(0xFF0EA5E9),
                    onTap: () => showAppearanceDialog(context),
                  ),
                HubMenuTile(
                    icon: Icons.logout,
                    title: 'Keluar',
                    subtitle: 'Logout dari akun ini',
                    color: const Color(0xFFEF4444),
                    onTap: () => _logout(context),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jumlah pengajuan yang menunggu keputusan di kelompok Keuangan.
///
/// Dijumlahkan supaya penandanya ikut naik ke halaman awal. Menyembunyikan
/// menu di balik pintu juga menyembunyikan titik merahnya — dan titik
/// merah itu satu-satunya cara orang tahu ada yang menunggu tanpa membuka
/// apa pun.
Future<int> _penandaKeuangan(String? restoId) async {
  if (restoId == null) return 0;
  final hasil = await Future.wait([
    PettyCashRepository().pendingCount(restoId),
    CashDepositRepository().pendingCount(restoId),
  ]);
  return hasil.fold<int>(0, (a, b) => a + b);
}
