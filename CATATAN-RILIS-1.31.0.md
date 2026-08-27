# MerchantPOS 1.31.0 — Owner & Multi-Resto

## Yang harus kamu lakukan lebih dulu

> **Perbaikan:** percobaan pertama gagal dengan
> `column "resto_id" ... contains null values`. Penyebabnya baris
> super_admin memang ber-`resto_id` NULL, sementara kunci utama menolak
> NULL. File sudah diperbaiki — memakai unique index, bukan kunci utama —
> jadi jalankan ulang file yang sama. Perlu APK 1.31.1 atau lebih baru.

Jalankan **satu file** ini di SQL Editor Supabase:

```
supabase/owner_multi_resto.sql
```

Isinya sudah digabung jadi satu dan aman dijalankan berulang kali. Kalau
belum dijalankan, aplikasi versi ini akan menolak login akun Owner dan
belum bisa membaca resto kedua.

## Cara membuat Owner / akun multi-resto

Lewat **Super Admin → Kelola Karyawan**:

- **Owner** — pilih peran "Owner" pada salah satu resto. Dia langsung
  memegang seluruh menu Kasir, Admin, Chef, dan Finance di resto itu.
- **Multi-resto** — tambahkan email yang sama sekali lagi, dengan resto
  yang berbeda. Satu email kini boleh punya beberapa baris, satu per
  resto. Berlaku untuk Admin, Finance, dan Owner.

Kalau satu orang diberi peran berbeda di tiap cabang, yang dipakai adalah
peran pada baris pertama — aplikasi ini tidak dirancang untuk satu orang
berganti peran saat berpindah cabang.

## Yang berubah di aplikasi

**Peran Owner.** Layar utamanya mengelompokkan tiga belas menu jadi
Penjualan, Keuangan, dan Pengelolaan. Daftar rata sepanjang itu memaksa
orang membaca semuanya untuk menemukan satu, padahal pemilik biasanya
sudah tahu sedang mengurus bidang yang mana.

**Pemilih resto.** Muncul di header layar utama sebagai tombol berisi
nama resto yang sedang dibuka — hanya untuk akun yang memegang lebih dari
satu. Ditaruh di depan, bukan di dalam Setelan, karena resto mana yang
aktif menentukan arti setiap angka di layar berikutnya; itu harus terbaca
sebelum orangnya mulai bekerja, bukan setelah dia terlanjur salah membaca
laporan cabang yang keliru. Pilihannya diingat sampai logout.

**Data tidak bercampur.** Ini bagian yang paling banyak memakan pekerjaan
dan tidak terlihat dari luar:

- Seluruh layar peran dibangun ulang dari nol saat resto berganti.
  Kebanyakan layar membaca `restoId` sekali di awal lalu menyimpannya;
  tanpa dipaksa mulai ulang, data cabang lama akan tertinggal di layar.
- Katalog produk dan kategori di penyimpanan lokal HP sebelumnya **tidak
  punya kolom resto sama sekali**. Berpindah cabang akan menggabungkan
  kedua katalog jadi satu daftar — dan lebih buruk lagi, sinkronisasi
  berikutnya akan mendorong produk cabang A ke cabang B. Sekarang
  keduanya bercakupan resto, dengan migrasi lokal yang mengakui produk
  lama sebagai milik resto yang pertama kali membukanya.
- Resto yang dinonaktifkan Super Admin kini disaring dari daftar, bukan
  memblokir seluruh akun: pemilik dua cabang yang satu cabangnya ditutup
  sementara tetap bisa mengurus cabang yang lain.

**Hak akses.** Owner lolos setiap pemeriksaan peran lewat satu perubahan
di dalam `is_resto_employee`, bukan dengan menyebut 'owner' di puluhan
policy. Menyebarkannya berarti setiap policy baru di masa depan berpeluang
lupa menyertakannya — dan lupa di sini bentuknya adalah Owner yang
tiba-tiba kehilangan akses ke satu layar tanpa sebab yang jelas.

## Yang perlu kamu uji

1. Login sebagai Owner — pastikan ketiga belas menunya terbuka semua.
2. Beri satu email dua resto, lalu berpindah lewat tombol di header.
   Periksa Kelola Produk, Pesanan Masuk, dan Saldo & Pengeluaran: isinya
   harus berganti sepenuhnya, tidak ada sisa dari cabang sebelumnya.
3. Tutup aplikasi lalu buka lagi — harus kembali ke resto terakhir yang
   kamu pilih.
