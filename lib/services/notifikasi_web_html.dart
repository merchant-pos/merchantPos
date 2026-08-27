// Lint ini menjaga aplikasi yang salah memakai pustaka web di kode
// bersama. Di sini justru itu tugasnya: berkas ini hanya pernah
// dikompilasi untuk web, lewat impor bersyarat di notifikasi_web.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Nada dering yang sama dengan yang dipakai di HP.
///
/// Berkasnya salinan dari `android/app/src/main/res/raw/merchantpos_notif.wav`.
/// Disalin, bukan dirujuk: yang di `res/raw` dibungkus ke dalam APK oleh
/// Gradle dan tidak pernah ikut ke berkas yang dilayani situs web.
///
/// Jalurnya relatif, jadi ia menempel pada base href halamannya —
/// jalur mutlak akan menunjuk akar domain, yang belum tentu tempat
/// aplikasinya tinggal.
const _berkasNada = 'merchantpos_notif.wav';

/// Dibuat sekali, dipakai berkali-kali.
///
/// Elemen audio baru tiap notifikasi berarti berkasnya diambil lagi
/// dari jaringan tiap kali, dan bunyinya terlambat beberapa ratus
/// milidetik dari notifikasi yang seharusnya ia temani.
html.AudioElement? _audio;

/// Menampilkan notifikasi peramban, lengkap dengan nadanya.
///
/// Izinnya sudah diminta lebih dulu oleh Firebase Messaging saat token
/// diambil; kalau ditolak, `permission` bukan 'granted' dan panggilan
/// ini diam saja. Melemparkan galat di sini tidak ada gunanya — orang
/// yang menolak izin notifikasi sedang menyatakan pilihannya, bukan
/// mengalami kerusakan.
void tampilkanNotifWeb({
  required String judul,
  required String isi,
  String? tag,
}) {
  if (html.Notification.permission != 'granted') return;
  // `tag` membuat pesan yang sama tidak berbaris dua kali: yang baru
  // menimpa yang lama alih-alih menumpuk.
  html.Notification(judul, body: isi, tag: tag);
  bunyikanNadaWeb();
}

/// Membunyikan nada notifikasi.
///
/// Notification API tidak punya cara memasang nada sendiri — pilihan
/// `sound` ada di spesifikasinya tapi tidak pernah dijalankan satu pun
/// peramban. Jadi nadanya dibunyikan terpisah oleh halamannya sendiri,
/// dan itu hanya mungkin selama halamannya masih hidup.
void bunyikanNadaWeb() {
  try {
    final audio = _audio ??= html.AudioElement(_berkasNada)..preload = 'auto';
    // Diputar ulang dari awal: notifikasi kedua yang datang sebelum
    // yang pertama selesai berbunyi tidak akan terdengar sama sekali
    // kalau pemutarnya dibiarkan di posisi terakhir.
    audio.currentTime = 0;
    // Peramban menolak memutar suara sebelum halamannya pernah
    // disentuh orangnya. Penolakan itu datang sebagai Future yang
    // gagal, bukan lemparan — dan mengabaikannya benar: yang belum
    // menyentuh apa pun juga belum menunggu kabar apa pun.
    audio.play().catchError((_) {});
  } catch (_) {
    // Berkas nadanya tidak ada atau formatnya ditolak. Notifikasinya
    // sudah terlanjur tampil, dan itu bagian yang penting.
  }
}
