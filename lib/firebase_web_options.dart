import 'package:firebase_core/firebase_core.dart';

/// Konfigurasi Firebase untuk web.
///
/// Di Android nilainya dibaca dari `google-services.json` yang
/// disisipkan Gradle saat membangun. Web tidak punya langkah itu — tidak
/// ada yang menyisipkan apa pun ke dalam bundel JS-nya, jadi nilainya
/// harus ada di kode.
///
/// Ini bukan rahasia. Kunci Firebase Web memang dirancang untuk
/// terlihat: ia ditanam di halaman yang bisa dibuka siapa saja, dan yang
/// menjaga datanya tetap RLS di Supabase, bukan kunci ini. Yang tidak
/// boleh ikut ke sini adalah service account dan server key.
const firebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyABO3rT8rfCYYSLd5_9T4A2SLMSyIV6jJ0',
  authDomain: 'kaata-pos.firebaseapp.com',
  projectId: 'kaata-pos',
  storageBucket: 'kaata-pos.firebasestorage.app',
  messagingSenderId: '1015088896093',
  appId: '1:1015088896093:web:ab98850f46bddba60e55b4',
  measurementId: 'G-YKN6F4THP7',
);

/// Kunci Web Push (VAPID).
///
/// Dipakai peramban untuk membuktikan langganan pushnya benar datang
/// dari proyek ini. Tidak ada padanannya di Android, dan tanpa ini
/// `getToken` di web selalu gagal.
const kVapidKey =
    'BGc99iQVUiiB0yfLhS_keJKPUJG2bP6p-r5KPo1EK58V5xh5WnbTLF-9sLh5FGiNYFEzknNFlXYApmTBXsKbGyI';
