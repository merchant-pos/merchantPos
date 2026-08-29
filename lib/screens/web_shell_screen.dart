import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../versi_web.dart';
import '../utils/logout_confirm.dart';
import '../widgets/merchantpos_logo.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/resto_switcher.dart';
import '../widgets/notification_test_tile.dart';
import '../widgets/support_fab.dart';
import 'web_menu.dart';

/// Kerangka versi web: menu di sidebar, isinya di sebelah kanan.
///
/// Bentuk beranda ponsel tidak dipindahkan apa adanya ke layar lebar.
/// Di ponsel, menu ditumpuk di balik kelompok karena layarnya sempit dan
/// tiap ketukan mahal. Di layar 1400 piksel, tumpukan yang sama justru
/// menyembunyikan hal yang sebenarnya muat ditampilkan seluruhnya — dan
/// memaksa orang mengetuk dua kali untuk sampai ke tempat yang bisa
/// terlihat sejak awal.
///
/// Isinya tetap layar yang sama persis dengan versi ponselnya. Tidak ada
/// satu pun layar yang ditulis ulang untuk web: dua salinan dari layar
/// yang sama akan berpisah pada perbaikan berikutnya, dan yang tertinggal
/// adalah yang lebih jarang dibuka.
class WebShellScreen extends StatefulWidget {
  const WebShellScreen({super.key});

  @override
  State<WebShellScreen> createState() => _WebShellScreenState();
}

class _WebShellScreenState extends State<WebShellScreen> {
  int _terpilih = 0;

  /// Lebar minimal supaya sidebar dan isinya sama-sama layak.
  ///
  /// Di bawah ini — jendela yang disempitkan, atau tablet yang diputar —
  /// sidebarnya berubah jadi laci yang ditarik dari tepi. Sidebar tetap
  /// selebar 260 piksel pada jendela 800 piksel menyisakan ruang isi
  /// yang lebih sempit daripada ponsel.
  static const _lebarMinimal = 1000.0;
  static const _lebarSidebar = 260.0;

  /// Tombol mengambang Merchant-POS Support — hanya untuk sisi merchant.
  ///
  /// Di versi HP tombol ini menempel di beranda tiap peran merchant,
  /// dan beranda itu tidak dipakai sama sekali di web. Tanpa dipasang
  /// di kerangkanya, pegawai merchant yang bekerja dari konsol tidak
  /// punya satu pun jalan untuk mengadu atau bertanya.
  ///
  /// Merchant-POS Admin tidak mendapatkannya. Dia berada di sisi seberang
  /// percakapan yang sama — yang dibukanya lewat menu Customer Service
  /// — dan tombol mengadu di layarnya sendiri hanya membuat dia bisa
  /// membuat tiket yang ujungnya dia jawab sendiri.
  ///
  /// Digeser ke atas karena layar di sebelahnya membawa tombol
  /// mengambangnya sendiri, dan keduanya berebut sudut yang sama:
  /// tanpa jarak ini yang satu menutupi yang lain, dan yang tertutup
  /// tampak seperti hilang.
  Widget? _support(AuthProvider auth) {
    if (auth.isSuperAdmin) return null;
    return const Padding(
      padding: EdgeInsets.only(bottom: 72),
      child: SupportFab(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tujuan = menuWebUntuk(auth);
    final menu = [if (tujuan.isNotEmpty) menuBerandaWeb, ...tujuan];

    if (menu.isEmpty) {
      // Tidak seharusnya sampai ke sini — RootScreen sudah menyaringnya.
      return const Scaffold(
        body: Center(child: Text('Peran ini belum punya versi web.')),
      );
    }

    final terpilih = _terpilih.clamp(0, menu.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final lebar = constraints.maxWidth >= _lebarMinimal;
        final isi = KeyedSubtree(
          // Kunci per tujuan DAN per merchant.
          //
          // Tanpa kunci, berpindah menu memakai ulang State layar
          // sebelumnya kalau jenis widgetnya kebetulan sama. Tanpa
          // restoId di dalamnya, berpindah cabang meninggalkan data
          // cabang lama di layar yang sudah terlanjur memuatnya.
          key: ValueKey('${menu[terpilih].judul}|${auth.restoId}'),
          child: terpilih == 0
              ? _Beranda(
                  menu: menu,
                  onPilih: (i) => setState(() => _terpilih = i),
                )
              : menu[terpilih].layar(),
        );

        if (!lebar) {
          return Scaffold(
            floatingActionButton: _support(auth),
            appBar: AppBar(title: Text(menu[terpilih].judul)),
            drawer: Drawer(
              child: _Sidebar(
                menu: menu,
                terpilih: terpilih,
                onPilih: (i) {
                  setState(() => _terpilih = i);
                  Navigator.pop(context);
                },
              ),
            ),
            body: isi,
          );
        }

        return Scaffold(
          floatingActionButton: _support(auth),
          body: Row(
            children: [
              SizedBox(
                width: _lebarSidebar,
                child: Material(
                  color: MerchantPosTheme.surfaceOf(context),
                  child: _Sidebar(
                    menu: menu,
                    terpilih: terpilih,
                    onPilih: (i) => setState(() => _terpilih = i),
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: MerchantPosTheme.borderOf(context)),
              // Layar yang dipilih membawa AppBar-nya sendiri. Itu
              // disengaja: judul, tombol, dan tab yang sudah ada di
              // versi ponselnya tetap berada di tempat yang sama.
              Expanded(child: isi),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<MenuWeb> menu;
  final int terpilih;
  final ValueChanged<int> onPilih;

  const _Sidebar({
    required this.menu,
    required this.terpilih,
    required this.onPilih,
  });

  /// Menanyakan dulu, lalu benar-benar keluar.
  ///
  /// [confirmLogout] hanya memunculkan dialognya dan mengembalikan
  /// jawabannya — ia tidak mengeluarkan siapa pun. Memanggilnya saja,
  /// tanpa membaca jawabannya, menghasilkan tombol yang terlihat
  /// bekerja: dialognya muncul, "Keluar" bisa ditekan, dialognya
  /// menutup, dan sesinya utuh seperti semula.
  Future<void> _keluar(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final muted = MerchantPosTheme.mutedOf(context);
    final nama = auth.employeeName?.trim();

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [MerchantPosTheme.brand, MerchantPosTheme.brandDark],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MerchantPosLogo(size: 34),
              const SizedBox(height: 10),
              Text(
                (nama == null || nama.isEmpty) ? 'Merchant-POS' : nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${auth.roleLabel ?? ''} • ${auth.user?.email ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const RestoSwitcher(),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: menu.length,
            itemBuilder: (context, i) {
              final m = menu[i];
              final aktif = i == terpilih;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.kelompok != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(18, i == 0 ? 10 : 18, 18, 6),
                      child: Text(
                        m.kelompok!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: muted,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 1),
                    child: Material(
                      color: aktif
                          ? MerchantPosTheme.brand.withOpacity(0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        // Sorotan fokus dimatikan, sorotan tunjuk
                        // dibedakan.
                        //
                        // Sesudah satu menu diketuk, fokus papan ketik
                        // mendarat di baris pertama sidebar dan Material
                        // melukiskan focusColor abu-abunya di sana — dan
                        // baris yang tersorot abu di antara baris polos
                        // terbaca sebagai "yang sedang dibuka", padahal
                        // yang sedang dibuka baris lain. Dua baris tampak
                        // aktif sekaligus, dan yang benar justru yang
                        // sorotannya lebih samar.
                        focusColor: Colors.transparent,
                        hoverColor: MerchantPosTheme.brand.withOpacity(0.06),
                        onTap: () => onPilih(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                m.ikon,
                                size: 18,
                                color: aktif
                                    ? MerchantPosTheme.brandOf(context)
                                    : muted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  m.judul,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: aktif
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: aktif
                                        ? MerchantPosTheme.brandOf(context)
                                        : MerchantPosTheme.textOf(context),
                                  ),
                                ),
                              ),
                              if (m.belumDibaca != null)
                                _PenandaMenu(
                                    hitung: m.belumDibaca!, auth: auth),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: MerchantPosTheme.borderOf(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                const AppearanceIconButton(),
                // Satu-satunya cara memastikan perangkat ini benar
                // terdaftar. Notifikasi yang tidak datang selalu
                // terlihat sama saja dari luar — izin ditolak, token
                // tidak terbit, atau token terbit tapi gagal disimpan —
                // dan tanpa alat ini ketiganya cuma bisa ditebak.
                IconButton(
                  icon: const Icon(Icons.notifications_active_outlined,
                      size: 18),
                  tooltip: 'Tes Notifikasi',
                  color: MerchantPosTheme.mutedOf(context),
                  onPressed: () => showNotificationTest(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _keluar(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Keluar'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            labelVersiWeb,
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
        ),
      ],
    );
  }
}

/// Halaman pertama konsol: pintasan ke seluruh menu perannya.
///
/// Dikelompokkan persis seperti sidebarnya. Dua susunan berbeda untuk
/// daftar yang sama memaksa orang belajar dua kali, dan yang dipelajari
/// belakangan biasanya menang — jadi sidebar yang dipakai sehari-hari
/// justru jadi yang terasa asing.
class _Beranda extends StatelessWidget {
  final List<MenuWeb> menu;
  final ValueChanged<int> onPilih;

  const _Beranda({required this.menu, required this.onPilih});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final nama = auth.employeeName?.trim();
    final muted = MerchantPosTheme.mutedOf(context);

    // Indeksnya dibawa serta, karena itulah yang dipakai memindahkan
    // pilihan sidebar. Menyaring dulu lalu mencari indeksnya kemudian
    // akan menunjuk baris yang salah begitu ada dua menu bernama sama.
    final isi = <(int, MenuWeb)>[
      for (var i = 1; i < menu.length; i++) (i, menu[i]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Beranda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Text(
            (nama == null || nama.isEmpty) ? 'Selamat datang' : 'Halo, $nama',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Pilih yang mau dibuka. Semuanya juga ada di sebelah kiri.',
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < isi.length; i++) ...[
            if (isi[i].$2.kelompok != null) ...[
              if (i > 0) const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  isi[i].$2.kelompok!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: muted,
                  ),
                ),
              ),
            ],
            if (isi[i].$2.kelompok != null)
              _BarisKartu(
                // Sekelompok sampai judul kelompok berikutnya.
                kartu: [
                  for (var j = i;
                      j < isi.length && (j == i || isi[j].$2.kelompok == null);
                      j++)
                    isi[j],
                ],
                onPilih: onPilih,
              ),
          ],
        ],
      ),
    );
  }
}

class _BarisKartu extends StatelessWidget {
  final List<(int, MenuWeb)> kartu;
  final ValueChanged<int> onPilih;

  const _BarisKartu({required this.kartu, required this.onPilih});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return LayoutBuilder(
      builder: (context, c) {
        const jarak = 12.0;
        const lebarMinimal = 240.0;
        final kolom =
            ((c.maxWidth + jarak) / (lebarMinimal + jarak)).floor().clamp(1, 5);
        final lebar = (c.maxWidth - jarak * (kolom - 1)) / kolom;

        return Wrap(
          spacing: jarak,
          runSpacing: jarak,
          children: [
            for (final (indeks, m) in kartu)
              SizedBox(
                width: lebar,
                child: Material(
                  color: MerchantPosTheme.surfaceOf(context),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onPilih(indeks),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: MerchantPosTheme.borderOf(context)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: MerchantPosTheme.brandTintOf(context),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(m.ikon,
                                size: 19,
                                color: MerchantPosTheme.onBrandTintOf(context)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              m.judul,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (m.belumDibaca != null)
                            _PenandaMenu(hitung: m.belumDibaca!, auth: auth),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Angka merah kecil di kanan baris sidebar.
///
/// Dihitung ulang berkala, bukan sekali saat sidebarnya dibangun.
/// Sidebar tidak pernah dibangun ulang sendiri selama orangnya berada
/// di satu menu yang sama — dan justru selama itulah pesan baru
/// berdatangan.
class _PenandaMenu extends StatefulWidget {
  final Stream<int> Function(AuthProvider auth) hitung;
  final AuthProvider auth;

  const _PenandaMenu({required this.hitung, required this.auth});

  @override
  State<_PenandaMenu> createState() => _PenandaMenuState();
}

class _PenandaMenuState extends State<_PenandaMenu> {
  late final Stream<int> _aliran;

  @override
  void initState() {
    super.initState();
    // Dibuat sekali di sini, bukan di build: aliran baru tiap kali
    // sidebarnya dibangun ulang berarti langganan baru tiap kali, dan
    // yang lama tidak pernah ditutup.
    _aliran = widget.hitung(widget.auth);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _aliran,
      builder: (context, snap) => _angka(context, snap.data ?? 0),
    );
  }

  Widget _angka(BuildContext context, int jumlah) {
    if (jumlah <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$jumlah',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
      ),
    );
  }
}
