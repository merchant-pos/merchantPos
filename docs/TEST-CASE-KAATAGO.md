# MerchantPOS — Test Case

**Versi Aplikasi:** 2.12.0 (build 118)
**Versi Dokumen:** 1.8
**Tanggal Terbit:** 22 Agustus 2026
**Status:** Rilis
**Jenis Dokumen:** Test Case — pengujian manual

> **Berkas kerjanya adalah `TEST-CASE-KAATAGO.xlsx`**, dihasilkan dari
> markdown ini lewat `scripts/test_case_ke_xlsx.py`. Isi hasil pengujian
> di sana, bukan di sini — spreadsheet bisa disaring per prioritas,
> diurutkan per modul, dan menghitung rekapnya sendiri. Sesudah mengubah
> markdown ini, bangun ulang xlsx-nya:
>
> ```
> /usr/bin/python3 scripts/test_case_ke_xlsx.py
> ```
>
> Lima lembar: **Rekap** (menghitung sendiri), **Kasus Uji**,
> **Defect** (daftar temuan berikut tombol pembuka folder capture di
> Google Drive), **Prasyarat**, dan **Cara Lampirkan Capture**. Temuan
> dicatat di lembar Defect, bukan di dokumen ini.

Dokumen ini menerjemahkan `FSD-KAATAGO` dan `TSD-KAATAGO` jadi langkah
yang bisa dijalankan orang. Tiap kasus uji menyebut kebutuhan yang
dijaganya, supaya jelas apa yang rusak kalau kasusnya gagal — bukan
sekadar "ada yang aneh di layar ini".

Kolom **P** adalah prioritas:

| P | Artinya | Kalau gagal |
|---|---|---|
| **P1** | Menyangkut uang, atau menghalangi transaksi | Rilis ditahan |
| **P2** | Fungsi utama, ada jalan memutarnya | Diperbaiki sebelum rilis berikutnya |
| **P3** | Tampilan dan kenyamanan | Dicatat, dijadwalkan |

---

## Daftar Isi

1. Cara memakai dokumen ini
2. Prasyarat lingkungan uji
3. Yang sudah dijaga tes otomatis
4. Pelanggan
5. Kasir
6. Pending Payment
7. Dapur
8. Keuangan
9. Setor Saldo Cash
10. Katalog & Pengaturan
11. QR Meja
12. Diskon
13. Kotak Masuk & Pengumuman
14. Pembayaran QRIS
15. Pembatalan & Kedaluwarsa
16. Sesi Meja & Identitas
17. Tampilan
18. Super Admin
19. Pembaruan Aplikasi
19b. Langganan & Tagihan Resto
19c. Finance MerchantPOS (Super Admin)
19d. Voucher Pelanggan
19e. Analisa Pasar
19f. Nomor Pesanan Harian
19g. Layar Pelanggan
19h. Fasilitas & Jam Buka
19i. Penilaian Merchant
19j. Label & Penilaian Menu
19k. Shift Kasir
20. Uji Ujung-ke-Ujung
21. Uji Teknis (lingkup TSD)
22. Regresi — bug yang pernah terjadi
23. Matriks Keterlacakan

---

## 1. Cara memakai dokumen ini

Tiap kasus uji punya satu hasil yang diharapkan, dan hasil itu ditulis
sebagai keadaan yang bisa dilihat — bukan sebagai "berfungsi normal".
"Berfungsi normal" adalah kalimat yang selalu bisa dicentang, dan karena
itu tidak pernah menemukan apa pun.

Kolom **Rujukan** menunjuk ke ID kebutuhan di FSD (`F-XX-NN`), kriteria
penerimaan (`A-NN`), atau bab TSD (`TSD §N`). Lampiran A di FSD memuat
208 tangkapan layar per peran — pakai itu sebagai pembanding tampilan
saat sesuatu terlihat berbeda dari yang tertulis di sini.

**Temuan ditulis apa adanya, bukan disaring dulu.** Perbedaan antara
dokumen dan aplikasi adalah temuan yang layak dilaporkan — bukan
kesalahan pembacaan penguji. Kalau dokumennya yang salah, itu juga
temuan.

---

## 2. Prasyarat lingkungan uji

Tanpa ini, sebagian besar kasus di bawah akan gagal karena sebab yang
tidak ada hubungannya dengan yang sedang diuji.

| # | Prasyarat | Kenapa |
|---|---|---|
| L-01 | Seluruh berkas SQL di `supabase/JALANKAN-INI.sql` (27 bagian) sudah dijalankan | Kolom yang belum ada membuat penyimpanan gagal dengan pesan yang menyesatkan |
| L-02 | Akun tersedia untuk tiap peran: Pelanggan, Kasir, Chef, Admin, Finance, Owner, Super Admin | Peran diambil dari tabel `employees`, bukan dari pilihan di layar |
| L-03 | Minimal **dua** resto, dan satu akun Owner yang memiliki keduanya | Isolasi antar cabang tidak bisa diuji dengan satu resto |
| L-04 | Resto uji punya bagan akun GL lengkap dan tarif PPN/service terisi | Baris yang GL-nya kosong dilewati pemicu jurnal — transaksinya terjadi, catatannya tidak |
| L-05 | Rekening bank resto sudah diisi di Info Pembayaran | Tombol setor mati tanpa ini |
| L-06 | Minimal 4 produk di 2 kategori, satu di antaranya punya kelompok level | Diskon bundling dan varian butuh lebih dari satu menu |
| L-07 | Perangkat Android sungguhan, bukan emulator, untuk uji notifikasi dan unduhan | Emulator tidak menerima FCM dengan andal |
| L-08 | Izin notifikasi dan lokasi sudah diberikan | Sebagian layar berperilaku berbeda sebelum izin diberikan — itu sendiri diuji terpisah |

> **Catat versi APK yang diuji.** Sebagian bug hanya muncul pada versi
> tertentu, dan laporan tanpa nomor versi tidak bisa ditelusuri.

---

## 3. Yang sudah dijaga tes otomatis

924 tes berjalan tiap kali kode diubah. Menguji ulang hal-hal ini secara
manual bukan salah, tapi waktunya lebih berguna di tempat lain.

| Sudah dijaga tes | Berkas |
|---|---|
| Perhitungan pajak dan pembulatan | `tax_calculator_test`, `cash_balance_test` |
| Pemilihan diskon, bundling, syarat jumlah | `discount_test` (31 tes) |
| Aturan pembatalan dan status pesanan | `cancel_order_test`, `pending_payment_test` |
| Token warna tema terang/gelap | `dark_mode_test`, `theme_switch_test` |
| Daftar nilai batasan di berkas SQL | `default_gl_test` |
| Pesan galat unduhan | `download_error_test` |
| Aturan isian dan ketersediaan produk | `field_rules_test`, `out_of_stock_test` |
| Label menu, ringkasan angka terjual | `label_menu_test` |
| Keterangan promo di dialog pesan | `deskripsi_diskon_test` |
| Aturan shift kasir dan letak menunya | `shift_kasir_test`, `hub_grouping_test` |
| Foto menu bertahan dari pembaruan stok | `foto_menu_bertahan_test` |
| Nilai kembalian tombol Batal di dialog | `dialog_batal_test` |

**Yang tidak bisa dijaga tes otomatis, dan karena itu jadi isi dokumen
ini:** apa pun yang melibatkan Supabase sungguhan, perangkat sungguhan,
uang sungguhan, dan mata orang yang melihat layarnya.

---

## 4. Pelanggan

Peran dengan permukaan terluas, dan satu-satunya yang dipakai orang yang
tidak pernah dilatih memakainya.

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-CU-01 | P1 | Buka aplikasi → Pelanggan → **Lewati, Pesan Tanpa Login** → pesan sampai selesai | Seluruh alur bisa dituntaskan tanpa membuat akun | F-CU-01, A-01 |
| TC-CU-02 | P1 | Scan QR meja sebuah resto | Menu resto terbuka, nomor meja terisi sendiri dan **tidak bisa diubah** | F-CU-02, F-CU-03 |
| TC-CU-03 | P2 | Pilih Resto tanpa memberi izin lokasi | Hanya bagian **Semua Resto** tampil; tidak ada galat, tidak ada bagian kosong berjudul "Terdekat" | F-CU-02 |
| TC-CU-04 | P2 | Beri izin lokasi, buka Pilih Resto lagi | Bagian **Terdekat** muncul berikut jarak tiap resto | F-CU-02 |
| TC-CU-05 | P2 | Cari resto dengan potongan alamat, bukan namanya | Resto yang alamatnya cocok ikut muncul | F-CU-02 |
| TC-CU-06 | P2 | Buka menu minuman yang punya tiga kelompok level | Ketiga kelompok tampil sekaligus; tiap kelompok wajib dipilih | F-CU-04 |
| TC-CU-07 | P2 | Tambahkan Nasi Goreng "Pedas", lalu Nasi Goreng "Tidak Pedas" | Keranjang berisi **dua baris terpisah**, bukan satu baris berjumlah 2 | F-CU-05 |
| TC-CU-08 | P2 | Tambahkan menu yang sama dengan level dan catatan persis sama, dua kali | Menyatu jadi **satu baris** berjumlah 2 | F-CU-05 |
| TC-CU-09 | P2 | Ubah jumlah dan hapus baris dari keranjang | Subtotal dan total ikut berubah seketika | F-CU-06 |
| TC-CU-10 | P1 | Pilih **Take Away** | Nomor meja **tidak diminta**; nama pemesan tetap wajib | F-CU-07, F-CU-08 |
| TC-CU-11 | P1 | Pilih **Dine In**, kosongkan nomor meja | Tombol bayar mati; petunjuknya menyebut kolom mana yang kurang | F-CU-07 |
| TC-CU-12 | P1 | Periksa ringkasan tagihan | Subtotal + biaya service + PPN = total, persis, tanpa selisih pembulatan | F-CU-10, A-04 |
| TC-CU-13 | P2 | Resto yang hanya melayani Dine In | Pilihan Take Away **tidak muncul sama sekali**, bukan muncul lalu ditolak | F-CU-23 |
| TC-CU-14 | P1 | Selesaikan pesanan, biarkan layar terbuka, minta kasir mengubah statusnya | Status di HP berubah sendiri tanpa disegarkan | F-CU-11 |
| TC-CU-15 | P2 | Buka Riwayat sebagai tamu | Riwayat tampil, disertai keterangan bahwa datanya hanya tersimpan di HP ini | F-CU-12 |
| TC-CU-16 | P2 | Ubah nama dan nomor HP di Profil, lalu hapus foto | Perubahan tersimpan; foto benar-benar hilang, bukan kembali setelah dibuka ulang | F-CU-14 |
| TC-CU-17 | P3 | Ketuk **Buka di Google Maps** dari halaman menu | Peta terbuka pada titik resto itu | F-CU-15 |
| TC-CU-18 | P2 | Gulir daftar menu ke bawah | Banner promo **ikut tergulir**, tidak menempel di atas | F-CU-16, A-12 |
| TC-CU-19 | P2 | Ketuk banner promo | Gambar tampil utuh, tidak terpotong, berikut keterangan dan periodenya | F-CU-16 |
| TC-CU-20 | P1 | Pesan menu yang sedang ada promonya | Potongan tampil sebagai baris tersendiri berikut nama promonya | F-CU-17, F-DS-07 |
| TC-CU-21 | P2 | Buka menu yang ditandai habis | Tetap tampil dengan tanda habis; tombol tambah **tidak aktif** | F-CU-21 |
| TC-CU-22 | P1 | Isi keranjang → minta admin menandai salah satu menu habis → tekan bayar | Ditolak dengan sebutan menu mana; menunya harus dihapus dulu | F-CU-22 |
| TC-CU-23 | P3 | Buka Kotak Masuk dari menu utama | Berisi promo resto yang pernah dipesan, tiap pesan menyebut **nama restonya** | F-CU-20, F-IN-13 |
| TC-CU-24 | P2 | Kotak Masuk → pilih beberapa → Hapus | Hanya yang terpilih hilang, dan hanya dari kotak masuk orang ini | F-IN-03, F-IN-15 |
| TC-CU-25 | P3 | Ganti tampilan dari menu utama pelanggan | Tema berganti seketika dan bertahan setelah aplikasi ditutup | F-CU-24, F-TM-03 |

---

## 5. Kasir

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-KS-01 | P2 | Buka Input Pesanan | Menu tersusun per kategori; sisa stok tampil di pojok kartu | F-KS-01 |
| TC-KS-02 | P1 | Checkout Dine In tanpa nomor meja | Ketiga tombol pembayaran mati | F-KS-04 |
| TC-KS-03 | P1 | Checkout Take Away tanpa nama pelanggan | Tombol pembayaran mati; yang diminta nama, bukan nomor meja | F-KS-08 |
| TC-KS-04 | P1 | Bayar tunai, isi uang **kurang** dari total | Tombol terima mati; kembalian tidak dihitung | F-KS-04 |
| TC-KS-05 | P1 | Bayar tunai Rp 100.000 untuk tagihan Rp 61.050 | Kembalian tertulis Rp 38.950 | F-KS-03 |
| TC-KS-06 | P2 | Pakai tombol nominal cepat | Nilainya masuk ke kolom uang diterima, kembaliannya ikut berubah | F-KS-03 |
| TC-KS-07 | P1 | Selesaikan pembayaran tunai | Stok menu berkurang sesuai jumlah yang dipesan | F-KS-01 |
| TC-KS-08 | P1 | Periksa struk hasil pembayaran tunai | Memuat nama kasir, uang bayar, dan kembaliannya | F-KS-05 |
| TC-KS-09 | P2 | Simpan struk ke galeri, bagikan, dan cetak | Ketiganya berhasil; hasil cetaknya terbaca | F-KS-05 |
| TC-KS-10 | P2 | Buka Riwayat Kasir → pilih transaksi lama → cetak ulang | Struk lama tampil apa adanya, termasuk diskon yang berlaku saat itu | F-KS-06, F-DS-08 |
| TC-KS-11 | P1 | Riwayat Kasir hari ini | Dikelompokkan per hari; rincian per metode bayar berjumlah sama dengan totalnya | F-KS-07, A-03 |
| TC-KS-12 | P1 | Bayar QRIS di kasir, periksa nominal di layar QR | Nominalnya **sudah termasuk** service dan PPN, dan sudah dikurangi diskon | F-KS-09, F-KS-11 |
| TC-KS-13 | P2 | Ketuk **Cetak QR untuk Customer** | QR berbingkai MerchantPOS tercetak, bisa dipindai | F-KS-10 |
| TC-KS-14 | P1 | Isi keranjang → tandai salah satu menu habis dari perangkat lain → terima pembayaran | Ditolak sebelum uang diterima | F-KS-12 |
| TC-KS-15 | P2 | Saldo & Pengeluaran → buka salah satu baris | Rincian jurnal GL di baliknya terbuka, isinya sama dengan yang dilihat Finance | F-KS-13 |
| TC-KS-16 | P2 | Buka Diskon dari hub Kasir → Ubah Diskon | Daftar menu termuat; **tidak** tertulis "Belum ada produk di resto ini" | F-DS-01 |

---

## 6. Pending Payment

Antrean yang menghubungkan pesanan dari HP pelanggan dengan uang tunai
di konter. Paling banyak kasus P1 di seluruh dokumen ini, karena tiap
kegagalan di sini berarti uang yang tidak tercatat atau tercatat dua
kali.

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-PP-01 | P1 | Pelanggan memesan, pilih Tunai | Pesanannya muncul di Pending Payment dalam hitungan detik | F-PP-01 |
| TC-PP-02 | P1 | Periksa kepala layar | Jumlah pesanan dan total nominal yang menunggu tampil dan cocok dengan isi daftarnya | F-PP-02 |
| TC-PP-03 | P2 | Buka rincian sebuah pesanan | Item, catatan, biaya service, PPN, dan total tampil lengkap | F-PP-03 |
| TC-PP-04 | P1 | Ketuk tombol terima pembayaran **dua kali beruntun** | Pesanan lunas **sekali**; tidak ada jurnal ganda, tidak ada dua baris di Riwayat Kasir | F-PP-05 |
| TC-PP-05 | P1 | Selesaikan pelunasan | Pesanan hilang dari antrean seketika tanpa disegarkan | F-PP-06 |
| TC-PP-06 | P1 | Lunasi dengan **Tunai** | Muncul di Riwayat Kasir dan ikut dihitung di total harian | F-PP-07, A-13 |
| TC-PP-07 | P1 | Lunasi dengan cara bayar diganti ke **QRIS** | Tetap muncul di Riwayat Kasir | F-PP-09, A-13 |
| TC-PP-08 | P1 | Lunasi dengan cara bayar diganti ke **Transfer** | Tetap muncul di Riwayat Kasir | F-PP-09, A-13 |
| TC-PP-09 | P2 | Periksa penanda merah di kartu menu | Angkanya sama dengan jumlah antrean sebenarnya | F-PP-08 |
| TC-PP-10 | P2 | Perhatikan sisa waktu di kartu | Menghitung mundur; berubah warna pada 10 menit terakhir | F-PP-10, F-CU-19 |
| TC-PP-11 | P1 | Pesanan QRIS yang belum dibayar | **Tidak** muncul di Pending Payment — antrean ini hanya untuk yang bayar di kasir | F-PP-01 |
| TC-PP-12 | P1 | Pelanggan membatalkan pesanannya saat kartunya terbuka di kasir | Kartunya hilang dari antrean; kasir tidak bisa menerima uang untuk pesanan batal | F-CN-01 |

---

## 7. Dapur

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-CH-01 | P2 | Buka layar dapur | Empat tab: Menunggu Bayar, Baru, Diproses, Selesai | F-CH-01 |
| TC-CH-02 | P1 | Pesanan tunai yang belum dilunasi | Ada di tab **Menunggu Bayar**, tidak bercampur di Baru | F-CH-06, A-16 |
| TC-CH-03 | P1 | Buka kartu di tab Menunggu Bayar | **Tidak ada** tombol Mulai Masak; yang tampil keterangan menunggu pembayaran | F-CH-07, A-16 |
| TC-CH-04 | P1 | Kasir melunasi pesanan itu | Kartunya berpindah ke tab **Baru** berikut tombol Mulai Masak | F-CH-06 |
| TC-CH-05 | P2 | Mulai Masak, centang sebagian menu | Tombolnya berbunyi **Simpan Progres**; pesanan tetap di Diproses | F-CH-02 |
| TC-CH-06 | P2 | Centang seluruh menu | Tombolnya berubah jadi **Tandai Pesanan Selesai** | F-CH-02 |
| TC-CH-07 | P2 | Buka tab Selesai | Dikelompokkan per tanggal, seluruhnya **tertutup** saat pertama dibuka | F-CH-03 |
| TC-CH-08 | P1 | Pelanggan membatalkan pesanan yang masih di tab Baru | Kartunya hilang dari **semua** tab | F-CH-08, A-17 |
| TC-CH-09 | P1 | Biarkan pesanan tunai lewat 30 menit | Kartunya hilang dari semua tab | F-CH-08, F-CN-05 |
| TC-CH-10 | P2 | Buka layar dapur sebagai **Owner** | Tombol Keluar, Kotak Masuk, Tes Notifikasi, dan Tampilan tidak ada | F-CH-05 |
| TC-CH-11 | P3 | Ganti tema dari layar dapur | Seluruh isi layar ikut berganti — tidak ada kartu yang tertinggal warna lama | F-TM-02, A-18 |
| TC-CH-12 | P3 | Periksa judul tiap tab | Terbaca rata tengah | — |

---

## 8. Keuangan

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-FN-01 | P1 | Bandingkan Saldo Total dengan hitungan tangan | Saldo Total = Penghasilan + Petty Cash + Setoran − Pengeluaran | F-FN-01 |
| TC-FN-02 | P1 | Bandingkan Saldo Cash dengan isi laci fisik saat tutup shift | Cocok rupiah demi rupiah | F-FN-02, A-03 |
| TC-FN-03 | P1 | Kasir mengajukan top up petty cash Rp 100.000 → Finance menyetujui | Petty Cash bertambah **Rp 100.000**, bukan Rp 200.000 | F-FN-03 |
| TC-FN-04 | P1 | Buka jurnal dari pengajuan yang baru disetujui | Dua baris: titipan suspense **dilepas**, dana masuk ke akun tujuan | TSD §6.4 |
| TC-FN-05 | P1 | Tolak sebuah pengajuan top up | Dananya kembali ke asal; tidak ada sisa tersangkut di akun suspense | F-SD-05, A-05 |
| TC-FN-06 | P1 | Catat pengeluaran melebihi saldo petty cash | Ditolak, dengan sebutan saldo tersedia | F-FN-04 |
| TC-FN-07 | P2 | Lampirkan foto nota pada pengeluaran, lalu buka lagi | Fotonya tersimpan dan bisa dibuka besar | F-FN-05, F-SD-06 |
| TC-FN-08 | P2 | Buka Riwayat Pengeluaran | Dikelompokkan per tanggal dan **tertutup** secara bawaan | F-FN-06 |
| TC-FN-09 | P2 | Buat pengajuan, buka Riwayat lagi | Tanggal yang menyimpan pengajuan **terbuka sendiri** dan bertanda merah | F-FN-07 |
| TC-FN-10 | P1 | Buka jurnal GL di balik sebuah pesanan lunas | Baris pemasukan, PPN, dan service tercatat terpisah, jumlahnya sama dengan totalnya | F-FN-08, TSD §6 |
| TC-FN-11 | P1 | Periksa arah debit/kredit di Jurnal GL | Kredit = uang masuk, debit = uang keluar; arah panah mengikuti | TSD §6.1 |
| TC-FN-12 | P1 | Periksa jurnal pesanan berdiskon | Diskon tercatat sebagai **debit** pada GL Diskon, bukan sebagai pengeluaran | F-DS-09, TSD §6.3 |
| TC-FN-13 | P2 | Ubah nomor GL sebuah metode bayar, lalu buat transaksi baru | Transaksi baru memakai nomor baru; jurnal lama tidak berubah | F-FN-09 |
| TC-FN-14 | P1 | Ubah tarif PPN dari 11% ke 12%, buat pesanan baru | Tagihan baru memakai 12%; pesanan lama tetap 11% | F-FN-10 |
| TC-FN-15 | P2 | Cetak/ekspor Laporan Transaksi untuk rentang tanggal | PDF terbentuk; saldo awal + mutasi = saldo akhir | F-FN-11 |
| TC-FN-16 | P2 | Ganti resto dari pemilih di atas | Seluruh angka di menu Finance ikut berganti | F-AD-08, A-10 |
| TC-FN-17 | P2 | Hapus sebuah pengeluaran yang sudah terjurnal | Jurnalnya **tidak dihapus**; muncul baris balikan | TSD §6.5 |

---

## 9. Setor Saldo Cash

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-SD-01 | P1 | Ajukan setoran berikut nominal, catatan, dan foto bukti | Tersimpan berstatus **Pending**; tunai di laci berkurang | F-SD-01 |
| TC-SD-02 | P2 | Periksa kolom rekening di formulir setoran | Terisi dari Info Pembayaran dan **tidak bisa diketik** | F-SD-02 |
| TC-SD-03 | P1 | Kosongkan rekening resto di Info Pembayaran, buka formulir setoran | Tombol simpan mati berikut alasannya | F-SD-03 |
| TC-SD-04 | P2 | Tekan simpan | Popup mengingatkan mencocokkan nominal dengan yang benar-benar ditransfer | F-SD-04 |
| TC-SD-05 | P1 | Finance mengonfirmasi setoran | Status jadi **Completed**; dana pindah dari suspense ke GL Total Saldo | F-SD-05, TSD §6.4 |
| TC-SD-06 | P1 | Finance menolak setoran | Dana kembali ke laci; tidak ada sisa di suspense | F-SD-05, A-05 |
| TC-SD-07 | P1 | Kasir mencoba menyetujui setorannya sendiri | Tidak ada tombol setuju untuk kasir | A-06 |
| TC-SD-08 | P2 | Periksa penanda merah di kartu Setor Saldo Cash | Angkanya sama dengan jumlah pengajuan menunggu | F-SD-07 |
| TC-SD-09 | P2 | Buka foto bukti dari riwayat | Tampil besar dan terbaca | F-SD-06 |

---

## 10. Katalog & Pengaturan

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-AD-01 | P2 | Tambah produk lengkap dengan foto, deskripsi, harga, stok | Tersimpan dan langsung tampil di layar pelanggan | F-AD-01 |
| TC-AD-02 | P1 | Isi harga bersih Rp 25.000 pada produk kena PPN | Harga jual yang ditampilkan sudah termasuk PPN, dihitung otomatis | F-AD-02 |
| TC-AD-03 | P1 | Tandai sebuah produk **bebas PPN**, lalu pesan | PPN tidak dipungut untuk menu itu | F-AD-03 |
| TC-AD-04 | P2 | Simpan produk **tanpa mengisi stok** | Diterima; ketersediaannya ditentukan penanda Out of Stock | F-AD-12 |
| TC-AD-05 | P2 | Geser saklar habis dari daftar produk | Berubah tanpa membuka formulirnya | F-AD-13 |
| TC-AD-06 | P1 | Buka layar pelanggan | Angka stok **tidak terlihat** di mana pun | F-AD-14 |
| TC-AD-07 | P2 | Tambah kategori, lalu pindahkan produk ke sana | Kategori baru muncul di layar pelanggan berikut isinya | F-AD-04 |
| TC-AD-08 | P2 | Buka tab **Level** pada resto baru | Lima kelompok bawaan sudah terisi | F-AD-10 |
| TC-AD-09 | P2 | Buat kelompok level dengan **satu** pilihan | Ditolak — minimal dua pilihan | F-AD-11 |
| TC-AD-10 | P2 | Buat kelompok level bernama sama dengan yang sudah ada | Ditolak | F-AD-11 |
| TC-TP-01 | P2 | Tambah produk tanpa mengisi topping | Tersimpan; layar pesannya tidak menampilkan bagian topping | F-AD-18 |
| TC-TP-02 | P2 | Tambah 5 topping berharga berbeda, maks. 2 | Tersimpan apa adanya | F-AD-18, F-AD-19 |
| TC-TP-03 | P1 | Pesan menu itu, pilih 2 topping | Harga naik sesuai jumlah keduanya; subtotal berubah seketika | F-CU-25, F-CU-26 |
| TC-TP-04 | P1 | Coba pilih topping ketiga | Pilihan sisanya mati, dengan keterangan batasnya | F-AD-19 |
| TC-TP-05 | P2 | Lepas satu topping saat batas tercapai | Bisa dilepas, lalu topping lain bisa dipilih | F-AD-19 |
| TC-TP-06 | P2 | Kosongkan maks. topping | Semua topping bisa dipilih sekaligus | F-AD-19 |
| TC-TP-07 | P2 | Isi maks. topping lebih besar dari jumlah toppingnya | Ditolak — disebutkan ada berapa | F-AD-19 |
| TC-TP-08 | P2 | Tambah topping berharga Rp 0 | Boleh; namanya tampil tanpa tambahan harga | F-AD-20 |
| TC-TP-09 | P1 | Pesan menu sama dua kali dengan urutan topping dibalik | Menyatu jadi satu baris, bukan dua | F-CU-05 |
| TC-TP-10 | P1 | Periksa tiket dapur dan struk | Toppingnya tertulis | F-CU-25 |
| TC-TP-11 | P2 | Sunting baris keranjang yang bertopping | Pilihan toppingnya masih tercentang | F-CU-06 |
| TC-TP-12 | P1 | Pesan dari HP pelanggan dan dari kasir | Perilaku dan harganya sama | F-CU-25 |
| TC-AD-11 | P1 | Ubah email seorang karyawan | Riwayat transaksinya tetap utuh atas namanya | F-AD-05 |
| TC-AD-12 | P2 | Info Resto → ambil titik lokasi sekali tekan | Pin berpindah ke posisi sekarang; pratinjau peta ikut bergeser | F-AD-06, F-AD-15 |
| TC-AD-13 | P2 | Geser pin di pratinjau peta, simpan, buka lagi | Titik yang tersimpan sama dengan yang terakhir digeser | F-AD-15 |
| TC-AD-14 | P1 | Matikan **kedua** cara makan | Ditolak — minimal satu harus menyala | F-AD-16 |
| TC-AD-15 | P2 | Unggah banner, atur urutan, nonaktifkan satu | Urutan di layar pelanggan mengikuti; yang nonaktif tidak tampil | F-AD-07 |
| TC-AD-16 | P2 | Isi tanggal mulai banner **kemarin** | Tanggal itu tidak bisa dipilih di kalendernya | F-AD-17 |
| TC-AD-17 | P2 | Owner dengan dua resto → berpindah resto | Data ikut berganti seluruhnya; tidak ada sisa data resto sebelumnya | F-AD-08, A-10 |
| TC-AD-18 | P2 | Admin membuka Info Pembayaran | Hanya bisa dilihat | F-SD-02 |
| TC-AD-19 | P2 | Owner membuka Info Pembayaran | **Bisa diubah** | F-SD-02 |

---

## 11. QR Meja

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-QR-01 | P2 | Buat QR satu meja bernomor `VIP-2` | Kartunya memuat nama resto dan nomor persis seperti diketik | F-QR-01, F-QR-04 |
| TC-QR-02 | P2 | Pindai QR hasilnya dengan HP pelanggan | Membuka resto itu dengan nomor meja terisi | F-QR-01, F-SS-01 |
| TC-QR-03 | P2 | Mode banyak meja: isi 10 | Terbentuk 10 QR bernomor 1–10 | F-QR-02 |
| TC-QR-04 | P2 | Isi awalan `A`, jumlah 3 | Menghasilkan A1, A2, A3 | F-QR-03 |
| TC-QR-05 | P2 | Periksa nomor pada kartu ke-7 | Tertulis `7`, bukan `07` | F-QR-07 |
| TC-QR-06 | P2 | Isi jumlah meja 101 | Ditolak — batasnya 100 | F-QR-02 |
| TC-QR-07 | P2 | **Download Semua** | Penghitung kemajuan berjalan; seluruh berkas masuk galeri urut nomornya | F-QR-05, F-QR-07 |
| TC-QR-08 | P3 | Cetak seluruh QR | Satu meja satu halaman | F-QR-06 |

---

## 12. Diskon

Modul yang paling banyak berubah belakangan, dan yang paling mudah salah
dibaca. Tiap kasus di bawah menguji satu perbedaan yang halus.

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-DS-01 | P2 | Buat diskon satu menu, 30% | Berlaku untuk menu itu saja, bukan seluruh tagihan | F-DS-01 |
| TC-DS-02 | P1 | Diskon menu dengan syarat **Minimal 2**, pesan **1** | **Tidak** dapat potongan | F-DS-10, F-DS-11 |
| TC-DS-03 | P1 | Kasus yang sama, pesan **2** | Dapat potongan, dihitung dari kedua porsinya | F-DS-11 |
| TC-DS-04 | P1 | Kasus yang sama, pesan **3** | Tetap dapat; potongan dihitung dari ketiganya | F-DS-11 |
| TC-DS-05 | P1 | Syarat **Tepat 2**, pesan **3** | **Tidak** dapat potongan | F-DS-11 |
| TC-DS-06 | P1 | Bundling Nasi Goreng (min 2) + Es Teh (min 1) → pesan **2 Nasi Goreng saja** | **Tidak** dapat potongan sama sekali | F-DS-12 |
| TC-DS-07 | P1 | Kasus yang sama → pesan 2 Nasi Goreng + 1 Kopi (di luar promo) | Tetap **tidak** dapat — menu lain tidak menggantikan yang kurang | F-DS-12 |
| TC-DS-08 | P1 | Kasus yang sama → pesan 2 Nasi Goreng + 1 Es Teh | Dapat potongan, dihitung dari kedua menu itu saja | F-DS-12 |
| TC-DS-09 | P1 | Tambahkan menu di luar promo ke keranjang yang sudah memenuhi | Potongannya tidak ikut membesar | F-DS-12 |
| TC-DS-10 | P1 | Diskon minimum belanja **≥ Rp 200.000**, tagihan pas Rp 200.000 | Dapat potongan | F-DS-02 |
| TC-DS-11 | P1 | Ubah indikatornya jadi **>**, tagihan pas Rp 200.000 | **Tidak** dapat potongan | F-DS-02 |
| TC-DS-12 | P1 | Dua promo berlaku bersamaan | Hanya **satu** yang dipakai — yang paling menguntungkan pelanggan | A-15 |
| TC-DS-13 | P1 | Diskon rupiah lebih besar daripada tagihannya | Potongan berhenti di nilai tagihan; total tidak pernah negatif | A-15 |
| TC-DS-14 | P1 | Pesan menu berpromo dari **HP pelanggan** | Potongan yang sama berlaku, berikut nama promonya | F-CU-17, A-14 |
| TC-DS-15 | P2 | Isi tanggal mulai **kemarin** | Tidak bisa dipilih di kalendernya | F-DS-04 |
| TC-DS-16 | P2 | Isi tanggal berakhir **hari ini** | Ditolak — minimal besok | F-DS-04 |
| TC-DS-17 | P2 | Periksa lencana promo yang belum mulai / sudah lewat / dimatikan | Berturut-turut: Terjadwal, Sudah lewat, Nonaktif | F-DS-05 |
| TC-DS-18 | P2 | Nonaktifkan promo tanpa menghapusnya | Hilang dari perhitungan, tetap ada di daftar | F-DS-06 |
| TC-DS-19 | P1 | Selesaikan transaksi berdiskon, lalu **hapus** promonya, lalu cetak ulang struknya | Struk lama tetap menyebut potongan yang benar | F-DS-08 |
| TC-DS-20 | P2 | Buat promo dengan potongan **101%** | Ditolak — persen antara 1 dan 100 | F-DS-03 |
| TC-DS-21 | P2 | Simpan promo berbasis menu tanpa memilih satu pun menu | Ditolak | F-DS-01 |
| TC-DS-22 | P1 | Menu Rp 25.000, Ukuran Besar +Rp 5.000. Buat promo sasaran "Tambahan Ukuran: Besar", potongan 100% | Pesan Ukuran Besar → bayar Rp 25.000, bukan Rp 30.000 | F-DS-14, F-DS-15 |
| TC-DS-23 | P1 | Pesan menu yang sama dengan Ukuran Regular | **Tidak** dapat potongan — pilihannya tidak dipesan | F-DS-16 |
| TC-DS-24 | P1 | Promo sasaran topping "Keju" 100%, pesan dengan Keju | Harga toppingnya hilang, menunya tetap penuh | F-DS-14, F-DS-15 |
| TC-DS-25 | P1 | Promo sasaran topping "Keju", pesan tanpa Keju | Tidak dapat potongan | F-DS-16 |
| TC-DS-26 | P2 | Pesan 3 porsi Ukuran Besar dengan promo 100% | Ketiganya bebas biaya ukuran | F-DS-15 |
| TC-DS-27 | P2 | Pilihan yang tidak menambah harga | Tidak muncul di daftar "Yang dipotong" | F-DS-14 |
| TC-DS-28 | P2 | Menu tanpa tambahan harga sama sekali | Kolom "Yang dipotong" tidak ditampilkan | F-DS-14 |
| TC-DS-29 | P2 | Ganti sasaran dari level ke topping | Sasaran lamanya terbuang, tidak menumpuk | F-DS-14 |

---

## 13. Kotak Masuk & Pengumuman

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-IN-01 | P2 | Buka kotak masuk karyawan | Dua tab: Update Aplikasi dan General, masing-masing berpenghitung sendiri | F-IN-01, F-IN-02 |
| TC-IN-02 | P1 | Buka tab General → **Tandai semua dibaca** | Hanya tab General yang tertandai; tab Update Aplikasi tidak tersentuh | F-IN-15 |
| TC-IN-03 | P1 | Hal yang sama untuk **Hapus semua** | Hanya tab yang sedang dibuka | F-IN-15 |
| TC-IN-04 | P2 | Hapus pesan, lalu buka dari akun lain | Pesannya masih ada di akun lain itu | F-IN-03 |
| TC-IN-05 | P1 | Admin resto A kirim pengumuman → buka kotak masuk karyawan resto B | **Tidak** muncul | F-IN-10, A-10 |
| TC-IN-06 | P1 | Kirim pengumuman bersasaran **Karyawan** → buka kotak masuk pelanggan | **Tidak** muncul | F-IN-11, A-20 |
| TC-IN-07 | P1 | Kirim pengumuman bersasaran **Customer** → buka kotak masuk karyawan | **Tidak** muncul | F-IN-11 |
| TC-IN-08 | P2 | Kirim bersasaran **Semua** | Muncul di keduanya | F-IN-11 |
| TC-IN-09 | P2 | Sertakan gambar promo pada pengumuman | Gambarnya tampil utuh saat dibuka | F-IN-09 |
| TC-IN-10 | P2 | Pelanggan yang pernah memesan di resto A membuka Kotak Masuk di menu utama | Promo resto A muncul berikut nama restonya | F-IN-12, F-IN-13 |
| TC-IN-11 | P2 | Hal yang sama sebagai **tamu** | Tetap menerima, berdasar pesanan yang tersimpan di HP-nya | F-IN-14 |
| TC-IN-12 | P2 | Pelanggan tamu membuka kotak masuk | Tombol tandai/hapus **tidak ditawarkan** — tamu tidak punya tempat menyimpan penandanya | F-IN-03 |
| TC-IN-13 | P1 | Terbitkan pengumuman baru saat aplikasi tertutup | Notifikasi sampai ke HP | F-IN-07, A-08 |
| TC-IN-14 | P2 | Terbitkan pengumuman saat aplikasi sedang **dibuka** | Notifikasi tetap muncul di bar notifikasi | TSD §8 |
| TC-IN-15 | P1 | Masuk sebagai Super Admin, terbitkan rilis baru | Notifikasinya sampai ke HP Super Admin | F-IN-10 |
| TC-IN-16 | P1 | Owner multi-cabang sebelum memilih cabang | Tetap menerima push | F-IN-10 |
| TC-IN-17 | P1 | Pelanggan login, belum buka resto, terbitkan voucher | Notifikasi vouchernya sampai | F-IN-11 |
| TC-IN-18 | P1 | Terbitkan voucher, periksa HP kasir dan chef | **Tidak** menerima — sasarannya pelanggan | F-IN-12 |
| TC-IN-19 | P1 | Pengumuman resto khusus karyawan | Tidak sampai ke pelanggan resto itu | F-IN-12 |
| TC-IN-20 | P2 | Tamu tanpa resto aktif | Tidak menerima — memang tidak ada penandanya | F-IN-11 |
| TC-IN-21 | P2 | Periksa `device_tokens` sesudah Super Admin membuka aplikasi | Ada barisnya dengan `resto_id` kosong | F-IN-10 |

---

## 14. Pembayaran QRIS

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-PG-01 | P1 | Pesan dan pilih QRIS pada resto yang sub-akunnya aktif | QR-nya dari penyedia pembayaran sungguhan, bisa dipindai aplikasi bank | F-PG-01 |
| TC-PG-02 | P1 | Bandingkan nominal di layar QRIS dengan total tagihan | Sama persis, sudah termasuk service dan PPN, sudah dikurangi diskon | F-PG-01 |
| TC-PG-03 | P1 | Bayar sungguhan lewat aplikasi bank | Layar berpindah **sendiri** ke Pembayaran Berhasil, tanpa ada yang menekan apa pun | F-PG-02 |
| TC-PG-04 | P1 | Periksa layar kasir pada resto dengan penyedia aktif | Tombol konfirmasi manual **tidak ada** | F-PG-07 |
| TC-PG-05 | P2 | Resto yang belum punya sub-akun | QR simulasi tampil berikut tombol konfirmasi manual | F-PG-06 |
| TC-PG-06 | P2 | Perhatikan hitungan mundur di layar QRIS | Berjalan; QR kedaluwarsa saat habis | F-PG-05 |
| TC-PG-07 | P1 | Dua resto berbeda menerima pembayaran QRIS | Dananya masuk ke rekening masing-masing | F-PG-03 |
| TC-PG-08 | P1 | Buka Info Pembayaran sebagai Finance dan Owner | Pengenal sub-akun **tidak terlihat** | F-PG-04 |
| TC-PG-09 | P1 | Buka layar resto sebagai Super Admin | Pengenal sub-akun terlihat dan bisa diubah | F-PG-04, F-SA-05 |
| TC-PG-10 | P2 | Simpan QR ke galeri dari layar pelanggan | Tersimpan dan masih bisa dipindai dari galeri | — |
| TC-PG-11 | P1 | Bayar QRIS sampai sukses, periksa `payment_charges` | Sepuluh kolom rincian kuitansinya terisi | F-PG-11 |
| TC-PG-12 | P1 | Cocokkan `transaction_id` dengan dashboard Xendit | Sama persis | F-PG-11 |
| TC-PG-13 | P2 | Jalankan bagian SQL-nya pada basis data berisi pembayaran lama | Pembayaran lama ikut terisi dari `raw` | F-PG-11 |
| TC-PG-14 | P2 | Kirim ulang callback yang sama | Nilai yang sudah terisi tidak tertimpa kosong | F-PG-11 |
| TC-PG-15 | P1 | Pembayaran gagal / kedaluwarsa | Rinciannya **tetap tersimpan**; `provider_status` terisi | F-PG-12, F-PG-13 |
| TC-PG-16 | P1 | Buat QR lalu biarkan menunggu, periksa barisnya | Rincian yang sudah diketahui tersimpan; `status` masih pending | F-PG-12 |
| TC-PG-17 | P1 | Bayar QR yang tadi menunggu | `status` jadi paid, `provider_status` jadi SUCCEEDED | F-PG-14 |
| TC-PG-18 | P1 | QR kedaluwarsa lalu pelanggan bayar tunai di kasir | Pesanannya tetap bisa dilunasi — `status` tidak ikut ditutup | F-PG-14 |
| TC-PG-19 | P2 | Periksa `failure_reason` pada pembayaran yang ditolak | Terisi sebabnya dari penyedia | F-PG-13 |

---

## 15. Pembatalan & Kedaluwarsa

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-CN-01 | P1 | Pesanan belum dibayar → **Pesanan Saya** → Batalkan | Berhasil; statusnya jadi Dibatalkan | F-CN-01, F-CN-02 |
| TC-CN-02 | P1 | Hal yang sama dari layar **Riwayat** | Tombolnya ada dan bekerja sama persis | F-CN-02 |
| TC-CN-03 | P1 | Dapur menekan Mulai Masak → pelanggan mencoba membatalkan | Ditolak; pesannya mengarahkan ke kasir | F-CN-03 |
| TC-CN-04 | P1 | Pesanan yang sudah dibayar | Tombol batal tidak ada | F-CN-01 |
| TC-CN-05 | P1 | Coba batalkan pesanan orang lain (dari perangkat berbeda) | Ditolak | F-CN-04, TSD §5.2 |
| TC-CN-06 | P1 | Pesanan tunai dibiarkan 31 menit | Statusnya jadi **Hangus** sendiri | F-CN-05 |
| TC-CN-07 | P1 | Bandingkan tampilan pesanan Dibatalkan dan Hangus | Dua label berbeda, tidak tertukar | F-CN-06 |
| TC-CN-08 | P1 | Buka **Pesanan Masuk** sesudah ada pesanan dibatalkan | Tidak muncul, dan **tidak** berlabel "Menunggu Pembayaran" | A-17 |
| TC-CN-09 | P1 | Pesanan **QRIS** yang belum dibayar dibiarkan 31 menit | **Tidak** ikut hangus — tenggangnya di sisi penyedia | TSD §7.2 |

---

## 16. Sesi Meja & Identitas

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-SS-01 | P2 | Pindai QR meja | Sesi terbuka: resto dan nomor meja terisi sendiri | F-SS-01 |
| TC-SS-02 | P2 | Pesan sebagai tamu, tutup aplikasi, buka lagi | Riwayatnya masih ada | F-SS-02 |
| TC-SS-03 | P1 | Pesan sebagai tamu → login dengan email yang **belum pernah** dipakai | Riwayat tamunya berpindah ke akun itu | F-SS-03, F-CU-13 |
| TC-SS-04 | P1 | Pesan sebagai tamu → login dengan email yang **sudah punya** riwayat | Keduanya tetap terpisah; riwayat akun tidak tercampur | F-SS-04, F-SS-05 |
| TC-SS-05 | P2 | Kasus di atas → logout lagi | Riwayat tamu masih ada di perangkat | F-SS-05 |
| TC-SS-06 | P2 | Selesaikan seluruh pesanan dalam sesi, tunggu 6 menit | Sesinya tertutup sendiri | F-SS-06 |
| TC-SS-07 | P2 | Sisakan satu pesanan belum selesai, tunggu 10 menit | Sesinya **tetap terbuka** | F-SS-07 |

---

## 17. Tampilan

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-TM-01 | P3 | Ganti tema dari halaman awal, sebelum masuk | Berlaku seketika | F-TM-01, F-TM-02 |
| TC-TM-02 | P3 | Ganti tema dari tiap peran: Kasir, Chef, Admin, Finance, Owner, Pelanggan | Tersedia dan bekerja di semuanya | F-TM-02 |
| TC-TM-03 | P3 | Pilih **Ikuti HP**, ubah tema sistem Android | Aplikasi mengikuti tanpa dibuka ulang | F-TM-01 |
| TC-TM-04 | P3 | Pilih Gelap, tutup aplikasi, buka lagi | Tetap gelap | F-TM-03 |
| TC-TM-05 | P2 | Telusuri **seluruh** layar dalam mode gelap | Tidak ada tulisan yang hilang di latarnya; kartu selalu lebih terang daripada latar | A-18 |
| TC-TM-06 | P2 | Hal yang sama dalam mode terang | Sama | A-18 |
| TC-TM-07 | P3 | Perkecil lebar layar / perangkat sempit | Pilihan tema menyusut jadi ikon saja | F-TM-04 |
| TC-TM-08 | P3 | Buka daftar panjang mana pun sampai ujung bawah | Tombol aksi tidak menutupi baris terakhir | A-11 |
| TC-TM-09 | P2 | Buka menu utama Kasir, Admin, Finance, Super Admin, Owner | Halaman awal berisi kartu kelompok, bukan belasan menu | F-TM-05 |
| TC-TM-10 | P1 | Buka tiap kelompok, hitung seluruh menunya | Tidak ada satu pun menu yang hilang | F-TM-05 |
| TC-TM-11 | P2 | Baca kartu kelompok tanpa membukanya | Isinya tersebut di keterangannya | F-TM-06 |
| TC-TM-12 | P1 | Periksa Kotak Masuk, Pengaturan, dan Keluar | Ketiganya di halaman awal, tidak di dalam kelompok | F-TM-07 |
| TC-TM-13 | P1 | Ajukan top up petty cash, buka halaman awal peran mana pun | Kartu **Keuangan** membawa penanda merah tanpa perlu dibuka | F-TM-08, A-07 |
| TC-TM-14 | P1 | Pesanan tunai pelanggan masuk antrean | Kartu **Penjualan** membawa penandanya | F-TM-08 |
| TC-TM-15 | P2 | Setujui seluruh pengajuan, buka lagi halaman awal | Penanda di kartu kelompok hilang | F-TM-08 |

---

## 18. Super Admin

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-SA-01 | P2 | Buka List Resto | Seluruh resto terdaftar tampil | F-SA-01 |
| TC-SA-02 | P2 | Kelola karyawan lintas resto, ubah perannya | Perubahan berlaku; karyawan itu melihat menu sesuai peran barunya | F-SA-02 |
| TC-SA-03 | P1 | Kirim pengumuman **versi aplikasi** | Sampai ke seluruh pengguna, di semua resto | F-SA-03, F-IN-07 |
| TC-SA-04 | P1 | Buka layar Kirim Pengumuman sebagai Admin resto | Pilihan kategori **Update Aplikasi** tidak tersedia | F-SA-03, F-IN-08 |
| TC-SA-05 | P2 | Kirim pengumuman umum ke seluruh resto | Muncul di kotak masuk semua resto | F-SA-04 |
| TC-SA-06 | P2 | Telusuri menu Super Admin | Tidak ada layar kasir, dapur, maupun keuangan resto | F-SA-06 |
| TC-SA-07 | P1 | List Resto → hapus sebuah resto | Hilang dari daftar; datanya tidak dibuang | F-SA-07 |
| TC-SA-08 | P1 | Buka Pilih Resto sebagai pelanggan | Resto terhapus **tidak muncul** | F-SA-10 |
| TC-SA-09 | P1 | Pindai QR meja resto yang sudah dihapus, coba pesan | Ditolak database, bukan hanya disembunyikan layarnya | F-SA-10 |
| TC-SA-10 | P1 | Coba ubah harga produk resto terhapus | Ditolak | F-SA-10 |
| TC-SA-11 | P1 | Terbitkan tagihan setelah resto dihapus | Tidak ada tagihan baru untuk resto itu | F-SA-11 |
| TC-SA-12 | P1 | Periksa tagihan lama resto terhapus | Masih ada dan bisa ditelusuri | F-SA-11 |
| TC-SA-13 | P2 | Nyalakan saklar **Tampilkan yang dihapus** | Resto terhapus muncul, hanya dengan tombol Kembalikan | F-SA-09 |
| TC-SA-14 | P1 | Ketuk **Kembalikan** | Kembali ke daftar, tapi **belum aktif** — harus dinyalakan sendiri | F-SA-08 |
| TC-SA-15 | P1 | Coba hapus penyewa platform (MerchantPOS) | Ditolak | TSD §7.4 |
| TC-SA-16 | P1 | Coba `set_resto_deleted` sebagai Owner resto | Ditolak — hanya Super Admin | F-SA-07 |
| TC-SA-17 | P2 | Periksa baris resto terhapus di database | `deleted_by` dan `deleted_at` terisi | F-SA-12 |

---

## 19. Pembaruan Aplikasi

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-UP-01 | P2 | Buka pengumuman versi → **Unduh Versi Terbaru** | Unduhan mulai **di dalam aplikasi**, tidak membuka peramban | F-UP-01, F-UP-02 |
| TC-UP-02 | P2 | Perhatikan bar notifikasi HP | Kemajuannya tampil berikut persennya | F-UP-03 |
| TC-UP-03 | P2 | Kunci HP saat unduhan berjalan, tunggu, buka lagi | Unduhannya lanjut, tidak mengulang dari nol | F-UP-04 |
| TC-UP-04 | P2 | Tekan tombol unduh lagi saat unduhan berjalan | Muncul pilihan **Batalkan** atau **Lanjutkan** | F-UP-05, F-IN-18 |
| TC-UP-05 | P2 | Pilih Batalkan | Unduhan berhenti; **tidak** ditampilkan sebagai galat | F-IN-19 |
| TC-UP-06 | P2 | Biarkan unduhan selesai | Notifikasi "ketuk untuk memasang"; pemasang Android terbuka | F-UP-06, F-IN-17 |
| TC-UP-07 | P2 | Matikan data seluler di tengah unduhan | Pesannya menyebut masalah koneksi, satu kalimat, tanpa isi galat mentah | F-UP-07, F-IN-19 |
| TC-UP-08 | P3 | Penuhi penyimpanan HP, lalu unduh | Pesannya menyebut penyimpanan penuh — dibedakan dari masalah koneksi | F-UP-07 |
| TC-UP-09 | P3 | Pakai jalur cadangan lewat peramban | Berkasnya terunduh | F-IN-06 |

---

## 19b. Langganan & Tagihan Resto

Fitur yang kegagalannya paling mahal di dua arah sekaligus: gagal
mengunci berarti pemakaian tanpa bayar, gagal membuka berarti resto yang
sudah membayar berhenti berjualan.

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-BL-01 | P2 | Super Admin → Billing Resto → atur harga dan tanggal untuk sebuah resto | Tersimpan; kartu restonya menampilkan harga, tanggal, dan tenggangnya | F-BL-01, F-BL-02 |
| TC-BL-02 | P2 | Buat resto baru, buka Billing Resto | Sudah punya barisnya sendiri, berstatus **Gratis** | F-BL-06 |
| TC-BL-03 | P1 | Setel harga Rp 0, lewatkan tanggal jatuh tempo jauh | Tidak pernah terbit tagihan, tidak pernah terkunci | F-BL-04 |
| TC-BL-04 | P1 | Matikan saklar langganan pada resto berbayar yang menunggak | Tidak terkunci | F-BL-05 |
| TC-BL-05 | P2 | Coba pilih tanggal tagihan 29, 30, atau 31 | Tidak tersedia di pilihan — hanya 1 sampai 28 | F-BL-02 |
| TC-BL-06 | P2 | Ketuk **Terbitkan tagihan sekarang** dua kali beruntun | Tagihan tetap satu untuk periode itu | F-BL-08 |
| TC-BL-07 | P1 | Setel jatuh tempo 3 hari lagi, buka aplikasi sebagai Kasir | Pita pengingat tampil di atas layar; isi layarnya **tetap bisa dipakai** | F-BL-09 |
| TC-BL-08 | P2 | Setel jatuh tempo 4 hari lagi | Pita **belum** tampil | F-BL-09 |
| TC-BL-09 | P1 | Lewati jatuh tempo, masih dalam tenggang | Pita berubah merah; aplikasi **belum** terkunci | F-BL-03, F-BL-10 |
| TC-BL-10 | P1 | Lewati tenggang, tagihan belum dibayar | Seluruh layar diganti halaman **Aplikasi Terkunci Sementara** | F-BL-15 |
| TC-BL-11 | P1 | Pada keadaan terkunci, coba buat pesanan lewat API langsung | Ditolak database — bukan hanya layarnya yang menutup | F-BL-18, TSD §7.3 |
| TC-BL-12 | P1 | Pada keadaan terkunci, ketuk **Lihat & Bayar Tagihan** | Layar tagihan terbuka dan bisa dipakai | F-BL-16 |
| TC-BL-13 | P1 | Pada keadaan terkunci, ketuk **Keluar** | Berhasil keluar akun | F-BL-16 |
| TC-BL-14 | P1 | Ketuk **Buat Virtual Account** → pilih BCA | Nomor VA tampil berikut nominal dan masa berlakunya | F-BL-11, F-BL-19 |
| TC-BL-14b | P1 | Tutup layar, buka lagi, ketuk lagi | Nomor VA **sama**, tidak diterbitkan yang baru | F-BL-23 |
| TC-BL-14c | P1 | Transfer **tepat** sesuai nominal ke VA itu | Tagihan lunas sendiri dalam hitungan detik; kunci terbuka tanpa mengirim bukti | F-BL-22 |
| TC-BL-14d | P1 | Transfer **kurang** dari nominal | Tidak melunasi; tagihan tetap terbuka | F-BL-20 |
| TC-BL-14e | P2 | Ketuk **Ganti Bank** → pilih BNI | Nomor VA baru untuk bank itu | F-BL-19 |
| TC-BL-14f | P1 | Periksa rekening tujuan dana VA di Dashboard Xendit | Masuk ke akun **MerchantPOS**, bukan sub-akun resto | F-BL-11, TSD §7.3 |
| TC-BL-14g | P1 | Kirim callback palsu ke `xendit-billing-webhook` tanpa token | Ditolak 401; tagihan tidak berubah | TSD §7.3 |
| TC-BL-14h | P2 | Xendit mengirim callback yang sama dua kali | Tagihan tetap lunas sekali; catatan pelunasnya tidak berubah | TSD §7.3 |
| TC-BL-14i | P2 | Unggah bukti transfer manual lewat jalur cadangan | Status jadi **Menunggu Verifikasi**; aplikasi **terbuka lagi** | F-BL-24, F-BL-12 |
| TC-BL-26 | P2 | Dengan kunci uji Xendit, buka tagihan ber-VA | Tombol **Simulasikan Pembayaran** muncul | TSD §7.3 |
| TC-BL-27 | P1 | Ketuk Simulasikan Pembayaran | Tagihan jadi Lunas sendiri lewat webhook; kunci resto terbuka | F-BL-22 |
| TC-BL-28 | P1 | Pasang kunci produksi Xendit, buka layar yang sama | Tombol simulasi **hilang sendiri** | TSD §7.3 |
| TC-BL-29 | P1 | Buat diskon langganan setelah tagihan terbit → ketuk segarkan di Super Admin | Nominal tagihan turun; nomor VA lama **dibuang** | F-BL-05 |
| TC-BL-30 | P1 | Buat VA baru setelah nominalnya berubah | Nominalnya sesuai yang sudah dipotong | F-BL-20 |
| TC-BL-31 | P1 | Set tanggal tagih 31, lihat jatuh tempo di April | 30 April | F-BL-19 |
| TC-BL-32 | P1 | Set tanggal tagih 31, lihat jatuh tempo di Februari 2026 | 28 Februari | F-BL-19 |
| TC-BL-33 | P1 | Set tanggal tagih 31, lihat jatuh tempo di Februari 2028 | 29 Februari — tahun kabisat | F-BL-19 |
| TC-BL-34 | P1 | Set tanggal tagih 29, Februari 2026 | 28 Februari, bukan gagal terbit | F-BL-19 |
| TC-BL-35 | P2 | Buka dropdown Tanggal Tagihan di Super Admin | Tersedia sampai 31; di atas 28 diberi keterangan akhir bulan | F-BL-19 |
| TC-BL-36 | P1 | Lunasi tagihan 18 Agustus, lihat kartu paket | Menyebut tagihan berikutnya 18 September | F-BL-20 |
| TC-BL-37 | P1 | Ada tagihan belum lunas, lihat kartu paket | Menyebut "setelah tagihan berjalan lunas" lebih dulu | F-BL-20 |
| TC-BL-38 | P2 | Resto gratis (harga 0) | Tidak menampilkan tanggal berikutnya | F-BL-20 |
| TC-BL-39 | P1 | Lihat tagihan yang sudah lunas | Nomor Virtual Account **tidak** tampil | F-BL-21 |
| TC-BL-40 | P1 | Lihat tagihan yang menunggu verifikasi | VA masih tampil | F-BL-21 |
| TC-BL-41 | P1 | Ketuk Unduh Invoice PDF pada tagihan lunas | PDF terbuka, bertanda LUNAS, tanpa nomor VA | F-BL-22 |
| TC-BL-42 | P1 | Periksa PDF tagihan berdiskon | Harga daftar, nama potongan, dan total dibayar tertulis terpisah | F-BL-22 |
| TC-BL-43 | P2 | Cari tombol PDF pada tagihan belum lunas | Tidak ada | F-BL-22 |
| TC-BL-44 | P1 | Masuk sebagai Finance, buka beranda | Ada menu **Tagihan Langganan** | F-BL-23 |
| TC-BL-45 | P1 | Finance mengunggah bukti bayar | Diterima — RPC mengizinkan peran finance | F-BL-23 |
| TC-BL-46 | P2 | Finance membuat Virtual Account | Berhasil, sama seperti Owner | F-BL-23 |
| TC-BL-47 | P2 | Kasir/Chef mencari menu itu | Tidak ada | F-BL-23 |
| TC-BL-15 | P1 | Coba kirim bukti tanpa melampirkan foto | Tombol Kirim mati | F-BL-11 |
| TC-BL-16 | P1 | Super Admin → tab Tagihan → **Terima** | Status jadi Lunas; resto tetap terbuka; pita hilang | F-BL-13 |
| TC-BL-17 | P1 | Super Admin → **Tolak** tanpa mengisi alasan | Tombol Tolak tidak menyelesaikan apa-apa — alasan wajib | F-BL-14 |
| TC-BL-18 | P1 | Tolak berikut alasan, lalu buka layar Tagihan dari sisi resto | Alasannya terbaca; kalau sudah lewat tenggang, terkunci lagi | F-BL-14, F-BL-15 |
| TC-BL-19 | P1 | Login sebagai Super Admin saat ada resto terkunci | Tidak terkunci sama sekali | F-BL-17 |
| TC-BL-20 | P1 | Sebagai resto terkunci, coba ubah harga produk | Ditolak — katalog ikut dibekukan | F-BL-18 |
| TC-BL-21 | P1 | Resto A terkunci; buka aplikasi sebagai karyawan resto B | Resto B **tidak** terpengaruh | F-BL-15, A-10 |
| TC-BL-22 | P1 | Coba panggil `review_billing_payment` sebagai Owner resto | Ditolak — hanya Super Admin | F-BL-13 |
| TC-BL-23 | P1 | Coba `UPDATE billing_invoices SET status='paid'` sebagai Owner | Ditolak | F-BL-13, TSD §7.3 |
| TC-BL-24 | P2 | Matikan sambungan, buka aplikasi resto berbayar yang lancar | Tidak terkunci karena gagal memeriksa | TSD §7.3 |
| TC-BL-25 | P2 | Owner → Tagihan Langganan | Terbuka, memuat paket dan riwayat tagihan | F-BL-11 |

### E2E-09 — Satu siklus langganan penuh (P1)

1. Super Admin setel resto uji: Rp 150.000, jatuh tempo 3 hari lagi, tenggang 1 hari
2. Terbitkan tagihan → periksa muncul di tab Tagihan berstatus Belum Dibayar
3. Buka aplikasi sebagai Kasir → pita pengingat tampil, layar tetap bisa dipakai
4. Majukan tanggal melewati jatuh tempo + 1 hari → buka lagi → **terkunci**
5. Coba buat pesanan lewat API langsung → ditolak database
6. Ketuk Lihat & Bayar Tagihan → Buat Virtual Account → pilih bank
7. Transfer tepat sesuai nominal ke nomor VA itu
8. Tanpa menyentuh aplikasi lagi → status jadi **Lunas** sendiri
9. Buka aplikasi → **tidak lagi terkunci**, pita hilang
10. Periksa Dashboard Xendit → dana masuk ke akun MerchantPOS, bukan sub-akun resto

**Rujukan:** F-BL-07 … F-BL-18, TSD §7.3

---

## 19c. Finance MerchantPOS (Super Admin)

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-PF-01 | P1 | Super Admin → Finance → Riwayat Langganan | Tagihan lunas tampil, dikelompokkan per bulan, dengan total | F-PF-01 |
| TC-PF-02 | P2 | Periksa penanda jalur pelunasan tiap baris | Tertulis **VA** atau **manual** sesuai cara lunasnya | F-PF-02 |
| TC-PF-03 | P1 | Buat diskon langganan 20% untuk satu resto → terbitkan tagihan | Tagihan resto itu berkurang 20%; resto lain tetap penuh | F-PF-03, F-PF-05 |
| TC-PF-04 | P1 | Simpan diskon tanpa memilih resto | Ditolak — diskon tanpa sasaran tidak mengenai siapa pun | F-PF-03 |
| TC-PF-05 | P2 | Buat diskon rupiah lebih besar daripada harga langganan | Potongannya berhenti di harga; tagihan tidak pernah negatif | F-PF-03 |
| TC-PF-06 | P2 | Nonaktifkan diskon, terbitkan tagihan berikutnya | Tidak memotong; diskonnya tetap ada di daftar | F-PF-04 |
| TC-PF-07 | P1 | Hapus diskon setelah tagihan terbit | Tagihan yang sudah terbit tetap menyebut potongannya | F-PF-05 |
| TC-PF-08 | P1 | Bayar tagihan berdiskon → buka Jurnal GL MerchantPOS | Dua baris: pendapatan **kredit**, diskon **debit** | F-PF-06, F-PF-07 |
| TC-PF-09 | P1 | Tagihan ditolak lalu diterima lagi | Jurnalnya tetap satu set — pendapatan tidak tercatat dua kali | F-PF-07 |
| TC-PF-10 | P1 | Buka Jurnal GL resto yang membayar | **Tidak** ada baris pendapatan langganan di sana | F-PF-07 |
| TC-PF-11 | P2 | Buka Mapping GL Account MerchantPOS | Bagan akun 11xxxxx lengkap, berbeda dari 19xxxxx milik resto | F-PF-08 |
| TC-PF-12 | P2 | Catat pengeluaran dan top up petty cash MerchantPOS | Bekerja sama seperti di resto | F-PF-09 |
| TC-PF-13 | P1 | Telusuri menu Finance MerchantPOS | **Tidak ada** Setor Saldo Cash | F-PF-10 |
| TC-PF-14 | P1 | Buka Jurnal GL Semua Resto | Jurnal seluruh resto tampil, bisa disaring per resto | F-PF-11 |
| TC-PF-15 | P1 | Cari cara mengubah baris di Jurnal GL Semua Resto | Tidak ada satu pun — hanya bisa dilihat | F-PF-12 |
| TC-PF-16 | P1 | Coba `UPDATE gl_journal_entries` sebagai Super Admin lewat API | Ditolak | F-PF-12, TSD §7.4 |
| TC-PF-17 | P1 | Buka Pilih Resto sebagai pelanggan | **MerchantPOS tidak muncul** di daftar mana pun | TSD §7.4 |
| TC-PF-18 | P1 | Buka List Resto dan Billing Resto sebagai Super Admin | MerchantPOS tidak muncul sebagai resto yang bisa ditagih | TSD §7.4 |
| TC-PF-19 | P2 | Buka Diskon Langganan sebagai Owner resto | Hanya diskon yang mengenai restonya yang terbaca | F-PF-03 |
| TC-PF-20 | P1 | Bandingkan total debit/kredit Jurnal Semua Resto dengan Jurnal GL resto itu (saring ke resto yang sama) | **Angkanya sama persis** | F-PF-14 |
| TC-PF-21 | P1 | Batalkan sebuah pengeluaran, lihat kedua layar jurnal | Total tidak naik; keterangan "N pembatalan tidak dihitung" muncul | F-PF-14 |
| TC-PF-22 | P2 | Cari baris pembatalan di daftar | Tetap tampil, bertanda **PEMBATALAN** | F-PF-15 |
| TC-PF-23 | P1 | Saring ke sebuah resto, lalu pilih **Semua resto** lagi | Kembali menampilkan seluruh resto — bukan tetap tersaring | F-PF-16 |
| TC-PF-24 | P1 | Saring ke resto A, lalu saring lagi ke resto B yang punya jurnal | Isinya berganti ke jurnal resto B | F-PF-16 |
| TC-PF-25 | P2 | Perhatikan pita di atas layar sesudah menyaring | Nama restonya tertulis, dengan tombol × untuk melepasnya | F-PF-16 |
| TC-PF-26 | P2 | Buka daftar saringan | Resto yang belum punya jurnal ditandai "Belum ada jurnal" | F-PF-17 |
| TC-PF-27 | P2 | Perhatikan pengelompokan | Per tanggal, bisa dilipat; tanggal terbaru terbuka, sisanya tertutup | F-PF-18 |
| TC-PF-28 | P1 | Buka Mapping GL Account resto mana pun | **GL Diskon** punya bagiannya dan nomornya sudah terisi | F-PF-19, F-DS-09 |
| TC-PF-29 | P2 | Buka Mapping GL Account MerchantPOS | Ada bagian **GL Langganan**; penghitung akun tidak pernah menyisakan yang mustahil terisi | F-PF-19 |
| TC-PF-30 | P1 | Pesan menu berpromo, bayar, buka Jurnal GL | Baris GL Diskon menyebut **nama promonya** | F-PF-20, F-DS-13 |
| TC-PF-31 | P1 | Buka Jurnal GL Semua Resto sesudah ada tagihan langganan lunas | Baris pendapatan langganan **tidak muncul** di sana | F-PF-21 |
| TC-PF-32 | P1 | Buka daftar saringan resto | **MerchantPOS tidak ada** di daftarnya | F-PF-21 |
| TC-PF-33 | P1 | Buka Jurnal GL MerchantPOS | Pendapatan langganan ada di sana, dan **Saldo Total tidak nol** | F-PF-07 |
| TC-PF-34 | P2 | Periksa nomor akun di Jurnal GL MerchantPOS | Golongan **11xxxxx**, berbeda dari 19xxxxx milik resto | F-PF-08 |
| TC-PF-35 | P1 | Bandingkan Saldo Total di Saldo & Pengeluaran dengan Jurnal GL MerchantPOS | Angkanya sama persis | F-PF-09 |
| TC-PF-36 | P1 | Terbitkan voucher, muat ulang kedua layar | Saldo Total **tidak** berubah — uangnya pindah kantong, bukan hilang | F-PF-09 |
| TC-PF-36b | P1 | Voucher dipakai pelanggan di resto | Saldo MerchantPOS berkurang sebesar nilai vouchernya | F-PF-09 |
| TC-PF-37 | P2 | Buka Saldo & Pengeluaran untuk MerchantPOS | Tidak ada kartu Saldo Cash / Non Cash | F-PF-10 |
| TC-PF-38 | P2 | Buka layar yang sama untuk resto biasa | Kartu Cash/Non Cash tetap ada | F-PF-10 |
| TC-CB-01 | P1 | Izinkan lokasi, lihat daftar Terdekat | Hanya resto ≤ 5 km yang muncul | F-CB-01 |
| TC-CB-02 | P1 | Resto berjarak 7 km | Tidak di Terdekat, tapi ada di Semua Resto | F-CB-01, F-CB-02 |
| TC-CB-03 | P2 | Periksa keterangan di judul bagian Terdekat | Tertulis "Dalam 5 km dari kamu" | F-CB-01 |
| TC-CB-04 | P2 | Tolak izin lokasi | Bagian Terdekat tidak tampil; Semua Resto tetap ada | F-CB-02 |
| TC-TB-01 | P1 | Tablet, Kasir: ketuk sebuah menu | Popup muncul di kiri; keranjang kanan tetap terbaca penuh | F-TB-02 |
| TC-TB-02 | P1 | Tablet, Kasir: ketuk ikon edit pada baris keranjang | Popup editnya juga di kiri | F-TB-02 |
| TC-TB-03 | P1 | Tablet, Pelanggan: buka menu resto | Keranjang tampil sebagai panel kanan | F-TB-01 |
| TC-TB-04 | P1 | Tablet, Pelanggan: ketuk sebuah menu | Popup di kiri, panel keranjang tidak tertutup | F-TB-02 |
| TC-TB-05 | P1 | Tablet, Pelanggan: isi meja, pilih voucher, lalu bayar dari panel | Berjalan sama persis dengan halaman keranjang | F-TB-01 |
| TC-TB-06 | P2 | Tablet: periksa bagian bawah layar | Tidak ada bar keranjang | F-TB-03 |
| TC-TB-07 | P1 | HP: ketuk sebuah menu | Popup tetap di tengah; keranjang tetap bar bawah | F-TB-04 |
| TC-TB-08 | P2 | Putar tablet ke potret sampai di bawah 1000px | Kembali ke tata letak HP tanpa kehilangan isi keranjang | F-TB-04 |
| TC-TB-09 | P1 | Tablet melintang: buka checkout dari Kasir dengan 3 item | Daftar itemnya terlihat; tidak ada yang terpotong | F-TB-05 |
| TC-TB-10 | P1 | Gulir sampai bawah di halaman itu | Tombol bayarnya tercapai penuh | F-TB-05 |
| TC-TB-11 | P1 | Ulangi keduanya dari sisi Pelanggan | Sama — keduanya diperbaiki, bukan salah satunya | F-TB-05 |
| TC-TB-12 | P2 | Buka menu sebagai Admin lalu Owner | Sama persis dengan Kasir — satu layar yang sama | F-TB-05, F-TB-06 |
| TC-TB-13 | P1 | Buka daftar menu | Semua kategori sudah terbuka | F-TB-06 |
| TC-TB-14 | P2 | Lipat satu kategori | Tetap bisa dilipat | F-TB-06 |
| TC-TB-15 | P1 | Tablet: lihat banner promo | Tingginya di bawah 45% layar, tidak mendorong menu keluar | F-TB-07 |
| TC-TB-16 | P2 | Pasang banner yang bukan 16:9 | Kotaknya mengikuti gambar; tidak ada pita kabur di sisinya | F-TB-07 |
| TC-TB-17 | P2 | Pasang banner potret ekstrem | Dijepit — tidak mengambil alih halaman menu | F-TB-07 |
| TC-TB-18 | P1 | Buka Info Resto lalu gulir | "Nama Resto" tidak terpotong di tepi atas | F-TB-08 |
| TC-TB-19 | P1 | Simpan Info Resto | Nama restonya tidak berubah dan tidak kosong | F-TB-08 |
| TC-TB-20 | P2 | Baca keterangan di bawah nama resto | Menyebut MerchantPOS Admin dan cara menghubunginya | F-TB-08 |
| TC-TU-01 | P1 | Owner → Saldo & Pengeluaran → Top Up Saldo | Tersimpan; Saldo Total naik sebesar nominalnya | F-TU-01, F-TU-02 |
| TC-TU-01b | P1 | Super Admin top up, periksa Saldo Total MerchantPOS | Naik sebesar nominalnya — bukan tetap | F-TU-02, F-TU-05 |
| TC-TU-02 | P1 | Periksa Jurnal GL sesudahnya | Satu baris kredit ke GL Setoran Modal | F-TU-05 |
| TC-TU-03 | P1 | Periksa Laporan Transaksi / Pemasukan | Setoran **tidak** muncul sebagai penjualan | F-TU-02 |
| TC-TU-04 | P1 | Simpan tanpa mengisi Dari | Ditolak — "Sebutkan penyetornya" | F-TU-03 |
| TC-TU-05 | P2 | Simpan tanpa bukti | Tetap tersimpan — buktinya opsional | F-TU-03 |
| TC-TU-06 | P1 | Masuk sebagai Kasir, buka layar yang sama | Riwayat terlihat, tombol Top Up Saldo tidak ada | F-TU-04 |
| TC-TU-07 | P1 | Kasir memanggil insert `balance_topups` lewat API | Ditolak RLS | F-TU-04 |
| TC-TU-08 | P1 | Super Admin → Finance → Saldo & Pengeluaran → Top Up | Saldo MerchantPOS naik; Jurnal GL MerchantPOS mencatatnya | F-TU-01, F-TU-05 |
| TC-TU-09 | P1 | Coba ubah atau hapus baris `balance_topups` | Ditolak — tidak ada kebijakannya | F-TU-06 |
| TC-TU-10 | P2 | Periksa kartu Cash / Non Cash sesudah top up | Non Cash naik; keduanya tetap berjumlah sama dengan Penghasilan | F-TU-02 |
| TC-TU-11 | P2 | Buka Pemetaan GL sebagai Finance resto | Ada bagian **GL Modal** | F-TU-02 |
| TC-TU-12 | P2 | Buka halaman awal aplikasi | Tombolnya bertuliskan **MerchantPOS Merchant** | — |

---

## 19d. Voucher Pelanggan

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-VC-01 | P1 | Super Admin → Voucher → terbitkan Rp 1.000.000 jadi 10 | 10 voucher @Rp 100.000; nominalnya tampil hidup di formulir | F-VC-01, F-VC-02 |
| TC-VC-02 | P1 | Terbitkan Rp 1.000.000 jadi 3 | @Rp 333.333, sisa Rp 1 disebutkan dan **tidak** ikut dijurnal | F-VC-02 |
| TC-VC-03 | P2 | Terbitkan dengan kode yang sudah dipakai | Ditolak — kodenya sudah ada | F-VC-01 |
| TC-VC-04 | P1 | Periksa Jurnal GL MerchantPOS sesudah terbit | Debit **Total Saldo 1100040**, kredit **Voucher 1100073** | F-VC-13 |
| TC-VC-05 | P1 | Pelanggan menebus kode di **Voucher Saya** | Berhasil; voucher masuk daftar "Siap Dipakai" | F-VC-07 |
| TC-VC-06 | P2 | Ketik kodenya dengan huruf kecil | Tetap diterima | F-VC-07 |
| TC-VC-07 | P2 | Ketik kode yang tidak ada | "Kode voucher tidak ditemukan" | F-VC-10 |
| TC-VC-08 | P1 | Periksa Jurnal GL MerchantPOS sesudah ditebus | Debit **Voucher**, kredit **Voucher Redeem 1100074** | F-VC-13 |
| TC-VC-09 | P1 | Orang yang sama menebus kode itu lagi | Ditolak — "Voucher ini sudah kamu tebus" | F-VC-08, F-VC-10 |
| TC-VC-10 | P1 | Batch berisi 10, orang ke-11 menebus | Ditolak — "Voucher ini sudah habis" | F-VC-09, F-VC-10 |
| TC-VC-11 | P1 | Dua orang menebus voucher terakhir bersamaan | Hanya satu lolos; yang lain ditolak kuota habis | F-VC-09 |
| TC-VC-12 | P2 | Tebus voucher dari batch yang sudah ditutup | "Voucher ini sudah ditutup" | F-VC-04, F-VC-10 |
| TC-VC-13 | P2 | Tebus voucher yang lewat masa berlaku | "Voucher ini sudah kedaluwarsa" | F-VC-04, F-VC-10 |
| TC-VC-14 | P1 | Di keranjang, ketuk baris voucher | Muncul **pilihan** voucher miliknya, bukan kolom ketik kode | F-VC-11 |
| TC-VC-15 | P1 | Voucher min belanja Rp 50.000, tagihan Rp 30.000 | Tidak bisa dipilih, disertai "Belanja belum mencapai minimum" | F-VC-05, F-VC-10 |
| TC-VC-16 | P1 | Voucher khusus resto A dibuka di resto B | Tidak bisa dipilih — "Tidak berlaku di resto ini" | F-VC-06, F-VC-10 |
| TC-VC-17 | P1 | Voucher Rp 100.000 pada tagihan Rp 60.000 | Yang dibayar Rp 0; sisa Rp 40.000 **tidak** dikembalikan | F-VC-12 |
| TC-VC-18 | P1 | Pasang voucher lalu selesaikan pesanan | Yang dibayar sudah dipotong; nominal QRIS-nya juga | F-VC-11 |
| TC-VC-19 | P1 | Ketuk **Lepas** setelah voucher terpasang | Tagihan kembali ke nominal semula | F-VC-11 |
| TC-VC-20 | P1 | Periksa Jurnal GL MerchantPOS sesudah dipakai | Debit **Voucher Redeem**, kredit GL **Transfer** restonya | F-VC-13 |
| TC-VC-21 | P1 | Periksa Jurnal GL restonya | Ada baris masuk sebesar nilai vouchernya | F-VC-13 |
| TC-VC-22 | P2 | Voucher yang sudah dipakai dibuka lagi di keranjang | Tidak muncul di daftar pilihan | F-VC-11 |
| TC-VC-23 | P1 | Jalankan `expire_vouchers()` — ada klaim tak terpakai | Debit **Voucher Redeem**, kredit **Total Saldo** | F-VC-14 |
| TC-VC-24 | P1 | Batch kedaluwarsa dengan sisa kuota tak tertebus | Debit **Voucher**, kredit **Total Saldo** sebesar sisanya | F-VC-14 |
| TC-VC-25 | P1 | Jalankan `expire_vouchers()` **dua kali** | Pengembaliannya sekali saja — dijaga `settled_at` | F-VC-14 |
| TC-VC-26 | P1 | Jumlahkan keempat tahap untuk satu batch | Debit dan kreditnya seimbang; tidak ada dana yang hilang | F-VC-13, F-VC-14 |
| TC-VC-27 | P1 | Tulis langsung ke `voucher_claims` lewat API | Ditolak RLS — tidak ada kebijakan tulis untuk siapa pun | F-VC-13 |
| TC-VC-28 | P1 | Panggil `generate_voucher_batch` sebagai bukan Super Admin | Ditolak — "Hanya Super Admin yang dapat menerbitkan voucher" | F-VC-01 |
| TC-VC-29 | P2 | Periksa kartu batch di layar Super Admin | Sisa kuota dan **nilai menggantung** cocok dengan penebusnya | F-VC-15 |
| TC-VC-30 | P2 | Tutup sebuah batch yang kuotanya masih ada | Tidak bisa ditebus lagi; yang sudah ditebus tetap bisa dipakai | F-VC-04 |
| TC-VC-31 | P1 | Pakai voucher, lalu periksa tabel `voucher_payouts` | Muncul satu baris `pending` sebesar nilai vouchernya | F-VC-16 |
| TC-VC-32 | P1 | Jalankan `settle-voucher-payouts` | Status jadi `sent`, `transfer_id` terisi, saldo sub-akun resto bertambah | F-VC-16 |
| TC-VC-33 | P1 | Jalankan fungsinya **dua kali** berturut-turut | Uangnya berpindah sekali; yang kedua duplikat dan tetap `sent` | F-VC-18 |
| TC-VC-34 | P1 | Matikan Xendit (kunci salah), lalu jalankan | Status `failed`, `last_error` menyebut sebabnya, `attempts` naik | F-VC-17 |
| TC-VC-35 | P1 | Perbaiki kuncinya lalu jalankan lagi | Baris yang tadi gagal terkirim | F-VC-17 |
| TC-VC-36 | P1 | Pakai voucher di resto yang belum punya sub-akun | Tetap `pending`, `attempts` **tidak** naik, tidak hilang | F-VC-19 |
| TC-VC-37 | P1 | Buat pesanan bervoucher saat Xendit mati total | Pesanannya tetap tersimpan dan masuk dapur | F-VC-17 |
| TC-VC-38 | P2 | Jalankan `voucher_payouts.sql` di basis data yang sudah ada pemakaian | Klaim `used` lama ikut terantre | F-VC-16 |
| TC-VC-39 | P1 | Tulis langsung ke `voucher_payouts` lewat API | Ditolak — tidak ada kebijakan tulis untuk siapa pun | F-VC-18 |
| TC-VC-40 | P2 | Baca `voucher_payout_config` sebagai Super Admin | Kosong — kunci layanan tidak terbaca peran mana pun | F-VC-16 |
| TC-VC-41 | P2 | Jalankan penjadwal sebelum `function_url` diisi | Berjalan tanpa melakukan apa-apa, tanpa galat | F-VC-17 |
| TC-VC-42 | P1 | Bandingkan total `sent` dengan mutasi transfer di dashboard Xendit | Cocok baris per baris lewat `transfer_id` | F-VC-16 |
| TC-VC-43 | P1 | Jalankan pencairan saat xenPlatform belum aktif | Seluruh antrean tetap `pending`, `attempts` nol, tidak ada galat | F-VC-19 |
| TC-VC-44 | P2 | Aktifkan xenPlatform + pasang sub-akun, lalu tunggu penjadwal | Tunggakan lama ikut terangkut tanpa dijalankan ulang manual | F-VC-16, F-VC-17 |
| TC-VC-45 | P1 | Super Admin → Finance → Pemetaan GL | Ada bagian **GL Voucher** berisi GL Voucher dan GL Voucher Redeem | F-VC-13 |
| TC-VC-46 | P1 | Buka Pemetaan GL sebagai Finance resto biasa | Bagian GL Voucher **tidak** muncul, penanda "belum dipetakan" tidak berbunyi | F-VC-13 |
| TC-VC-47 | P2 | Ubah nomor GL Voucher lalu simpan | Tersimpan, dan jurnal voucher berikutnya memakai nomor baru | F-VC-13 |
| TC-VC-48 | P1 | Terbitkan batch, lalu buka Kotak Masuk pelanggan | Ada kabar di tab **Umum** berisi kode, nilai, kuota, dan tenggat | F-VC-20, F-VC-21 |
| TC-VC-49 | P1 | Terbitkan batch dengan HP pelanggan terkunci | Push muncul di layar kunci | F-VC-20 |
| TC-VC-50 | P2 | Terbitkan batch tanpa minimal belanja | Kalimat minimal belanja **tidak** muncul di pengumuman | F-VC-21 |
| TC-VC-51 | P2 | Buka Kotak Masuk sebagai pegawai resto | Kabar voucher **tidak** muncul — audiensnya pelanggan | F-VC-20 |
| TC-VC-52 | P2 | Ketik nama resto di kolom cari pada form terbit | Daftarnya menyusut sesuai kata kuncinya | F-VC-22 |
| TC-VC-53 | P1 | Centang 3 resto, lalu cari kata yang menyaringnya keluar | Ketiganya tetap terpilih; hitungannya tidak berubah | F-VC-22 |
| TC-VC-54 | P1 | Saring daftarnya, lalu ketuk **Pilih semua** | Hanya yang tampil tercentang, bukan seluruh resto | F-VC-22 |
| TC-VC-55 | P2 | Ketuk **Lepas semua** saat semua yang tampil tercentang | Yang tampil terlepas; pilihan di luar saringan tetap | F-VC-22 |
| TC-VC-56 | P2 | Cari nama resto yang tidak ada | Muncul "Tidak ada resto bernama itu" | F-VC-22 |
| TC-VC-57 | P1 | Terbitkan batch berbanner, lalu buka Kotak Masuk pelanggan | Gambarnya tampil bersama kabarnya | F-VC-23 |
| TC-VC-58 | P2 | Pilih gambar potret, lihat pratinjaunya | Dipotong 16:9, sama dengan yang nanti muncul di kotak masuk | F-VC-23 |
| TC-VC-59 | P2 | Terbitkan batch tanpa banner | Kabarnya tetap terkirim, tanpa gambar | F-VC-23 |
| TC-VC-60 | P1 | Cari tombol Hapus pada batch yang masih berjalan | Tidak ada — harus ditutup dulu | F-VC-24 |
| TC-VC-61 | P1 | Tutup batch yang belum ada penebusnya, lalu hapus | Terhapus; dananya kembali ke GL Total Saldo | F-VC-24 |
| TC-VC-62 | P1 | Periksa Kotak Masuk pelanggan sesudah batch dihapus | Kabar vouchernya ikut hilang | F-VC-24 |
| TC-VC-63 | P1 | Panggil `delete_voucher_batch` untuk batch yang sudah ada penebusnya | Ditolak, dengan jumlah penebusnya disebut | F-VC-24 |
| TC-VC-64 | P1 | Panggil `delete_voucher_batch` sebagai bukan Super Admin | Ditolak | F-VC-24 |
| TC-VC-65 | P2 | Hapus batch yang sudah pernah disettle penjadwal | Dananya **tidak** dikembalikan dua kali | F-VC-24 |
| TC-VC-66 | P1 | Ketuk **Penebus** pada sebuah batch | Daftar email penebut berikut tanggal tebus dan statusnya | F-VC-25 |
| TC-VC-67 | P1 | Periksa ringkasan di atas daftar penebus | Dipakai / Menggantung / Hangus berjumlah sama dengan barisnya | F-VC-25 |
| TC-VC-68 | P1 | Lewati tanggal kedaluwarsa sebelum penjadwal berjalan | Statusnya sudah **Hangus**, bukan Belum Dipakai | F-VC-25 |
| TC-VC-69 | P1 | Terbitkan batch dengan ceklis **Khusus pengguna baru** | Tersimpan; kartunya menyebut "khusus pengguna baru" | F-VC-26 |
| TC-VC-70 | P1 | Akun yang belum pernah memesan menebusnya | Berhasil | F-VC-26 |
| TC-VC-71 | P1 | Akun yang pernah punya pesanan terbayar menebusnya | Ditolak — "hanya untuk pengguna baru MerchantPOS" | F-VC-26, F-VC-27 |
| TC-VC-72 | P1 | Akun yang pesanannya semua **batal** menebusnya | Berhasil — batal tidak menghilangkan status pengguna baru | F-VC-26 |
| TC-VC-73 | P1 | Akun yang pernah memesan di resto lain saja | Ditolak — batasnya seluruh MerchantPOS | F-VC-26 |
| TC-VC-74 | P1 | Batch khusus pengguna baru berkuota 1, ditebus akun lama lalu akun baru | Akun lama ditolak dengan sebab yang benar; kuotanya tidak berkurang | F-VC-26, F-VC-27 |
| TC-VC-75 | P2 | Periksa pengumuman kotak masuknya | Menyebut "Khusus pengguna baru" | F-VC-28 |
| TC-VC-76 | P2 | Terbitkan batch tanpa ceklis itu | Siapa pun bisa menebus; kalimat syaratnya tidak muncul | F-VC-26, F-VC-28 |
| TC-VC-77 | P2 | Periksa batch lama yang terbit sebelum fitur ini | Tetap terbuka untuk siapa saja | F-VC-26 |
| TC-VC-78 | P1 | Buka aplikasi sebagai tamu, lihat layar awal pelanggan | Tidak ada menu Voucher Saya | F-VC-29 |
| TC-VC-79 | P1 | Tamu memesan lalu buka keranjang | Baris **Pakai Voucher** tidak muncul | F-VC-29 |
| TC-VC-80 | P2 | Masuk dengan akun, buka keranjang yang sama | Baris Pakai Voucher muncul kembali | F-VC-29 |
| TC-VC-81 | P2 | Tamu menyelesaikan pesanan | Tersimpan tanpa voucher, nilai vouchernya nol | F-VC-29 |

---

## 19e. Analisa Pasar

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-MR-01 | P1 | Super Admin → Analisa Pasar | Empat bagian termuat tanpa galat | F-MR-01…04 |
| TC-MR-02 | P1 | Bandingkan Top 5 Pelanggan dengan jumlah manual dari `orders` | Cocok nominal dan jumlah pesanannya | F-MR-01 |
| TC-MR-03 | P1 | Batalkan sebuah pesanan besar, muat ulang | Nominalnya berkurang — yang batal tidak dihitung | F-MR-05 |
| TC-MR-04 | P1 | Buat akun pelanggan baru tanpa memesan | Muncul di daftar Belum Pernah Memesan | F-MR-02 |
| TC-MR-05 | P1 | Pelanggan itu menyelesaikan satu pesanan, muat ulang | Hilang dari daftar tersebut | F-MR-02 |
| TC-MR-06 | P1 | Bandingkan Top 5 Resto dengan Jurnal GL resto bersangkutan | Nominalnya sejalan | F-MR-03 |
| TC-MR-07 | P1 | Resto yang seluruh pesanannya batal | Muncul di Belum Ada Penghasilan, jumlah pesanan **0** | F-MR-04 |
| TC-MR-08 | P2 | Resto baru tanpa pesanan sama sekali | Muncul dengan "Belum ada pesanan" | F-MR-04 |
| TC-MR-09 | P1 | Periksa apakah resto MerchantPOS ikut terhitung | Tidak — resto platform dikecualikan | F-MR-06 |
| TC-MR-10 | P1 | Hapus lunak sebuah resto, muat ulang | Hilang dari keempat daftar | F-MR-06 |
| TC-MR-11 | P1 | Panggil `report_top_customers` sebagai Owner resto | Daftar kosong, bukan pesan galat | F-MR-07 |
| TC-MR-12 | P2 | Panggil salah satu RPC dengan `p_limit` 99999 | Dijepit ke batas atasnya | F-MR-07 |
| TC-MR-13 | P2 | Pesanan kasir atas nama tamu | Tidak ikut peringkat pelanggan — bukan akun terdaftar | F-MR-01 |

---

## 19f. Nomor Pesanan Harian

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-NO-01 | P1 | Buat pesanan pertama hari itu | Bernomor **1** | F-NO-01, F-NO-02 |
| TC-NO-02 | P1 | Buat pesanan berikutnya | Nomornya berurutan, tanpa lompat | F-NO-01 |
| TC-NO-03 | P1 | Buat pesanan QRIS, jangan dibayar | Sudah bernomor walau masih menunggu bayar | F-NO-03 |
| TC-NO-04 | P1 | Bandingkan dua merchant pada hari yang sama | Deret nomornya berdiri sendiri-sendiri | F-NO-04 |
| TC-NO-05 | P1 | Lewati tengah malam WIB, buat pesanan | Kembali ke **1** | F-NO-02 |
| TC-NO-06 | P2 | Cetak struk | Nomornya tercetak | F-NO-05 |
| TC-NO-07 | P2 | Buka Riwayat Saya pelanggan | Nomornya tampil | F-NO-05 |
| TC-NO-08 | P2 | Buka pesanan lama sebelum fitur ini | Tanpa nomor, bukan nomor karangan | F-NO-06 |
| TC-NO-09 | P1 | Dua pesanan masuk hampir bersamaan | Nomornya berbeda | F-NO-01, TSD §7.7 |

---

## 19g. Layar Pelanggan

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-LP-01 | P2 | Buka Layar Pelanggan di perangkat kedua | Nama merchant, logonya, dan keadaan menunggu | F-LP-01, F-LP-05 |
| TC-LP-02 | P1 | Kasir menekan Bayar QRIS | QR dan nominalnya muncul di perangkat kedua tanpa disegarkan | F-LP-02 |
| TC-LP-03 | P1 | Bandingkan nominal di kedua layar | Sama persis | F-LP-01 |
| TC-LP-04 | P2 | Merchant tanpa logo | Memakai logo MerchantPOS, bukan kotak kosong | F-LP-03 |
| TC-LP-05 | P3 | Periksa bagian bawah layar | Ada tulisan powered by MerchantPOS | F-LP-04 |
| TC-LP-06 | P2 | Pembayaran selesai | Kembali ke keadaan menunggu | F-LP-05 |
| TC-LP-07 | P2 | Tutup lalu buka lagi Layar Pelanggan saat transaksi berjalan | Keadaannya termuat, bukan layar kosong | F-LP-02 |

---

## 19h. Fasilitas & Jam Buka

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-IM-01 | P2 | Isi fasilitas merchant, buka daftar pilih merchant | Fasilitasnya tampil di kartunya | F-IM-01, F-IM-02 |
| TC-IM-02 | P2 | Merchant dengan sembilan fasilitas | Yang muat ditampilkan, sisanya jadi "+N" | F-IM-02 |
| TC-IM-03 | P3 | Perkecil lebar layar | Tidak ada teks yang meluber keluar kartu | F-IM-02 |
| TC-IM-04 | P2 | Isi jam buka hanya Senin–Jumat | Sabtu dan Minggu terbaca **tutup** | F-IM-03 |
| TC-IM-05 | P1 | Buka daftar merchant di luar jam bukanya | Ditandai tutup, berada di bawah, tidak bisa dipilih | F-IM-04 |
| TC-IM-06 | P1 | Coba pilih merchant yang tutup | Muncul ajakan memilih merchant lain | F-IM-04 |
| TC-IM-07 | P2 | Periksa saran lokasi terdekat | Merchant yang tutup tidak muncul di sana | F-IM-05 |
| TC-IM-08 | P2 | Buka Info Merchant | Alamat, peta, kontak, fasilitas, jam buka, penilaian termuat | F-IM-06 |

---

## 19i. Penilaian Merchant

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-PM-01 | P1 | Pelanggan berakun menilai merchant: bintang, komentar, tiga foto | Tersimpan dan tampil | F-PM-01 |
| TC-PM-02 | P2 | Periksa nama penilai di daftar ulasan | Namanya tampil | F-PM-02 |
| TC-PM-03 | P1 | Nilai merchant yang sama untuk kedua kalinya | Formulirnya berisi penilaian sebelumnya, dan menimpanya | F-PM-03 |
| TC-PM-04 | P2 | Buka daftar pilih merchant | Rata-rata bintang dan jumlah penilainya tampil | F-PM-04 |
| TC-PM-05 | P2 | Ketuk foto di ulasan | Terbuka selayar penuh | F-PM-05 |
| TC-PM-06 | P2 | Masuk sebagai Kasir → Penilaian Pelanggan | Ulasannya terbaca | F-PM-06 |
| TC-PM-07 | P2 | Masuk sebagai MerchantPOS Admin | Menu Penilaian Pelanggan tidak ada | F-PM-06 |
| TC-PM-08 | P2 | Pegawai membuka Info Merchant tempatnya sendiri | Tombol Beri Penilaian tidak muncul | F-PM-07 |
| TC-PM-09 | P2 | Tunggu 1–3 jam setelah membayar | Notifikasi ajakan menilai masuk | F-PM-08 |
| TC-PM-10 | P2 | Ketuk notifikasi itu | Langsung membuka formulir merchant tersebut | F-PM-09 |
| TC-PM-11 | P2 | Tamu tanpa akun membuka Info Merchant | Ulasannya terbaca, tombol menilai tidak ada | F-PM-01 |

---

## 19j. Label & Penilaian Menu

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-LM-01 | P2 | Kelola Produk → centang BARU dan TERLARIS → simpan | Kedua label tampil di kartu menunya | F-LM-01, F-LM-03 |
| TC-LM-02 | P2 | Periksa formulir menu | Tidak ada centangan untuk label DISKON | F-LM-02 |
| TC-LM-03 | P1 | Buat promo yang mengenai sebuah menu | Label DISKON muncul sendiri di kartunya | F-LM-02 |
| TC-LM-04 | P1 | Lewati tanggal berakhir promonya | Label DISKON hilang sendiri | F-LM-02 |
| TC-LM-05 | P2 | Bandingkan kartu menu di HP pelanggan, tamu, kasir, admin, owner | Labelnya sama di semuanya | F-LM-03 |
| TC-LM-06 | P3 | Menu dengan empat label sekaligus | Paling banyak dua yang tampil, diskon paling depan | F-LM-04 |
| TC-LM-07 | P1 | Pesan menu, bayar, buka Riwayat Saya | Ada ajakan "Boleh bantu rating pesanannya yaa" | F-LM-05 |
| TC-LM-08 | P1 | Nilai satu menu, lalu pesan menu yang sama di pesanan lain | Formulirnya **kosong**, bukan berisi bintang sebelumnya | F-LM-06 |
| TC-LM-09 | P1 | Nilai menu yang sama pada pesanan yang sama dua kali | Menimpa, bukan menambah baris kedua | F-LM-07 |
| TC-LM-10 | P1 | Nilai seluruh menu di sebuah pesanan | Ajakannya hilang dari kartu pesanan itu | F-LM-08 |
| TC-LM-11 | P2 | Buka daftar menu untuk dinilai | Yang sudah dinilai bertanda bintang dan masih bisa diketuk | F-LM-09 |
| TC-LM-12 | P1 | Setelah menilai, kembali ke daftar menu | Bintangnya muncul tanpa menutup aplikasi | F-LM-10 |
| TC-LM-13 | P1 | Bandingkan angka terjual dengan `product_stats` | Cocok | F-LM-10 |
| TC-LM-14 | P1 | Batalkan sebuah pesanan besar, muat ulang | Angka terjualnya tidak bertambah | F-LM-11 |
| TC-LM-15 | P2 | Menu yang belum pernah dinilai maupun terjual | Barisnya tidak muncul sama sekali — bukan "★ 0,0" | F-LM-12 |
| TC-LM-16 | P2 | Buka Info Merchant → Ulasan Menu | Dikelompokkan per menu, yang paling banyak dibicarakan di atas | F-LM-13 |
| TC-LM-17 | P1 | Kirim penilaian lewat HTTP untuk menu yang tidak pernah dipesan | Ditolak basis data | F-LM-14, TSD §7.9 |
| TC-LM-18 | P1 | Kirim penilaian atas nama pesanan orang lain | Ditolak basis data | F-LM-14, TSD §7.9 |
| TC-LM-19 | P2 | Pelanggan tanpa akun membuka riwayat | Tidak ada ajakan menilai | F-LM-05 |
| TC-LM-20 | P2 | Pesanan yang belum lunas | Tidak ada ajakan menilai | F-LM-05 |
| TC-LM-21 | P2 | Pesanan yang diinput kasir atas nama pelanggan | Tidak bisa dinilai — bukan atas nama akunnya | FSD §10 |

---

## 19k. Shift Kasir

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-SH-01 | P2 | Buka beranda Kasir | Menu Shift Kasir ada di halaman utama, bukan di dalam grup | F-SH-12 |
| TC-SH-02 | P1 | Buka shift dengan modal awal Rp 500.000 | Kartunya berubah jadi "Shift sedang berjalan" | F-SH-01 |
| TC-SH-03 | P1 | Coba buka shift kedua di merchant yang sama | Ditolak, dengan pesan yang bisa dibaca | F-SH-02 |
| TC-SH-04 | P1 | Tekan Tutup Shift | Kolom hitungan muncul **tanpa** menyebut angka yang seharusnya | F-SH-04 |
| TC-SH-05 | P1 | Tulis nominalnya, tekan Lanjut | Selisihnya ditunjukkan, dengan pilihan Perbaiki Nominal | F-SH-05 |
| TC-SH-06 | P1 | Tekan Perbaiki Nominal | Kolomnya terbuka lagi berisi angka tadi, bukan kosong | F-SH-05 |
| TC-SH-07 | P1 | Jual tunai Rp 200.000 selama shift, tutup dengan hitungan yang pas | Selisih **nol** | F-SH-06 |
| TC-SH-08 | P1 | Setor tunai Rp 100.000 selama shift, lalu tutup | Yang seharusnya berkurang Rp 100.000 | F-SH-06 |
| TC-SH-09 | P1 | Setoran itu ditolak Finance, lalu tutup shift | Tidak dikurangkan — uangnya kembali ke laci | F-SH-07 |
| TC-SH-10 | P1 | Tarik petty cash dari laci selama shift | Yang seharusnya berkurang sebesar itu | F-SH-06 |
| TC-SH-11 | P1 | Jual QRIS Rp 300.000 selama shift | Tidak mempengaruhi angka laci sama sekali | F-SH-06 |
| TC-SH-12 | P1 | Tutup dengan hitungan kurang Rp 50.000 | Tercatat **Kurang Rp 50.000**, berikut anjuran melapor | F-SH-08 |
| TC-SH-13 | P2 | Isi catatan saat menutup | Tersimpan dan tampil di riwayat | F-SH-08 |
| TC-SH-14 | P1 | Kasir lain mencoba menutup shift rekannya | Ditolak | F-SH-09 |
| TC-SH-15 | P1 | Owner menutup shift kasir yang sudah pulang | Berhasil | F-SH-09 |
| TC-SH-16 | P1 | Tutup shift yang sudah ditutup | Ditolak | F-SH-10 |
| TC-SH-17 | P2 | Buka Shift Kasir sebagai Finance | Riwayat dan selisih tiap shift terbaca | F-SH-11 |
| TC-SH-18 | P1 | Ubah `expected_cash` lewat HTTP langsung | Ditolak — tidak ada kebijakan update | TSD §7.10 |
| TC-SH-19 | P2 | Bandingkan yang seharusnya dengan Saldo Cash di Saldo & Pengeluaran | Aturannya sejalan | F-SH-06, TSD §11.1b |
| TC-SH-20 | P2 | Batalkan dialog Buka Shift dan Tutup Shift | Menutup diam-diam, tanpa pesan galat | TSD §15.1 |

---

## 20. Uji Ujung-ke-Ujung

Mengikuti alur di FSD §3 dan diagram TSD §1.1. Dijalankan utuh, tanpa
memotong langkah — justru sambungan antar-modul yang paling sering
retak.

### E2E-01 — Pelanggan bayar QRIS (P1)

1. Pelanggan scan QR meja → pilih 2 menu → Dine In → isi nama
2. Pilih QRIS → bayar sungguhan dari aplikasi bank
3. Periksa layar pelanggan → **Pembayaran Berhasil**, struk terbentuk
4. Periksa dapur → pesanan ada di tab **Baru**, bukan Menunggu Bayar
5. Dapur: Mulai Masak → centang seluruh menu → Selesai
6. Periksa pelanggan → status berubah tanpa disegarkan
7. Periksa Jurnal GL → baris pemasukan QRIS, PPN, dan service tercatat
8. Periksa Saldo → masuk **Non Cash**, bukan Cash

**Rujukan:** F-CU-09, F-PG-02, F-CH-06, TSD §6, TSD §7.1

### E2E-02 — Pelanggan bayar tunai di kasir (P1)

1. Pelanggan pesan → pilih **Tunai** → catat nomor pesanannya
2. Periksa layar pelanggan → hitungan mundur 30 menit berjalan
3. Periksa dapur → ada di tab **Menunggu Bayar**, tanpa tombol masak
4. Kasir buka Pending Payment → temukan pesanan itu → terima tunai
5. Periksa antrean → pesanannya hilang seketika
6. Periksa dapur → berpindah ke tab **Baru** berikut tombol masak
7. Periksa Riwayat Kasir → masuk, ikut dihitung di total harian
8. Periksa Saldo Cash → bertambah sebesar totalnya

**Rujukan:** F-CU-09, F-PP-01, F-PP-06, F-PP-07, F-CH-06, A-02, A-13

### E2E-03 — Tunai dengan cara bayar diganti (P1)

Ulangi E2E-02, tapi pada langkah 4 ganti cara bayarnya ke **QRIS**.
Pesanannya harus tetap masuk **Riwayat Kasir**, dan masuk **Non Cash**
di Saldo.

**Rujukan:** F-PP-09, A-13, TSD §4.2

### E2E-04 — Setor tunai ke rekening (P1)

1. Kasir buka Setor Saldo Cash → catat tunai di laci
2. Ajukan setoran sebesar sebagian dari itu, lampirkan bukti
3. Periksa → status **Pending**; tunai di laci berkurang; muncul baris "menunggu approval" di Saldo
4. Periksa Jurnal GL → dana ada di **GL Suspense Setor Tunai**
5. Finance buka, cocokkan nominal, **Konfirmasi**
6. Periksa → status **Completed**
7. Periksa Jurnal GL → titipan suspense dilepas, dana masuk GL Total Saldo

Ulangi dari langkah 1 dengan **Tolak** di langkah 5: dana harus kembali
ke laci, dan suspense harus kosong.

**Rujukan:** F-SD-01, F-SD-05, A-05, TSD §6.4

### E2E-05 — Top up petty cash (P1)

Sama polanya dengan E2E-04, lewat GL Suspense Petty Cash. Top up
Rp 100.000 harus menambah Petty Cash **Rp 100.000** — bukan Rp 200.000.

**Rujukan:** F-FN-03, TSD §6.4

### E2E-06 — Promo bundling dari HP pelanggan (P1)

1. Admin buat promo: Nasi Goreng **Minimal 2** + Es Teh **Minimal 1**, potongan 30%
2. Pelanggan pesan 2 Nasi Goreng saja → **tidak** ada potongan
3. Tambah 1 Kopi (di luar promo) → tetap **tidak** ada potongan
4. Tambah 1 Es Teh → potongan muncul, dihitung dari Nasi Goreng + Es Teh saja
5. Bayar → periksa struk → potongan dan nama promonya tertulis
6. Periksa Jurnal GL → diskon tercatat **debit** di GL Diskon
7. Admin hapus promonya → cetak ulang struk tadi → potongannya tetap tertulis

**Rujukan:** F-DS-10, F-DS-12, F-CU-17, F-DS-08, F-DS-09, A-14

### E2E-07 — Pembatalan oleh pelanggan (P1)

1. Pelanggan pesan, pilih Tunai
2. Batalkan dari Pesanan Saya → berhasil
3. Periksa Pending Payment → hilang
4. Periksa dapur → hilang dari **semua** tab
5. Periksa Pesanan Masuk → tidak ada, dan tidak berlabel "Menunggu Pembayaran"
6. Periksa Riwayat Kasir → tidak ikut terhitung

**Rujukan:** F-CN-01, A-17

### E2E-08 — Isolasi antar cabang (P1)

Dengan akun Owner yang memiliki dua resto: buat transaksi, promo, dan
pengumuman di resto A, lalu berpindah ke resto B. **Tidak satu pun**
boleh terlihat di resto B — termasuk angka di Saldo, isi Riwayat Kasir,
dan kotak masuk.

**Rujukan:** F-AD-08, F-IN-10, A-10

---

## 21. Uji Teknis (lingkup TSD)

Kasus di bawah tidak bisa dijalankan dari layar aplikasi saja. Sebagian
butuh SQL Editor Supabase, sebagian butuh memanggil API langsung.

| ID | P | Skenario | Hasil yang diharapkan | Rujukan |
|---|---|---|---|---|
| TC-TS-01 | P1 | Panggil `GET /rest/v1/orders` memakai kunci anon tanpa login | Tidak mengembalikan pesanan resto mana pun | TSD §5 |
| TC-TS-02 | P1 | Login sebagai karyawan resto A, baca `orders` resto B lewat API | Kosong — bukan galat, tapi juga bukan data | TSD §5 |
| TC-TS-03 | P1 | Login sebagai **Owner**, buka tiap layar resto miliknya | Tidak ada layar yang kosong karena RLS — `owner` harus disebut di setiap daftar peran | TSD §5 |
| TC-TS-04 | P1 | Login sebagai Kasir, baca `gl_journal_entries` | Hanya yang terkait catatan yang memang boleh dia lihat | F-KS-13, TSD §5.1 |
| TC-TS-05 | P1 | Coba `UPDATE products` langsung lewat API sebagai pelanggan | Ditolak; pengurangan stok hanya lewat `decrement_stock` | TSD §5.2 |
| TC-TS-06 | P1 | Panggil `cancel_my_order` untuk pesanan milik orang lain | Ditolak | TSD §5.2 |
| TC-TS-07 | P1 | Jalankan ulang **seluruh** `JALANKAN-INI.sql` di database yang sudah terisi | Selesai tanpa galat; tidak ada data yang berubah | TSD §11 |
| TC-TS-08 | P1 | Jalankan ulang satu berkas SQL lama saja, misal `cash_payment_expiry.sql` | Tidak menyempitkan daftar nilai batasan mana pun | TSD §11.1 |
| TC-TS-09 | P1 | Buat resto baru dari Super Admin | Bagan akun GL 12 jenis dan tarif PPN/service langsung terisi | A-19, TSD §6.2 |
| TC-TS-10 | P1 | Kosongkan satu nomor GL, lalu buat transaksi | Jurnal untuk baris itu **tidak** terbentuk — pastikan gejalanya dikenali penguji | TSD §6.2 |
| TC-TS-11 | P2 | Periksa `push_outbox` sesudah pengumuman terbit | Baris masuk, lalu `sent_at` terisi | TSD §8 |
| TC-TS-12 | P2 | Matikan sambungan, pakai aplikasi | Katalog tetap tampil; pesanan tunai tetap bisa dibuat | TSD §10, FSD §5.6 |
| TC-TS-13 | P2 | Sambungkan lagi | Pesanan yang dibuat saat luring terkirim | TSD §10 |
| TC-TS-14 | P1 | Coba bayar QRIS saat luring | Ditolak dengan jelas — bukan menggantung tanpa kabar | FSD §5.6 |
| TC-TS-15 | P1 | Panggil `create-qris` dengan nominal yang dipalsukan di badan permintaan | Nominal yang dipakai tetap dari basis data | TSD §7.1 |
| TC-TS-16 | P1 | Tandai pesanan lunas lewat API tanpa lewat webhook | Ditolak | F-PG-02, TSD §7.1 |
| TC-TS-17 | P2 | Bongkar APK, cari kunci Xendit/FCM/Resend | Tidak ada satu pun kunci pengirim di dalamnya | TSD §1.2 |
| TC-TS-18 | P2 | Pesanan berpindah status lunas lebih dari sekali | Jurnalnya tetap satu set — tidak ada baris ganda | TSD §6.5 |
| TC-TS-19 | P2 | Hapus resto uji | Seluruh isinya ikut terhapus, termasuk jurnalnya | TSD §4.0 |

---

## 22. Regresi — bug yang pernah terjadi

Semuanya pernah benar-benar terjadi dan sudah diperbaiki. Diuji ulang
tiap rilis karena semuanya jenis yang gagal **diam-diam**: tidak ada
pesan galat, tidak ada yang terlihat rusak, sampai angkanya tidak cocok
berminggu-minggu kemudian.

| ID | P | Yang pernah terjadi | Yang harus dipastikan sekarang | Rujukan |
|---|---|---|---|---|
| TC-RG-01 | P1 | Nominal QRIS kasir memakai subtotal menu, bukan total tagihan | Nominal di layar QRIS = total termasuk service dan PPN | F-KS-09 |
| TC-RG-02 | P1 | Pesanan dilunasi lewat QRIS hilang dari Riwayat Kasir | Semua cara bayar masuk Riwayat Kasir | F-PP-09, A-13 |
| TC-RG-03 | P1 | Pesanan dibatalkan tampil "Menunggu Pembayaran" di Pesanan Masuk | Tidak muncul sama sekali | A-17 |
| TC-RG-04 | P1 | Top up Rp 100.000 tercatat Rp 200.000 di jurnal | Nominalnya sama dengan yang diajukan | F-FN-03 |
| TC-RG-05 | P1 | Diskon tidak berlaku untuk pesanan mandiri pelanggan | Berlaku sama di kasir dan HP pelanggan | A-14 |
| TC-RG-06 | P1 | Promo "beli 2" lolos oleh keranjang berisi dua menu berbeda | Syarat jumlah dihitung per menu, dan seluruhnya harus terpenuhi | F-DS-10, F-DS-12 |
| TC-RG-07 | P2 | Tombol pilih/hapus di kotak masuk tidak bereaksi sama sekali | Bekerja di kotak masuk karyawan **dan** pelanggan | F-IN-15 |
| TC-RG-08 | P2 | Layar Diskon dari hub Kasir menyebut "Belum ada produk di resto ini" | Daftar menu termuat | F-DS-01 |
| TC-RG-09 | P2 | Kasir tidak bisa membuka detail jurnal — terlihat seperti GL belum dipetakan | Detail jurnal terbuka | F-KS-13 |
| TC-RG-10 | P2 | Layar dapur meninggalkan jejak warna lama saat tema diganti | Seluruh layar berganti bersih | A-18 |
| TC-RG-11 | P2 | Banner promo menempel di atas, tidak ikut tergulir | Ikut tergulir bersama menunya | F-CU-16, A-12 |
| TC-RG-12 | P2 | Owner hanya bisa melihat Info Pembayaran | Owner bisa mengubahnya | F-SD-02 |
| TC-RG-13 | P1 | Migrasi gagal: daftar nilai batasan menyempit saat berkas lama dijalankan ulang | Menjalankan ulang berkas mana pun tidak pernah menolak data yang sudah ada | TSD §11.1 |
| TC-RG-14 | P2 | QR meja borongan bernomor `07`, berbeda dengan mode satu meja | Keduanya menulis `7` | F-QR-07 |
| TC-RG-15 | P1 | Foto menu yang barusan dipesan mendadak hilang dari daftar | Fotonya tetap ada sesudah pesanan masuk | TSD §7.11 |
| TC-RG-16 | P1 | Tombol Batal memunculkan galat dan dialognya tidak jadi tertutup | Batal menutup diam-diam di seluruh dialog | TSD §15.1 |
| TC-RG-17 | P1 | Menyimpan penilaian gagal dengan galat 42P10 | Tersimpan tanpa galat | TSD §7.9 |
| TC-RG-18 | P1 | Menu yang dipesan lagi sudah terisi bintang pesanan sebelumnya | Formulirnya kosong | F-LM-06 |
| TC-RG-19 | P2 | Bintang menu tidak muncul di kartu sesudah dinilai | Muncul tanpa menutup aplikasi | F-LM-10, TSD §15.2 |
| TC-RG-20 | P2 | Nama merchant tidak terbaca di kartu QR meja pada mode gelap | Terbaca di kedua mode | F-QR-01 |
| TC-RG-21 | P2 | Shift Kasir tidak ditemukan karena tersembunyi di dalam grup Keuangan | Ada di halaman utama | F-SH-12 |

---

## 23. Matriks Keterlacakan

Tiap kelompok kebutuhan di FSD, dan kasus uji yang menjaganya.

Angkanya dihitung dari daftar kasusnya sendiri, bukan dijaga manual.
Selama ini kolomnya dinaikkan sedikit-sedikit tiap ada tambahan, dan
tabel yang dirawat dengan tangan seperti itu pasti meleset cepat atau
lambat: terakhir ia menyebut 351 kasus padahal barisnya sudah 474, dan
lima kelompok hilang sama sekali dari daftar.

| Kelompok | Kasus uji | Rentang |
|---|---|---|
| Pelanggan (CU) | 25 | TC-CU-01…25 |
| Kasir (KS) | 16 | TC-KS-01…16 |
| Pending Payment (PP) | 12 | TC-PP-01…12 |
| Dapur (CH) | 12 | TC-CH-01…12 |
| Keuangan (FN) | 17 | TC-FN-01…17 |
| Setor Saldo (SD) | 9 | TC-SD-01…09 |
| Katalog (AD) | 19 | TC-AD-01…19 |
| Topping (TP) | 12 | TC-TP-01…12 |
| QR Meja (QR) | 8 | TC-QR-01…08 |
| Diskon (DS) | 29 | TC-DS-01…29 |
| Kotak Masuk (IN) | 21 | TC-IN-01…21 |
| QRIS (PG) | 19 | TC-PG-01…19 |
| Pembatalan (CN) | 9 | TC-CN-01…09 |
| Sesi Meja (SS) | 7 | TC-SS-01…07 |
| Tampilan (TM) | 15 | TC-TM-01…15 |
| Super Admin (SA) | 17 | TC-SA-01…17 |
| Pembaruan (UP) | 9 | TC-UP-01…09 |
| Langganan (BL) | 55 | TC-BL-01…47 (+8 sisipan) |
| Finance MerchantPOS (PF) | 39 | TC-PF-01…38 (+1 sisipan) |
| Pilih Resto (CB) | 4 | TC-CB-01…04 |
| Tata Letak Tablet (TB) | 20 | TC-TB-01…20 |
| Setoran Modal (TU) | 13 | TC-TU-01…12 (+1 sisipan) |
| Voucher (VC) | 81 | TC-VC-01…81 |
| Analisa Pasar (MR) | 13 | TC-MR-01…13 |
| Pengaturan & Sesi (TS) | 19 | TC-TS-01…19 |
| Nomor Pesanan (NO) | 9 | TC-NO-01…09 |
| Layar Pelanggan (LP) | 7 | TC-LP-01…07 |
| Fasilitas & Jam Buka (IM) | 8 | TC-IM-01…08 |
| Penilaian Merchant (PM) | 11 | TC-PM-01…11 |
| Label & Penilaian Menu (LM) | 21 | TC-LM-01…21 |
| Shift Kasir (SH) | 20 | TC-SH-01…20 |
| Peran & Akses (RG) | 21 | TC-RG-01…21 |
| **Total** | **597** | **597 kasus + 9 alur ujung-ke-ujung** |

Kriteria penerimaan A-01…A-20 di FSD §9 seluruhnya terpetakan lewat
kolom Rujukan di atas. Bab TSD yang diuji: §1.2, §4, §5, §6, §7, §8,
§10, §11, §15.

---

*Dokumen ini disusun dari aplikasi versi 2.12.0 berikut `FSD-KAATAGO`
dan `TSD-KAATAGO` pada tanggal yang sama. Kasus uji yang tidak lagi
cocok dengan aplikasinya adalah temuan — entah pada aplikasinya, entah
pada dokumennya.*
