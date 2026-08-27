
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/badged_hub_tile.dart';
import '../widgets/hub_group_tile.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/merchantpos_logo.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/responsive.dart';
import 'employee_management_screen.dart';
import '../db/support_repository.dart';
import 'market_report_screen.dart';
import 'support_admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'publish_announcement_screen.dart';
import 'restaurant_manage_list_screen.dart';
import 'super_admin_billing_screen.dart';
import 'super_admin_finance_screen.dart';

/// Home screen for the 'super_admin' role — not scoped to any single
/// restaurant. Two jobs: manage employees across every resto (the app
/// previously had no UI for this at all), and manage restos (including
/// creating new ones — that's the "+ Resto Baru" FAB inside List Resto,
/// not a separate menu entry here).
class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key});

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
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'MerchantPOS Admin';
    final email = auth.user?.email;

    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      // Fixed header + scrolling menu, rather than a SliverAppBar: with
      // enough entries to scroll, a collapsing app bar took the logo,
      // name and email away with it. Only the menu should move.
      body: Column(
        children: [
          HubHeader(
            logo: const MerchantPosLogo(size: 64),
            title: name,
            subtitle: email == null ? 'MerchantPOS Admin' : 'MerchantPOS Admin • $email',
            colorA: MerchantPosTheme.brand,
            colorB: MerchantPosTheme.brandDark,
          ),
          Expanded(
            child: HubMenuLayout(
              tiles: [
                HubGroupTile(
                  icon: Icons.storefront_outlined,
                  title: 'Merchant & Karyawan',
                  subtitle: 'Daftar merchant dan akun karyawan semua merchant',
                  color: const Color(0xFF0EA5E9),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.storefront_outlined,
                      title: 'List Merchant',
                      subtitle: 'Lihat & edit semua merchant terdaftar di MerchantPOS',
                      color: const Color(0xFF0EA5E9),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RestaurantManageListScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.badge_outlined,
                      title: 'Kelola Karyawan',
                      subtitle: 'Tambah/edit/hapus akun Admin, Kasir, Chef, Finance — semua resto',
                      color: const Color(0xFF6366F1),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()),
                      ),
                    ),
                  ],
                ),
                HubGroupTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Langganan & Keuangan',
                  subtitle: 'Billing merchant, pendapatan, pembukuan MerchantPOS',
                  color: const Color(0xFF10B981),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Billing Merchant',
                      subtitle: 'Harga & tanggal langganan tiap merchant, verifikasi pembayaran',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SuperAdminBillingScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.account_balance_outlined,
                      title: 'Finance',
                      subtitle: 'Pendapatan langganan, pembukuan MerchantPOS, jurnal semua merchant',
                      color: const Color(0xFF14B8A6),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SuperAdminFinanceScreen()),
                      ),
                    ),
                  ],
                ),
                // Paling atas di antara menu yang berdiri sendiri.
                // Pengaduan yang menunggu jawaban adalah satu-satunya
                // isi beranda ini yang punya orang di ujung sana, sedang
                // menunggu.
                BadgedHubTile(
                  icon: Icons.support_agent,
                  title: 'Customer Service',
                  subtitle: 'Pengaduan dari pelanggan dan merchant',
                  color: const Color(0xFF0EA5E9),
                  loadCount: () => SupportRepository().milikSemuaBelumDibaca(),
                  destination: () => const SupportAdminScreen(),
                ),
                HubMenuTile(
                  icon: Icons.insights_outlined,
                  title: 'Analisa Pasar',
                  subtitle:
                      'Pelanggan & merchant teratas, dan yang belum bergerak',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MarketReportScreen()),
                  ),
                ),
                HubMenuTile(
                    icon: Icons.campaign_outlined,
                    title: 'Kirim Pengumuman',
                    subtitle: 'Blast info versi baru ke semua kotak masuk',
                    color: const Color(0xFFF59E0B),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PublishAnnouncementScreen()),
                    ),
                  ),
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
