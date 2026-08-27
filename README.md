# MerchantPOS

Aplikasi POS + pesan-sendiri untuk merchant, dibangun dengan Flutter.
Berasal dari salinan KaataGo, tapi sejak commit pemisahan ia berdiri
sendiri: proyek Supabase-nya sendiri, datanya sendiri, dan tidak ada
lagi konstanta yang terikat merek lain.

## Backend

Supabase: `pekjbgjmeayxdcaiwhsk`.

Seluruh skema, fungsi, kebijakan RLS, dan pemicunya ada di `supabase/`,
dan digabung jadi satu berkas siap jalan oleh:

```
bash scripts/gabung_sql.sh      # → supabase/JALANKAN-INI.sql
```

Berkas itu aman dijalankan berulang kali.

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
  aplikasinya terbuka tapi tidak menemukan tabel apa pun
- **8 edge function** belum di-deploy, berikut 9 rahasianya:
  `FCM_SERVICE_ACCOUNT`, `PUSH_HOOK_SECRET`, `RELEASE_HOOK_SECRET`,
  `RESEND_API_KEY`, `XENDIT_SECRET_KEY`, `XENDIT_CALLBACK_TOKEN`,
  `XENDIT_ACCOUNT_ID`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- **Firebase** masih memakai proyek `kaata-pos`. Push notif baru jalan
  setelah `com.gamskahfi.merchantpos` didaftarkan sebagai aplikasi
  Android di sana (atau di proyek Firebase sendiri), berikut
  `google-services.json`-nya
- **Login Google**: SHA-1 kunci rilis harus terdaftar untuk package
  barunya — lihat `android/BACA-DULU-KUNCI-RILIS.md`
- `lib/utils/tautan_meja.dart` → `kAlamatWeb` masih menunjuk situs
  KaataGo
- `.github/workflows/web.yml` → `REPO_SITUS`, dan pemicu push-nya masih
  dimatikan supaya tidak menimpa situs KaataGo
- `scripts/release.sh` → repo rilis dan landing page
