// Penerima notifikasi saat tabnya tidak sedang dibuka.
//
// Berkas ini berjalan di luar aplikasi Flutter — ia hidup sendiri di
// peramban, dan tetap dibangunkan saat seluruh tab KaataGo sudah
// ditutup. Karena itu konfigurasinya ditulis lagi di sini: kode Dart
// yang memuatnya sudah tidak berjalan pada saat notifikasinya tiba.
//
// Namanya tidak boleh diubah. Firebase JS SDK mencarinya persis dengan
// nama ini, di akar domain.
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyABO3rT8rfCYYSLd5_9T4A2SLMSyIV6jJ0',
  authDomain: 'kaata-pos.firebaseapp.com',
  projectId: 'kaata-pos',
  storageBucket: 'kaata-pos.firebasestorage.app',
  messagingSenderId: '1015088896093',
  appId: '1:1015088896093:web:ab98850f46bddba60e55b4',
});

const messaging = firebase.messaging();

// Pesan yang membawa blok `notification` ditampilkan peramban sendiri.
// Yang ditangani di sini hanya pesan data-saja — supaya notifikasinya
// tetap muncul, bukan hilang tanpa jejak.
messaging.onBackgroundMessage((payload) => {
  if (payload.notification) return;
  const data = payload.data || {};
  self.registration.showNotification(data.title || 'KaataGo', {
    body: data.body || '',
    icon: 'icons/Icon-192.png',
    data: data,
  });
});

// Ketukan adalah pernyataan niat: orangnya ingin melihat hal itu,
// sekarang. Kalau tab KaataGo sudah terbuka, tab itu yang dimunculkan
// ke depan — membuka tab kedua ke aplikasi yang sama hanya membuat dua
// salinan yang saling tidak tahu.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const tujuan = self.registration.scope.replace(
    'firebase-cloud-messaging-push-scope/', '');
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((daftar) => {
        for (const klien of daftar) {
          if (klien.url.startsWith(tujuan) && 'focus' in klien) {
            return klien.focus();
          }
        }
        return self.clients.openWindow(tujuan);
      })
  );
});
