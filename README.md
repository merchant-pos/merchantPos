# MerchantPOS

Aplikasi POS + pesan-sendiri untuk merchant, dibangun dengan Flutter.

**Web saja.** Tidak ada APK, dan alur rilisnya sengaja dihapus —
`release.sh`, pengunggah aset GitHub, dan catatan kunci penandatangan
rilis ikut dibuang. Yang tertinggal cuma alur terbit konsol web.

Folder `android/` sengaja dibiarkan. Ia tidak dipakai, tapi
menghapusnya membuat `flutter` perlu membangkitkannya lagi kalau suatu
hari APK-nya dibutuhkan — dan yang dibangkitkan ulang tidak membawa
serta penyesuaian yang pernah ada di dalamnya.
Berasal dari salinan KaataGo, tapi sejak commit pemisahan ia berdiri
sendiri: proyek Supabase-nya sendiri, datanya sendiri, dan tidak ada
lagi konstanta yang terikat merek lain.

## Backend

Supabase: `pekjbgjmeayxdcaiwhsk`.

Seluruh skema, fungsi, kebijakan RLS, dan pemicunya ada di `supabase/`.
Ada dua penggabung, dan memilih yang salah adalah kesalahan pertama
yang akan dibuat orang di sini:

```
bash scripts/gabung_sql_lengkap.sh   # → JALANKAN-SEMUA.sql  (101 berkas)
bash scripts/gabung_sql.sh           # → JALANKAN-INI.sql    (63 berkas)
```

**Database kosong pakai yang lengkap.** Yang pendek hanya memuat
tambalan sejak database KaataGo sudah berdiri, jadi ia mengandaikan
tabel dasarnya ada — dijalankan di proyek baru, ia berhenti di baris
pertama yang menyentuh `employees`, tabel yang tidak pernah ia buat.

Urutan di dalamnya bukan abjad melainkan urutan berkas-berkas itu dulu
benar-benar dijalankan, dibaca dari riwayat git. Keduanya aman
dijalankan berulang kali.

Butuh tiga ekstensi, dan ketiganya dibuat sendiri oleh bundelnya:
`pgcrypto`, `pg_cron`, `pg_net`.

**Jangan pernah menjalankannya di proyek KaataGo.** Isinya
mendefinisikan ulang fungsi dan pemicu dengan nama merek dan penyewa
platform yang berbeda — yang di KaataGo akan membuat chat tercatat
sebagai pengaduan dan pembukuan platformnya menunjuk penyewa yang tidak
ada, keduanya tanpa satu pun galat yang menyebutkannya.

### Dua nilai yang harus berubah berbarengan

Nilainya ada di Dart dan dicocokkan apa adanya oleh Postgres. Mengubah
salah satu saja tidak pernah menghasilkan galat — hanya layar yang
angkanya nol, atau chat yang diam-diam jadi pengaduan.

| Dart | Nilai | Dipakai SQL |
|---|---|---|
| `kPlatformRestoId` (`lib/models/billing.dart`) | `merchantpos` | 42 tempat |
| `kSubjekChatUmum` (`lib/models/support_ticket.dart`) | `Chat dengan MerchantPOS Admin` | 4 tempat |

## Yang belum diisi

- **SQL-nya belum dijalankan** di proyek Supabase baru — tanpa itu
  aplikasinya terbuka tapi tidak menemukan tabel apa pun. Pakai
  `JALANKAN-SEMUA.sql`
- **8 edge function** belum di-deploy, berikut 9 rahasianya:
  `FCM_SERVICE_ACCOUNT`, `PUSH_HOOK_SECRET`, `RELEASE_HOOK_SECRET`,
  `RESEND_API_KEY`, `XENDIT_SECRET_KEY`, `XENDIT_CALLBACK_TOKEN`,
  `XENDIT_ACCOUNT_ID`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- **Firebase** masih memakai proyek `kaata-pos`. Karena web saja, yang
  dibutuhkan cuma konfigurasi web di `lib/firebase_web_options.dart`
  berikut kunci VAPID-nya — bukan `google-services.json` maupun sidik
  jari SHA-1, yang keduanya hanya berlaku untuk aplikasi Android
- **Auth Google** di proyek Supabase baru: aktifkan providernya, lalu
  daftarkan alamat webnya di Redirect URLs dan Site URL
- `lib/utils/tautan_meja.dart` → `kAlamatWeb` masih menunjuk situs
  KaataGo
- `.github/workflows/web.yml` → `REPO_SITUS`, dan pemicu push-nya masih
  dimatikan supaya tidak menimpa situs KaataGo
- `scripts/release.sh` → repo rilis dan landing page
