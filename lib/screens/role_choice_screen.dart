import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/customer_login_flow.dart';
import '../l10n/strings.dart';
import '../widgets/merchantpos_logo.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/loading_overlay.dart';
import 'about_screen.dart';
import 'customer_home_screen.dart';
import '../widgets/app_toast.dart';

/// First screen shown to anyone who isn't already a recognized employee
/// and hasn't scanned a table before. Picks the experience: browse/order
/// as a customer (which first offers an optional Gmail login), or sign
/// in as staff.
class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key});

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  String _versionLabel = '';
  bool _signingInEmployee = false;

  /// Web ini konsol backoffice, bukan tempat pelanggan memesan.
  ///
  /// Pintu Pelanggan tidak ditampilkan sama sekali di sini — bukan
  /// disembunyikan supaya rapi, tapi karena seluruh yang ada di
  /// baliknya (pindai QR meja, kamera, keranjang) memang tidak
  /// dibuatkan versi webnya. Pintu yang ada tapi tidak menuju ke mana-
  /// mana lebih buruk daripada pintu yang tidak ada.
  bool get _hanyaMerchant => kIsWeb;

  /// Galat login yang datang dari pengalihan web.
  ///
  /// Di ponsel, penolakan tampil di tempat: `signInWithGoogle` kembali,
  /// lalu barisan sesudahnya membaca [AuthProvider.lastError] dan
  /// memunculkan dialognya. Di web tidak ada "barisan sesudahnya" —
  /// halamannya benar-benar ditinggalkan ke Google dan dimuat ulang
  /// dari nol, jadi kode yang seharusnya menampilkan pesannya tidak
  /// pernah dijalankan.
  ///
  /// Akibatnya yang emailnya belum terdaftar sebagai karyawan mendarat
  /// kembali di layar ini tanpa sepatah kata pun — persis sama dengan
  /// tampilan orang yang membatalkan sendiri login-nya.
  Future<void> _tampilkanGalatTertunda() async {
    final auth = context.read<AuthProvider>();
    final pesan = auth.lastError;
    if (pesan == null || !mounted) return;
    await _showLoginBlocked(context, pesan);
    auth.bersihkanGalat();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _tampilkanGalatTertunda());
    // Nomor versi tidak berlaku di web: yang dibuka selalu versi yang
    // sedang dilayani servernya, tidak ada yang bisa tertinggal dan
    // perlu dicocokkan saat melapor masalah.
    if (_hanyaMerchant) return;
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _versionLabel = 'v${info.version} (${info.buildNumber})');
    });
  }

  Future<void> _chooseCustomer() async {
    final loginFirst = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.mail_outline, size: 40, color: MerchantPosTheme.brand),
        title: const Text('Login dengan Gmail?'),
        content: const Text(
          'Login supaya riwayat pesanan kamu tersimpan dan bisa dilihat lagi '
          'dari merchant mana pun. Nggak login juga tetap bisa pesan seperti biasa — '
          'riwayatnya cuma tersimpan di HP ini.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Login dengan Gmail'),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Lewati, Pesan Tanpa Login'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (loginFirst == null || !mounted) return; // dialog dismissed without a choice

    if (!loginFirst) {
      // Guest: nothing for RootScreen to react to, so open the customer
      // experience on top of this screen.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
      );
      return;
    }

    // A successful customer login makes RootScreen swap this screen out
    // for CustomerHomeScreen — which disposes it mid-flow. Hold the root
    // navigator's context so the steps after sign-in still have somewhere
    // valid to show a dialog from; `this.context` is gone by then, and
    // guarding on `mounted` instead would silently skip them.
    final navigator = Navigator.of(context, rootNavigator: true);
    final toast = AppToast.of(context);
    final rootContext = navigator.context;
    final auth = context.read<AuthProvider>();

    var claimed = 0;
    // rootContext belongs to the app's root navigator, which outlives
    // this screen — the usual "don't reuse a context across an await"
    // hazard doesn't apply, and that's the whole point of capturing it.
    // ignore: use_build_context_synchronously
    await withLoadingOverlay(rootContext, () async {
      await auth.signInWithGoogle(intent: LoginIntent.customer);
      // Orders placed on this device before signing in follow them into
      // the account, but only if the email is new to Merchant-POS — see
      // claimGuestOrdersForLogin. Folded into the same overlay so there's
      // one uninterrupted "signing you in" beat rather than two.
      if (auth.isLoggedIn && !auth.isEmployee) {
        claimed = await claimGuestOrdersForLogin();
      }
    });

    // A staff email handed to the Customer door is refused outright now,
    // with the reason left here. Previously it just signed them into the
    // staff app instead, quietly ignoring which button they pressed.
    if (auth.lastError != null) {
      // ignore: use_build_context_synchronously
      await _showLoginBlocked(rootContext, auth.lastError!);
      auth.bersihkanGalat();
      return;
    }
    // Backed out of Google's account picker — nothing to do.
    if (!auth.isLoggedIn) return;

    if (claimed > 0) {
      toast.show('$claimed riwayat pesanan dipindahkan ke akun ini.');
    }

    await ensureCustomerProfile(navigator, auth.user!.email!);
    // No push: RootScreen is already showing CustomerHomeScreen for this
    // now-logged-in customer.
  }

  /// Straight to Google's account picker — no intermediate "Masuk sebagai
  /// Karyawan" screen at all. If it succeeds and the account is a
  /// registered employee, RootScreen (watching AuthProvider) swaps to the
  /// staff app on its own. If the picker is cancelled, or the account
  /// isn't a registered employee (or their merchant's been deactivated), we
  /// just stay right here on the choice screen — same page as before.
  Future<void> _chooseEmployee() async {
    setState(() => _signingInEmployee = true);
    final auth = context.read<AuthProvider>();
    await withLoadingOverlay(
      context,
      () => auth.signInWithGoogle(intent: LoginIntent.employee),
    );
    if (!mounted) return;
    setState(() => _signingInEmployee = false);

    // Not staff, resto switched off, or the lookup failed — AuthProvider
    // refuses all of them the same way and leaves the reason here. It
    // never signs a rejected account in, so this screen is still mounted
    // to explain.
    if (auth.lastError != null) {
      await _showLoginBlocked(context, auth.lastError!);
      auth.bersihkanGalat();
    }
    // Otherwise: either cancelled (nothing logged in, no error — just
    // stay put), or they're a valid employee and RootScreen already
    // handles the swap.
  }

  Future<void> _showLoginBlocked(BuildContext context, String reason) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.block, size: 40, color: Colors.orange),
        title: const Text('Tidak Bisa Masuk'),
        content: Text(reason, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.surfaceOf(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Tombol selebar layar 1600 piksel bukan tombol lagi — itu
            // pita. Lebarnya dikunci ke ukuran yang wajar dijangkau
            // mata dan tetikus, lalu ditaruh di tengah.
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Deliberately understated next to the two role buttons —
              // it's a "what is this?" affordance, not a third choice.
              Row(
                children: [
                  // Bahasa dipilih di sini, sebelum masuk — dan pilihan
                  // itu ikut ke seluruh menu setelah login. Sesudah
                  // keluar akun tidak ada lagi menu Pengaturan yang bisa
                  // dibuka, jadi tombolnya harus tetap ada di halaman
                  // yang selalu bisa dicapai siapa pun.
                  const LanguageToggle(compact: true),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    color: MerchantPosTheme.mutedOf(context),
                    tooltip: context.tr('Tentang Merchant-POS'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const MerchantPosLogo(size: 96),
              const SizedBox(height: 20),
              Text(
                'Merchant-POS',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: MerchantPosTheme.brandOf(context),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Order Cepat, Merchant Hebat',
                style: TextStyle(
                  color: MerchantPosTheme.brandOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('Masuk sebagai'),
                style: TextStyle(
                    color: MerchantPosTheme.mutedOf(context), fontSize: 15),
              ),
              const SizedBox(height: 40),
              if (!_hanyaMerchant) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.person_outline),
                    label: Text(context.tr('Pelanggan')),
                    onPressed: _chooseCustomer,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Satu-satunya pintu di web, jadi diberi bobot penuh.
              // Tombol bergaris di layar tanpa pembanding terbaca
              // seperti pilihan kedua yang pilihan pertamanya hilang.
              Builder(builder: (context) {
                final ikon = _signingInEmployee
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storefront_outlined);
                final label = Text(context.tr('Merchant-POS'));
                final tekan = _signingInEmployee ? null : _chooseEmployee;

                return SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _hanyaMerchant
                      ? FilledButton.icon(
                          icon: ikon, label: label, onPressed: tekan)
                      : OutlinedButton.icon(
                          icon: ikon, label: label, onPressed: tekan),
                );
              }),
              const SizedBox(height: 20),
              // Di bawah kedua tombol masuk, bukan di atas logonya.
              //
              // Yang membuka layar ini datang untuk satu hal: masuk.
              // Pemilih tema yang duduk di baris pertama menjadi hal
              // pertama yang dibaca — dan sempat terbaca sebagai
              // pilihan cara masuk, karena bentuknya memang tombol
              // berderet sama seperti dua tombol di bawahnya.
              const ThemeToggle(),
              const Spacer(),
              if (!_hanyaMerchant && _versionLabel.isNotEmpty)
                Text(
                  _versionLabel,
                  style: TextStyle(
                      color: MerchantPosTheme.mutedOf(context), fontSize: 12),
                ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}
