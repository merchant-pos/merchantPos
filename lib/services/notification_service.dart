import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifikasi MerchantPOS: banner di layar HP lengkap dengan nada dering
/// sendiri, seperti pesan masuk yang lain.
///
/// Nada deringnya dibuat khusus (`res/raw/merchantpos_notif.wav`) — tiga nada
/// naik D5–A5–D6 bertimbre marimba. Nada bawaan Android terdengar sama
/// dengan puluhan aplikasi lain di HP yang sama, jadi tidak ada yang
/// menoleh; yang ini cukup berbeda untuk dikenali tanpa harus melihat
/// layar, tapi tidak seperti bel error yang bikin panik.
///
/// Catatan penting: ini notifikasi *lokal*. Ia muncul selama aplikasinya
/// masih hidup — di depan layar maupun baru saja dilatarbelakangkan.
/// Kalau aplikasinya benar-benar ditutup, Android menghentikan koneksi
/// realtime-nya dan tidak ada yang bisa memicu notifikasi. Untuk itu
/// perlu push notification (FCM) dengan server pengirim — pekerjaan
/// tersendiri yang belum ada di sini.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Dipisah per jenis supaya pemakainya bisa mematikan salah satunya
  /// lewat setelan Android tanpa ikut mematikan yang lain — dapur mungkin
  /// ingin bunyi terus, sementara kasir cukup yang pesanannya sendiri.
  static const _channels = [
    (
      id: 'kaata_order_status',
      name: 'Status Pesanan',
      description: 'Pemberitahuan saat pesanan mulai dimasak atau siap',
    ),
    (
      id: 'kaata_new_order',
      name: 'Pesanan Baru',
      description: 'Pemberitahuan untuk dapur saat ada pesanan masuk',
    ),
    (
      id: 'kaata_fund_review',
      name: 'Hasil Pengajuan',
      description: 'Setoran tunai & top up petty cash yang sudah diputus Finance',
    ),
    (
      id: 'kaata_download',
      name: 'Unduhan Pembaruan',
      description: 'Kemajuan unduhan versi baru aplikasi',
    ),
    (
      id: 'kaata_announcement',
      name: 'Pengumuman',
      description: 'Kabar dari merchant dan pemberitahuan versi baru aplikasi',
    ),
  ];

  static const _sound = RawResourceAndroidNotificationSound('merchantpos_notif');

  /// Turun jadi false kalau perangkat menolak nada dering khususnya.
  bool _customSoundWorks = true;

  /// Dicatat saat penyiapan gagal, supaya layar tes bisa menyebut
  /// sebabnya alih-alih diam.
  String? initError;

  Future<void> init() async {
    if (_ready) return;
    // Tidak ada notifikasi sistem di web — plugin-nya pun tidak punya
    // implementasinya. Dimatikan di sini supaya pemanggilnya tidak perlu
    // memeriksa satu per satu.
    if (kIsWeb) {
      _ready = true;
      return;
    }

    // 'ic_notification', bukan '@mipmap/ic_launcher'. Plugin mencari
    // ikonnya dengan getIdentifier(name, "drawable", package) — hanya di
    // folder drawable, dan tanpa memahami awalan '@mipmap/'. Nama yang
    // tidak ketemu menghasilkan id 0, Android menolak notifikasi tanpa
    // ikon kecil yang sah, dan kegagalannya tidak terlihat di mana pun
    // kecuali log. Itulah sebabnya notifikasi sebelumnya diam total.
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final handler = onNotificationTap;
        if (handler != null) handler(response.payload);
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Channel dibuat lebih dulu: di Android 8+ suara dan tingkat
    // kepentingan melekat pada channel-nya, bukan pada tiap notifikasi.
    // Setelah channel terbentuk, keduanya tidak bisa diubah lagi dari
    // kode — pemakainya yang berkuasa lewat Setelan.
    for (final c in _channels) {
      try {
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            c.id,
            c.name,
            description: c.description,
            importance: Importance.high, // banner + bunyi
            sound: _sound,
            playSound: true,
            enableVibration: true,
          ),
        );
      } catch (e) {
        // Nada dering khusus yang tidak bisa dibaca perangkat tidak boleh
        // ikut menjatuhkan notifikasinya. Lebih baik berbunyi dengan nada
        // bawaan daripada tidak muncul sama sekali.
        debugPrint('[Notif] channel ${c.id} gagal dengan nada khusus: $e');
        initError = '$e';
        _customSoundWorks = false;
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            c.id,
            c.name,
            description: c.description,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    }

    _ready = true;
    initError = null;
  }

  /// Android 13+ mewajibkan izin ini; tanpa itu notifikasinya terkirim
  /// tapi tidak terlihat sama sekali. Ditolak bukan alasan untuk gagal —
  /// aplikasinya tetap jalan, hanya diam.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> showOrderStatus({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(channel: _channels[0], id: id, title: title, body: body);

  Future<void> showNewOrder({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(channel: _channels[1], id: id, title: title, body: body);

  /// Kabar bahwa setoran atau top up yang diajukan sudah diputus Finance.
  ///
  /// Kanalnya sendiri, bukan menumpang kanal pesanan: kasir yang memilih
  /// membisukan hiruk-pikuk pesanan tetap harus mendengar kabar soal
  /// uang yang dia pertanggungjawabkan.
  Future<void> showFundReview({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(channel: _channels[2], id: id, title: title, body: body);

  /// Pengumuman — dari resto maupun dari sistem.
  Future<void> showAnnouncement({
    required int id,
    required String title,
    required String body,
    String? event,
    String? restoId,
  }) =>
      _show(
        channel: _channels[3],
        id: id,
        title: title,
        body: body,
        // Diberi awalan supaya tidak tertukar dengan payload pemasang
        // APK, yang isinya jalur berkas. Satu kolom payload dipakai dua
        // hal, dan yang membedakannya harus terbaca — bukan ditebak
        // dari bentuk isinya.
        //
        // Sebagian tujuan butuh lebih dari nama kejadiannya: ajakan
        // menilai perlu tahu merchant mana. Ditempel sebagai kueri,
        // bentuk yang sudah dikenal semua orang dan gampang dibaca
        // manusia saat menelusuri log.
        payload: event == null
            ? null
            : 'event:$event${restoId == null ? '' : '?resto_id=$restoId'}',
      );

  /// Dipanggil saat notifikasi diketuk, dengan payload-nya.
  ///
  /// Dipasang [AppUpdater] supaya notifikasi "siap dipasang" bisa
  /// membuka layar pemasang — termasuk saat aplikasinya sedang tidak
  /// dibuka, yang justru keadaan paling sering untuk unduhan 83 MB.
  void Function(String? payload)? onNotificationTap;

  /// Id tetap untuk notifikasi unduhan.
  ///
  /// Tetap, bukan acak: tiap pembaruan angka persen harus menimpa
  /// notifikasi yang sama. Id baru tiap kali berarti seratus baris
  /// notifikasi untuk satu unduhan.
  static const _downloadId = 424242;

  /// Baris kemajuan unduhan di bar notifikasi.
  ///
  /// Ada karena unduhan 83 MB bukan sesuatu yang ditunggui orang sambil
  /// menatap layar. Dia akan mengunci HP-nya atau pindah aplikasi, dan
  /// sejak itu penanda di dalam aplikasi tidak lagi terlihat oleh
  /// siapa pun.
  ///
  /// [percent] null berarti panjang berkasnya tidak diberitahukan
  /// server — batangnya berjalan tanpa ujung, dan itu jujur.
  Future<void> showDownloadProgress(int? percent) async {
    await init();
    try {
      await _plugin.show(
        _downloadId,
        'Mengunduh pembaruan MerchantPOS',
        percent == null ? 'Sedang berjalan…' : '$percent%',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'kaata_download',
            'Unduhan Pembaruan',
            channelDescription: 'Kemajuan unduhan versi baru aplikasi',
            icon: 'ic_notification',
            // Tanpa suara dan tanpa getar: ini kabar yang menemani,
            // bukan yang memanggil. Berbunyi tiap satu persen adalah
            // cara tercepat membuat orang mematikan notifikasinya.
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            onlyAlertOnce: true,
            // Tidak bisa disapu hilang selagi berjalan — kalau bisa,
            // orangnya kehilangan satu-satunya jendela ke unduhan yang
            // masih jalan.
            ongoing: true,
            autoCancel: false,
            showProgress: true,
            maxProgress: 100,
            progress: percent ?? 0,
            indeterminate: percent == null,
          ),
        ),
      );
    } catch (_) {
      // Notifikasi tidak pernah cukup penting untuk menjatuhkan
      // unduhannya sendiri.
    }
  }

  /// Berkasnya sudah turun dan tinggal dipasang.
  ///
  /// Berbunyi dan bisa diketuk — kebalikan dari baris kemajuannya.
  /// Inilah satu-satunya jalan yang tersisa kalau orangnya sedang
  /// membuka aplikasi lain: Android tidak mengizinkan aplikasi latar
  /// membuka layar sendiri, tapi notifikasi yang diketuk boleh.
  Future<void> showDownloadReady(String filePath) async {
    await init();
    try {
      await _plugin.show(
        _downloadId,
        'Pembaruan siap dipasang',
        'Ketuk untuk memasang versi terbaru MerchantPOS',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'kaata_download',
            'Unduhan Pembaruan',
            icon: 'ic_notification',
            importance: Importance.high,
            priority: Priority.high,
            sound: _customSoundWorks ? _sound : null,
            ongoing: false,
            autoCancel: true,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: filePath,
      );
    } catch (_) {
      // Diabaikan — pemasangnya tetap bisa dibuka dari dalam aplikasi.
    }
  }

  Future<void> cancelDownloadNotification() async {
    try {
      await _plugin.cancel(_downloadId);
    } catch (_) {
      // Tidak ada yang perlu diselamatkan dari gagal menghapus
      // notifikasi.
    }
  }

  Future<void> _show({
    required ({String id, String name, String description}) channel,
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
            sound: _customSoundWorks ? _sound : null,
            // Isi pesan bisa lebih panjang dari satu baris — tanpa ini
            // Android memotongnya diam-diam.
            styleInformation: BigTextStyleInformation(body),
            ticker: title,
          ),
          iOS: const DarwinNotificationDetails(sound: 'merchantpos_notif.wav'),
        ),
        payload: payload,
      );
      lastError = null;
    } catch (e) {
      // Notifikasi tidak pernah cukup penting untuk menjatuhkan alur yang
      // sedang berjalan — pesanannya sendiri sudah tersimpan. Tapi
      // penyebabnya disimpan, supaya layar Tes Notifikasi bisa
      // menyebutkannya alih-alih membiarkan orang menebak.
      lastError = '$e';
      debugPrint('[Notif] gagal menampilkan: $e');
    }
  }

  /// Alasan kegagalan terakhir, atau null kalau yang terakhir berhasil.
  String? lastError;

  /// Mengirim satu notifikasi contoh dan melaporkan hasilnya.
  ///
  /// Notifikasi gagal secara diam-diam karena banyak sebab di luar
  /// aplikasi — izin ditolak, channel dibisukan pemakainya, mode fokus.
  /// Tanpa cara mengujinya, "notifikasi tidak jalan" tidak bisa
  /// dibedakan dari "belum ada pesanan baru".
  Future<String> sendTest() async {
    try {
      await init();
    } catch (e) {
      return 'Sistem notifikasi gagal disiapkan: $e';
    }

    bool granted;
    try {
      granted = await requestPermission();
    } catch (e) {
      return 'Gagal meminta izin notifikasi: $e';
    }

    if (!granted) {
      return 'Izin notifikasi belum diberikan. Aktifkan lewat Setelan HP > '
          'Aplikasi > MerchantPOS > Notifikasi.';
    }

    lastError = null;
    await showNewOrder(
      id: 999999,
      title: 'Tes Notifikasi MerchantPOS',
      body: 'Kalau kamu melihat dan mendengar ini, notifikasi sudah aktif.',
    );

    if (lastError != null) return 'Gagal menampilkan notifikasi: $lastError';
    if (!_customSoundWorks) {
      return 'Notifikasi terkirim, tapi memakai nada bawaan HP — nada khas '
          'MerchantPOS ditolak perangkat ini.';
    }
    return 'Notifikasi terkirim. Cek layar HP kamu — kalau tidak muncul, '
        'periksa Setelan HP > Aplikasi > MerchantPOS > Notifikasi.';
  }
}
