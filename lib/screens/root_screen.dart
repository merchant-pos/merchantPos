import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import '../utils/tautan_meja.dart';
import 'admin_home_screen.dart';
import 'chef_home_screen.dart';
import 'customer_home_screen.dart';
import 'finance_home_screen.dart';
import 'kasir_home_screen.dart';
import 'owner_home_screen.dart';
import '../widgets/billing_gate.dart';
import 'role_choice_screen.dart';
import 'super_admin_home_screen.dart';
import 'web_menu.dart';
import 'web_shell_screen.dart';

/// Decides which experience to show:
/// - Admin/Kasir/Chef still signed in (Firebase Auth persists across app
///   restarts) → straight to their role's screen, bypassing the choice
///   screen entirely.
/// - Customer with a still-active table session on this device → straight
///   back into [CustomerHomeScreen] (no re-choosing needed).
/// - Otherwise (logged out employee, or an ended/no session) →
///   [RoleChoiceScreen] to pick Customer or Karyawan.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<TableSessionProvider>();
      if (!session.loaded) await session.load();
      if (!mounted) return;
      await _bukaMejaDariAlamat(session);
    });
  }

  /// Meja yang datang dari alamat halaman, bukan dari kamera.
  ///
  /// Inilah pintu masuk pelanggan di web: QR di meja berisi tautan, dan
  /// yang memindainya dengan kamera bawaan HP mendarat di sini dengan
  /// resto dan nomor mejanya menempel di alamat. Tidak ada kamera yang
  /// perlu dibuka aplikasi ini, karena kameranyalah yang mengantar
  /// orangnya ke sini.
  Future<void> _bukaMejaDariAlamat(TableSessionProvider session) async {
    if (!kIsWeb) return;
    final meja = bacaTautanMeja(Uri.base.toString());
    if (meja == null) return;
    // Memindai QR meja yang sama berulang kali — atau sekadar memuat
    // ulang halamannya — tidak boleh memulai sesi baru. Sesi baru
    // berarti pesanan yang sedang berjalan ditinggalkan di sesi lama,
    // dan yang menunggu makanannya kehilangan jejak pesanannya sendiri.
    if (session.hasActiveResto &&
        session.restoId == meja.restoId &&
        session.tableNumber == meja.meja) {
      return;
    }
    await session.setTable(meja.restoId, meja.meja);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Only gate on the one-time app-launch bootstrap check. Deliberately
    // NOT gating on auth.isCheckingRole here — that also flips true for
    // every later role re-check (e.g. a customer optionally logging in
    // from RoleChoiceScreen), and swapping this screen out mid-flow would
    // tear down whatever screen/dialog was mid-await, discarding it.
    // Screens that specifically want a spinner during a role check show
    // one themselves (e.g. the Google sign-in flow in RoleChoiceScreen).
    if (auth.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Di web, empat peran meja kerja memakai kerangka sidebar.
    //
    // Kasir dan Chef tidak: keduanya bekerja sambil berdiri, di depan
    // antrean, dengan satu tangan memegang perangkat — dan tidak ada
    // satu pun bagian pekerjaannya yang lebih mudah dengan tetikus.
    // Pelanggan juga tidak: memesan dari meja butuh kamera untuk
    // memindai QR-nya.
    if (kIsWeb && punyaVersiWeb(auth)) {
      final shell = KeyedSubtree(
        key: ValueKey(auth.restoId),
        child: const WebShellScreen(),
      );
      // Gerbang langganannya tetap berlaku, sama seperti di ponsel —
      // kecuali untuk Merchant-POS Admin, yang justru membuka kuncinya.
      return auth.isSuperAdmin ? shell : BillingGate(child: shell);
    }

    if (auth.isSuperAdmin) return const SuperAdminHomeScreen();

    // Layar peran dibangun ulang sepenuhnya saat resto berganti.
    // Sebagian besar layar membaca restoId sekali di initState dan
    // menyimpan hasilnya; tanpa dipaksa mulai dari awal, berpindah resto
    // akan meninggalkan data cabang lama di layar — persis percampuran
    // yang harus dihindari.
    final home = _homeForRole(auth);
    if (home != null) {
      return KeyedSubtree(key: ValueKey(auth.restoId), child: home);
    }

    // Signed in but not on the employee list — a customer. Their hub is
    // home the same way each role's screen is, so a restart lands there
    // instead of asking "Customer or Resto?" again. CustomerHomeScreen
    // decides for itself whether to show the hub, the chooser, or the
    // menu, based on whether a resto session is active.
    if (auth.isLoggedIn) return const CustomerHomeScreen();

    final session = context.watch<TableSessionProvider>();
    if (!session.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session.hasActiveResto) return const CustomerHomeScreen();
    return const RoleChoiceScreen();
  }

  Widget? _homeForRole(AuthProvider auth) {
    // Kelima peran resto dibungkus satu gerbang langganan. Dipasang di
    // sini, bukan di dalam tiap layar: lima pemasangan berarti lima
    // tempat yang bisa terlewat, dan yang terlewat tidak akan terlihat
    // sampai ada resto menunggak yang kebetulan memakai peran itu.
    //
    // Super Admin sengaja di luar — dialah yang membuka kuncinya.
    final home = switch (auth) {
      _ when auth.isOwner => const OwnerHomeScreen(),
      _ when auth.isAdmin => const AdminHomeScreen(),
      _ when auth.isKasir => const KasirHomeScreen(),
      _ when auth.isChef => const ChefHomeScreen(),
      _ when auth.isFinance => const FinanceHomeScreen(),
      _ => null,
    };
    return home == null ? null : BillingGate(child: home);
  }
}
