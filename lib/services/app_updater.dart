import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/apk_updater.dart';
import 'notification_service.dart';

/// Unduhan pembaruan aplikasi, hidup di luar layar mana pun.
///
/// Dulu keadaannya dititipkan pada tombol di dalam kotak masuk, dan itu
/// berarti menutup kotak masuknya membatalkan unduhan yang sedang
/// berjalan — 80 MB yang hangus hanya karena orangnya ingin melihat
/// pesanan yang masuk sementara menunggu. Yang paling sering terjadi
/// justru itu: unduhan besar bukan sesuatu yang ditunggui orang sambil
/// menatap layar.
///
/// Sebagai singleton, unduhannya terus berjalan ke mana pun orangnya
/// pergi di dalam aplikasi, dan kemajuannya tetap bisa dilihat lewat
/// penanda mengambang di bawah layar.
class AppUpdater extends ChangeNotifier {
  AppUpdater._();
  static final instance = AppUpdater._();

  ApkUpdater? _updater;
  String? _url;

  /// 0..1, atau null saat panjang berkasnya tidak diberitahukan server.
  double? progress;

  bool downloading = false;

  /// Dijeda, dan berkas separuhnya menunggu dilanjutkan.
  bool paused = false;

  /// Keterangan galat terakhir, atau null kalau tidak ada.
  String? error;

  /// Persen bulat untuk ditampilkan, atau null kalau belum diketahui.
  int? get percent => progress == null ? null : (progress! * 100).round();

  /// Persen terakhir yang sudah dikirim ke notifikasi Android.
  ///
  /// Tiap potongan data memanggil onProgress — ribuan kali untuk 83 MB —
  /// dan mengirim semuanya ke Android berarti membanjiri antrean
  /// notifikasi demi angka yang sama.
  int? _lastPercent;

  Future<void> start(String url) async {
    if (downloading) return;

    _url = url;
    error = null;
    _noticeTimer?.cancel();
    notice = null;
    paused = false;
    progress = 0;

    final updater = ApkUpdater(onProgress: (p) {
      progress = p;
      final now = p == null ? null : (p * 100).round();
      if (now != _lastPercent) {
        _lastPercent = now;
        NotificationService.instance.showDownloadProgress(now);
      }
      notifyListeners();
    });
    _updater = updater;

    await _jalankan(url, updater);
  }

  /// Menjalankan unduhannya, entah dari nol atau melanjutkan yang dijeda.
  ///
  /// Dipisah dari [start] supaya melanjutkan memakai ApkUpdater yang
  /// sama — di situlah tersimpan berapa byte yang sudah turun, dan
  /// membuat yang baru berarti mengulang dari nol dengan nama "lanjut".
  Future<void> _jalankan(String url, ApkUpdater updater) async {
    downloading = true;
    error = null;
    notifyListeners();

    _lastPercent = percent;
    NotificationService.instance.showDownloadProgress(_lastPercent ?? 0);

    final failure = await updater.downloadAndInstall(
      url,
      // Berkasnya sudah turun, layar pemasang belum tentu terbuka.
      //
      // Android melarang aplikasi yang sedang di latar membuka layar
      // sendiri — jadi kalau HP-nya terkunci atau orangnya sedang di
      // aplikasi lain, panggilan membuka pemasang itu diam saja.
      // Notifikasi ini jalan yang tersisa: satu ketukan, dan layar
      // pemasangnya terbuka.
      onDownloaded: (path) =>
          NotificationService.instance.showDownloadReady(path),
    );

    final dijeda = paused;
    downloading = false;
    // Kemajuannya dipertahankan saat dijeda — angka yang kembali ke nol
    // membuat orang mengira unduhannya hangus, dan itu justru kebalikan
    // dari yang dijanjikan tombol Jeda.
    if (!dijeda) {
      _updater = null;
      progress = null;
    }
    error = failure;
    if (failure != null || dijeda) {
      NotificationService.instance.cancelDownloadNotification();
    }
    notifyListeners();
  }

  /// Mengulang unduhan yang gagal, dengan tautan yang sama.
  Future<void> retry() async {
    final url = _url;
    if (url == null) return;
    await start(url);
  }

  /// Menjeda unduhan. Berkas separuhnya tetap tersimpan.
  void pause() {
    if (!downloading) return;
    paused = true;
    _updater?.pause();
    notifyListeners();
  }

  /// Melanjutkan dari byte terakhir yang sudah turun.
  ///
  /// Kalau servernya menolak melanjutkan, unduhannya dimulai dari nol —
  /// dan itu ditangani di lapisan bawah, bukan di sini.
  Future<void> resume() async {
    final url = _url;
    if (url == null || downloading) return;
    final updater = _updater;
    paused = false;
    if (updater == null) {
      await start(url);
      return;
    }
    await _jalankan(url, updater);
  }

  @visibleForTesting
  void setUjiGagal(String pesan) {
    downloading = false;
    paused = false;
    progress = null;
    error = pesan;
    notice = null;
    notifyListeners();
  }

  @visibleForTesting
  void setUjiBerjalan(double kemajuan) {
    downloading = true;
    paused = false;
    error = null;
    notice = null;
    progress = kemajuan;
    notifyListeners();
  }

  @visibleForTesting
  void setUjiDijeda(double kemajuan) {
    downloading = false;
    paused = true;
    error = null;
    notice = null;
    progress = kemajuan;
    notifyListeners();
  }

  @visibleForTesting
  void resetUji() {
    downloading = false;
    paused = false;
    error = null;
    notice = null;
    progress = null;
    notifyListeners();
  }

  /// Kabar singkat yang hilang sendiri — bukan galat.
  ///
  /// Membatalkan unduhan sendiri bukan kegagalan, jadi tidak boleh
  /// muncul sebagai kotak merah berisi keterangan teknis yang menuntut
  /// dibaca dan ditutup. Cukup satu kalimat yang menegaskan bahwa yang
  /// diminta memang terjadi, lalu pergi.
  String? notice;

  Timer? _noticeTimer;

  void cancel() {
    NotificationService.instance.cancelDownloadNotification();
    paused = false;
    _updater?.cancel();
    _updater = null;
    downloading = false;
    progress = null;
    error = null;
    _showNotice('Unduhan dibatalkan');
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    notice = message;
    notifyListeners();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      notice = null;
      notifyListeners();
    });
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
