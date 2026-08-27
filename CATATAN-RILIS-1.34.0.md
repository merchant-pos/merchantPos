# Merchant-POS 1.34.0 — Bayar Tunai di Kasir, Penanda Pengajuan, Logo Baru

## Yang harus kamu lakukan lebih dulu

Jalankan file ini di SQL Editor Supabase:

```
supabase/customer_cash_payment.sql
```

Aman dijalankan berulang kali. Kalau belum dijalankan:

- pelanggan yang memilih bayar tunai akan gagal dilunasi di kasir
  (kolom `cash_received` belum ada), dan
- notifikasi hasil persetujuan setoran/top up **tidak akan pernah
  bunyi** — kedua tabelnya belum disiarkan realtime.

Kalau tiga file berikut belum sempat dijalankan dari rilis sebelumnya,
jalankan juga: `supabase/employee_surrogate_key.sql`,
`supabase/promo_banner.sql`, dan **ulangi**
`supabase/rilis_setor_petty_inbox.sql`.

## Bayar tunai untuk pesanan dari HP pelanggan

Di keranjang sekarang ada pilihan **QRIS** atau **Tunai**.

Memilih Tunai berarti pesanannya **selesai dibuat saat itu juga** dan
langsung diteruskan ke dapur — yang tertunda cuma uangnya. Layar
penutupnya menampilkan nomor pesanan besar-besar berikut ajakan ke
kasir, dan statusnya "Menunggu Pembayaran" sampai kasir menerima
uangnya.

### Menu baru: Pending Payment

Ada di **Kasir, Admin, dan Owner**. Isinya antrean pesanan yang menunggu
dilunasi, lengkap dengan totalnya. Tiap baris punya:

- **Detail** — rincian item, catatan, biaya service, dan PPN-nya, supaya
  pertanyaan "kok segini?" bisa dijawab tanpa menebak.
- **Terima Pembayaran** — dialog uang diterima dan kembalian yang sama
  persis dengan checkout kasir.

Begitu dilunasi, pesanannya **hilang dari Pending Payment dan muncul di
Riwayat Transaksi**. Uangnya memang lewat laci, jadi ikut dihitung saat
tutup shift. Pesanan mandiri yang dibayar QRIS tetap tidak masuk situ —
uangnya langsung ke rekening.

## Penanda merah untuk yang belum diurus

- **Finance & Owner** — kartu *Setor Saldo Cash* dan *Saldo &
  Pengeluaran* membawa bulatan merah berisi jumlah pengajuan yang masih
  menunggu keputusan.
- **Di dalam Petty Cash** — tanggal yang menyimpan pengajuan diberi
  bulatan merah, dan **hari itu terbuka sendiri**, jadi tidak perlu
  menyisir tanggal demi tanggal untuk menemukan tiga baris yang
  menunggu.
- **Kotak Masuk** — jumlah pesan belum dibaca pindah dari judul ke
  bulatan merah.

## Notifikasi hasil pengajuan

Begitu Finance menyetujui, mengonfirmasi, atau menolak, HP yang
mengajukan berbunyi — beserta alasannya kalau penolakannya disertai
catatan. Kanalnya sendiri (*Hasil Pengajuan*), jadi kasir yang
membisukan notifikasi pesanan tetap mendengar kabar soal uang yang dia
pertanggungjawabkan.

## QR Meja: berbingkai Merchant-POS, bisa disimpan, bisa borongan

- Kartunya kini bergaya Merchant-POS: bidang ungu bergradasi, siku amber di
  keempat pojok, nama resto, QR-nya, dan nomor meja di pil amber.
- **Simpan ke galeri** (album Merchant-POS), bagikan, atau cetak.
- **Mode Banyak Meja** — isi awalan opsional (`A`, `VIP-`) plus rentang
  nomor, maksimal 100 sekali jalan, lalu **Download Semua**. Nomornya
  otomatis diberi nol di depan (`08`…`12`) supaya urutannya benar di
  galeri.

## Logo baru

Garpu dan sendok diganti monogram **K berpanah** — nama mereknya sendiri,
ditambah arah jalan pesanan. Warnanya tidak berubah. Sudah dipakai di
ikon aplikasi, splash, header, ikon notifikasi, dan halaman promosi.

## Perbaikan penting

**Pesanan tunai dari HP sempat akan tercatat masuk ke GL QRIS.** Dua
tempat berjauhan sama-sama memetakan setiap pesanan mandiri ke QRIS
tanpa melihat cara bayarnya — benar pada waktunya, karena dulu QRIS
memang satu-satunya pilihan. Jumlah uangnya tidak akan salah, tapi
kantongnya salah, dan baru ketahuan saat mencocokkan mutasi QRIS yang
tidak pernah ada. Sekarang cara bayar yang disebut pesanannya yang
dipakai; pesanan lama yang memang tidak menyebutkannya tetap dibaca
sebagai QRIS.
