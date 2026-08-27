import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Versi web hanya untuk peran meja kerja.
///
/// Kasir dan Chef bekerja sambil berdiri, di depan antrean, dengan satu
/// tangan memegang perangkat — dan tidak ada satu pun bagian
/// pekerjaannya yang lebih mudah dengan tetikus. Pelanggan butuh kamera
/// untuk memindai QR mejanya.
void main() {
  final menu = File('lib/screens/web_menu.dart').readAsStringSync();
  final shell = File('lib/screens/web_shell_screen.dart').readAsStringSync();
  final root = File('lib/screens/root_screen.dart').readAsStringSync();

  group('siapa yang punya versi web', () {
    test('empat peran meja kerja, bukan lebih', () {
      final fungsi = menu.substring(menu.indexOf('List<MenuWeb> menuWebUntuk'));
      final badan = fungsi.substring(0, fungsi.indexOf('}'));
      for (final p in ['isSuperAdmin', 'isOwner', 'isAdmin', 'isFinance']) {
        expect(badan, contains(p), reason: '$p belum punya menunya');
      }
      expect(badan, isNot(contains('isKasir')));
      expect(badan, isNot(contains('isChef')));
    });

    test('peran tanpa menu tidak masuk kerangka web', () {
      expect(menu, contains('bool punyaVersiWeb('));
      expect(root, contains('if (kIsWeb && punyaVersiWeb(auth))'));
    });

    // Gerbang langganan berlaku sama di web maupun ponsel. Merchant
    // menunggak yang membuka konsol web tidak boleh menemukan pintu
    // belakang yang tidak ada di ponselnya.
    test('gerbang langganan tetap dipasang, kecuali untuk MerchantPOS Admin', () {
      expect(root, contains('auth.isSuperAdmin ? shell : BillingGate(child: shell)'));
    });
  });

  group('kerangkanya', () {
    // Dua salinan dari layar yang sama akan berpisah pada perbaikan
    // berikutnya, dan yang tertinggal adalah yang lebih jarang dibuka.
    test('memakai layar yang sama dengan versi ponsel', () {
      expect(shell, contains('menu[terpilih].layar()'));
      // Tidak ada layar ber-akhiran _web yang ditulis khusus.
      final layarWeb = Directory('lib/screens')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_web_screen.dart'));
      expect(layarWeb, isEmpty);
    });

    // Sidebar selebar 260 piksel pada jendela 800 piksel menyisakan
    // ruang isi yang lebih sempit daripada ponsel.
    test('jendela sempit memakai laci, bukan sidebar tetap', () {
      expect(shell, contains('_lebarMinimal = 1000.0'));
      expect(shell, contains('drawer: Drawer('));
    });

    test('berpindah merchant membangun ulang layarnya', () {
      expect(shell, contains(r"ValueKey('${menu[terpilih].judul}|${auth.restoId}')"));
    });
  });

  group('login di web', () {
    final auth = File('lib/providers/auth_provider.dart').readAsStringSync();

    // Di web google_sign_in hanya mengembalikan access token; ID token
    // yang dibutuhkan signInWithIdToken tidak pernah ada.
    test('memakai pengalihan Supabase, bukan signInWithIdToken', () {
      expect(auth, contains('if (kIsWeb) {\n        await _mulaiLoginWeb(intent);'));
      expect(auth, contains('_supabase.auth.signInWithOAuth('));
      expect(auth, contains('redirectTo: _alamatKembali()'));
    });

    // Di GitHub Pages aplikasinya tinggal di .../MerchantPOS/, dan origin
    // saja menunjuk ke akar domain — tempat aplikasi ini tidak ada.
    test('alamat kembalinya membawa jalur, bukan origin saja', () {
      expect(auth, isNot(contains('redirectTo: Uri.base.origin')));
      expect(auth, contains("Uri.base.replace(query: '', fragment: '')"));
    });

    // Halamannya benar-benar ditinggalkan, jadi pemeriksaan pintu masuk
    // tidak bisa menunggu di fungsi yang memanggilnya.
    test('pintu masuknya dititipkan melewati pengalihan', () {
      expect(auth, contains('prefs.setString(_kunciNiatTertunda, intent.name)'));
      expect(auth, contains('if (current != null && niat != null)'));
      expect(auth, contains('await _terimaSesi(current, niat)'));
    });

    // Niat yang tertinggal akan menagih pemeriksaan lagi pada pembukaan
    // berikutnya, dan sesi yang sah bisa ikut dibuang.
    test('titipan niatnya dihapus begitu dibaca', () {
      expect(auth, contains('await prefs.remove(_kunciNiatTertunda)'));
    });

    // Pemeriksaan pintunya harus tetap satu perilaku, bukan dua salinan
    // yang bisa berpisah antara ponsel dan web.
    test('ponsel dan web memakai pemeriksaan yang sama', () {
      expect('_terimaSesi('.allMatches(auth).length, greaterThanOrEqualTo(3));
      expect(auth, contains('belum terdaftar sebagai karyawan merchant'));
      expect('belum terdaftar sebagai karyawan merchant'.allMatches(auth).length, 1);
    });

    test('signOut plugin Google tidak dipanggil di web', () {
      expect(auth, isNot(contains('    await _googleSignIn.signOut();')));
      expect('if (!kIsWeb) await _googleSignIn.signOut();'.allMatches(auth).length, 2);
    });
  });

  // Salinan lokal di web tersimpan di IndexedDB satu peramban di satu
  // perangkat. Kalau dipakai, produk yang dibuat di HP tidak akan pernah
  // muncul di web dan sebaliknya — dua katalog yang mengaku sama.
  group('datanya sama dengan versi HP', () {
    for (final f in ['product_provider', 'category_provider']) {
      final isi = File('lib/providers/$f.dart').readAsStringSync();

      test('$f: di web membaca Supabase, bukan basis data lokal', () {
        expect(isi, contains('bool get _tanpaSalinanLokal => kIsWeb;'));
        final muat = isi.substring(isi.indexOf('Future<void> load() async {'));
        expect(muat.substring(0, muat.indexOf('_repo.getAll')),
            contains('getAllOnce'));
      });

      test('$f: tulisannya juga langsung ke Supabase, dan ditunggu', () {
        // Di HP penulisan lokalnya berhasil lebih dulu, jadi kiriman yang
        // gagal cuma tertunda. Di web tidak ada yang berhasil lebih dulu —
        // kiriman yang gagal berarti datanya tidak pernah ada, dan
        // .catchError((_) {}) akan menelan kegagalan itu diam-diam.
        for (final potong in isi.split('if (_tanpaSalinanLokal) {').skip(1)) {
          final cabang = potong.substring(0, potong.indexOf('    }'));
          expect(cabang, isNot(contains('catchError')),
              reason: 'cabang web menelan kegagalan: $cabang');
          expect(cabang, isNot(contains('_repo.insert')));
          expect(cabang, isNot(contains('_repo.delete')));
          expect(cabang, isNot(contains('_repo.update')));
        }
      });
    }

    // sqflite tetap bisa dibuka di web sebagai jaring pengaman, tapi
    // tidak boleh jadi jalan yang dipakai katalog.
    test('sqflite di web hanya jaring pengaman', () {
      final isi = File('lib/db/database_helper.dart').readAsStringSync();
      expect(isi, contains('databaseFactory = databaseFactoryFfiWeb'));
      expect(File('web/sqflite_sw.js').existsSync(), isTrue);
      expect(File('web/sqlite3.wasm').existsSync(), isTrue);
    });
  });

  // Web ini konsol backoffice yang dibuka dari PC, bukan aplikasi
  // sehalaman penuh di genggaman.
  group('tampilannya disesuaikan layar lebar', () {
    final login = File('lib/screens/role_choice_screen.dart').readAsStringSync();
    final tema = File('lib/widgets/language_theme_toggle.dart').readAsStringSync();
    final utama = File('lib/main.dart').readAsStringSync();

    test('halaman masuk hanya menawarkan Merchant', () {
      expect(login, contains('bool get _hanyaMerchant => kIsWeb;'));
      expect(login, contains("if (!_hanyaMerchant) ..."));
    });

    test('nomor versi tidak ditampilkan, dan tidak pula dibaca', () {
      expect(login, contains('if (!_hanyaMerchant && _versionLabel.isNotEmpty)'));
      // Dibaca lewat PackageInfo — memanggilnya di web sia-sia.
      expect(login, contains('if (_hanyaMerchant) return;'));
    });

    // Tombol selebar jendela 1600 piksel bukan tombol lagi, itu pita.
    test('lebar isinya dibatasi lalu ditaruh di tengah', () {
      expect(login, contains('BoxConstraints(maxWidth: 420)'));
    });

    test('temanya hanya Terang dan Gelap', () {
      expect(tema, contains('kIsWeb ? _pilihan.sublist(0, 2) : _pilihan'));
      // Setelan lama bisa saja masih "Ikuti HP" — kalau tidak
      // diterjemahkan, tidak ada satu pun tombol yang menyala.
      expect(tema, contains('kIsWeb && prefs.themeMode == ThemeMode.system'));
    });

    // Popup dengan insetPadding 24 di layar 1600 piksel jadi selebar
    // 1552 piksel — bukan popup, tapi halaman bersudut bulat.
    test('lebar popup dibatasi sekali untuk seluruh aplikasi', () {
      expect(utama, contains('insetPadding: insetDialogWeb(context)'));
      expect(utama, contains('if (!kIsWeb) return child;'));
    });

    // Popup di tengah jendela tinggi memaksa mata berpindah jauh dari
    // tempat yang barusan diketuk, dan popup berisi panjang memanjang
    // ke dua arah sekaligus.
    test('popup menempel ke atas, bukan melayang di tengah', () {
      expect(utama, contains('alignment: Alignment.topCenter'));
    });

    // Membentang tepi ke tepi jendela lebar, satu kalimat pendek jadi
    // pita setipis garis yang isinya menempel di ujung kiri.
    test('pesan sekilas dibatasi lebarnya di web', () {
      final toast = File('lib/widgets/app_toast.dart').readAsStringSync();
      expect(toast, contains('kIsWeb ? Alignment.bottomCenter'));
      expect(toast, contains('maxWidth: kIsWeb ? kLebarDialogWeb'));
    });

    // Baris `actions` milik AlertDialog melipat jadi kolom begitu
    // labelnya tidak muat, dan urutannya mengikuti daftar — Batal jadi
    // berdiri di atas hal yang justru didatangi orangnya.
    test('tombol batal di bawah, bukan di atas', () {
      final billing =
          File('lib/screens/super_admin_billing_screen.dart').readAsStringSync();
      expect(billing, contains('DialogActions('));
      expect(billing, isNot(contains("child: const Text('Batal')")));
    });

    // Nilai di tempat pemakaian selalu menang atas nilai tema, jadi
    // satu pun yang tertinggal akan tetap melar.
    test('tidak ada lagi popup yang mematok jarak tepinya sendiri', () {
      final nakal = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('lebar_web.dart'))) {
        final isi = f.readAsStringSync();
        for (final m in RegExp(r'insetPadding: const ').allMatches(isi)) {
          final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
          nakal.add('${f.path}:$baris');
        }
      }
      expect(nakal, isEmpty, reason: nakal.join(', '));
    });

    // Kotaknya setinggi 160 piksel dan selebar isi; tanpa batas lebar
    // gambarnya terpotong jadi segaris tipis oleh BoxFit.cover.
    test('formulir produk tidak membuat fotonya gepeng', () {
      final form = File('lib/screens/product_form_screen.dart').readAsStringSync();
      expect(form, contains('body: IsiWebTerpusat('));
    });
  });

  group('kelola katalog di web', () {
    final daftar = File('lib/screens/product_list_screen.dart').readAsStringSync();

    // Satu hal yang sama lewat dua jalan berbeda, dan yang satu
    // bersarang di menu yang namanya tidak menyebutnya.
    test('Kelola Produk berisi produk saja, tanpa tab', () {
      expect(daftar, contains('if (kIsWeb) {'));
      final cabang = daftar.substring(daftar.indexOf('if (kIsWeb) {'));
      expect(cabang.substring(0, cabang.indexOf('return DefaultTabController')),
          isNot(contains('TabBar')));
    });

    test('Kategori dan Level punya menunya sendiri di sidebar', () {
      for (final peran in ['_owner', '_admin']) {
        final blok = menu.substring(menu.indexOf('const $peran = <MenuWeb>['));
        final isi = blok.substring(0, blok.indexOf('\n];'));
        expect(isi, contains("judul: 'Kategori'"), reason: peran);
        expect(isi, contains("judul: 'Level'"), reason: peran);
      }
    });

    // Keduanya ditulis sebagai tab dan mengandalkan induknya memuat
    // data. Sendirian di sidebar, daftarnya cuma kosong — dan yang
    // ditambahkan diam-diam tidak tersimpan.
    test('keduanya dibungkus penyiap datanya', () {
      expect(menu, contains('child: CategoryManagementScreen(),'));
      expect(menu, contains('child: LevelManagementScreen(),'));
      expect('KatalogSiap('.allMatches(menu).length, 2);
      final siap = File('lib/screens/katalog_siap.dart').readAsStringSync();
      expect(siap, contains('categories.restoId = restoId'));
      expect(siap, contains('if (restoId == _dimuatUntuk) return;'));
    });

    // Keduanya ditulis tanpa AppBar karena sebagai tab judulnya
    // dipegang layar induknya.
    test('keduanya diberi judul di atasnya', () {
      final siap = File('lib/screens/katalog_siap.dart').readAsStringSync();
      expect(siap, contains('appBar: AppBar(title: Text(widget.judul))'));
      expect(menu, contains("judul: 'Kategori',"));
      expect(menu, contains("judul: 'Level',"));
    });
  });

  // Sidebar web menunjuk layarnya langsung, tanpa melewati layar
  // perantara yang di HP menyaring siapa boleh apa. Menunjuk layar
  // yang keliru berarti memberi hak yang tidak pernah dimiliki peran
  // itu di aplikasinya — dan hak yang diberi lewat menu tidak terlihat
  // seperti pemberian hak, cuma seperti menu biasa.
  group('hak ubah sama dengan versi HP', () {
    String blok(String peran) {
      final b = menu.substring(menu.indexOf('const $peran = <MenuWeb>['));
      return b.substring(0, b.indexOf('\n];'));
    }

    // SettingsScreen bisa mengubah QRIS dan rekening bank;
    // PaymentInfoScreen hanya menampilkannya.
    test('info pembayaran hanya bisa diubah Owner dan Finance', () {
      expect(blok('_owner'), contains('layar: SettingsScreen.new'));
      expect(blok('_finance'), contains('layar: SettingsScreen.new'));
      expect(blok('_admin'), isNot(contains('layar: SettingsScreen.new')));
      expect(blok('_admin'), contains('layar: PaymentInfoScreen.new'));
    });

    // Di HP hanya MerchantPOS Admin yang punya jalan ke sana sama sekali.
    test('kelola karyawan hanya untuk MerchantPOS Admin', () {
      expect(blok('_superAdmin'), contains('EmployeeManagementScreen'));
      for (final peran in ['_owner', '_admin', '_finance']) {
        expect(blok(peran), isNot(contains('EmployeeManagementScreen')),
            reason: peran);
      }
    });
  });

  // Hub bertingkat masuk akal di ponsel yang sempit. Di sidebar yang
  // memang memuat semuanya, kartu hub cuma jadi ketukan tambahan
  // menuju daftar yang seharusnya sudah terlihat sejak awal.
  group('hub tidak bersarang lagi di sidebar', () {
    final blok = menu.substring(menu.indexOf('const _superAdmin'));
    final superAdmin = blok.substring(0, blok.indexOf('\n];'));

    test('isi Finance MerchantPOS dibongkar ke sidebar', () {
      for (final m in [
        'Riwayat Langganan',
        'Diskon Langganan',
        'Voucher Pelanggan',
        'Saldo & Pengeluaran',
        'Mapping GL Account',
        'Jurnal GL MerchantPOS',
        'Jurnal GL Semua Merchant',
      ]) {
        expect(superAdmin, contains("judul: '$m'"), reason: m);
      }
      // Kartunya sendiri tidak ikut, kalau tidak jadi dua jalan ke
      // tujuan yang sama.
      expect(superAdmin, isNot(contains('SuperAdminFinanceScreen')));
    });

    // Ketiganya membaca pembukuan MerchantPOS sendiri, bukan pembukuan
    // merchant mana pun — salah resto berarti angka orang lain.
    test('pembukuan MerchantPOS menunjuk resto semu merchantpos', () {
      for (final f in ['_saldoMerchantPOS', '_mappingMerchantPOS', '_jurnalMerchantPOS']) {
        expect(menu, contains(f));
      }
      expect('restoId: kPlatformRestoId'.allMatches(menu).length, 3);
    });
  });

  group('penanda dan popup di sidebar', () {
    final shell = File('lib/screens/web_shell_screen.dart').readAsStringSync();

    // Tanpa ini, "1 belum dibaca" hanya terlihat sesudah menunya
    // dibuka — padahal justru itu yang seharusnya membuat orang
    // membukanya.
    test('Customer Service membawa angka belum dibaca ke sidebar', () {
      expect(menu, contains('belumDibaca: _supportBelumDibaca'));
      expect(menu, contains('SupportRepository().semua()'));
      expect(shell, contains('if (m.belumDibaca != null)'));
    });

    // Angka yang diperbarui berkala selalu tertinggal sebanyak selang
    // waktunya, dan yang menunggu jawaban membaca keterlambatan itu
    // sebagai "harus muat ulang dulu".
    test('angkanya mengalir, bukan dihitung berkala', () {
      expect(shell, contains('StreamBuilder<int>('));
      expect(shell, isNot(contains('Timer.periodic(')));
      // Dari aliran tiket yang sama dengan layar Customer Service: dua
      // sumber untuk satu angka akan berbeda cepat atau lambat.
      expect(menu, contains('SupportRepository().semua().map('));
    });

    // Sidebar sudah memuat semuanya, jadi ini bukan satu-satunya jalan
    // ke mana pun — gunanya memakai ruang kosong di sebelah sidebar
    // untuk menunjukkan apa saja yang ada.
    test('beranda berisi pintasan ke seluruh menu perannya', () {
      expect(menu, contains('const menuBerandaWeb = MenuWeb('));
      expect(shell, contains('if (tujuan.isNotEmpty) menuBerandaWeb'));
      expect(shell, contains('class _Beranda'));
    });

    // Kartunya dirakit per kelompok, dan yang berada sebelum judul
    // kelompok pertama tidak akan ikut terpasang sama sekali.
    test('tiap peran mulai dengan sebuah kelompok', () {
      for (final peran in ['_superAdmin', '_owner', '_admin', '_finance']) {
        final b = menu.substring(menu.indexOf('const $peran = <MenuWeb>['));
        final pertama = b.substring(0, b.indexOf('judul:'));
        expect(pertama, contains('kelompok:'), reason: peran);
      }
    });

    // Lembar bawah selalu selebar jendela dan menempel di dasarnya; di
    // jendela lebar ia jadi panel raksasa di pojok yang berlawanan
    // dengan tombol yang barusan ditekan.
    test('menu Support menempel pada tombolnya di web', () {
      final fab = File('lib/widgets/support_fab.dart').readAsStringSync();
      expect(fab, contains('if (kIsWeb) {'));
      expect(fab, contains('alignment: Alignment.bottomRight'));
      // Satu badan menu, dipakai dua bentuk — bukan dua salinan yang
      // bisa berpisah pada perubahan berikutnya.
      expect("title: const Text('Chat MerchantPOS Admin')".allMatches(fab).length, 1);
    });
  });

  group('yang tidak boleh hilang di web', () {
    final shell = File('lib/screens/web_shell_screen.dart').readAsStringSync();

    // Tombolnya menempel di beranda tiap peran di versi HP — beranda
    // yang tidak dipakai sama sekali di web. Tanpa dipasang di
    // kerangkanya, pegawai merchant yang bekerja dari konsol tidak
    // punya satu pun jalan untuk mengadu atau bertanya.
    test('MerchantPOS Support ada di kedua bentuk kerangka', () {
      expect('floatingActionButton: _support(auth),'.allMatches(shell).length, 2);
      expect(shell, contains('child: SupportFab(),'));
    });

    // MerchantPOS Admin berada di sisi seberang percakapan yang sama —
    // tombol mengadu di layarnya sendiri hanya membuat dia bisa
    // membuat tiket yang ujungnya dia jawab sendiri.
    test('MerchantPOS Admin tidak mendapat tombolnya', () {
      expect(shell, contains('if (auth.isSuperAdmin) return null;'));
    });

    // Layar di sebelahnya membawa tombol mengambangnya sendiri, dan
    // keduanya berebut sudut yang sama.
    test('tidak berebut sudut dengan tombol layarnya', () {
      expect(shell, contains('padding: EdgeInsets.only(bottom: 72)'));
    });

    // Menu yang ada di beranda HP tapi tidak di sidebar berarti hilang
    // sama sekali bagi yang bekerja dari web — tidak ada jalan lain
    // menuju layarnya.
    test('menu keuangan dan langganan tidak tertinggal', () {
      final blokOwner = menu.substring(menu.indexOf('const _owner'));
      final owner = blokOwner.substring(0, blokOwner.indexOf('\n];'));
      for (final m in [
        'Laporan Penjualan',
        'Laporan Transaksi',
        'Pencairan Gateway',
        'Tagihan Langganan',
        'Kirim Pengumuman',
      ]) {
        expect(owner, contains("judul: '$m'"), reason: 'Owner kehilangan $m');
      }

      final blokFinance = menu.substring(menu.indexOf('const _finance'));
      final finance = blokFinance.substring(0, blokFinance.indexOf('\n];'));
      for (final m in ['Tagihan Langganan', 'Pengaturan Pembayaran']) {
        expect(finance, contains("judul: '$m'"), reason: 'Finance kehilangan $m');
      }

      final blokAdmin = menu.substring(menu.indexOf('const _admin'));
      final admin = blokAdmin.substring(0, blokAdmin.indexOf('\n];'));
      expect(admin, contains("judul: 'Laporan Penjualan'"));
      expect(admin, contains("judul: 'Kirim Pengumuman'"));
      expect(admin, contains("judul: 'Info Pembayaran'"));
    });

    // Tagihan langganan butuh tahu cabang mana yang sedang dibuka.
    test('tagihan langganan tidak dibuka tanpa merchant', () {
      expect(menu, contains("if (restoId == null)"));
      expect(menu, contains('BillingScreen(restoId: restoId)'));
    });
  });

  // Produk, Kategori, dan Level adalah daftar yang dikelola dengan cara
  // yang sama, dan sampai sekarang hanya Level yang terlihat begitu.
  group('daftar katalog seragam', () {
    for (final f in [
      'product_list_screen',
      'category_management_screen',
      'level_management_screen',
    ]) {
      test('$f: kartu, dan lebarnya dibatasi', () {
        final isi = File('lib/screens/$f.dart').readAsStringSync();
        expect(isi, contains('ResponsiveCenter('), reason: f);
        expect(isi, contains('Card('), reason: f);
      });
    }
  });

  group('notifikasi dorong di web', () {
    final push = File('lib/services/push_service.dart').readAsStringSync();

    test('memakai konfigurasi web dan kunci VAPID', () {
      expect(push, contains('Firebase.initializeApp(options: firebaseWebOptions)'));
      // Tanpa kunci VAPID, getToken di web selalu gagal — dan tidak ada
      // padanannya sama sekali di Android.
      expect(push, contains('getToken(vapidKey: kVapidKey)'));
    });

    // Berkas ini berjalan di luar aplikasi Flutter dan tetap
    // dibangunkan saat seluruh tab sudah ditutup, jadi konfigurasinya
    // harus ada di dalamnya sendiri.
    test('service worker penerima ada dan membawa konfigurasinya', () {
      final sw = File('web/firebase-messaging-sw.js').readAsStringSync();
      expect(sw, contains('firebase.initializeApp('));
      expect(sw, contains('messagingSenderId'));
      expect(sw, contains('onBackgroundMessage'));
      expect(sw, contains('notificationclick'));
    });

    // flutter_local_notifications tidak punya sisi web.
    // Notification API punya pilihan `sound` di spesifikasinya, tapi
    // tidak ada satu pun peramban yang menjalankannya — jadi nadanya
    // dibunyikan terpisah oleh halamannya sendiri.
    test('nadanya sama dengan yang di HP', () {
      final html =
          File('lib/services/notifikasi_web_html.dart').readAsStringSync();
      expect(html, contains("_berkasNada = 'merchantpos_notif.wav'"));
      expect(html, contains('bunyikanNadaWeb()'));
      // Berkasnya harus benar-benar ikut terkirim; yang di res/raw
      // dibungkus Gradle ke dalam APK dan tidak pernah sampai ke web.
      expect(File('web/merchantpos_notif.wav').existsSync(), isTrue);
      final kosong =
          File('lib/services/notifikasi_web_kosong.dart').readAsStringSync();
      expect(kosong, contains('void bunyikanNadaWeb()'));
    });

    test('notifikasi depan layar memakai API peramban', () {
      expect(push, contains('tampilkanNotifWeb('));
      final pintu = File('lib/services/notifikasi_web.dart').readAsStringSync();
      expect(pintu, contains("if (dart.library.html) 'notifikasi_web_html.dart'"));
      // Sisi bukan-web harus tetap ada, kalau tidak Android gagal
      // dibangun begitu berkas ini dipanggil.
      expect(File('lib/services/notifikasi_web_kosong.dart').existsSync(), isTrue);
    });

    test('izin yang ditolak tidak dianggap kerusakan', () {
      expect(push, contains('Izin notifikasi ditolak di peramban ini.'));
    });

    // Platform datang dari dart:io, yang di web melempar begitu
    // disentuh — dan galatnya tertangkap catch di sekitarnya, tersamar
    // jadi "gagal disimpan ke server". Yang terlihat cuma notifikasi
    // yang tidak pernah datang.
    test('platform perangkat tidak menyentuh dart:io di web', () {
      expect(push, contains("kIsWeb ? 'web' : (Platform.isIOS"));
      expect(push, isNot(contains("'p_platform': Platform.isIOS")));
    });

    // Izin ditolak, token tidak terbit, dan token terbit tapi gagal
    // disimpan terlihat sama saja dari luar: notifikasi yang tidak
    // datang.
    test('ada alat untuk memastikan pendaftarannya di web', () {
      final shell = File('lib/screens/web_shell_screen.dart').readAsStringSync();
      expect(shell, contains('showNotificationTest(context)'));
    });
  });

  group('Jurnal GL Semua Merchant', () {
    final isi =
        File('lib/screens/super_admin_finance_screen.dart').readAsStringSync();
    final layar = isi.substring(isi.indexOf('class _AllRestoJournalScreenState'));

    // Sama seperti Jurnal GL MerchantPOS di sebelahnya: daftarnya bukan
    // bacaan mengalir yang barisnya perlu dipendekkan — tiap barisnya
    // kartu bertumpu pada nomor akun di kiri dan nominal di kanan, dan
    // jarak itulah yang membuat keduanya terbaca sebagai sepasang.
    test('kartunya selebar isi, tanpa pembatas', () {
      final daftar = layar.substring(layar.indexOf('RefreshIndicator('));
      expect(daftar.substring(0, daftar.indexOf('ListView.builder')),
          isNot(contains('ResponsiveCenter')));
      final kaataGo =
          File('lib/screens/finance_journal_screen.dart').readAsStringSync();
      expect(kaataGo, isNot(contains('ResponsiveCenter')));
    });

    // Saringan yang sama sudah berdiri sebagai pita di bawah judul.
    // Dua pintu ke satu saringan membuat yang satu tampak melakukan
    // hal lain.
    test('ikon saring di pojok tidak ditampilkan di web', () {
      expect(layar, contains('actions: kIsWeb'));
      expect(layar, contains('_PitaSaringan('));
    });
  });

  // APK terbit sesekali dan nomornya menempel pada berkas yang sudah
  // terpasang di HP orang; konsol web terbit tiap push dan yang dibuka
  // selalu yang terakhir. Satu nomor untuk keduanya pasti berbohong
  // tentang salah satunya.
  group('versi konsol web berdiri sendiri', () {
    final versi = File('lib/versi_web.dart').readAsStringSync();
    final shell = File('lib/screens/web_shell_screen.dart').readAsStringSync();
    final alur = File('.github/workflows/web.yml').readAsStringSync();

    test('nomornya sendiri, bukan dari pubspec', () {
      expect(versi, contains("const kVersiWeb = '"));
      expect(versi, isNot(contains('PackageInfo')));
    });

    // Yang dibaca orang cuma nomor versinya. Tujuh huruf commit di
    // sebelahnya tidak berarti apa-apa baginya, dan yang tidak berarti
    // apa-apa di kaki layar cuma jadi sampah yang harus dilewati mata.
    test('tanpa penanda build', () {
      expect(versi, isNot(contains('BUILD_WEB')));
      expect(alur, isNot(contains('--dart-define=BUILD_WEB=')));
    });

    test('ditulis di kaki sidebar', () {
      expect(shell, contains('labelVersiWeb'));
    });
  });

  // Konsol web dibuka dari PC maupun dari HP, dan susunan yang benar
  // di satu tempat salah di tempat lain.
  group('isinya menyesuaikan lebar layar', () {
    final resp = File('lib/widgets/responsive.dart').readAsStringSync();

    // Angka 840 lahir dari tablet kasir melintang. Di monitor 1900
    // piksel ia menyisakan dua pita kosong selebar telapak tangan.
    test('batas lebar isi lebih lapang di web', () {
      expect(resp, contains('_bawaanWeb = 1280.0'));
      expect(resp, contains('maxWidth ?? (kIsWeb ? _bawaanWeb : _bawaanPonsel)'));
    });

    // Yang menyetel angkanya sendiri tidak ikut melebar: formulir yang
    // sengaja dipersempit tetap sempit.
    test('yang menentukan lebarnya sendiri tidak tersentuh', () {
      expect(resp, contains('final double? maxWidth;'));
    });

    // Popup tetap sempit — namanya juga popup.
    test('popup tidak ikut melebar', () {
      final lebar = File('lib/utils/lebar_web.dart').readAsStringSync();
      expect(lebar, contains('kLebarDialogWeb = 460'));
    });

    // Tumpukan kartu di monitor memaksa orang menggulir melewati ruang
    // kosong selebar kartunya sendiri di sebelah kanan.
    test('kartu ringkasan berdampingan saat ruangnya cukup', () {
      expect(resp, contains('class KartuBerdampingan'));
      final pasar =
          File('lib/screens/market_report_screen.dart').readAsStringSync();
      expect(pasar, contains('KartuBerdampingan(kartu: ['));
    });
  });

  group('yang dimatikan di web', () {
    test('notifikasi sistem bawaan aplikasi', () {
      final isi =
          File('lib/services/notification_service.dart').readAsStringSync();
      expect(isi, contains('if (kIsWeb) {'));
    });

    // Halamannya sudah selalu versi terbaru begitu dimuat ulang.
    test('penanda unduhan pembaruan APK', () {
      final isi =
          File('lib/widgets/update_download_banner.dart').readAsStringSync();
      expect(isi, contains('if (kIsWeb) return child;'));
    });
  });
}
