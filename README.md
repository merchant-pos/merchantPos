# MerchantPOS

Aplikasi POS + pesan-sendiri untuk merchant, dibangun dengan Flutter.

Salinan dari KaataGo, dengan satu keputusan penting yang perlu diingat
oleh siapa pun yang menyentuh kode ini:

## Backend-nya dipakai bersama KaataGo

Supabase dan Firebase-nya sama persis dengan yang dipakai KaataGo. Yang
berbeda cuma merek dan aplikasinya. Konsekuensinya:

- **Datanya satu.** Merchant, menu, pesanan, pelanggan, voucher, dan
  pembukuan yang muncul di aplikasi ini adalah yang sama dengan yang di
  KaataGo. Tidak ada penyaring yang memisahkannya.
- **Perubahan SQL berlaku untuk keduanya.** Berkas di `supabase/`
  sengaja tidak ikut diganti namanya — isinya milik backend bersama,
  dan menjalankan versi yang sudah "dirapikan" akan merusak KaataGo.
- **Dua konstanta sengaja tetap bernama KaataGo**, karena nilainya
  dicocokkan apa adanya oleh Postgres. Keduanya diberi penjelasan
  panjang di tempatnya: `kPlatformRestoId` (`lib/models/billing.dart`)
  dan `kSubjekChatUmum` (`lib/models/support_ticket.dart`). Jangan
  diganti.
- **Teks yang dibuat database masih menyebut KaataGo** — misalnya pesan
  penolakan voucher pengguna baru. Itu tidak bisa dibedakan per aplikasi
  selama backend-nya satu.

Kalau suatu hari kedua produk ini harus benar-benar terpisah,
memisahkannya jauh lebih mahal setelah ada data sungguhan.

## Yang belum diisi

- `lib/utils/tautan_meja.dart` → `kAlamatWeb` masih menunjuk situs
  KaataGo
- `.github/workflows/web.yml` → `REPO_SITUS`, dan pemicu push-nya masih
  dimatikan
- `scripts/release.sh` → repo rilis dan landing page
- `android/BACA-DULU-KUNCI-RILIS.md` → kunci penandatangan rilis
- Firebase: aplikasi Android baru untuk `com.gamskahfi.merchantpos`,
  berikut `google-services.json`-nya dan sidik jari SHA-1-nya
