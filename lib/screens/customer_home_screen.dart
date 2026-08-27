import '../widgets/responsive.dart';
import '../widgets/side_cart_dialog.dart';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/customer_profile_repository.dart';
import '../db/firestore_product_repository.dart';
import '../db/guest_order_store.dart';
import '../db/order_repository.dart';
import '../db/restaurant_repository.dart';
import '../db/session_repository.dart';
import '../models/cart_item.dart';
import '../models/customer_order.dart';
import '../models/product.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/level_group_provider.dart';
import '../providers/table_session_provider.dart';
import '../utils/customer_login_flow.dart';
import '../utils/greeting.dart';
import '../utils/resto_location.dart';
import '../utils/logout_confirm.dart';
import '../theme.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/update_banner.dart';
import '../widgets/merchantpos_logo.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/product_category_list.dart';
import '../widgets/product_lines_sheet.dart';
import '../widgets/promo_banner_carousel.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/quantity_dialog.dart';
import 'customer_cart_screen.dart';
import 'customer_history_screen.dart';
import 'customer_order_status_screen.dart';
import 'customer_profile_screen.dart';
import 'my_vouchers_screen.dart';
import 'restaurant_list_screen.dart';
import 'scan_table_screen.dart';
import '../widgets/dialog_actions.dart';
import '../utils/id_time.dart';
import '../utils/menu_meta.dart';
import '../widgets/app_toast.dart';
import '../widgets/support_fab.dart';

/// Self-order browsing screen for customers. Reads the product catalog
/// live from Firestore (mirrored by the employee app), so stock/prices
/// stay in sync without needing a local database on the customer's
/// device.
///
/// Ordering requires having scanned a table's QR code first — this
/// screen gates on [TableSessionProvider.hasActiveTable] and shows the
/// scan screen otherwise.
///
/// While a session is active, this screen also watches the session's
/// orders in the background: once every order is "done" and 5 minutes
/// pass without a new one, the session auto-ends — same as tapping
/// "Selesai" on the order-status screen.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  static const _autoEndDelay = Duration(minutes: 5);

  /// Stream menu dan info resto, dibuat sekali per resto.
  ///
  /// Sebelumnya keduanya dibuat di dalam `build`, jadi tiap kali layar
  /// dibangun ulang — dan itu terjadi tiap kali keranjang berubah —
  /// StreamBuilder menerima stream yang berbeda, kembali ke keadaan
  /// "menunggu", lalu menampilkan lingkaran memuat. Yang terlihat:
  /// menunya berkedip hilang-muncul tiap menambah satu item.
  final _productRepo = FirestoreProductRepository();
  final _restoInfoRepo = RestaurantRepository();

  /// Langganannya dipegang layar ini, bukan diserahkan ke StreamBuilder.
  ///
  /// Sempat dicoba dengan `asBroadcastStream()` yang disimpan di sini,
  /// dan itu justru merusak: stream siaran ikut selesai begitu
  /// pendengar terakhirnya berhenti. Layar yang ditutup lalu dibuka
  /// lagi mendengarkan stream yang sudah mati — tidak ada data yang
  /// datang, tidak ada galat, dan lingkarannya berputar selamanya.
  ///
  /// Datanya disimpan di sini juga. Kembali ke layar ini langsung
  /// menampilkan menu yang terakhir diketahui, bukan lingkaran memuat
  /// yang mengulang dari nol tiap kali.
  StreamSubscription<List<Product>>? _produkSub;
  StreamSubscription<Restaurant?>? _restoSub;
  List<Product>? _produk;
  Restaurant? _restoInfo;
  Object? _galatProduk;

  /// Label promo, bintang, dan angka terjual tiap menu.
  MenuMeta _meta = MenuMeta.kosong;

  /// Nama menu, untuk menyebut isi paket bundling di keterangan promo.
  Map<String, String> get _namaMenu =>
      {for (final p in _produk ?? const <Product>[]) p.id: p.name};

  /// Kapan terakhir label promo dan bintangnya diambil.
  ///
  /// Diambil ulang tiap kali layar ini dibuka lagi, tapi tidak lebih
  /// sering dari [_jedaMeta]. Tanpa pengambilan ulang, bintang yang
  /// barusan diberikan lewat Riwayat Saya tidak akan pernah muncul di
  /// kartu menunya sampai aplikasinya ditutup — datanya sudah ada di
  /// server, yang basi cuma salinan di layar. Tanpa jedanya, tiap
  /// gambar ulang layar berarti dua permintaan ke server.
  DateTime? _metaTerakhir;
  static const _jedaMeta = Duration(seconds: 30);

  void _segarkanMeta(String restoId, {bool paksa = false}) {
    final terakhir = _metaTerakhir;
    if (!paksa &&
        terakhir != null &&
        DateTime.now().difference(terakhir) < _jedaMeta) {
      return;
    }
    _metaTerakhir = DateTime.now();
    muatMenuMeta(restoId).then((m) {
      if (!mounted || _streamRestoId != restoId) return;
      setState(() => _meta = m);
    });
  }
  String? _streamRestoId;

  StreamSubscription<List<CustomerOrder>>? _orderWatch;
  StreamSubscription<bool>? _remoteActiveWatch;
  String? _watchedSessionId;
  Timer? _autoEndTimer;

  /// Drives whether the chooser offers "Riwayat Pesanan" to a guest —
  /// there's no point showing the entry when the device has never placed
  /// an order, since it'd only ever open an empty screen.
  bool _hasGuestHistory = false;

  /// Logged-in customers land on a hub (Pesan / Profil / Riwayat /
  /// Logout) like every employee role does; the Scan-or-Pick chooser is
  /// one step in from there. Guests skip the hub — there'd be almost
  /// nothing on it for them — and go straight to the chooser.
  bool _showChooser = false;

  /// Name from their saved profile, for the greeting. Falls back to the
  /// email's local part while it loads or if no profile exists yet.
  String? _profileName;

  /// Foto profil mereka, kalau sudah diunggah — dipakai menggantikan
  /// logo MerchantPOS di header, supaya hub-nya terasa milik mereka sendiri.
  String? _profilePhoto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<TableSessionProvider>();
      if (!session.loaded) await session.load();
      _syncOrderWatch();
      _refreshGuestHistoryFlag();
      _loadProfileName();
      _loadRates(session.restoId);
      // Kelompok level disusun tiap resto sendiri; tanpa dimuat lebih
      // dulu, dropdown pilihannya jatuh ke lima kelompok bawaan.
      if (session.restoId != null) primeLevelGroups(session.restoId!);
    });
  }

  /// Menu prices are shown inclusive of the resto's PPN, so the cart has
  /// to know the rates before it can price anything.
  Future<void> _loadRates(String? restoId) async {
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted || resto == null) return;
      context.read<CustomerCartProvider>()
          .setRates(ppn: resto.ppnPercent, service: resto.servicePercent);
    } catch (_) {
      // Offline — prices fall back to the stored originals.
    }
  }

  Future<void> _loadProfileName() async {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null) return;
    try {
      final profile = await CustomerProfileRepository().getOnce(email);
      if (!mounted || profile == null || profile.name.trim().isEmpty) return;
      setState(() {
        _profileName = profile.name.trim();
        _profilePhoto = profile.photoBase64;
      });
    } catch (_) {
      // Offline — the greeting falls back to the email's local part.
    }
  }

  /// Re-run from the per-build post-frame callback as well as initState,
  /// so the entry appears as soon as a guest's first order lands without
  /// needing this screen to be rebuilt from scratch. Only calls setState
  /// on an actual change — otherwise it would loop, since the callback
  /// fires on every build.
  Future<void> _refreshGuestHistoryFlag() async {
    final ids = await GuestOrderStore().ids();
    if (!mounted || ids.isNotEmpty == _hasGuestHistory) return;
    setState(() => _hasGuestHistory = ids.isNotEmpty);
  }

  /// (Re)subscribes to this session's orders so the auto-end timer stays
  /// accurate — called after load and whenever the session changes (e.g.
  /// right after scanning/resuming a table).
  void _syncOrderWatch() {
    final session = context.read<TableSessionProvider>();
    if (!session.hasActiveResto) {
      _orderWatch?.cancel();
      _orderWatch = null;
      _remoteActiveWatch?.cancel();
      _remoteActiveWatch = null;
      _watchedSessionId = null;
      _autoEndTimer?.cancel();
      return;
    }
    if (_watchedSessionId == session.sessionId) {
      return; // already watching this one
    }

    _orderWatch?.cancel();
    _remoteActiveWatch?.cancel();
    _watchedSessionId = session.sessionId;

    // Local fallback: while this screen is open, end the session 5 minutes
    // after everything's done — instant, no round trip needed.
    _orderWatch = OrderRepository().watchBySession(session.sessionId!).listen((orders) {
      final allDone =
          orders.isNotEmpty && orders.every((o) => o.kitchenStatus == KitchenStatus.done);
      _autoEndTimer?.cancel();
      if (allDone) {
        _autoEndTimer = Timer(_autoEndDelay, () {
          if (mounted) context.read<TableSessionProvider>().endSession();
        });
      }
    });

    // Backend backstop: the Cloud Function can end this session even if
    // the app was closed the whole time — this listener just makes sure
    // the UI catches up once we're back online/foregrounded.
    _remoteActiveWatch = SessionRepository().watchActive(session.sessionId!).listen((active) {
      if (!active && mounted) {
        context.read<TableSessionProvider>().applyRemoteEnded();
      }
    });
  }

  @override
  void dispose() {
    _orderWatch?.cancel();
    _remoteActiveWatch?.cancel();
    _produkSub?.cancel();
    _restoSub?.cancel();
    _autoEndTimer?.cancel();
    super.dispose();
  }

  bool _loggingIn = false;

  Future<void> _loginWithEmail() async {
    final auth = context.read<AuthProvider>();
    // This screen is only ever reached as a pushed route while browsing
    // as a guest. Once the login lands, RootScreen renders its own
    // CustomerHomeScreen underneath — so these survive the teardown and
    // let us clear the now-duplicate copy off the stack afterwards.
    final navigator = Navigator.of(context);
    final toast = AppToast.of(context);

    setState(() => _loggingIn = true);
    var claimed = 0;
    await withLoadingOverlay(context, () async {
      await auth.signInWithGoogle(intent: LoginIntent.customer);
      if (auth.isLoggedIn && !auth.isEmployee) {
        claimed = await claimGuestOrdersForLogin();
      }
    });

    if (auth.lastError != null) {
      if (mounted) setState(() => _loggingIn = false);
      toast.show(auth.lastError!, isError: true);
      return;
    }

    if (auth.isLoggedIn && !auth.isEmployee) {
      await ensureCustomerProfile(navigator, auth.user!.email!);
      toast.show(claimed > 0
          ? 'Login sebagai ${auth.user?.email}. $claimed riwayat pesanan dipindahkan ke akun ini.'
          : 'Login sebagai ${auth.user?.email}');
      // Drop this pushed copy so the one RootScreen now renders — the
      // customer hub — is what's actually on screen.
      if (navigator.mounted) navigator.popUntil((r) => r.isFirst);
      return;
    }

    // Left over: the account picker was dismissed. A staff email is no
    // longer a case that reaches here — AuthProvider refuses it and the
    // lastError branch above explains why.
    if (mounted) setState(() => _loggingIn = false);
  }

  /// Icons shown on both the "scan first" screen and the main ordering
  /// screen: a customer login (so their order history follows their
  /// email across restaurants/devices) plus the existing staff entry
  /// point. Registering as staff isn't required anywhere here — anyone
  /// who signs in and isn't found in the `employees` collection is just
  /// treated as a normal logged-in customer.
  List<Widget> _customerAppBarActions(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedInAsCustomer = auth.isLoggedIn && !auth.isEmployee;

    return [
      if (loggedInAsCustomer)
        IconButton(
          icon: const Icon(Icons.account_circle_outlined),
          tooltip: 'Profil Saya',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerProfileScreen(email: auth.user!.email!),
            ),
          ),
        ),
      if (loggedInAsCustomer)
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Riwayat Saya',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CustomerHistoryScreen()),
          ),
        )
      // Tombol login tidak ada di web.
      //
      // Web pelanggan sengaja hanya untuk yang tidak masuk akun: ia
      // dibuka dari kamera bawaan HP tanpa memasang apa pun, dan
      // gunanya satu — memesan dari meja yang barusan dipindai. Akun,
      // riwayat lintas merchant, dan voucher ada di aplikasinya.
      //
      // Menyediakan pintu masuk di sini berarti menjanjikan hal yang
      // tidak ada di baliknya: separuh isi akun tidak dibuatkan versi
      // webnya.
      else if (!kIsWeb)
        IconButton(
          icon: _loggingIn
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          tooltip: 'Login dengan Email',
          onPressed: _loggingIn ? null : _loginWithEmail,
        ),
      if (loggedInAsCustomer)
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout (${auth.user?.email})',
          onPressed: () async {
            if (!await confirmLogout(context)) return;
            if (!context.mounted) return;
            await auth.signOut();
            if (!context.mounted) return;
            // Logging out also ends the table session — resuming after
            // this always requires scanning the table QR again.
            await context.read<TableSessionProvider>().clear();
            if (!context.mounted) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
    ];
  }

  /// Returns to the "Scan QR Meja / Pilih Resto" chooser. That chooser is
  /// this same route rendered in its no-active-resto state, so getting
  /// back to it means dropping the resto session rather than popping.
  ///
  /// Confirms first when the cart has something in it — the cart is
  /// scoped to the current resto, so leaving necessarily discards it, and
  /// a stray back swipe shouldn't silently wipe an order in progress.
  Future<void> _backToChooser(BuildContext context) async {
    final cart = context.read<CustomerCartProvider>();

    if (cart.items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.remove_shopping_cart_outlined, size: 40, color: Colors.orange),
          title: const Text('Keluar dari merchant ini?'),
          content: const Text(
            'Keranjang belanja kamu akan dikosongkan.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            DialogActions(
              confirmLabel: 'Keluar',
              destructive: true,
              onConfirm: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;
    }

    cart.clear();
    // Land on the chooser, not all the way back at the hub — the nesting
    // is hub → chooser → ordering, so one back step is one level up.
    if (mounted) setState(() => _showChooser = true);
    await context.read<TableSessionProvider>().clear();
  }

  /// Only offered when this session started via "Pilih Resto" (not a QR
  /// scan — a scanned table is tied to one resto, switching wouldn't make
  /// sense there). Clears the cart (it's scoped to the old merchant's
  /// products) and the current resto/session, then lets them pick a new
  /// one from the list.
  Future<void> _switchResto(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ganti Merchant?'),
        content: const Text('Keranjang belanja kamu saat ini akan dikosongkan.'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Ganti Merchant',
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    context.read<CustomerCartProvider>().clear();
    await context.read<TableSessionProvider>().clear();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RestaurantListScreen()),
    );
  }

  /// Menaruh keranjang sebagai panel tetap di kanan pada layar lebar.
  ///
  /// Alasannya sama dengan di layar kasir: ruangnya ada, dan memaksa
  /// orang berpindah halaman untuk melihat apa yang sudah dipesan
  /// membuat mereka menghitungnya dari ingatan. Di HP tata letaknya
  /// tidak berubah sama sekali — di sana ruangnya memang tidak ada.
  ///
  /// Panelnya isi halaman keranjang yang sama, bukan salinannya. Dua
  /// tempat yang harus diingat berbarengan tiap kali aturan
  /// pembayarannya berubah akan berpisah, dan yang kedua selalu
  /// ketinggalan.
  Widget _denganKeranjangSamping(BuildContext context, Widget menu) {
    if (!Breakpoints.isWide(context)) return menu;
    return Row(
      children: [
        Expanded(child: menu),
        const VerticalDivider(width: 1),
        const SizedBox(
          width: kSideCartWidth,
          child: CustomerCartScreen(embedded: true),
        ),
      ],
    );
  }

  /// Menu yang belum ada di keranjang langsung membuka popup jumlah.
  /// Yang sudah ada membuka daftar barisnya, supaya jumlahnya bisa
  /// diubah atau dihapus tanpa harus maju dulu ke keranjang.
  Future<void> _onTapProduct(
    BuildContext context,
    CustomerCartProvider cart,
    Product product,
  ) async {
    if (cart.linesOf(product.id).isEmpty) {
      await _addLine(context, cart, product);
      return;
    }
    await _openLinesSheet(context, product);
  }

  Future<void> _addLine(
    BuildContext context,
    CustomerCartProvider cart,
    Product product,
  ) async {
    final result = await showDialogBesideCart<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: product,
        ppnPercent: cart.ppnPercent,
        stats: _meta.stats[product.id],
        sedangDiskon: _meta.diskonProductIds.contains(product.id),
        diskon: _meta.diskonUntuk(product.id),
        namaMenu: _namaMenu,
      ),
    );
    if (result == null) return;
    cart.addLine(
      product,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      selectedToppings: result.selectedToppings,
      notes: result.notes,
    );
  }

  Future<void> _editLine(
    BuildContext context,
    CustomerCartProvider cart,
    CartItem line,
  ) async {
    final result = await showDialogBesideCart<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: line.product,
        initialQuantity: line.quantity,
        initialLevels: line.selectedLevels,
        initialToppings: line.selectedToppings,
        initialNotes: line.notes,
        ppnPercent: cart.ppnPercent,
        editing: true,
        stats: _meta.stats[line.product.id],
        sedangDiskon: _meta.diskonProductIds.contains(line.product.id),
        diskon: _meta.diskonUntuk(line.product.id),
        namaMenu: _namaMenu,
      ),
    );
    if (result == null) return;
    cart.updateLine(
      line.lineId,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      selectedToppings: result.selectedToppings,
      notes: result.notes,
    );
  }

  Future<void> _openLinesSheet(BuildContext context, Product product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Consumer<CustomerCartProvider>(
        builder: (_, cart, __) {
          final lines = cart.linesOf(product.id);
          // Baris terakhir dihapus berarti tidak ada lagi yang bisa
          // diatur — menutup sendiri lebih baik daripada menyisakan
          // panel kosong.
          if (lines.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(sheetContext).canPop()) Navigator.of(sheetContext).pop();
            });
            return const SizedBox.shrink();
          }
          return ProductLinesSheet(
            product: product,
            lines: lines,
            unitPriceOf: (l) => cart.menuSubtotalOf(l) ~/ l.quantity,
            lineTotalOf: cart.menuSubtotalOf,
            onIncrement: cart.incrementLine,
            onDecrement: cart.decrementLine,
            onDelete: cart.removeLine,
            onEdit: (line) => _editLine(sheetContext, cart, line),
            onAddVariant: () {
              Navigator.pop(sheetContext);
              _addLine(context, cart, product);
            },
          );
        },
      ),
    );
  }

  String get _displayName {
    if (_profileName != null && _profileName!.isNotEmpty) return _profileName!;
    // No name saved yet (or still loading) — a warm stand-in reads far
    // better here than the email's local part, which is often something
    // like "abdul.p92" and makes the greeting feel machine-generated.
    return 'Sahabat MerchantPOS';
  }

  Widget _hubView(BuildContext context) {
    // Jam WIB, bukan jam perangkat: customer yang HP-nya masih di zona
    // lain akan disapa "makan malam" saat di sini baru sore.
    final greeting = greetingFor(DateTime.now().toWib());

    // This hub is a logged-in customer's home, the same way each role's
    // hub is for employees — so back exits the app rather than dropping
    // them onto the "Customer or Resto?" screen they've already moved
    // past. Employee hubs get this for free by being the root route;
    // this one is pushed, so it has to say so explicitly.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: MerchantPosTheme.backgroundOf(context),
        // Mengambang di beranda, bukan jadi satu tombol lagi di daftar.
        // Yang mencarinya sedang kesulitan, dan orang yang sedang
        // kesulitan tidak menggulir daftar menu mencari jalan mengadu.
        floatingActionButton: const SupportFab(),
        // Header stays put; only the menu scrolls — matching the
        // employee hubs.
        body: Column(
          children: [
            HubHeader(
              logo: _CustomerAvatar(photoBase64: _profilePhoto),
              title: 'Hi, $_displayName!',
              subtitle: greeting,
              colorA: MerchantPosTheme.brand,
              colorB: MerchantPosTheme.brandDark,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Menu',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                  const SizedBox(height: 10),
                  HubMenuTile(
                    icon: Icons.restaurant_menu,
                    title: 'Pesan',
                    subtitle: 'Scan QR meja atau pilih merchant',
                    color: const Color(0xFF10B981),
                    onTap: () => setState(() => _showChooser = true),
                  ),
                  const SizedBox(height: 12),
                  HubMenuTile(
                    icon: Icons.account_circle_outlined,
                    title: 'Profil',
                    subtitle: 'Nama, nomor HP, dan foto kamu',
                    color: const Color(0xFF6366F1),
                    onTap: () async {
                      final email = context.read<AuthProvider>().user!.email!;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CustomerProfileScreen(email: email),
                        ),
                      );
                      // They may have just changed their name — refresh so
                      // the greeting doesn't keep showing the old one.
                      _loadProfileName();
                    },
                  ),
                  const SizedBox(height: 12),
                  HubMenuTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'Riwayat',
                    subtitle: 'Semua pesanan kamu sebelumnya',
                    color: const Color(0xFFF59E0B),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CustomerHistoryScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  HubMenuTile(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Voucher Saya',
                    subtitle: 'Tebus kode voucher & lihat yang siap dipakai',
                    color: const Color(0xFFF59E0B),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MyVouchersScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  const InboxTile(forCustomer: true),
                  const SizedBox(height: 12),
                  // Tampilan diatur dari menu utama, bukan dari bilah
                  // atas layar menu resto. Yang sedang memilih makanan
                  // tidak sedang memikirkan tema aplikasinya — dan
                  // tombol di sana cuma menambah barang di bilah yang
                  // sudah penuh.
                  HubMenuTile(
                    icon: Icons.brightness_6_outlined,
                    title: 'Tampilan',
                    subtitle: 'Mode terang, gelap, atau ikut setelan HP',
                    color: const Color(0xFF0EA5E9),
                    onTap: () => showAppearanceDialog(context),
                  ),
                  // Tombol tes notifikasi disembunyikan: push-nya sudah
                  // berjalan, dan tombol uji yang tertinggal di layar
                  // pemakai akhirnya ditekan seseorang yang mengira itu
                  // fitur.
                  //
                  // Jaraknya cuma satu, bukan dua. Saat tilenya dibuang,
                  // kedua SizedBox pengapitnya sempat tertinggal — dan
                  // celah 24 di antara barisan yang semuanya berjarak 12
                  // terbaca seperti ada sesuatu yang gagal dimuat di
                  // situ.
                  const SizedBox(height: 12),
                  HubMenuTile(
                    icon: Icons.logout,
                    title: 'Keluar',
                    subtitle: 'Logout dari akun ini',
                    color: const Color(0xFFEF4444),
                    onTap: () async {
                      if (!await confirmLogout(context)) return;
                      if (!context.mounted) return;
                      await context.read<AuthProvider>().signOut();
                      if (!context.mounted) return;
                      await context.read<TableSessionProvider>().clear();
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Menyiapkan stream sekali untuk sebuah resto, dan membuatnya ulang
  /// hanya kalau restonya benar-benar berganti.
  void _siapkanStream(String restoId) {
    if (_streamRestoId == restoId && _produkSub != null) return;
    _streamRestoId = restoId;
    _produkSub?.cancel();
    _restoSub?.cancel();
    _produk = null;
    _restoInfo = null;
    _galatProduk = null;
    // Ikut dibuang saat restonya berganti. Bintang dan label milik
    // merchant sebelumnya yang masih menempel di menu merchant baru
    // adalah keterangan yang salah, bukan keterangan yang basi.
    _meta = MenuMeta.kosong;
    _metaTerakhir = null;
    _segarkanMeta(restoId);

    _produkSub = _productRepo.watchAll(restoId).listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _produk = items;
          _galatProduk = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _galatProduk = e);
      },
    );

    _restoSub = _restoInfoRepo.watch(restoId).listen((r) {
      if (!mounted) return;
      setState(() => _restoInfo = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<TableSessionProvider>();
    final auth = context.watch<AuthProvider>();
    // Once logged in, this screen is the customer's "home" — back
    // navigation is blocked so they can't fall back to the role-choice
    // page by accident; logging out is the only way there.
    final loggedInAsCustomer = auth.isLoggedIn && !auth.isEmployee;

    if (!session.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Keep the auto-end watcher in sync with whichever session is active
    // right now (a no-op if it's already watching this sessionId).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOrderWatch();
      _refreshGuestHistoryFlag();
    });

    // Logged-in customers get the same hub treatment as every employee
    // role; the chooser sits one level in, behind "Pesan".
    if (!session.hasActiveResto && loggedInAsCustomer && !_showChooser) {
      return _hubView(context);
    }

    if (!session.hasActiveResto) {
      return PopScope(
        // Coming from the hub, back returns there rather than leaving.
        canPop: !loggedInAsCustomer,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && loggedInAsCustomer) setState(() => _showChooser = false);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: loggedInAsCustomer
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Kembali',
                    onPressed: () => setState(() => _showChooser = false),
                  )
                : null,
            title: Text(loggedInAsCustomer ? 'Mau Pesan Di Mana?' : 'MerchantPOS (Customer)'),
            actions: loggedInAsCustomer ? null : _customerAppBarActions(context),
          ),
          body: Column(
            children: [
              // Hanya untuk tamu.
              //
              // Tamu tidak punya kotak masuk, jadi inilah satu-satunya
              // jalan pemberitahuan versi baru sampai ke mereka. Yang
              // sudah masuk punya kotak masuknya sendiri — menampilkan
              // spanduk yang sama di sini berarti kabar yang sama
              // ditawarkan dua kali di dua tempat, dan yang kedua
              // muncul justru di layar tempat orang sedang memilih mau
              // makan di mana.
              if (!loggedInAsCustomer)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: kIsWeb ? SizedBox.shrink() : UpdateBanner(),
                ),
              Expanded(
                child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner, size: 72, color: Colors.indigo),
                const SizedBox(height: 16),
                const Text(
                  'Scan QR code di meja kamu, atau pilih merchant dulu untuk mulai pesan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScanTableScreen()),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Meja'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RestaurantListScreen()),
                  ),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Pilih Merchant'),
                ),
                // Guests can only reach their history from here — once
                // they're inside a merchant the app bar's history action is
                // login-only, and this chooser is the one screen that
                // exists before any resto is picked.
                if (!loggedInAsCustomer && _hasGuestHistory) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CustomerHistoryScreen()),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Riwayat Pesanan Saya'),
                  ),
                ],
              ],
            ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sesudah titik ini restonya sudah pasti terpilih, jadi streamnya
    // aman disiapkan — dan hanya dibuat ulang kalau restonya berganti.
    _siapkanStream(session.restoId!);
    // Dipanggil dari build, jadi ikut berjalan tiap kali orangnya
    // kembali ke layar ini — dan itu persis saat bintang yang barusan
    // diberikannya perlu muncul.
    _segarkanMeta(session.restoId!);

    // The chooser and this menu are the same route — which one shows
    // depends on hasActiveResto — so "back" here can't pop to the chooser,
    // it has to drop the resto session and let this screen rebuild into
    // it. Same for guests and logged-in customers alike.
    // Pelanggan web yang datang dari QR meja tidak punya "kembali".
    //
    // Tombol itu mengakhiri sesi restonya lalu membangun ulang layar ini
    // jadi pemilih merchant. Di aplikasi itu masuk akal — pemilihnya
    // ada, dan QR-nya bisa dipindai lagi dari sana. Di web pemilih itu
    // tidak ada: yang tersisa cuma halaman masuk merchant, dan satu-
    // satunya jalan kembali ke mejanya adalah memindai ulang QR yang
    // barangkali sudah tidak ada di depannya.
    //
    // Jadi yang ditekan sekali karena mengira akan mundur satu langkah
    // justru kehilangan keranjangnya sekaligus jalan pulangnya.
    final tanpaKembali = kIsWeb && session.enteredViaQr;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !tanpaKembali) _backToChooser(context);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: tanpaKembali
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Kembali',
                  onPressed: () => _backToChooser(context),
                ),
          title: Text(
            session.tableNumber != null ? 'Meja ${session.tableNumber}' : 'MerchantPOS (Customer)',
          ),
          actions: [
            if (!session.enteredViaQr)
              IconButton(
                icon: const Icon(Icons.storefront_outlined),
                tooltip: 'Ganti Merchant',
                onPressed: () => _switchResto(context),
              ),
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Pesanan Saya',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomerOrderStatusScreen()),
              ),
            ),
            // Profil, Riwayat and Logout deliberately aren't here: for a
            // logged-in customer they already sit on the hub this screen
            // was opened from, and repeating them crowded the bar. Guests
            // still get the login button, which has no other home.
            if (!loggedInAsCustomer) ..._customerAppBarActions(context),
          ],
        ),
        body: _denganKeranjangSamping(
          context,
          Column(
          children: [
            Builder(
              builder: (context) {
                final resto = _restoInfo;
                if (resto == null) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  color: MerchantPosTheme.tintOf(context, Colors.indigo),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(resto.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (resto.address.isNotEmpty)
                        Text(resto.address,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      // Hanya muncul kalau restonya sudah menyimpan
                      // titik lokasi — tombol peta yang membuka
                      // koordinat kosong lebih buruk daripada tidak ada
                      // tombol sama sekali.
                      if (resto.hasLocation)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.directions_outlined, size: 16),
                            label: const Text('Buka di Google Maps'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => openInMaps(
                              resto.latitude!,
                              resto.longitude!,
                              label: resto.name,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_galatProduk != null) {
                    return Center(
                      child: Text('Gagal memuat produk.\n$_galatProduk',
                          textAlign: TextAlign.center),
                    );
                  }
                  if (_produk == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final products = _produk!;
                  if (products.isEmpty) {
                    return const Center(child: Text('Belum ada produk tersedia.'));
                  }
                  return Consumer<CustomerCartProvider>(
                    builder: (context, cart, _) {
                      return ProductCategoryList(
                        products: products,
                        quantityOf: cart.quantityOf,
                        ppnPercent: cart.ppnPercent,
                        onTapProduct: (p) => _onTapProduct(context, cart, p),
                        diskonProductIds: _meta.diskonProductIds,
                        stats: _meta.stats,
                        // Ikut tergulir bersama menunya, bukan diam di
                        // atasnya.
                        header: PromoBannerCarousel(restoId: session.restoId!),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        ),
        // Di layar lebar keranjangnya sudah berdiri di kanan, jadi bar
        // bawah cuma menawarkan jalan ke tempat yang sedang terbuka.
        bottomNavigationBar: Breakpoints.isWide(context)
            ? null
            : Consumer<CustomerCartProvider>(
                builder: (context, cart, _) {
                  return CartBottomBar(
                    itemCount: cart.itemCount,
                    total: cart.total,
                    actionLabel: 'Keranjang',
                    actionIcon: Icons.shopping_cart_outlined,
                    onPressed: cart.items.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const CustomerCartScreen()),
                            ),
                  );
                },
              ),
      ),
    );
  }
}

/// Foto profil customer di header hub, dengan logo MerchantPOS sebagai
/// penggantinya selama belum ada foto — termasuk kalau data fotonya
/// ternyata rusak, karena gagal menggambar di sini akan mengosongkan
/// seluruh header.
class _CustomerAvatar extends StatelessWidget {
  final String? photoBase64;

  const _CustomerAvatar({required this.photoBase64});

  @override
  Widget build(BuildContext context) {
    final photo = photoBase64;
    if (photo == null || photo.isEmpty) return const MerchantPosLogo(size: 64);

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.memory(
        base64Decode(photo),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const MerchantPosLogo(size: 64),
      ),
    );
  }
}
