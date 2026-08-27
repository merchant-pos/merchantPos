import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/http.dart' show ClientException;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Mengunduh APK versi baru di dalam aplikasi, lalu menyerahkannya ke
/// pemasang bawaan Android.
///
/// Sebelumnya tombol Unduh cuma membuka tautan di browser. Itu berarti
/// orangnya berpindah aplikasi, menunggu di sana, mencari berkasnya di
/// folder unduhan, lalu membukanya sendiri — empat langkah yang
/// masing-masing bisa membuat orang berhenti di tengah jalan. Dan di
/// sebagian HP, browser bawaannya justru menampilkan peringatan
/// menakutkan tentang berkas yang "mungkin berbahaya".
///
/// Di sini seluruhnya terjadi di satu layar: unduh berikut angka
/// kemajuannya, lalu layar pemasang langsung terbuka.
class ApkUpdater {
  /// Perkembangan unduhan, 0..1. Null berarti panjang berkasnya tidak
  /// diberitahukan server — jarang, tapi mungkin.
  final void Function(double? progress)? onProgress;

  ApkUpdater({this.onProgress});

  http.Client? _client;

  /// Unduhannya dihentikan orangnya sendiri.
  ///
  /// Dicatat terpisah dari galat, karena menutup koneksi di tengah
  /// unduhan memang melempar galat jaringan sungguhan — "Connection
  /// closed while receiving data" dan sejenisnya. Tanpa penanda ini,
  /// menekan Batalkan dijawab dengan pesan galat sepanjang paragraf
  /// untuk sesuatu yang justru diminta orangnya.
  bool _cancelled = false;

  /// Dijeda orangnya, bukan dibatalkan.
  ///
  /// Bedanya cuma satu, dan itu yang penting: berkas separuhnya
  /// dipertahankan. Menjeda 80 MB di angka 70% lalu memulainya lagi dari
  /// nol bukan jeda — itu pembatalan yang memakai kata yang salah.
  bool _paused = false;

  /// Berapa byte yang sudah turun dan tersimpan.
  int _received = 0;

  /// Ada berkas separuh yang bisa dilanjutkan.
  bool get bisaDilanjutkan => _received > 0;

  /// Membatalkan unduhan yang sedang berjalan.
  void cancel() {
    _cancelled = true;
    _received = 0;
    _client?.close();
    _client = null;
  }

  /// Menjeda unduhan, menyisakan berkas separuhnya.
  void pause() {
    _paused = true;
    _client?.close();
    _client = null;
  }

  /// Mengunduh lalu membuka pemasangnya.
  ///
  /// Mengembalikan null kalau berhasil, atau keterangan galat yang layak
  /// dibaca orang biasa.
  Future<String?> downloadAndInstall(
    String url, {
    void Function(String filePath)? onDownloaded,
  }) async {
    // Android menolak memasang aplikasi dari luar Play Store sampai izin
    // ini diberikan. Tanpa memintanya lebih dulu, unduhannya berhasil
    // lalu layar pemasangnya muncul kosong — terlihat persis seperti
    // aplikasinya yang rusak.
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        return 'Izin memasang aplikasi belum diberikan. Aktifkan di Setelan '
            'HP → Aplikasi → MerchantPOS.';
      }
    }

    final File file;
    try {
      file = await _download(url);
    } on _Cancelled {
      return null;
    } on _Paused {
      return null;
    } catch (e) {
      // Pembatalan menang atas galat apa pun. Yang muncul saat koneksi
      // ditutup di tengah jalan memang galat jaringan yang sah, tapi
      // menyampaikannya ke orang yang baru saja menekan Batalkan cuma
      // membuat tindakannya sendiri terlihat seperti kerusakan.
      if (_cancelled || _paused) return null;
      return downloadErrorMessage(e);
    }

    // Notifikasinya dipasang sebelum mencoba membuka pemasangnya.
    // Kalau aplikasinya sedang di latar, panggilan di bawah tidak
    // menghasilkan apa pun — dan tanpa notifikasi ini, berkas 83 MB
    // yang sudah turun tidak punya satu pun jalan untuk dipasang.
    onDownloaded?.call(file.path);

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      return 'Berkasnya sudah terunduh, tapi layar pemasangnya tidak bisa '
          'dibuka. Coba buka lagi dari notifikasi unduhan.';
    }
    return null;
  }

  Future<File> _download(String url) async {
    final client = http.Client();
    _client = client;
    _cancelled = false;
    _paused = false;
    try {
      // Disimpan di folder milik aplikasi sendiri, bukan folder Unduhan
      // bersama: berkas 80 MB yang tertinggal di Unduhan akan
      // membingungkan orangnya berbulan-bulan kemudian, sementara yang
      // di sini ikut terhapus saat aplikasinya dicopot.
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/MerchantPOS-update.apk');

      // Berkas separuh dari jeda sebelumnya dilanjutkan, bukan diulang.
      //
      // Panjangnya diperiksa, bukan dipercaya dari ingatan: aplikasi
      // bisa mati di antara jeda dan lanjut, dan menambahkan byte baru
      // ke berkas yang panjangnya tidak sesuai catatan menghasilkan APK
      // rusak yang gagal dipasang tanpa sebab yang jelas.
      var lanjut = _received > 0 &&
          await file.exists() &&
          await file.length() == _received;
      if (!lanjut) {
        if (await file.exists()) await file.delete();
        _received = 0;
      }

      final request = http.Request('GET', Uri.parse(url));
      if (lanjut) request.headers['Range'] = 'bytes=$_received-';
      var response = await client.send(request);

      // Server yang menolak melanjutkan menjawab 200 berisi seluruh
      // berkas, bukan 206 berisi sisanya. Menambahkannya ke belakang
      // berkas separuh akan menghasilkan berkas dobel.
      if (lanjut && response.statusCode == 200) {
        lanjut = false;
        _received = 0;
        if (await file.exists()) await file.delete();
      } else if (response.statusCode != 200 && response.statusCode != 206) {
        throw _BadStatus(response.statusCode);
      }

      final sisa = response.contentLength;
      final total = sisa == null ? null : _received + sisa;

      final sink =
          file.openWrite(mode: lanjut ? FileMode.append : FileMode.write);

      await for (final chunk in response.stream) {
        if (_cancelled) {
          await sink.close();
          await file.delete();
          _received = 0;
          throw const _Cancelled();
        }
        if (_paused) {
          // Berkasnya sengaja TIDAK dihapus. Itu seluruh gunanya jeda.
          await sink.flush();
          await sink.close();
          throw const _Paused();
        }
        sink.add(chunk);
        _received += chunk.length;
        onProgress?.call(
            total == null || total == 0 ? null : _received / total);
      }
      await sink.flush();
      await sink.close();
      _received = 0;
      return file;
    } finally {
      _client?.close();
      _client = null;
    }
  }
}

/// Menerjemahkan galat teknis jadi satu kalimat yang berguna.
///
/// Yang dilempar http dan dart:io ditulis untuk yang menulis
/// programnya: "ClientException with SocketException: Connection reset
/// by peer (OS Error: Connection reset by peer, errno = 54), address
/// = objects.githubusercontent.com, port = 443". Orang yang membacanya
/// tidak bisa berbuat apa pun dengan satu pun kata di dalamnya, dan
/// paragraf sepanjang itu di layar HP terbaca seperti aplikasinya yang
/// rusak — padahal yang terjadi cuma sinyalnya putus.
///
/// Yang perlu dia tahu cuma dua: apa yang gagal, dan apakah mencoba
/// lagi masuk akal.
String downloadErrorMessage(Object e) {
  if (e is _BadStatus) {
    // 404 berarti berkasnya memang tidak ada di sana — mengulanginya
    // akan gagal dengan cara yang sama persis, dan mengatakan
    // "masalah koneksi" cuma mengirim orang memeriksa wifi-nya
    // berulang kali untuk sesuatu yang bukan salahnya.
    return e.status == 404
        ? 'Berkas pembaruannya tidak ditemukan di server.'
        : 'Unduhan gagal — server sedang tidak bisa melayani '
            '(kode ${e.status}).';
  }
  if (e is SocketException ||
      e is HttpException ||
      e is HandshakeException ||
      e is TimeoutException ||
      e is ClientException) {
    return 'Unduhan gagal karena masalah koneksi.';
  }
  if (e is FileSystemException) {
    return 'Unduhan gagal — ruang penyimpanan HP tidak cukup.';
  }
  return 'Unduhan gagal. Coba lagi sebentar lagi.';
}


/// Dijeda orangnya. Berkas separuhnya dipertahankan.
class _Paused implements Exception {
  const _Paused();
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _BadStatus implements Exception {
  final int status;

  const _BadStatus(this.status);
}
