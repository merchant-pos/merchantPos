# Merchant-POS — Functional Specification Document

**Versi Aplikasi:** 2.16.0 (build 122)
**Versi Dokumen:** 3.1
**Tanggal Terbit:** 24 Agustus 2026
**Status:** Rilis
**Jenis Dokumen:** FSD — sisi fungsional

Dokumen ini menjelaskan **apa** yang dilakukan Merchant-POS: siapa memakainya,
proses apa yang dijalankan, aturan apa yang berlaku, dan hasil apa yang
diharapkan. Sisi teknisnya — arsitektur, tabel, kebijakan keamanan baris
— ada di dokumen terpisah (`TSD-KAATAGO`).

Isinya diambil dari aplikasi yang berjalan, bukan dari rencana. Setiap
perbedaan antara dokumen ini dan aplikasinya adalah temuan yang layak
dilaporkan.

---

## Daftar Isi

1. Ruang Lingkup
2. Peran Pengguna
3. Proses Bisnis Utama
4. Kebutuhan Fungsional per Modul
5. Aturan Bisnis
6. Aturan Validasi Isian
7. Daftar Status
8. Notifikasi
9. Kriteria Penerimaan
10. Batasan yang Diketahui
11. Lampiran A — Tangkapan Layar

---

## 1. Ruang Lingkup

Merchant-POS adalah aplikasi kasir sekaligus pemesanan mandiri untuk rumah
makan di Indonesia. Satu aplikasi melayani dua kelompok yang sangat
berbeda: **pelanggan**, yang memesan dari HP sendiri, dan **karyawan
resto** — kasir, dapur, admin, keuangan, pemilik — yang masing-masing
melihat menu berbeda begitu masuk.

### 1.1 Yang termasuk

| Bidang | Cakupan |
|---|---|
| Pemesanan | Pesan mandiri dari HP pelanggan (scan QR meja atau pilih resto), dan input pesanan oleh kasir |
| Pembayaran | QRIS, Tunai, Transfer; pelanggan boleh memilih bayar tunai di kasir |
| Dapur | Antrean masak per status, centang per menu |
| Keuangan | Pemasukan, pengeluaran, petty cash, setoran tunai, jurnal GL otomatis |
| Katalog | Produk, kategori, level/varian, stok, banner promo |
| Organisasi | Karyawan, banyak resto per akun, QR meja |
| Komunikasi | Kotak masuk pengumuman bersasaran, notifikasi push |
| Promo | Diskon per menu, bundling, minimum belanja; banner promo bermasa berlaku |
| Tampilan | Mode terang, gelap, atau mengikuti setelan HP |

### 1.2 Yang tidak termasuk

| Hal | Keterangan |
|---|---|
| Bahasa Inggris | Mekanismenya sudah ada tapi terjemahannya belum lengkap, jadi pemilih bahasanya **dimatikan**. Seluruh antarmuka berbahasa Indonesia |
| Pencocokan mutasi bank | Transfer dan setoran dipastikan manual oleh Finance |
| Aplikasi iOS | Rilis saat ini hanya Android |
| Pengiriman/kurir | Take Away berarti diambil sendiri |

---

## 2. Peran Pengguna

Login karyawan **hanya lewat Google Sign-In**, dan alamatnya harus sudah
terdaftar. Pelanggan boleh memesan **tanpa akun sama sekali**.

| Peran | Tugas utamanya |
|---|---|
| **Customer** | Memesan dari HP sendiri, membayar, memantau status pesanannya |
| **Kasir** | Menerima pesanan di konter, menerima pembayaran, menyetor tunai |
| **Chef** | Menjalankan antrean dapur |
| **Admin** | Katalog, karyawan, pengaturan resto, QR meja, pengumuman resto |
| **Finance** | Memutuskan setoran & petty cash, pemetaan GL, laporan |
| **Owner** | Seluruh menu di restonya, dan berpindah antar cabang |
| **Super Admin** | Seluruh resto, dan pengumuman versi aplikasi |

### 2.1 Matriks akses menu

| Menu | Super Admin | Owner | Admin | Kasir | Chef | Finance | Customer |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Kasir / Input Pesanan | – | ✔ | ✔ | ✔ | – | – | – |
| Pesanan Masuk | – | ✔ | ✔ | – | – | – | – |
| Layar Dapur | – | ✔ | – | – | ✔ | – | – |
| Pending Payment | – | ✔ | ✔ | ✔ | – | – | – |
| Riwayat Transaksi | – | ✔ | ✔ | ✔ | – | – | – |
| Pemasukan | – | ✔ | – | – | – | ✔ | – |
| Saldo & Pengeluaran | – | ✔ | ✔ | ✔ | – | ✔ | – |
| Setor Saldo Cash | – | ✔ | ✔ | ✔ | – | ✔ | – |
| Mapping GL Account | – | ✔ | – | – | – | ✔ | – |
| Jurnal GL | – | ✔ | – | – | – | ✔ | – |
| Laporan Transaksi | – | ✔ | – | – | – | ✔ | – |
| Tagihan Langganan | ✔ | ✔ | – | – | – | – | – |
| Billing Resto (semua) | ✔ | – | – | – | – | – | – |
| Finance Merchant-POS | ✔ | – | – | – | – | – | – |
| Voucher Pelanggan | ✔ | – | – | – | – | – | – |
| Jurnal GL semua resto | ✔ | – | – | – | – | – | – |
| Kelola Produk | – | ✔ | ✔ | – | – | – | – |
| Pengaturan Resto & QR Meja | – | ✔ | ✔ | – | – | – | – |
| Pengaturan Pembayaran | – | ✔ | – | – | – | ✔ | – |
| Kelola Karyawan | ✔ | ✔ | ✔ | – | – | – | – |
| List Resto | ✔ | – | – | – | – | – | – |
| Kirim Pengumuman | ✔ | ✔ | ✔ | – | – | – | – |
| Kotak Masuk | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | – |
| Pesan / Profil / Riwayat | – | – | – | – | – | – | ✔ |

### 2.2 Pemisahan wewenang

> **Yang mengajukan tidak boleh menyetujui.** Kasir dan Admin
> **mengajukan** setoran tunai dan top up petty cash. Finance dan Owner
> yang **memutuskan**. Aturan ini berlaku mutlak: tombolnya tidak muncul
> di aplikasi, dan permintaannya ditolak di sisi server sekalipun
> dipaksakan.

> **Pengumuman versi aplikasi hanya dari Super Admin.** Admin resto boleh
> mengirim pengumuman umum untuk restonya sendiri, tapi tidak
> pemberitahuan versi — dia tidak punya cara mengetahui versi mana yang
> sebenarnya sudah dirilis.

---

## 3. Proses Bisnis Utama

### 3.1 Pelanggan pesan sendiri — bayar QRIS

![Alur pesan sendiri — bayar QRIS](gambar/alur-01-qris.png)

### 3.2 Pelanggan pesan sendiri — bayar tunai di kasir

![Alur pesan sendiri — bayar tunai di kasir](gambar/alur-02-tunai-kasir.png)

Pesanannya **selesai dibuat saat itu juga** dan langsung diteruskan ke
dapur. Yang tertunda hanya uangnya. Pelanggan diberi nomor pesanan dan
diarahkan ke kasir; kasir menyelesaikannya lewat menu Pending Payment.

### 3.3 Setor saldo tunai

![Alur setor saldo tunai dan persetujuannya](gambar/alur-03-setor.png)

### 3.4 Top up petty cash

![Alur top up petty cash dan persetujuannya](gambar/alur-04-petty.png)

Perbedaannya dengan setoran tunai: perantaranya **GL Suspense Petty
Cash**, tombolnya berbunyi *Setuju*/*Tolak* (setoran: *Konfirmasi*/
*Tolak*), dan top up yang dibuat Finance sendiri langsung berstatus
selesai — tidak ada gunanya menyetujui permintaan sendiri.

### 3.5 Alur dapur

![Alur status dapur](gambar/alur-05-dapur.png)

---

## 4. Kebutuhan Fungsional per Modul

### 4.1 Pemesanan Mandiri (Customer)

| ID | Kebutuhan |
|---|---|
| F-CU-01 | Pelanggan dapat memesan tanpa akun (tamu) maupun dengan akun Google |
| F-CU-02 | Masuk ke menu resto lewat scan QR meja **atau** memilih resto dari daftar |
| F-CU-03 | Scan QR meja mengisi nomor mejanya otomatis dan menguncinya |
| F-CU-04 | Memilih level/varian dan menuliskan catatan per menu |
| F-CU-25 | Memilih **beberapa topping sekaligus**, dibatasi maksimal yang disetel resto |
| F-CU-26 | Harga tiap topping tampil di pilihannya, dan subtotal berubah seketika |
| F-CU-05 | Satu produk dengan varian berbeda menjadi **baris terpisah** di keranjang |
| F-CU-06 | Menu yang telanjur ditambahkan dapat dihapus atau diubah dari keranjang |
| F-CU-07 | Memilih **Dine In** atau **Take Away**; Take Away tidak meminta nomor meja |
| F-CU-08 | Nama pemesan wajib diisi pada kedua jenis |
| F-CU-09 | Memilih cara bayar: **QRIS** atau **Tunai** (bayar di kasir) |
| F-CU-10 | Ringkasan tagihan menampilkan subtotal, biaya service, PPN, dan total |
| F-CU-11 | Memantau status pesanannya secara langsung tanpa perlu menyegarkan |
| F-CU-12 | Melihat riwayat pesanan; tamu tetap melihat riwayat dari perangkatnya |
| F-CU-13 | Riwayat tamu berpindah ke akunnya saat pertama kali login |
| F-CU-14 | Mengatur nama, nomor HP, dan foto profil; foto dapat **dihapus** |
| F-CU-15 | Melihat lokasi resto dan membukanya di Google Maps |
| F-CU-16 | Melihat banner promo resto **utuh, tidak terpotong**, dan ikut tergulir bersama daftar menu |
| F-CU-17 | Diskon yang sedang berlaku ikut dihitung pada pesanan mandiri, berikut nama promonya |
| F-CU-18 | Pesanan yang belum dibayar dapat **dibatalkan sendiri** dari Pesanan Saya maupun Riwayat |
| F-CU-19 | Pesanan tunai yang tidak dilunasi dalam **30 menit** hangus otomatis, dengan hitungan mundur di layar |
| F-CU-20 | Kotak Masuk di menu utama berisi promo resto yang pernah dipesan, berikut **nama restonya** |
| F-CU-21 | Menu yang ditandai habis tetap tampil dengan tanda, tapi tidak bisa dipesan |
| F-CU-22 | Ketersediaan diperiksa **ulang saat hendak membayar**; menu yang keburu habis harus dihapus dulu |
| F-CU-23 | Pilihan Dine In / Take Away hanya muncul untuk cara makan yang dilayani resto itu |
| F-CU-24 | Mengatur tampilan terang, gelap, atau mengikuti setelan HP |

### 4.2 Kasir

| ID | Kebutuhan |
|---|---|
| F-KS-01 | Memilih produk dari daftar per kategori, dengan stok berkurang saat checkout |
| F-KS-02 | Menerima pembayaran Tunai, QRIS, atau Transfer |
| F-KS-03 | Pembayaran tunai menampilkan uang diterima, kembalian, dan saran nominal |
| F-KS-04 | Tombol terima pembayaran mati selama uang yang dimasukkan kurang dari total |
| F-KS-05 | Struk dapat disimpan ke galeri, dibagikan, dan dicetak |
| F-KS-06 | Struk transaksi lama dapat ditampilkan dan dicetak ulang dari riwayat |
| F-KS-07 | Riwayat Kasir dikelompokkan per hari berikut rincian per metode bayar |
| F-KS-08 | Nama pelanggan dapat diisi pada Dine In (opsional) maupun Take Away (wajib) |
| F-KS-09 | QRIS kasir dibangkitkan penyedia pembayaran sungguhan, dan lunas sendiri saat pembayarannya masuk |
| F-KS-10 | QR pembayaran dapat **dicetak** untuk diserahkan ke pelanggan, dengan bingkai yang sama seperti QR meja |
| F-KS-11 | Diskon yang berlaku ikut dihitung dan ditampilkan sebagai baris tersendiri sebelum pembayaran |
| F-KS-12 | Ketersediaan diperiksa ulang sebelum pembayaran diterima |
| F-KS-13 | Detail jurnal dari catatan yang tampil di layar Saldo dapat dibuka kasir |

### 4.3 Pending Payment

| ID | Kebutuhan |
|---|---|
| F-PP-01 | Menampilkan pesanan mandiri berstatus menunggu pembayaran dengan cara bayar tunai |
| F-PP-02 | Menampilkan jumlah pesanan dan total nominal yang menunggu |
| F-PP-03 | Rincian pesanan dapat dibuka: item, catatan, biaya service, PPN, total |
| F-PP-04 | Menerima pembayaran memakai dialog yang sama dengan checkout kasir |
| F-PP-05 | Satu pesanan tidak dapat dilunasi dua kali oleh ketukan beruntun |
| F-PP-06 | Pesanan yang lunas **hilang seketika** dari antrean tanpa perlu menyegarkan |
| F-PP-07 | Pesanan yang lunas **muncul di Riwayat Kasir** dan ikut dihitung pada total harian, **apa pun cara bayar yang dipakai saat pelunasan** |
| F-PP-08 | Kartu menunya membawa penanda merah berisi jumlah antrean |
| F-PP-09 | Cara bayar dapat **diganti** ke QRIS atau Transfer saat pelunasan |
| F-PP-10 | Sisa waktu pelunasan tampil di tiap kartu, berwarna pada 10 menit terakhir |

**Negatif:** pesanan QRIS yang belum dibayar dan pesanan yang diinput
kasir **tidak boleh** muncul di daftar ini.

### 4.4 Dapur

| ID | Kebutuhan |
|---|---|
| F-CH-01 | Empat tab: **Menunggu Bayar**, Baru, Diproses, Selesai |
| F-CH-02 | Mencentang menu satu per satu; sebagian tercentang → Diproses, seluruhnya → Selesai |
| F-CH-03 | Pesanan selesai dikelompokkan per tanggal, tertutup secara bawaan |
| F-CH-04 | Kotak masuk dapat dibuka dari layar dapur berikut penanda belum dibaca |
| F-CH-05 | Owner yang membuka layar dapur tidak melihat tombol Keluar, Kotak Masuk, Tes Notifikasi, dan Tampilan |
| F-CH-06 | Pesanan yang belum dibayar dikumpulkan di tab Menunggu Bayar, **tidak** bercampur di Baru |
| F-CH-07 | Pesanan yang belum dibayar **tidak punya tombol Mulai Masak**; yang tampil keterangan untuk menunggu kasir |
| F-CH-08 | Pesanan yang hangus atau dibatalkan tidak muncul di tab mana pun |

### 4.5 Keuangan

| ID | Kebutuhan |
|---|---|
| F-FN-01 | Saldo total = Penghasilan + Petty Cash + Setoran − Pengeluaran |
| F-FN-02 | Penghasilan dipisah **Cash** dan **Non Cash**; angka tunai harus cocok dengan isi laci |
| F-FN-03 | Mengajukan/menambah top up petty cash dari tiga sumber dana |
| F-FN-04 | Mencatat pengeluaran, selalu diambil dari petty cash, dibatasi saldo tersedia |
| F-FN-05 | Melampirkan foto nota pada pengeluaran |
| F-FN-06 | Riwayat dikelompokkan per tanggal, **tertutup secara bawaan** |
| F-FN-07 | Tanggal yang menyimpan pengajuan **terbuka sendiri** dan diberi penanda merah |
| F-FN-08 | Setiap baris dapat dibuka untuk melihat jurnal GL di baliknya |
| F-FN-09 | Memetakan nomor GL untuk tiap metode bayar, PPN, service, dan akun perantara |
| F-FN-10 | Mengatur tarif PPN dan biaya service |
| F-FN-11 | Mencetak/mengekspor laporan transaksi bergaya rekening koran |

### 4.6 Setor Saldo Cash

| ID | Kebutuhan |
|---|---|
| F-SD-01 | Mengajukan setoran: nominal, catatan, dan foto bukti transfer |
| F-SD-02 | Nama bank, nomor rekening, dan nama pemilik **hanya ditampilkan**, mengikuti Pengaturan Pembayaran |
| F-SD-03 | Tombol simpan mati bila rekening resto belum diatur |
| F-SD-04 | Popup konfirmasi mengingatkan agar nominalnya sesuai yang benar-benar ditransfer |
| F-SD-05 | Finance mengonfirmasi atau menolak; keputusannya mengembalikan atau meneruskan dananya |
| F-SD-06 | Foto bukti dapat dibuka besar |
| F-SD-07 | Kartu menunya membawa penanda merah berisi jumlah pengajuan menunggu |

### 4.7 Katalog & Pengaturan Resto

| ID | Kebutuhan |
|---|---|
| F-AD-01 | Menambah, mengubah, menonaktifkan produk berikut foto, deskripsi, harga, stok |
| F-AD-02 | Harga diisi sebagai **harga bersih**; harga jual dihitung otomatis |
| F-AD-03 | Menandai produk bebas PPN |
| F-AD-04 | Mengelola kategori |
| F-AD-09 | **Tab Level**: menyusun sendiri kelompok level/varian resto ini berikut pilihannya |
| F-AD-10 | Resto baru disemai lima kelompok bawaan (Level Pedas, Level Gula, Level Es, Suhu, Ukuran) |
| F-AD-11 | Kelompok level minimal punya **2 pilihan**; nama kelompok tidak boleh kembar dalam satu resto |
| F-AD-18 | Produk dapat menawarkan **topping** — opsional, masing-masing dengan harganya sendiri |
| F-AD-19 | Topping dapat dibatasi: **maksimal berapa** yang boleh dipilih sekaligus; kosong berarti tanpa batas |
| F-AD-20 | Topping berharga **Rp 0** tetap boleh ditawarkan |
| F-AD-12 | Stok **opsional**; ketersediaan ditentukan penanda **Out of Stock**, bukan angka stok |
| F-AD-13 | Produk dapat ditandai habis langsung dari daftar, tanpa membuka formulirnya |
| F-AD-14 | Stok tidak ditampilkan ke pelanggan |
| F-AD-05 | Mengelola karyawan; **email dapat diubah** tanpa kehilangan riwayat |
| F-AD-06 | Mengatur info resto, termasuk mengambil titik lokasi sekali tekan |
| F-AD-15 | Lokasi resto punya **pratinjau peta**; titiknya dapat dipilih dengan menggeser pin di peta |
| F-AD-16 | Resto memilih melayani **Dine In**, **Take Away**, atau keduanya; minimal satu harus menyala |
| F-AD-07 | Mengunggah banner promo, mengaktifkan/menonaktifkan, dan mengurutkannya |
| F-AD-17 | Banner promo punya **masa berlaku**: mulai tidak boleh mundur, berakhir minimal besok |
| F-AD-08 | Akun dengan beberapa cabang dapat berpindah resto tanpa logout |

### 4.8 QR Meja

| ID | Kebutuhan |
|---|---|
| F-QR-01 | Membuat QR untuk satu meja dengan nomor bebas ("7", "A01", "VIP-2") |
| F-QR-02 | Membuat banyak meja sekaligus: **isi jumlah mejanya**, misal 10 → 10 QR bernomor 1–10. Maksimal **100** |
| F-QR-03 | Awalan opsional; diisi "A" menghasilkan A1, A2, A3, … |
| F-QR-07 | Nomor meja ditulis polos (`7`, bukan `07`) supaya sama dengan mode satu meja; urutan berkas di galeri dijaga lewat nama berkasnya |
| F-QR-04 | Kartunya bergaya Merchant-POS, memuat nama resto dan nomor meja |
| F-QR-05 | Menyimpan ke galeri satuan maupun **seluruhnya sekaligus**, dengan penghitung kemajuan |
| F-QR-06 | Membagikan dan mencetak, satu meja satu halaman |

### 4.9 Kotak Masuk & Pengumuman

| ID | Kebutuhan |
|---|---|
| F-IN-01 | Kotak masuk terbagi dua tab: **Update Aplikasi** dan **General** |
| F-IN-02 | Tiap tab menampilkan jumlah pesan belum dibaca sendiri-sendiri |
| F-IN-03 | Pesan dapat dihapus satuan maupun seluruhnya; hanya hilang dari kotak masuk orang itu |
| F-IN-04 | Pengumuman versi memuat tombol **Unduh Versi Terbaru** |
| F-IN-05 | Unduhan berjalan **di dalam aplikasi** berikut persen kemajuan, lalu membuka pemasangnya |
| F-IN-06 | Tersedia jalur cadangan mengunduh lewat browser |
| F-IN-07 | Super Admin mengirim pengumuman versi maupun umum ke seluruh resto |
| F-IN-08 | Admin/Owner mengirim pengumuman umum untuk restonya sendiri |
| F-IN-09 | Pengumuman umum dapat memuat **gambar promo** |
| F-IN-10 | Pengumuman milik sebuah resto tidak muncul di kotak masuk resto lain |
| F-IN-11 | Pengumuman resto memilih sasarannya: **Karyawan**, **Customer**, atau **Semua** |
| F-IN-12 | Pelanggan punya kotak masuknya sendiri di menu utama, berisi promo resto yang pernah dia pesan |
| F-IN-13 | Tiap promo di kotak masuk pelanggan menyebutkan **nama resto pengirimnya** |
| F-IN-14 | Pelanggan tamu ikut menerima; jangkauannya dari pesanan yang tersimpan di perangkatnya |
| F-IN-15 | Tandai-dibaca dan hapus massal hanya mengenai **tab yang sedang dibuka** |
| F-IN-16 | Unduhan tampil di **bar notifikasi HP** berikut persennya, dan tetap jalan saat aplikasi ditinggalkan |
| F-IN-17 | Selesai mengunduh memunculkan notifikasi **"ketuk untuk memasang"** |
| F-IN-18 | Popup unduhan menawarkan **Batalkan** atau **Lanjutkan** |
| F-IN-19 | Galat unduhan diringkas satu kalimat; pembatalan tidak ditampilkan sebagai galat |
| F-IN-10 | **Semua peran karyawan** menerima push, termasuk Super Admin dan Owner yang belum memilih cabang |
| F-IN-11 | Pelanggan yang sudah masuk menerima push walau belum membuka resto mana pun |
| F-IN-12 | Pengumuman khusus pelanggan tidak sampai ke karyawan, dan sebaliknya |


### 4.10 Diskon

Menu ini ada di **Kasir, Admin, dan Owner**. Satu aturan diskon berlaku
untuk transaksi kasir maupun pesanan yang dibuat sendiri oleh pelanggan
— promo yang cuma berlaku kalau kasir yang mengetikkan pesanannya bukan
promo, melainkan janji yang gagal ditepati di depan orang yang
membacanya.

| ID | Kebutuhan |
|---|---|
| F-DS-01 | Diskon berbasis **menu tertentu**: satu menu, atau beberapa sekaligus untuk bundling |
| F-DS-02 | Diskon berbasis **minimum belanja** dengan indikator **≥** atau **>** yang dipilih sendiri |
| F-DS-10 | Tiap menu dalam promo membawa **syarat jumlahnya sendiri**, bukan satu angka untuk seluruh promo |
| F-DS-11 | Syarat jumlah berbentuk **Minimal** (lebih banyak tetap dapat) atau **Tepat** (kurang maupun lebih tidak dapat) |
| F-DS-12 | Pada bundling, **seluruh** menu yang disebut harus terpenuhi — kurang satu berarti promonya tidak berlaku sama sekali |
| F-DS-14 | Diskon dapat menyasar bagian menu yang lebih sempit: level/varian, topping, atau harga menu utamanya saja |
| F-DS-15 | Sasaran sempit memotong **tambahan harganya saja** — "gratis ukuran besar" tetap membayar harga menunya |
| F-DS-16 | Promo bersasaran sempit hanya berlaku kalau pilihan itu **benar-benar dipesan** |
| F-DS-17 | Satu menu boleh menyasar **beberapa bagian sekaligus**, dipilih lewat daftar centang berisi seluruh topping dan level berharga |
| F-DS-18 | Sasaran yang dicentang **dijumlahkan**, bukan dipilih salah satu |
| F-DS-19 | **"Harga menu utama"** dibedakan dari **"Seluruh harga menu"**: yang pertama tidak ikut memotong topping dan tambahan yang dipilih pemesan |
| F-DS-20 | Mencentang "Seluruh harga menu" mengosongkan sasaran lainnya |
| F-DS-21 | Menu yang sedang kena promo diberi label **DISKON** di kartunya, tanpa dicentang siapa pun |
| F-DS-22 | Menu berlabel DISKON, saat diketuk, menjelaskan promonya: nama, besar potongan, syarat jumlah, sasaran, isi paket, dan tanggal berakhir |
| F-DS-03 | Potongan berbentuk **persen** (1–100) atau **rupiah** |
| F-DS-04 | Masa berlaku: mulai tidak boleh mundur ke belakang, berakhir minimal besok |
| F-DS-05 | Lencana status: **Berjalan**, **Terjadwal**, **Sudah lewat**, **Nonaktif** |
| F-DS-06 | Dapat dinonaktifkan tanpa dihapus |
| F-DS-07 | Potongan tampil sebagai baris tersendiri berikut nama promonya, lalu nominal **DIBAYAR** |
| F-DS-08 | Diskon tercatat pada pesanannya, sehingga struk lama tetap menyebut potongan yang benar |
| F-DS-09 | Diskon punya **GL sendiri** sebagai pengurang pendapatan, terisi bawaannya |
| F-DS-13 | Baris jurnal diskon menyebut nama promonya — "Ngopi Santai — pesanan #A2F6F5A2" |

**Aturan pemilihan:**

| Aturan | Alasan |
|---|---|
| Hanya **satu** diskon dipakai — yang paling menguntungkan pelanggan | Menumpuk terdengar murah hati sampai dua promo berlaku bersamaan dan totalnya melebihi harga barangnya |
| Bundling menjumlahkan seluruh menu yang ikut, baru dipotong | Kalau dipotong per baris, diskon rupiah tetap terkalikan sebanyak menu yang ikut |
| Syarat jumlah menempel di **menunya**, bukan di promonya | Satu angka untuk seluruh promo membuat "Nasi Goreng + Es Teh, beli 2" lolos oleh keranjang berisi dua Nasi Goreng dan segelas kopi |
| Bundling menuntut **seluruh** menunya terpenuhi | Sebagian-cukup berarti paket yang dijanjikan tidak pernah benar-benar dibeli, tapi restonya tetap membayar potongannya |
| Menu di luar promo tidak ikut dipotong sekalipun ada di keranjang | Potongannya dihitung dari menu yang memang ikut promo |
| Sasaran sempit memotong tambahan harganya saja | "Gratis ukuran besar" berarti selisih ukurannya yang hilang, bukan harga menunya — kalau seluruhnya dipotong, promonya jadi jauh lebih mahal daripada yang dijanjikan |
| Beberapa sasaran dijumlahkan, bukan dipilih salah satu | Promo "topping gratis" nyaris tidak pernah berarti satu topping tertentu. Menyatakannya sebagai beberapa promo terpisah membuat semuanya jadi syarat yang harus dipenuhi berbarengan — dan yang memilih satu dari tiga topping tidak dapat apa-apa |
| Label DISKON tidak pernah dicentang merchant | Ia dibaca dari promo yang sedang berjalan. Label yang dicentang akan tetap terpasang seminggu setelah promonya habis, dan yang menanggung selisihnya kasir di depan pelanggan |
| Potongan tidak pernah melebihi tagihannya | Kalau tidak, totalnya negatif — resto berutang kepada orang yang belum membayar apa pun |
| Diskon dihitung dari **total setelah service dan PPN** | Itulah angka yang dilihat dan dijanjikan ke pelanggan |

### 4.11 Pembayaran QRIS lewat Penyedia

| ID | Kebutuhan |
|---|---|
| F-PG-01 | QR pembayaran dibangkitkan penyedia pembayaran, bukan QR simulasi |
| F-PG-02 | Pesanan menjadi lunas saat penyedia mengabarkan pembayarannya masuk — bukan lewat ketukan di layar |
| F-PG-03 | Tiap resto punya sub-akun sendiri, sehingga dananya cair ke rekening masing-masing |
| F-PG-04 | Pengenal sub-akun hanya terlihat dan dapat diubah oleh **Super Admin** |
| F-PG-05 | Layar QRIS menampilkan hitungan mundur masa berlaku QR-nya |
| F-PG-06 | Resto yang belum punya sub-akun tetap dapat memakai QR simulasi berikut konfirmasi manual |
| F-PG-07 | Dengan penyedia aktif, tombol konfirmasi manual **dihilangkan** dari layar kasir |
| F-PG-11 | Pembayaran QRIS menyimpan rincian kuitansinya: ID Transaksi, ID Referensi, ID Product, Mitra, ID QR, Customer PAN, ID Kuitansi Mitra, Sumber, ID Pengakuisisi, Partner |
| F-PG-12 | Rinciannya disimpan untuk **semua** keadaan — menunggu, gagal, maupun sukses |
| F-PG-13 | Status penyedia disimpan terpisah dari status pembayaran Merchant-POS, berikut sebab kegagalannya |
| F-PG-14 | Transaksi yang menunggu **berubah jadi lunas** saat kabar suksesnya datang; yang gagal tidak menutup pesanannya |

### 4.12 Pembatalan Pesanan

| ID | Kebutuhan |
|---|---|
| F-CN-01 | Pelanggan dapat membatalkan pesanannya sendiri selama **belum dibayar** |
| F-CN-02 | Tombolnya tersedia di **Pesanan Saya** dan **Riwayat** |
| F-CN-03 | Pembatalan ditolak kalau dapur **sudah mulai memasak**; pesannya mengarahkan ke kasir |
| F-CN-04 | Pembatalan hanya berlaku untuk pesanannya sendiri — dikenali dari email atau sesi perangkatnya |
| F-CN-05 | Pesanan tunai yang tidak dilunasi dalam 30 menit **hangus otomatis** |
| F-CN-06 | Status **Dibatalkan** dibedakan dari **Hangus** |

### 4.13 Tampilan

| ID | Kebutuhan |
|---|---|
| F-TM-01 | Tiga pilihan: **Terang**, **Gelap**, **Ikuti HP** (bawaan) |
| F-TM-02 | Dapat diatur sebelum masuk, di halaman awal, maupun sesudah masuk dari tiap peran |
| F-TM-03 | Pilihannya tersimpan di perangkat dan bertahan setelah aplikasi ditutup |
| F-TM-04 | Pilihan tampilan menyusut jadi ikon saja saat ruangnya sempit |
| F-TM-05 | Menu tiap peran **ditumpuk di balik kelompoknya** — halaman awal berisi 6 pintu, bukan belasan |
| F-TM-06 | Kartu kelompok menyebutkan isinya, bukan hanya judulnya |
| F-TM-07 | **Kotak Masuk, Pengaturan, dan Keluar berdiri sendiri**, tidak ditumpuk |
| F-TM-08 | Penanda merah di dalam kelompok **dijumlahkan ke kartu kelompoknya** |

### 4.14 Super Admin

Satu peran di luar seluruh resto. Ia tidak menjual, tidak memasak, dan
tidak memegang uang siapa pun — yang dipegangnya adalah hal-hal yang
kalau diserahkan ke tiap resto akan berbeda-beda di tempat yang
seharusnya sama.

| ID | Kebutuhan |
|---|---|
| F-SA-01 | Melihat dan mengelola **seluruh resto** yang terdaftar |
| F-SA-07 | Menghapus resto dari daftar — **soft delete**, datanya tidak dibuang |
| F-SA-08 | Resto terhapus dapat **dikembalikan**, dan tidak langsung ikut aktif |
| F-SA-09 | Daftar menyembunyikan yang terhapus, dengan saklar untuk menampilkannya |
| F-SA-10 | Resto terhapus: pelanggan tidak bisa memesan, katalognya terkunci |
| F-SA-11 | Resto terhapus **berhenti ditagih**; tagihan yang sudah terbit tetap ada |
| F-SA-12 | Penghapusan mencatat **siapa dan kapan** |
| F-SA-02 | Mengelola karyawan lintas resto, termasuk menetapkan perannya |
| F-SA-03 | Mengirim **pengumuman versi aplikasi** ke seluruh pengguna — satu-satunya peran yang boleh |
| F-SA-04 | Mengirim pengumuman umum ke seluruh resto sekaligus |
| F-SA-05 | Melihat dan mengubah **pengenal sub-akun penyedia pembayaran** tiap resto |
| F-SA-06 | Tidak punya layar kasir, dapur, maupun keuangan resto mana pun |

> **Kenapa pengumuman versi dikunci di sini.** Nomor versi yang beredar
> harus satu untuk semua. Kalau tiap resto boleh mengumumkan versinya
> sendiri, yang terjadi bukan kebebasan melainkan lima pengumuman
> berbeda tentang versi yang sama, dan pelanggan yang membaca kotak
> masuknya tidak tahu mana yang benar.

### 4.15 Sesi Meja & Identitas Pelanggan

Pelanggan boleh memesan tanpa mendaftar apa pun. Itu keputusan yang
disengaja — meminta orang membuat akun sebelum memesan segelas kopi
adalah cara tercepat kehilangan pesanan itu. Konsekuensinya harus
ditangani: tamu tetap perlu bisa melihat pesanannya, dan kalau nanti dia
membuat akun, riwayatnya tidak boleh hilang.

| ID | Kebutuhan |
|---|---|
| F-SS-01 | Memindai QR meja membuka **sesi meja**: resto dan nomor mejanya terisi sendiri |
| F-SS-02 | Pesanan tamu ditandai `Tamu` dan dilacak lewat daftar id di **HP-nya sendiri** |
| F-SS-03 | Tamu yang kemudian login **mewarisi** riwayat pesanannya ke akun itu |
| F-SS-04 | Pewarisan hanya terjadi bila emailnya **belum pernah** punya pesanan |
| F-SS-05 | Bila emailnya sudah punya riwayat, keduanya dibiarkan terpisah — riwayat tamu tetap di HP |
| F-SS-06 | Sesi meja berakhir sendiri **5 menit** setelah seluruh pesanannya selesai dimasak |
| F-SS-07 | Pesanan yang belum selesai menahan sesinya tetap terbuka, berapa lama pun |

> **Kenapa pewarisan menolak email yang sudah berisi.** Kalau riwayat
> tamu ditumpahkan ke akun yang sudah punya pesanan, tidak ada cara
> membedakan mana yang benar-benar miliknya dan mana yang kebetulan ada
> di HP itu — HP yang mungkin dipinjam, atau dipakai bergantian di satu
> keluarga. Menolak lebih aman daripada mencampur, dan yang ditolak
> tidak kehilangan apa pun: daftarnya tetap ada di perangkatnya.

### 4.16 Pembaruan Aplikasi

Merchant-POS dibagikan sebagai APK, bukan lewat toko aplikasi. Tidak ada yang
memperbarui aplikasinya diam-diam di latar belakang — jadi seluruh
alurnya harus ada di dalam aplikasi itu sendiri.

| ID | Kebutuhan |
|---|---|
| F-UP-01 | Pengumuman versi memuat tombol **Unduh Versi Terbaru** |
| F-UP-02 | Unduhannya berjalan **di dalam aplikasi**, bukan membuka peramban |
| F-UP-03 | Kemajuannya tampil di **bar notifikasi HP** berikut persennya |
| F-UP-04 | Unduhan tetap berjalan saat aplikasi ditinggalkan atau HP dikunci |
| F-UP-05 | Menekan tombol saat unduhan berjalan memunculkan pilihan **Batalkan** atau **Lanjutkan** |
| F-UP-06 | Selesai mengunduh, pemasang Android dibuka otomatis |
| F-UP-07 | Galat dibedakan: koneksi terputus, penyimpanan penuh, atau galat lain — dan tidak pernah menampilkan isi galat mentahnya |

### 4.17 Langganan & Tagihan Resto

Resto membayar biaya langganan bulanan kepada Merchant-POS. Ini satu-satunya
bagian aplikasi tempat **resto menjadi pelanggan**, bukan penjual — dan
karena itu sengaja dipisah dari seluruh menu keuangan resto, yang
mencatat uang masuk ke resto, bukan uang keluar dari resto ke kami.

| ID | Kebutuhan |
|---|---|
| F-BL-01 | Harga langganan bulanan ditentukan **per resto** oleh Super Admin |
| F-BL-02 | Tanggal jatuh tempo ditentukan **per resto**, antara tanggal 1 sampai 28 |
| F-BL-03 | Tenggang sesudah jatuh tempo dapat diatur; bawaannya **1 hari** |
| F-BL-04 | Harga **Rp 0** berarti gratis — tidak pernah ditagih dan tidak pernah terkunci |
| F-BL-05 | Langganan dapat dimatikan per resto tanpa menghapus datanya |
| F-BL-06 | Resto baru langsung punya setelan langganan, **gratis**, sampai harganya ditetapkan |
| F-BL-07 | Tagihan terbit otomatis **7 hari** sebelum jatuh tempo |
| F-BL-08 | Satu tagihan per resto per periode — tidak pernah ganda |
| F-BL-09 | Mulai **H-3**, pita pengingat tampil di layar utama tiap peran resto |
| F-BL-10 | Pengingat tetap tampil sesudah lewat jatuh tempo selama belum lunas |
| F-BL-11 | Pembayaran lewat **Virtual Account Xendit** ke rekening Merchant-POS |
| F-BL-19 | Resto memilih banknya: BCA, BNI, BRI, Mandiri, Permata, BSI, atau CIMB |
| F-BL-20 | Nomor VA **tertutup di nominal tagihan** — kurang bayar tidak melunasi |
| F-BL-21 | Nomor VA **sekali pakai**, dan berlaku sampai 7 hari sesudah jatuh tempo |
| F-BL-22 | Tagihan lunas **otomatis** begitu transfernya masuk — tanpa mengirim bukti |

> **Kenapa Finance ikut memegangnya.** Yang membayar tagihan di
> kebanyakan resto memang bagian Finance, bukan Owner. Basis datanya
> sejak awal sudah mengizinkan — hanya pintunya yang belum ada, dan
> menyuruh Finance meminjam akun Owner untuk membayar adalah cara
> tercepat membuat satu akun dipakai dua orang.

> **Kenapa tanggal 29–31 sekarang boleh.** Batas lama 1–28 menghindari
> pertanyaan "tanggal 31 di Februari itu kapan" dengan cara melarang
> resto memilih tanggal tagihnya sendiri — dan resto yang siklus kasnya
> jatuh di akhir bulan terpaksa menagih di tanggal yang bukan
> tanggalnya. Sekarang pertanyaannya dijawab: bulannya yang dilihat,
> bukan angka yang dipatok.

> **Kenapa tanggal berikutnya ditampilkan, bukan cuma "tiap tanggal
> 31".** Tanggal 31 tidak ada di setiap bulan. Menyebut angkanya saja
> membuat orang menunggu tanggal yang tidak akan datang.

> **Kenapa VA hilang begitu lunas.** Nomor yang masih terbaca di bawah
> tulisan "Lunas" adalah undangan untuk mentransfer dua kali — dan uang
> kedua itu tidak punya tagihan untuk dilunasi.

> **Kenapa invoice PDF memisahkan harga daftar dan potongannya.**
> Bagian keuangan resto mencocokkan angka itu dengan harga yang
> disepakati; netto tanpa rinciannya membuat mereka mengira harganya
> berubah diam-diam.
| F-BL-23 | VA yang masih hidup dipakai ulang, tidak diterbitkan ulang tiap dibuka |
| F-BL-24 | Tersedia jalur cadangan: unggah bukti transfer manual untuk diperiksa |
| F-BL-12 | Bukti manual yang sudah diunggah menahan penguncian selama diperiksa |
| F-BL-13 | Hanya **Super Admin** yang menyatakan sebuah tagihan lunas |
| F-BL-14 | Penolakan bukti **wajib menyertakan alasan**, dan alasannya dibaca resto |
| F-BL-15 | Lewat tenggang dan belum dibayar → **aplikasi terkunci** untuk resto itu |
| F-BL-16 | Layar terkunci tetap menyediakan **Lihat & Bayar Tagihan** dan **Keluar** |
| F-BL-17 | Super Admin tidak pernah terkunci |
| F-BL-18 | Penguncian ditegakkan di **basis data**, bukan hanya di layar |
| F-BL-19 | Tanggal tagih boleh **1–31**; tanggal yang melebihi umur bulannya jatuh di **hari terakhir** bulan itu |
| F-BL-20 | Layar tagihan menampilkan **kapan tagihan berikutnya** jatuh tempo |
| F-BL-21 | Nomor Virtual Account **hilang begitu tagihannya lunas** |
| F-BL-22 | Tagihan lunas dapat **diunduh sebagai invoice PDF**, memuat harga daftar dan potongannya terpisah |
| F-BL-23 | **Finance** punya menu Tagihan Langganan dengan akses yang sama dengan Owner |

**Kapan terkunci, kapan tidak:**

| Keadaan | Terkunci? |
|---|---|
| Belum jatuh tempo | Tidak |
| Jatuh tempo hari ini, belum bayar | Tidak — tenggang belum lewat |
| Lewat tenggang, belum bayar | **Ya** |
| Lewat tenggang, transfer VA sudah masuk | Tidak — lunas seketika |
| Lewat tenggang, bukti manual sudah diunggah | Tidak — sedang diperiksa |
| Bukti ditolak, lewat tenggang | **Ya** |
| Harga Rp 0, atau langganan dimatikan | Tidak, apa pun keadaannya |

> **Kenapa bukti yang sudah diunggah menahan penguncian.** Transfer
> antarbank yang dikirim Jumat sore baru terlihat Senin. Mengunci resto
> yang uangnya sedang dalam perjalanan berarti menghentikan
> penjualannya sehari penuh karena keterlambatan yang bukan salahnya —
> dan itu kesalahan yang paling mahal di seluruh fitur ini, karena yang
> hilang bukan cuma kepercayaan tapi pendapatan hari itu.

> **Kenapa layar terkunci tetap punya jalan keluar.** Mengunci
> satu-satunya jalan membayar berarti resto yang sudah mentransfer tidak
> punya cara memberi tahu siapa pun.

### 4.18 Finance Merchant-POS (Super Admin)

Pembukuan Merchant-POS sendiri, terpisah dari pembukuan resto. Ini bagian
yang mencatat **uang masuk ke kami** — kebalikan arah dari seluruh menu
keuangan lain di aplikasi ini.

| ID | Kebutuhan |
|---|---|
| F-PF-01 | Riwayat langganan: seluruh tagihan yang sudah dibayar, dikelompokkan per bulan |
| F-PF-02 | Tiap baris menyebut jalur pelunasannya — **VA** (mesin) atau **manual** (keputusan orang) |
| F-PF-03 | **Diskon langganan** untuk resto yang dipilih, berbentuk persen atau rupiah |
| F-PF-04 | Diskon punya masa berlaku dan dapat dinonaktifkan tanpa dihapus |
| F-PF-05 | Diskon dipakai saat tagihan **berikutnya** terbit; tagihan yang sudah terbit tidak berubah |
| F-PF-06 | Diskon punya **GL sendiri** sebagai pengurang pendapatan |
| F-PF-07 | Pendapatan langganan masuk **Jurnal GL Merchant-POS** secara otomatis saat tagihan lunas |
| F-PF-13 | Pendapatan dicatat sebesar **harga daftar**; diskon jadi baris pengurang tersendiri |
| F-PF-08 | Merchant-POS punya **bagan akun sendiri** — pendapatan, diskon, kas, petty cash, suspense, pengeluaran |
| F-PF-09 | Saldo Merchant-POS dihitung dari **total kredit − total debit seluruh buku**, sumber yang sama dengan Jurnal GL |
| F-PF-10 | Layar Saldo Merchant-POS tidak menampilkan Saldo Cash/Non Cash — Merchant-POS tidak punya laci kasir |
| F-CB-01 | Daftar **Terdekat** hanya memuat resto dalam radius **5 km** dari titik pelanggan |
| F-CB-02 | Resto di luar radius tetap tersedia di daftar **Semua Resto** |
| F-TB-01 | Di layar lebar, keranjang tampil sebagai **panel tetap di kanan** — untuk Kasir maupun Pelanggan |
| F-TB-02 | Popup menu dan popup edit baris muncul **di sisi kiri**, tidak menutupi panel keranjang |
| F-TB-03 | Bar keranjang di bawah tidak muncul saat panelnya tampil |
| F-TB-04 | Di HP tata letaknya tidak berubah: keranjang tetap bar bawah, popup tetap di tengah |
| F-TB-05 | Halaman checkout menggulir sebagai **satu kesatuan** — daftar item dan rinciannya, di layar tinggi berapa pun |
| F-TB-06 | Kategori menu **terbuka sejak awal**, masih bisa dilipat |
| F-TB-07 | Banner promo dibatasi lebarnya dan mengikuti **bentuk gambarnya sendiri** |
| F-TB-08 | Nama resto di Info Resto tampil sebagai keterangan, bukan isian yang dimatikan |
| F-TU-01 | **Top Up Saldo** tersedia di Saldo & Pengeluaran untuk Owner, Finance, dan Super Admin |
| F-TU-02 | Setoran modal menambah **saldo utama**, dan tercatat di **GL Setoran Modal** — bukan sebagai pendapatan |
| F-TU-03 | Nama penyetor **wajib**; keterangan dan bukti transfer opsional |
| F-TU-04 | Kasir dapat melihat riwayat setoran, tapi **tidak dapat menambah** |
| F-TU-05 | Setoran tercatat otomatis di Jurnal GL — kredit Total Saldo, debit Setoran Modal |
| F-TU-06 | Setoran tidak dapat diubah maupun dihapus; koreksinya berupa setoran baru |
| F-PF-09 | Petty cash dan pengeluaran Merchant-POS dikelola seperti di resto |
| F-PF-10 | **Tidak ada Setor Saldo Cash** di sisi Merchant-POS |
| F-PF-11 | Super Admin dapat melihat **Jurnal GL seluruh resto klien**, dengan saringan per resto |
| F-PF-21 | Pembukuan Merchant-POS **tidak ikut** di layar itu — ia punya Jurnal GL Merchant-POS sendiri |
| F-PF-12 | Jurnal lintas resto **hanya bisa dilihat** — tidak ada satu pun cara mengubahnya |
| F-PF-14 | Total debit/kredit **tidak menghitung baris pembatalan**, sama seperti jurnal per resto |
| F-PF-15 | Baris pembatalan tetap **ditampilkan** dan ditandai, demi jejak audit |
| F-PF-16 | Saringan resto yang sedang berlaku **tertulis di layar**, berikut cara melepasnya |
| F-PF-17 | Resto yang belum punya jurnal disebut apa adanya di daftar saringan |
| F-PF-18 | Jurnal dikelompokkan **per tanggal** dan dapat dilipat; tanggal terbaru terbuka |
| F-PF-19 | GL Diskon punya **nilai bawaan** di tiap resto, tetap dapat diubah lewat Mapping GL |
| F-PF-20 | Baris jurnal diskon menyebut **nama promonya**, bukan sekadar kata "Diskon" |

> **Kenapa tidak ada Setor Saldo Cash.** Menyetor tunai ke rekening
> adalah pekerjaan resto yang uangnya menumpuk di laci kasir. Merchant-POS
> tidak punya laci — seluruh pendapatannya masuk lewat Virtual Account,
> langsung ke rekening.

> **Kenapa jurnal lintas resto hanya bisa dilihat.** Tiap baris jurnal
> ditulis pemicu yang mengikuti kejadian nyata di pesanan dan
> pengeluaran. Tangan yang bisa menulis langsung ke sana adalah tangan
> yang bisa membuat pembukuan berbeda dari yang benar-benar terjadi —
> dan itu berlaku untuk Super Admin persis seperti untuk yang lain.

### 4.19 Voucher Pelanggan

Promo Merchant-POS, bukan promo resto. Bedanya bukan sekadar siapa yang
membuat: **yang menanggung potongannya juga Merchant-POS** — dananya diambil
dari saldo Merchant-POS di muka, bukan ditagihkan belakangan.

Voucher diterbitkan **per batch**. Super Admin mengalokasikan sejumlah
uang lalu memecahnya jadi beberapa voucher bernilai sama: Rp 1.000.000
jadi 10 voucher @Rp 100.000. Satu kode untuk seluruh batch, dan sengaja
begitu — kodenya diumumkan ke banyak orang sekaligus, dan kode yang
berbeda per orang tidak bisa diumumkan.

**Empat tahap, empat perpindahan uang.** Dana voucher tidak muncul dan
hilang begitu saja; ia berpindah antar-kantong dan selalu ada di salah
satunya.

| Tahap | Yang terjadi | Jurnal GL Merchant-POS |
|---|---|---|
| 1. Terbit | Super Admin menerbitkan batch | Debit **Total Saldo** (1100040) → Kredit **Voucher** (1100073) |
| 2. Ditebus | Pelanggan memasukkan kode, kuotanya berkurang | Debit **Voucher** → Kredit **Voucher Redeem** (1100074) |
| 3. Dipakai | Vouchernya membayar pesanan di resto | Debit **Voucher Redeem** → Kredit **GL Transfer resto**, **dan uangnya benar-benar ditransfer ke resto lewat Xendit** |
| 4. Hangus | Lewat masa berlaku tanpa dipakai | Debit kantong yang menahannya → Kredit **Total Saldo** |

| ID | Kebutuhan |
|---|---|
| F-VC-01 | Super Admin menerbitkan **batch**: nominal total, dipecah jadi berapa, dan kodenya |
| F-VC-02 | Nilai tiap voucher **dihitung server** — total dibagi jumlahnya; sisa pembagian tidak diterbitkan |
| F-VC-03 | Nominalnya **exact dalam rupiah**, bukan persentase |
| F-VC-04 | Punya masa berlaku, dan dapat ditutup tanpa dihapus |
| F-VC-05 | Dapat mensyaratkan **minimal belanja** |
| F-VC-06 | Berlaku di **semua resto** atau hanya resto yang dipilih |
| F-VC-07 | Pelanggan menebus kode di halaman **Voucher Saya**; kodenya tidak peduli huruf besar-kecil |
| F-VC-08 | **Satu pelanggan satu voucher per batch** |
| F-VC-09 | Penebus melebihi kuota **ditolak** — orang ke-11 dari batch berisi 10 |
| F-VC-10 | Setiap penolakan menyebutkan **alasannya** |
| F-VC-11 | Di keranjang, pelanggan **memilih** dari voucher miliknya, bukan mengetik kode lagi |
| F-VC-12 | Potongannya tidak pernah melebihi tagihan — sisanya tidak dikembalikan |
| F-VC-13 | Empat perpindahan GL di atas tercatat otomatis, tidak ada yang dijurnal manual |
| F-VC-14 | Yang hangus dan yang tak pernah ditebus **kembali ke Total Saldo**, masing-masing sekali saja |
| F-VC-15 | Super Admin melihat sisa kuota dan **nilai yang menggantung di tangan pelanggan** |
| F-VC-16 | Nilai voucher yang dipakai **dicairkan sungguhan** ke resto lewat Xendit, bukan sekadar dijurnal |
| F-VC-17 | Pencairannya diantre dan dicoba ulang; kegagalan tidak menggagalkan pesanan pelanggan |
| F-VC-18 | Satu voucher hanya bisa dicairkan **sekali**, dijaga di sisi Xendit maupun basis data |
| F-VC-19 | Resto tanpa sub-akun Xendit tetap tercatat sebagai utang, tidak hilang |
| F-VC-20 | Batch yang terbit **langsung diumumkan** ke Kotak Masuk pelanggan tab **Umum**, berikut push ke layar kunci |
| F-VC-21 | Pengumumannya memuat **kode**, nilai per voucher, kuota, tenggat, dan minimal belanja bila ada |
| F-VC-22 | Daftar resto sasaran dapat **dicari** dan dipilih sekaligus lewat **Pilih semua** |
| F-VC-23 | Batch dapat dibekali **banner 16:9** yang ikut tampil di Kotak Masuk pelanggan |
| F-VC-24 | Batch dapat **dihapus** hanya bila sudah **ditutup** dan **belum ada penebusnya**; dananya kembali ke saldo dan pengumumannya dicabut |
| F-VC-25 | Super Admin dapat melihat **daftar penebus**: email, tanggal tebus, tanggal pakai, dan statusnya |
| F-VC-26 | Batch dapat ditandai **khusus pengguna baru** — hanya bisa ditebus yang belum pernah punya pesanan terbayar di resto mana pun |
| F-VC-27 | Penolakannya menyebut sebabnya: "Voucher ini hanya untuk pengguna baru Merchant-POS" |
| F-VC-28 | Syarat itu ikut disebut di pengumuman kotak masuknya |
| F-VC-29 | Pelanggan **tamu** tidak melihat menu Voucher Saya maupun **Pakai Voucher** di keranjang |

> **Kenapa nominalnya exact, bukan persentase.** Anggaran promo yang
> ditetapkan di muka bisa dihitung sampai habis. "Diskon 20%" pada
> tagihan sejuta rupiah adalah dua ratus ribu dari saldo Merchant-POS untuk
> satu transaksi — anggaran sebulan bisa habis oleh satu orang.

> **Kenapa dananya keluar saat terbit, bukan saat dipakai.** Voucher
> yang sudah diumumkan adalah kewajiban, apa pun yang terjadi
> setelahnya. Mencatatnya baru saat dipakai membuat saldo Merchant-POS
> terlihat lebih besar dari yang benar-benar bebas dipakai.

> **Kenapa kuotanya ditegakkan server.** Menghitungnya di aplikasi
> berarti dua orang yang menekan tombol di detik yang sama sama-sama
> lolos sebagai penebus terakhir — dan batch berisi 10 mengeluarkan 11
> voucher.

> **Kenapa satu orang satu voucher.** Kodenya satu untuk seluruh batch
> dan diumumkan terbuka. Tanpa batas ini, orang pertama yang membaca
> pengumumannya bisa menebus kesepuluhnya sekaligus.

> **Kenapa setiap penolakan menyebutkan alasannya.** "Voucher tidak
> berlaku" tanpa sebab membuat orang mencoba lagi dengan kode yang sama,
> lalu menyalahkan aplikasinya.

> **Kenapa pengumumannya terbit bersama vouchernya, bukan langkah
> terpisah.** Voucher yang diterbitkan tapi tidak diumumkan adalah uang
> yang sudah keluar dari saldo Merchant-POS untuk sesuatu yang tidak ada yang
> tahu — kuotanya habis oleh siapa pun yang kebetulan membuka layarnya,
> sisanya hangus tanpa pernah dilihat orang. Dua langkah yang harus
> diingat berurutan berarti suatu saat yang kedua terlewat.

> **Kenapa checkout jadi satu gulungan.** Daftar item dan blok
> rinciannya dulu berbagi tinggi lewat `Expanded`. Di tablet melintang,
> blok rinciannya lebih tinggi daripada layarnya sendiri — daftar
> itemnya kebagian nol dan tidak pernah dibangun, sementara tombol
> bayarnya melimpah keluar layar. Yang bisa digulir justru bagian yang
> tingginya nol.

> **Kenapa kategori terbuka sejak awal.** Menu yang bersembunyi di
> balik judul kategori adalah menu yang tidak ditemukan. Kasir yang
> melayani antrean tidak membuka satu per satu kategori untuk mencari
> satu item, dan pelanggan yang melihat tiga baris judul akan mengira
> restonya belum mengisi menunya.

> **Kenapa banner mengikuti bentuk gambarnya.** Kotak yang dipatok 16:9
> menyisakan pita kabur di sisi gambar yang bentuknya lain, dan pita itu
> yang membuatnya terlihat tidak menyatu dengan halamannya.

> **Kenapa popupnya menepi, bukan sekadar dikecilkan.** Kasir
> membacakan pesanan sambil pelanggan menyebutkannya, dan keranjang di
> kanan itu yang sedang dibaca. Popup yang menutupinya memaksa kasir
> menutup popup untuk memeriksa lalu membukanya lagi — dan yang paling
> sering hilang dari ingatan justru baris yang barusan diucapkan.

> **Kenapa panel pelanggan memakai halaman keranjang yang sama.**
> Isinya bukan sekadar daftar: ada jenis pesanan, nomor meja, voucher,
> rincian tagihan, dan aturan cara bayarnya. Menyalinnya jadi panel
> terpisah berarti dua tempat yang harus diingat berbarengan tiap kali
> aturan itu berubah, dan yang kedua selalu ketinggalan.

> **Kenapa modal punya akun sendiri.** Uangnya benar-benar masuk, tapi
> tidak dijual ke siapa pun. Mencatatnya sebagai penghasilan membuat
> laporan penjualan memuat uang yang tidak pernah dijual — dan resto
> yang menyetor modal besar akan terlihat seperti resto yang laris.

> **Kenapa kasir tidak boleh mencatatnya.** Baris yang menaikkan saldo
> tanpa uang sungguhan adalah cara paling rapi menutupi selisih laci.
> Kasir tetap boleh melihatnya, karena angkanya memengaruhi saldo yang
> dia pertanggungjawabkan.

> **Kenapa voucher disembunyikan dari tamu.** Voucher menempel pada
> akun, bukan pada perangkat, dan penebusannya ditolak server tanpa
> email. Daftar yang dibuka tamu selalu kosong — dan yang menekannya
> akan mengira vouchernya hilang, padahal ia memang belum pernah punya.

> **Kenapa "pengguna baru" dihitung se-Merchant-POS, bukan per resto.**
> Voucher ini promo Merchant-POS. Orang yang sudah rutin memesan di resto
> sebelah bukan pengguna baru hanya karena belum pernah masuk resto
> ini.

> **Kenapa pesanan batal tidak menghilangkan status pengguna baru.**
> Orang yang memesan lalu membatalkannya belum pernah benar-benar
> memakai Merchant-POS — dan menutup pintu untuknya justru menutup pintu
> bagi orang yang paling ingin dibujuk kembali.

> **Kenapa syaratnya diperiksa sebelum kuota.** Orang yang tidak berhak
> menebus tidak boleh menghabiskan jatah orang yang berhak, dan tidak
> boleh diberi tahu "sudah habis" padahal sebabnya bukan itu.

> **Kenapa batch berjalan tidak bisa dihapus.** Kodenya sudah tersebar
> lewat pengumuman. Menghapusnya berarti kode itu tiba-tiba tidak ada,
> dan yang menemukannya adalah pelanggan yang mengetik kode dari
> notifikasi lalu diberi tahu kodenya tidak ditemukan.

> **Kenapa batch yang sudah ada penebusnya tidak bisa dihapus sama
> sekali.** Klaim adalah uang yang sudah menggantung di tangan orang,
> dan barisnya dirujuk jurnal penebusan serta antrean pencairan.
> Menghapus induknya membuat catatan itu kehilangan namanya — yang
> tersisa angka di buku besar tanpa keterangan dari mana asalnya.

> **Kenapa "Pilih semua" hanya mencentang yang sedang tampil.** Kalau
> pencariannya sedang menyaring, mencentang diam-diam resto yang tidak
> terlihat berarti voucher berlaku di tempat yang tidak pernah
> dimaksud. Dan mencentang seluruh resto tidak sama dengan
> mengosongkannya: daftar yang dicentang membeku pada resto yang ada
> hari ini, yang bergabung bulan depan tidak ikut.

> **Kenapa pencairannya diantre, bukan langsung saat pesanan.** Kalau
> panggilan ke Xendit ikut di dalam transaksi yang menyimpan pesanan,
> pesanan pelanggan gagal tersimpan setiap kali Xendit lambat — dan
> pelanggan yang sudah antre di kasir menanggung akibat gangguan pihak
> ketiga. Antreannya boleh gagal dan boleh diulang; pesanannya tidak.

> **Keadaan saat rilis ini.** xenPlatform di akun Xendit Merchant-POS belum
> aktif, jadi belum ada satu pun sub-akun resto. Seluruh pencairan
> voucher tertahan sebagai antrean `pending` — tercatat penuh, belum
> dibayar. Begitu xenPlatform disetujui dan sub-akunnya terpasang,
> penjadwal yang sudah berjalan mengangkut seluruh tunggakan sekaligus
> tanpa ada yang perlu dijalankan ulang. Selama masa itu, GL resto
> sudah terkredit sejak pesanannya selesai, sehingga buku mereka
> mendahului rekeningnya; selisihnya menumpuk selama masa tunggu, dan
> yang menemukannya adalah resto yang mencocokkan mutasi.

> **Kenapa resto tanpa sub-akun tidak dilewati diam-diam.** Utangnya
> tetap tercatat sebagai antrean tertunda. Menandainya selesai karena
> tidak ada tujuan pengiriman berarti Merchant-POS berhenti berutang dengan
> cara tidak membayar.

> **Kenapa resto tetap menerima penuh.** Voucher adalah promo Merchant-POS.
> Resto menagih pelanggan sesuai harga menunya; selisihnya dibayar
> Merchant-POS lewat perpindahan tahap 3 ke GL Transfer restonya, bukan
> ditanggung restonya — dan sejak §4.19 ini, pembayarannya bukan lagi
> dilakukan di luar aplikasi.

### 4.20 Analisa Pasar (Super Admin)

Empat pertanyaan yang selama ini hanya bisa dijawab dengan membuka satu
per satu resto. Dua di antaranya sengaja tentang yang **belum** terjadi.

| ID | Kebutuhan |
|---|---|
| F-MR-01 | **Top 5 pelanggan** lintas resto, berikut jumlah pesanan dan total transaksinya |
| F-MR-02 | **Pelanggan terdaftar yang belum pernah memesan**, berikut nama dan kontaknya |
| F-MR-03 | **Top 5 resto** berdasarkan penghasilan, berikut nominalnya |
| F-MR-04 | **Resto yang belum menghasilkan**, berikut jumlah pesanan terbayarnya |
| F-MR-05 | Hanya pesanan **terbayar** yang dihitung |
| F-MR-06 | Resto platform dan resto terhapus tidak ikut dihitung |
| F-MR-07 | Seluruh perhitungannya di server; hanya Super Admin yang bisa membacanya |

> **Kenapa daftar yang diam justru yang paling berguna.** Peringkat
> teratas menyenangkan dilihat tapi tidak menyuruh melakukan apa pun.
> Pelanggan yang sudah memasang aplikasinya lalu berhenti sudah
> melewati bagian tersulit dan cuma belum punya alasan untuk kembali —
> dan resto yang punya pesanan tapi nol rupiah adalah resto yang
> mencoba memakainya dan gagal menyelesaikan.

> **Kenapa hanya pesanan terbayar yang dihitung.** Pesanan batal pernah
> ada di layar kasir, tapi tidak pernah jadi uang. Memasukkannya membuat
> resto yang banyak pesanan batal terlihat lebih besar daripada resto
> yang benar-benar berjualan.

> **Kenapa peringkat pelanggan hanya menghitung akun terdaftar.**
> Pesanan kasir memakai nama tamu yang diketik di tempat, dan dua tamu
> bernama "Budi" di dua resto berbeda bukan satu orang. Memeringkatnya
> sebagai satu orang bukan angka yang kasar — itu angka yang salah.

> **Kenapa perhitungannya di server.** Mengunduh seluruh pesanan
> seluruh resto ke sebuah HP berarti batas 1.000 baris PostgREST
> memotongnya diam-diam, dan yang tampil adalah peringkat yang salah
> tanpa satu pun tanda ada yang hilang.

---

### 4.21 Nomor Pesanan Harian

| ID | Kebutuhan |
|---|---|
| F-NO-01 | Tiap pesanan menerima **nomor urut harian** milik merchantnya sendiri |
| F-NO-02 | Nomornya dimulai dari **1 tiap hari**, mengikuti tanggal WIB |
| F-NO-03 | Nomor diberikan **saat pesanan dibuat**, apa pun status bayarnya — termasuk yang masih menunggu QRIS |
| F-NO-04 | Dua merchant berbeda punya deretan nomornya masing-masing |
| F-NO-05 | Nomornya tercetak di struk dan tampil di dapur, kasir, dan riwayat pelanggan |
| F-NO-06 | Pesanan yang terbit sebelum penomoran ini dipasang tetap tanpa nomor |

> **Kenapa nomornya diberikan sebelum dibayar.** Yang berdiri di depan
> kasir sambil menunggu QRIS-nya lunas tetap perlu dipanggil kalau
> pesanannya keburu jadi. Menunggu pembayaran berarti pesanan yang sudah
> masuk dapur tidak punya nama untuk dipanggil ke ruangan.

> **Kenapa bukan UUID pesanannya.** UUID cukup untuk mesin, tidak untuk
> orang: kasir tidak bisa memanggil "pesanan 8f3a1c2e", dan pelanggan
> tidak bisa mengingatnya sampai makanannya datang.

---

### 4.22 Layar Pelanggan

Perangkat kedua yang menghadap pelanggan di meja kasir.

| ID | Kebutuhan |
|---|---|
| F-LP-01 | Perangkat kedua menampilkan nama merchant, logonya, QR pembayaran, dan nominal yang harus dibayar |
| F-LP-02 | Isinya berubah **seketika** mengikuti apa yang sedang dikerjakan kasir |
| F-LP-03 | Merchant tanpa logo memakai logo Merchant-POS |
| F-LP-04 | Ada tulisan **powered by Merchant-POS** di bawahnya |
| F-LP-05 | Saat tidak ada transaksi, layarnya kembali ke keadaan menunggu |

> **Kenapa yang dikirim bukan penunjuk ke pesanannya.** Baris pesanan
> kasir baru dibuat setelah pembayarannya lunas. Layar yang menunggu
> nomor pesanan tidak akan pernah menampilkan QR yang justru dibutuhkan
> untuk membayarnya.

---

### 4.23 Info Merchant: Fasilitas & Jam Buka

| ID | Kebutuhan |
|---|---|
| F-IM-01 | Merchant mencantumkan **fasilitasnya** (AC, Smoking Area, Live Music, dan lainnya) |
| F-IM-02 | Fasilitas tampil di daftar pilih merchant, memenuhi lebar kartunya, sisanya diringkas jadi **"+N"** |
| F-IM-03 | Merchant mencantumkan **jam buka per hari**; hari yang tidak diisi berarti tutup |
| F-IM-04 | Merchant yang sedang tutup **ditandai**, diurutkan ke bawah, dan **tidak bisa dipilih** |
| F-IM-05 | Merchant yang tutup tidak muncul di saran lokasi terdekat |
| F-IM-06 | Halaman Info Merchant memuat alamat, tautan peta, kontak, fasilitas, jam buka, dan penilaian |

> **Kenapa hari tanpa jam berarti tutup, bukan buka 24 jam.**
> Menyimpan "00:00–00:00" untuk hari libur adalah kalimat yang bisa
> dibaca dua arah, dan yang membacanya salah akan datang ke tempat yang
> tutup.

---

### 4.24 Penilaian Merchant

| ID | Kebutuhan |
|---|---|
| F-PM-01 | Pelanggan **yang punya akun** dapat menilai merchant: bintang, komentar, dan sampai tiga foto |
| F-PM-02 | Nama penilainya ditampilkan, disalin saat menilai |
| F-PM-03 | Satu orang satu penilaian per merchant; yang berubah pikiran **mengubah** tulisannya |
| F-PM-04 | Rata-rata bintang dan jumlah penilai tampil di daftar pilih merchant |
| F-PM-05 | Foto ulasan dapat dibuka selayar penuh |
| F-PM-06 | Seluruh peran pegawai merchant dapat membacanya, kecuali Merchant-POS Admin |
| F-PM-07 | Yang menilai tempatnya sendiri tidak ditawari tombol menilai |
| F-PM-08 | 1–3 jam setelah pembayaran, pelanggan menerima ajakan menilai lewat notifikasi |
| F-PM-09 | Ajakan itu, saat diketuk, langsung membuka formulir penilaian merchant tersebut |

> **Kenapa satu orang satu suara di sini, tapi tidak di penilaian menu.**
> Yang dinilai di sini tempatnya — dan tempat tidak berubah tiap
> kunjungan. Masakan berubah.

> **Kenapa Merchant-POS Admin tidak diberi akses.** Tempatnya bukan miliknya,
> dan daftar keluhan yang tidak bisa dia tindaklanjuti cuma menumpuk.

---

### 4.25 Label & Penilaian Menu

| ID | Kebutuhan |
|---|---|
| F-LM-01 | Merchant memberi label pada menunya lewat Kelola Produk: **BARU**, **TERLARIS**, **REKOMENDASI** |
| F-LM-02 | Label **DISKON** muncul sendiri selama promonya berjalan dan hilang sendiri saat habis — tidak dicentang siapa pun |
| F-LM-03 | Label tampil di kartu menu pada seluruh layar pesan: pelanggan berakun, tamu, kasir, admin, dan owner |
| F-LM-04 | Paling banyak dua label tampil di satu kartu, diurutkan menurut kepentingannya |
| F-LM-05 | Pelanggan berakun menilai **tiap menu yang pernah dipesannya** lewat riwayat pesanannya |
| F-LM-06 | Penilaian menempel pada **pesanannya**, bukan pada menunya — menu yang dipesan lagi dinilai lagi dari kosong |
| F-LM-07 | Satu pesanan satu penilaian per menu; yang berubah pikiran mengubah penilaian pesanan itu |
| F-LM-08 | Ajakan menilai **hilang** setelah seluruh menu di pesanan itu dinilai |
| F-LM-09 | Menu yang sudah dinilai tetap tampil di daftarnya dengan tanda, dan masih bisa diubah |
| F-LM-10 | Rata-rata bintang dan **angka terjual** tampil di kartu menu, di seluruh layar pesan |
| F-LM-11 | Angka terjual dihitung dari pesanan **lunas** saja |
| F-LM-12 | Menu yang belum pernah dinilai tidak menampilkan "0,0"; yang belum pernah terjual tidak menampilkan "0 terjual" |
| F-LM-13 | Ulasan menu dapat dibaca di Info Merchant, dikelompokkan per menu, diurutkan dari yang paling banyak dibicarakan |
| F-LM-14 | Hanya yang benar-benar memesan menu itu, pada pesanan lunas miliknya, yang boleh menilainya |

> **Kenapa penilaian menempel pada pesanan.** Semula satu orang hanya
> boleh menilai sebuah menu satu kali. Terdengar benar — sampai orang
> yang sama memesan nasi goreng untuk kedua kalinya dan menemukan
> bintang lima dari bulan lalu sudah terisi. Yang mau bilang "kali ini
> keasinan" tidak punya tempat mengatakannya.

> **Akibatnya, dan itu disengaja.** Rata-rata bintang sebuah menu tidak
> lagi "satu orang satu suara". Yang memesan sepuluh kali menyumbang
> sepuluh penilaian — masing-masing menilai masakan hari itu.

> **Kenapa angka nol disembunyikan.** "★ 0,0" terbaca sebagai penilaian
> terburuk, padahal artinya belum ada yang menilai. "0 terjual" adalah
> kalimat yang merugikan menu baru tanpa memberi tahu apa pun.

> **Kenapa hanya pesanan lunas yang dihitung terjual.** Kalau tidak,
> angka yang dipajang ke pelanggan bisa dinaikkan dengan memesan lalu
> tidak membayar.

---

### 4.26 Shift Kasir

| ID | Kebutuhan |
|---|---|
| F-SH-01 | Kasir **membuka shift** dengan mencatat modal awal laci |
| F-SH-02 | Satu merchant hanya boleh punya **satu shift terbuka** pada satu waktu |
| F-SH-03 | Menutup shift dilakukan dengan **menghitung uang di laci** dan menuliskan jumlahnya |
| F-SH-04 | Angka yang seharusnya ada **tidak ditampilkan sebelum** jumlah hitungannya ditulis |
| F-SH-05 | Sesudah ditulis, selisihnya ditunjukkan lebih dulu, dan nominalnya **masih bisa diperbaiki** sebelum disimpan |
| F-SH-06 | Yang seharusnya ada = modal awal + penjualan tunai lunas − setoran keluar laci − penarikan petty cash tunai, sepanjang rentang shiftnya |
| F-SH-07 | Setoran dan petty cash yang **ditolak** tidak dikurangkan — uangnya kembali ke laci |
| F-SH-08 | Selisih tersimpan pada shiftnya, berikut catatan opsional |
| F-SH-09 | Yang membuka shift boleh menutupnya sendiri; menutup shift orang lain hanya untuk Owner, Finance, dan Admin |
| F-SH-10 | Shift yang sudah ditutup tidak bisa ditutup dua kali |
| F-SH-11 | Riwayat shift dapat dibaca seluruh pegawai merchant, berikut selisih tiap shift |
| F-SH-12 | Menunya ada di halaman utama Kasir, Admin, Owner, dan Finance |
| F-SH-13 | Modal awal yang ditulis saat membuka shift dibandingkan dengan yang ditinggalkan penutupan terakhir |
| F-SH-14 | Kalau tidak cocok, selisihnya ditunjukkan dan nominalnya masih bisa diperbaiki sebelum shift dibuka |
| F-SH-15 | Merchant yang belum pernah menutup shift tidak punya pembanding — modal awal apa pun diterima |
| F-SH-16 | Gagal mengambil pembandingnya tidak menahan shift dibuka |

> **Kenapa angkanya tidak ditampilkan sebelum dihitung.** Kasir yang
> tahu lebih dulu "seharusnya Rp 1.240.000" akan menghitung sampai ketemu
> angka itu, bukan menghitung apa adanya. Selisih yang tidak pernah
> muncul bukan berarti tidak ada — ia cuma pindah ke bulan depan, dan ke
> orang yang tidak melakukannya.

> **Kenapa tetap boleh diperbaiki sesudahnya.** Salah ketik satu angka
> nol akan tercatat selamanya sebagai selisih jutaan rupiah atas nama
> orang yang tidak melakukan apa-apa. Menutup shift tidak bisa
> dibatalkan, jadi kesempatan memperbaikinya harus ada sebelum
> disimpan — dan pada titik itu hitungannya sudah terlanjur ditulis,
> jadi tidak ada lagi yang bisa dianggarkan.

> **Kenapa satu shift terbuka per merchant, bukan per kasir.** Yang
> dihitung isi laci, dan lacinya cuma ada satu. Dua shift terbuka
> bersamaan akan menghitung penjualan tunai yang sama dua kali, lalu
> keduanya sama-sama terlihat kelebihan uang.

> **Kenapa pembandingnya uang yang DIHITUNG, bukan yang seharusnya.**
> Kalau shift kemarin kurang Rp 10.000, yang betul-betul tertinggal di
> laci memang jumlah yang kurang itu — dan kekurangannya sudah punya
> tagihannya sendiri atas nama kasir kemarin. Memakai angka "seharusnya"
> berarti menagihkan kekurangan yang sama dua kali, kepada dua orang
> yang berbeda.

---

### 4.27 Selisih Kasir

| ID | Kebutuhan |
|---|---|
| F-SK-01 | Selisih saat shift ditutup masuk pembukuan lewat **GL Selisih Kasir** |
| F-SK-02 | Selisih **kurang** dijurnal debit; selisih **lebih** dijurnal credit |
| F-SK-03 | Selisih kurang jadi **tagihan terbuka** atas nama kasir yang memegang laci |
| F-SK-04 | Selisih lebih **tidak** jadi tagihan |
| F-SK-05 | Tagihan dilunasi lewat **Bayar Selisih** — kasir menyerahkan tunai, uangnya kembali ke laci |
| F-SK-06 | Yang boleh mencatat pelunasan hanya **Owner, Finance, dan Admin** |
| F-SK-07 | Kasir **melihat** tagihan atas namanya sendiri, tanpa tombol |
| F-SK-08 | Pelunasan dijurnal credit, sehingga akunnya kembali nol untuk tagihan itu |
| F-SK-09 | **Saldo Cash dikurangi** selisih yang belum dilunasi |
| F-SK-10 | Yang sudah dilunasi tidak dikurangkan lagi |
| F-SK-11 | Shift yang selisihnya lunas berlencana **Pas**, berikut rincian nominal, selisih, dan siapa yang membayar |
| F-SK-12 | GL Selisih Kasir bisa dipetakan sendiri di Mapping GL Account |
| F-SK-13 | Satu shift paling banyak melahirkan satu tagihan |
| F-SK-14 | Tagihan yang sudah lunas tidak bisa dilunasi dua kali |

> **Kenapa selisih lebih tidak ditagih.** Tidak ada yang bisa ditagih
> dari uang yang justru berlebih. Yang perlu dilakukan menelusuri
> penjualan yang belum diinput, dan itu pekerjaan Finance — bukan utang
> kasir.

> **Kenapa Saldo Cash ikut dikurangi.** Tanpa itu, layar Saldo &
> Pengeluaran tetap menyebut angka yang lebih besar daripada uang yang
> bisa dihitung tangan — persis penyakit yang mau disembuhkan fitur ini.

> **Kenapa kasir tidak boleh melunasi sendiri.** Angka yang menilai
> seseorang tidak boleh bisa dihapus oleh orang itu juga. Tapi ia tetap
> melihatnya: tagihan yang hanya bisa dilihat atasannya adalah tuduhan
> yang tidak bisa dijawab.

> **Kenapa angkanya tidak ikut dihapus saat lunas.** Riwayat yang
> menyembunyikan bahwa pernah ada selisih tidak bisa dipakai menelusuri
> apa pun nanti — dan yang paling butuh menelusurinya justru orang yang
> belum ada di sana waktu kejadiannya.

---

### 4.28 Laporan Penjualan Merchant

Hanya **Owner dan Admin**. Kasir dan Chef tidak: yang mereka butuhkan
pesanan yang sedang berjalan, dan omzet merchant bukan angka yang perlu
beredar di antara semua orang yang memegang HP.

| ID | Kebutuhan |
|---|---|
| F-RP-01 | Rentang tanggal bisa dipilih; bawaannya 30 hari terakhir |
| F-RP-02 | **Ringkasan**: omzet, jumlah pesanan, rata-rata transaksi, porsi terjual |
| F-RP-03 | **Menu terlaris** berikut porsi dan omzetnya |
| F-RP-04 | **Menu tidak laku** — nol porsi sepanjang rentang itu |
| F-RP-05 | **Jam ramai** per jam WIB, berikut jam tersibuknya |
| F-RP-06 | Hanya pesanan **lunas** yang dihitung |
| F-RP-07 | Seluruhnya dihitung server; yang tidak berhak menerima daftar kosong, bukan pesan galat |
| F-RP-08 | Nama menu diambil dari baris pesanannya, sehingga menu yang sudah dihapus tetap terhitung |

> **Kenapa "menu tidak laku" yang paling berguna.** Peringkat teratas
> menyenangkan dilihat tapi tidak menyuruh melakukan apa pun. Menu yang
> diam sebulan adalah bahan yang dibeli, tempat di daftar, dan waktu
> pelanggan yang terpakai untuk melewatinya.

> **Kenapa bawaannya 30 hari, bukan bulan berjalan.** Tanggal 2 bulan
> depan, "bulan ini" berisi dua hari — dan laporan yang isinya dua hari
> tidak memberi tahu apa pun tentang menu mana yang laku.

---

### 4.29 Merchant-POS Support

| ID | Kebutuhan |
|---|---|
| F-SP-01 | Tombol mengambang **Merchant-POS Support** di beranda pelanggan dan pegawai merchant |
| F-SP-02 | Tiga pilihan: **Buat Pengaduan Baru**, **Chat Merchant-POS Admin**, **Lihat Status Pengaduan** |
| F-SP-03 | Pengaduan berisi judul, cerita, dan satu foto opsional |
| F-SP-04 | Chat bebas tidak meminta judul, dan memakai percakapan yang masih terbuka kalau ada |
| F-SP-05 | Status tiket: **Open**, **On Progress**, **Confirm Customer**, **Close** |
| F-SP-06 | Hanya Merchant-POS Admin yang mengubah status; pelapor hanya boleh **menutup** |
| F-SP-07 | Tiap perubahan status ikut jadi pesan di percakapannya |
| F-SP-08 | Tiket **Confirm Customer** yang didiamkan 24 jam ditutup sendiri |
| F-SP-09 | Penutupan otomatis hanya berlaku kalau pesan terakhirnya dari admin |
| F-SP-10 | Balasan pelapor mengembalikan status ke **On Progress** |
| F-SP-11 | Tiket tertutup tidak bisa dibalas, tapi percakapannya tetap terbaca |
| F-SP-12 | Menu **Customer Service** untuk Merchant-POS Admin, berbentuk daftar percakapan |
| F-SP-13 | Daftarnya bisa dicari, dan menyembunyikan yang sudah ditutup secara bawaan |
| F-SP-14 | Penanda belum dibaca di tombol mengambang dan di beranda Merchant-POS Admin |
| F-SP-15 | Notifikasi saat pengaduan masuk, dibalas, atau statusnya bergerak |
| F-SP-16 | Notifikasi diketuk membuka percakapannya, bukan sekadar aplikasinya |
| F-SP-17 | Balasan admin menyebut **nama penjawabnya** — "Merchant-POS Admin - Gamal" |
| F-SP-18 | Merchant-POS Admin melihat pelapor ini **pelanggan** atau **merchant mana** |
| F-SP-19 | Pelapor hanya melihat tiketnya sendiri, bukan tiket rekan sekantornya |
| F-SP-20 | Tidak ditawarkan kepada yang belum masuk |

> **Kenapa tiket, bukan WhatsApp.** Gulungan obrolan tidak bisa menjawab
> tiga hal: keluhan ini sudah selesai atau belum, siapa yang sedang
> menunggu siapa, dan sudah berapa lama.

> **Kenapa penutupan otomatis memeriksa siapa yang bicara terakhir.**
> Tiket yang pesan terakhirnya dari pelapor berarti bolanya ada di
> Merchant-POS. Menutupnya karena "tidak ada jawaban" akan menghukum orang
> yang justru sudah menjawab.

> **Kenapa pelapor tidak melihat tiket rekannya.** Keluhan sering
> berisi hal yang tidak ingin dibaca seruangan — termasuk keluhan
> tentang orang di ruangan itu.

> **Kenapa nama penjawabnya disebut.** Yang mengadu berhak tahu sedang
> bicara dengan siapa, dan yang menjawab jadi ikut bertanggung jawab
> atas kalimatnya.

---

## 5. Aturan Bisnis

### 5.1 Perhitungan tagihan

```
service = harga bersih × tarif service
ppn     = (harga bersih + service) × tarif PPN
total   = harga bersih + service + ppn
```

| Aturan | Keterangan |
|---|---|
| PPN dikenakan atas harga bersih **+ service** | Biaya service sendiri kena PPN. Menghitungnya dari harga bersih saja membuat laporan kurang beberapa ratus rupiah tiap nota |
| Harga di menu = harga bersih + PPN | Biaya service tidak dimasukkan, karena itu biaya per-nota yang hanya berlaku Dine In |
| Take Away | Tidak kena service, tetap kena PPN. Totalnya **sama persis** dengan harga yang tertera di menu |
| Produk bebas PPN | Ditandai per produk |

**Contoh:** harga bersih 55.000, service 5%, PPN 11% → service 2.750,
PPN 6.353, **total 64.103**. Ketiga komponennya selalu berjumlah persis
sama dengan totalnya.

### 5.2 Pengakuan uang

| Kejadian | Akibatnya |
|---|---|
| Pesanan lunas | Tercatat sebagai pemasukan pada GL sesuai cara bayarnya, terpisah dari PPN dan biaya service |
| Setoran diajukan | Uangnya **keluar dari Saldo Cash** dan mengendap di akun perantara |
| Setoran dikonfirmasi | Berpindah dari perantara ke saldo rekening resto |
| Setoran ditolak | **Kembali** ke Saldo Cash |
| Top up petty diajukan | Keluar dari sumbernya, mengendap di perantara petty cash |
| Top up disetujui / ditolak | Masuk ke petty cash / kembali ke sumbernya |
| Pengeluaran | Mengurangi petty cash |
| Diskon diberikan | Didebit ke GL Diskon sebagai **pengurang pendapatan**, bukan sebagai biaya — diskon bukan uang yang keluar, melainkan uang yang tidak pernah masuk |

Setiap perpindahan uang menghasilkan jurnal yang **seimbang**, dan
pembatalan selalu mengembalikan dananya ke asal — tidak boleh ada yang
tersangkut di akun perantara.

**Dua tahap, dua pasang baris.** Setoran dan top up petty cash tidak
berpindah sekali, tapi dua kali: dari sumbernya ke akun perantara saat
diajukan, lalu dari perantara ke tujuannya saat disetujui. Karena itu
total debit dan kreditnya **dua kali lipat** nilai transaksinya,
sementara saldo perantaranya kembali nol. Layar rincian jurnal
menyebutkan hal ini supaya angkanya tidak dikira salah hitung.

### 5.3 Isi Riwayat Kasir

Yang menentukan bukan siapa yang mengetik pesanannya, melainkan **apakah
uangnya diterima di meja kasir**.

| Pesanan | Masuk Riwayat Kasir? |
|---|:--:|
| Diinput Kasir/Admin/Owner, metode apa pun | ✔ |
| Pelanggan, dilunasi di kasir — **tunai, QRIS, maupun transfer** | ✔ |
| Pelanggan, belum dibayar | ✘ — masih di Pending Payment |
| Pelanggan, QRIS dibayar sendiri lewat HP | ✘ — tidak pernah lewat meja kasir |
| Pelanggan, dibatalkan atau hangus | ✘ — uangnya tidak pernah berpindah |

Penandanya adalah catatan **siapa yang menerima pembayarannya**, bukan
cara bayarnya. Sebelumnya cara bayar yang dipakai menebak, dan tebakan
itu runtuh begitu cara bayar boleh diganti saat pelunasan: uang masuk
laci, transaksinya lenyap dari riwayat.

### 5.4 Ketersediaan produk

| Aturan | Keterangan |
|---|---|
| Stok **tidak** menentukan ketersediaan | Angka stok jadi catatan biasa, boleh diisi boleh tidak |
| Yang menentukan cuma penanda **Out of Stock** | Dinyatakan sengaja oleh orang yang tahu keadaan dapurnya |
| Produk habis tetap tampil | Dengan tanda dan tidak bisa dipesan — pelanggan berhak tahu menunya ada tapi sedang kosong |
| Diperiksa ulang sebelum membayar | Keranjang bisa terisi berjam-jam sebelum dibayar |
| Pemeriksaan yang gagal karena jaringan **tidak** menahan pesanan | Menahan pesanan yang mungkin baik-baik saja merugikan lebih banyak orang |

### 5.5 Masa berlaku promo

| Aturan | Keterangan |
|---|---|
| Tanggal mulai tidak boleh mundur | Transaksi kemarin sudah dijurnal tanpa diskonnya |
| Tanggal berakhir minimal besok | Promo yang berakhir hari ini juga tidak pernah sempat dipakai |
| Hari terakhir berlaku **penuh** | "Sampai 31 Agustus" berarti sampai tutup toko tanggal 31 |
| Batasnya ditegakkan di kalendernya | Tanggal yang tidak sah tidak bisa dipilih, bukan ditolak setelah dipilih |

### 5.6 Perilaku saat luring

Resto tidak berhenti berjualan ketika internetnya putus, jadi
aplikasinya juga tidak boleh. Yang dijanjikan bukan "semuanya tetap
jalan" — itu tidak mungkin untuk pembayaran QRIS — melainkan batas yang
jelas antara yang jalan dan yang menunggu.

| Bagian | Saat luring |
|---|---|
| Katalog menu, kategori, level | Tetap tampil — disimpan di perangkat |
| Input pesanan & pembayaran tunai | Tetap jalan, tersimpan lokal, dikirim saat sambungan kembali |
| Pembayaran QRIS | **Tidak bisa** — QR-nya dibangkitkan penyedia pembayaran |
| Kotak masuk | Menampilkan yang sudah pernah dimuat |
| Kotak masuk pelanggan | Jatuh ke resto yang sedang dibuka saja |
| Riwayat & laporan | Angka terakhir yang sempat dimuat |

---

## 6. Aturan Validasi Isian

Berlaku sama di seluruh layar. Tiap aturan dipasang **dua lapis**: isian
menolak karakter terlarang saat diketik, dan diperiksa lagi saat
disimpan.

> **Wajib diuji dengan tempel (paste), bukan hanya diketik.** Lapis
> kedua ada justru untuk isian yang masuk lewat tempel atau papan ketik
> yang mengabaikan pembatasnya.

| Jenis | Maks | Diizinkan | Aturan tambahan |
|---|:--:|---|---|
| **Nama** (orang, resto, produk, bank) | **40** | Huruf, angka, spasi, `. , ' ( ) & / -` | Wajib, kecuali dinyatakan opsional |
| **Nomor HP** | **15** | Angka saja | Minimal 8 angka; tanda `+` tidak diizinkan |
| **Email** | **25** | Huruf, angka, `@ . _ -` | **Wajib `@gmail.com`** |
| **NIP** | **15** | Angka saja | Opsional |
| **Nomor rekening** | **20** | Angka saja | — |
| **Tarif persen** | **6** | Angka, `.` `,` | Rentang 0–100; koma dibaca desimal; kosong berarti 0 |
| **Harga & stok** | — | Angka | Wajib |
| **Awalan QR meja** | **6** | Bebas | Opsional |
| **Jumlah meja** | **3** digit | Angka | 1 sampai 100 |
| **Nama diskon** | **40** | Sama seperti nama | Wajib |
| **Persen diskon** | 3 | Angka | 1 sampai 100 |
| **Nominal diskon** | — | Angka | Harus lebih dari 0, tidak pernah melebihi tagihan |
| **Minimum belanja** | — | Angka | Harus lebih dari 0 |
| **Nama kelompok level** | **40** | Sama seperti nama | Tidak boleh kembar dalam satu resto |
| **Pilihan level** | — | Bebas | Minimal 2, tidak boleh kembar |
| **Stok** | — | Angka | **Opsional** — kosong berarti tidak dihitung |

### 6.1 Alasan aturan yang sering dikira bug

| Aturan | Alasan |
|---|---|
| Email wajib Gmail | Satu-satunya cara masuk adalah Login dengan Google. Alamat lain akan tersimpan rapi lalu gagal login tanpa penjelasan apa pun |
| Nomor HP tanpa `+` | Nomor Indonesia ditulis mulai `0` atau `62`. Mengizinkan `+` membuat nomor yang sama tersimpan dalam dua bentuk yang tidak bisa dicocokkan |
| Tarif menolak `11.` | Bentuk setengah jadi itu lolos begitu saja kalau hanya diperiksa sebagai angka |
| Emoji ditolak pada nama | Nama dipakai di struk dan PDF, yang fontnya tidak memuat emoji |
| Kelompok level minimal 2 pilihan | Satu pilihan bukan pilihan — cuma dropdown yang jawabannya sudah ditentukan, menambah satu ketukan di tiap pesanan tanpa menghasilkan keterangan apa pun |
| Tanggal mulai promo tidak bisa mundur | Pembukuan yang sudah ditutup tidak lagi cocok dengan daftar promonya |
| Stok boleh kosong | Nasi goreng tidak punya "sisa 7 porsi" — yang ada cuma "masih ada" atau "bahannya habis" |

### 6.2 Pesan galat

Pesan galat selalu tampil **di depan dialog isian**, tidak pernah
tertutup di belakangnya.

---

## 7. Daftar Status

### 7.1 Pembayaran pesanan

| Status | Arti |
|---|---|
| **Menunggu Pembayaran** | Pesanan sudah masuk, uangnya belum |
| **Sudah Dibayar** | Lunas dan tercatat sebagai pemasukan |
| **Dibatalkan** | Ditarik sendiri oleh pelanggannya sebelum dibayar |
| **Hangus, tidak dibayar** | Tidak dilunasi sampai 30 menit lewat; dibatalkan sistem, bukan orang |

### 7.2 Dapur

| Status | Dipicu oleh |
|---|---|
| **Menunggu Bayar** | Pesanan mandiri yang uangnya belum diterima |
| **Baru** | Pesanan masuk dan sudah dibayar |
| **Diproses** | Dapur mencentang sebagian menu |
| **Selesai** | Seluruh menu tercentang |

### 7.3 Setoran & top up

| Status | Setoran | Petty cash |
|---|---|---|
| Menunggu | Pending | Pending |
| Disetujui | **Completed** | **Completed** |
| Ditolak | Ditolak | Ditolak |

> Pada setoran, Finance tidak "menyetujui permintaan" — dia memastikan
> uangnya benar-benar masuk rekening. Karena itu istilahnya
> **konfirmasi**, dan hasilnya **Completed**.

---

## 8. Notifikasi

### 8.1 Siapa dikabari, kapan

| Peran | Dikabari saat |
|---|---|
| Pelanggan | Pesanannya mulai dimasak, dan saat siap |
| Dapur | Ada pesanan baru masuk |
| Kasir | Pesanan yang dia input sendiri mulai dimasak / siap |
| Kasir, Admin, Owner | Ada pesanan menunggu dibayar di kasir |
| Finance, Owner | Ada setoran atau top up yang menunggu keputusan |
| Kasir & Admin | Pengajuannya sendiri sudah diputus, berikut alasannya bila ditolak |
| Seluruh pengguna | Ada pengumuman baru — dari Super Admin maupun dari restonya |
| Sesuai sasaran | Pengumuman resto hanya membunyikan HP kelompok yang dituju: karyawan saja, pelanggan saja, atau keduanya |

**Tidak ada gema:** yang memutuskan tidak dikabari soal keputusannya
sendiri, dan yang membuat pesanan tidak dikabari soal pesanan yang baru
saja dia buat.

### 8.2 Sifatnya

| Sifat | Keterangan |
|---|---|
| Tetap sampai saat aplikasi tertutup | Notifikasi dikirim dari server, bukan dibangkitkan aplikasi yang sedang berjalan |
| Lima jenis terpisah | Status Pesanan, Pesanan Baru, Hasil Pengajuan, Pengumuman, Unduhan Pembaruan — masing-masing bisa dibisukan sendiri lewat Setelan Android |
| Pengumuman tetap berbunyi saat aplikasi terbuka | Berbeda dari kabar pesanan, yang sudah dibunyikan aliran langsungnya |
| Unduhan tidak berbunyi | Baris kemajuannya menemani, bukan memanggil |
| Nada dering khas | Nada Merchant-POS, bukan nada bawaan |
| Tidak menumpuk | Kabar baru untuk kejadian yang sama menimpa kabar lama — kecuali pengumuman, yang tiap kabarnya berdiri sendiri |
| Tidak membanjir saat dibuka | Membuka aplikasi setelah lama tertutup tidak memunculkan notifikasi beruntun untuk kejadian lama |

---

## 9. Kriteria Penerimaan

Rilis dianggap layak bila seluruh butir berikut terpenuhi.

| # | Kriteria |
|---|---|
| A-01 | Pelanggan tamu dapat menyelesaikan pesanan dari scan QR sampai pembayaran tanpa membuat akun |
| A-02 | Pesanan tunai dari HP pelanggan muncul di Pending Payment, dan setelah dilunasi berpindah ke Riwayat Kasir — tidak ada di keduanya, tidak hilang dari keduanya |
| A-03 | Total harian di Riwayat Kasir cocok dengan isi laci saat tutup shift |
| A-04 | Komponen tagihan (harga bersih + service + PPN) selalu berjumlah persis sama dengan totalnya |
| A-05 | Setoran atau top up yang ditolak mengembalikan dananya ke asal, tidak tersangkut di akun perantara |
| A-06 | Kasir tidak dapat menyetujui pengajuannya sendiri |
| A-07 | Pengajuan yang menunggu terlihat sebagai penanda merah tanpa perlu membuka layarnya |
| A-08 | Notifikasi sampai ke HP dalam keadaan aplikasi tidak terbuka |
| A-09 | Setiap kolom isian menolak masukan tidak sah, baik diketik maupun ditempel |
| A-10 | Data antar cabang tidak saling bocor saat akun berpindah resto |
| A-11 | Tombol aksi tidak pernah menutupi baris terakhir daftar mana pun |
| A-12 | Banner promo tampil utuh tanpa terpotong, dan ikut tergulir bersama menunya |
| A-13 | Pesanan yang dilunasi di kasir masuk Riwayat Kasir **apa pun cara bayar** yang dipilih saat pelunasan |
| A-14 | Diskon yang sama berlaku untuk transaksi kasir maupun pesanan mandiri pelanggan |
| A-15 | Hanya satu diskon dipakai per transaksi, dan potongannya tidak pernah melebihi tagihannya |
| A-16 | Pesanan yang belum dibayar tidak dapat dimasak dari layar dapur |
| A-17 | Pesanan yang dibatalkan atau hangus tidak muncul di dapur, Pending Payment, maupun Riwayat Kasir |
| A-18 | Seluruh layar terbaca pada mode terang maupun gelap — tidak ada tulisan yang hilang di latarnya |
| A-19 | Resto baru langsung punya bagan akun GL dan tarif pajak, sehingga transaksi hari pertamanya terjurnal |
| A-20 | Pengumuman internal resto tidak pernah sampai ke pelanggan |

---

## 10. Batasan yang Diketahui

Hal-hal berikut **disengaja atau sudah diketahui**, jadi tidak perlu
dilaporkan sebagai temuan.

| Batasan | Dampak |
|---|---|
| **QRIS simulasi untuk resto tanpa sub-akun** | Resto yang belum punya sub-akun penyedia tetap memakai QR simulasi berikut konfirmasi manual |
| **Bahasa Inggris belum lengkap** | Mekanismenya ada, terjemahannya baru sebagian, jadi pemilih bahasanya dimatikan |
| **Popup pemasang tidak menginterupsi sendiri** | Android melarang aplikasi di latar membuka layar sendiri. Selesai mengunduh memunculkan notifikasi yang harus diketuk |
| **Unduhan besar bisa terhenti** | Kalau sistem kehabisan memori saat aplikasi di latar, unduhannya ikut berhenti |
| **Ubin peta dari OpenStreetMap** | Gratis dan tanpa kunci API; kerapatan petanya di bawah Google Maps |
| **Notifikasi tertahan pada sebagian HP** | Di Xiaomi, Oppo, Vivo, Realme, dan sebagian Samsung, menggeser aplikasi dari daftar aplikasi terkini sama dengan menghentikannya paksa — notifikasi baru masuk saat aplikasi dibuka lagi. Perlu mengaktifkan *Autostart* dan menyetel baterainya *Tidak dibatasi* |
| **Penanda merah bukan waktu-nyata** | Angkanya dimuat saat layar dibuka dan saat kembali dari layarnya, bukan dipantau terus-menerus |
| **Penanda di kasir menghitung se-resto** | Termasuk pengajuan rekan seshift, bukan hanya miliknya sendiri |
| **Maksimal 100 QR sekali buat** | Batas yang disengaja |
| **Struk & QR butuh internet saat dibuat** | Dalam keadaan benar-benar luring, hurufnya jatuh ke font bawaan; bentuknya tetap benar |
| **Titik lokasi memakai layanan gratis** | Pengambilan lokasi beruntun dalam waktu singkat bisa ditolak sementara |
| **Selisih lebih tidak ditagihkan** | Dijurnal, tapi berhenti di situ. Yang perlu dilakukan menelusuri penjualan yang belum diinput — bukan menagih kasir |
| **Chat bebas dibedakan lewat judulnya** | Bukan lewat kolom tersendiri. Percakapan bebas yang judulnya diubah manual di basis data akan berhenti dikenali sebagai chat bebas |
| **Notifikasi support tidak mengikuti peran perangkat** | Disasar lewat email Merchant-POS Admin. HP yang sama dipakai sebagai pelanggan tetap menerima kabar pengaduan — orangnya memang sama |
| **Rata-rata bintang menu bukan satu-orang-satu-suara** | Penilaian menempel pada pesanan, jadi yang memesan sepuluh kali menyumbang sepuluh penilaian. Disengaja: tiap kunjungan adalah masakan yang berbeda |
| **Pesanan kasir tidak bisa dinilai pelanggannya** | Barisnya tersimpan atas nama kasir, bukan email pelanggan, jadi tidak ada kaitan ke akun siapa pun. Hanya pesanan dari HP dengan akun yang bisa dinilai |
| **Penilaian menu tidak berfoto** | Berbeda dari penilaian merchant. Satu pesanan bisa berisi lima menu, dan lima ulasan berfoto untuk satu kunjungan membuat barisnya jauh lebih berat daripada seluruh katalognya |

---

---

## 11. Lampiran A — Tangkapan Layar

Tangkapan layar berikut diambil dari aplikasi yang berjalan, disusun per
peran dan per mode tampilan. Urutannya mengikuti alur pemakaian
sebenarnya, dari layar pertama sampai layar terakhir yang dibuka.

Dua mode disertakan karena keduanya bukan sekadar pembalikan warna:
warna merek dinaikkan terangnya di mode gelap, bilah atas ikut gelap,
dan latar kartunya dibedakan dari latar halaman. Yang perlu dipastikan
saat memeriksanya cuma satu — tidak ada tulisan yang hilang di
latarnya.

### A.1 Pelanggan — tanpa akun (tamu)

Tamu memesan tanpa mendaftar apa pun. Yang dikorbankan cuma satu — jejak
pesanannya hanya tersimpan di HP itu sendiri, dan hilang bersama
aplikasinya kalau dihapus.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Halaman awal** | Memilih masuk sebagai Pelanggan atau Merchant-POS Merchant; mengatur tema; membuka Tentang Merchant-POS |
| **Ajakan login** | Melewatinya lewat "Lewati, Pesan Tanpa Login" dan langsung memesan |
| **Layar pembuka tamu** | Tiga pintu saja: Scan QR Meja, Pilih Resto, dan Riwayat Pesanan Saya |
| **Pilih Resto** | Mencari resto; melihat yang terdekat berikut jaraknya begitu izin lokasi diberikan — sebelum itu hanya bagian Semua Resto yang tampil |
| **Menu resto** | Melihat banner promo, membuka kategori, menambah menu ke keranjang |
| **Dialog menu** | Memilih level/varian — minuman bisa punya tiga kelompok sekaligus (Gula, Es, Ukuran) — menulis catatan, mengatur jumlah |
| **Keranjang** | Memilih Dine In atau Take Away; Take Away tidak meminta nomor meja, tapi nama pemesan tetap wajib; memilih QRIS atau Tunai |
| **Bayar dengan QRIS** | Memindai QR berbingkai Merchant-POS, melihat masa berlakunya, menyimpannya ke galeri |
| **Pesanan diterima** | Membaca nomor pesanan untuk disebutkan di kasir, dan hitung mundur 30 menit sebelum pesanannya hangus |
| **Pesanan Saya** | Memantau status dapur dan pembayaran untuk sesi meja yang sedang berjalan |
| **Riwayat Saya** | Melihat pesanan sebelumnya — disertai peringatan bahwa riwayatnya hanya ada di HP ini |


**Mode Terang** — 13 tangkapan

!!ss[Halaman awal — pilih peran, pemilih tema, nomor versi](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215645.jpg)
!!ss[Tentang Merchant-POS — tautan situs dan ringkasan fitur tiap peran](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215651.jpg)
!!ss[Ajakan login; tamu memilih Lewati, Pesan Tanpa Login](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215655.jpg)
!!ss[Layar pembuka tamu — Scan QR Meja, Pilih Resto, dan Riwayat Pesanan Saya](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215700.jpg)
!!ss[Pilih Resto sebelum izin lokasi diberikan — hanya bagian Semua Resto](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215705.jpg)
!!ss[Layar yang sama setelah lokasi diketahui — bagian Terdekat muncul berikut jaraknya](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215711.jpg)
!!ss[Menu resto — banner promo, kategori terlipat, keranjang kosong](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215715.jpg)
!!ss[Dialog menu makanan — Level Pedas, catatan, jumlah, subtotal](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215723.jpg)
!!ss[Dialog menu minuman — tiga kelompok level: Gula, Es, dan Ukuran](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215730.jpg)
!!ss[Keranjang Take Away — nomor meja tidak diminta, nama pemesan wajib](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215807.jpg)
!!ss[Cara bayar Tunai dipilih — tombolnya berubah jadi Pesan & Bayar di Kasir](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215811.jpg)
!!ss[Pesanan diterima — nomor pesanan untuk disebutkan di kasir dan hitung mundur 30 menit](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215816.jpg)
!!ss[Riwayat Saya milik tamu — peringatan bahwa riwayatnya hanya tersimpan di HP ini](gambar/capture/Lightmode/Customer-NonLogin/Screenshot_20260816-215833.jpg)


**Mode Gelap** — 9 tangkapan

!!ss[Halaman awal dengan tema Gelap aktif](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213321.jpg)
!!ss[Layar pembuka tamu](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213329.jpg)
!!ss[Pilih Resto — Terdekat dan Semua Resto](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213335.jpg)
!!ss[Menu resto — banner promo dan kategori](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213341.jpg)
!!ss[Dialog menu — deskripsi produk ikut tampil di bawah harganya](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213349.jpg)
!!ss[Keranjang Dine In — nomor meja dan nama pemesan, rincian biaya service dan PPN](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213408.jpg)
!!ss[Bayar dengan QRIS — kartu QR berbingkai, masa berlaku, simpan ke galeri](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213417.jpg)
!!ss[Pembayaran berhasil berikut nomor pesanannya](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213425.jpg)
!!ss[Pesanan Saya — status dapur dan pembayaran untuk sesi meja ini](gambar/capture/Darkmode/Customer-NonLogin/Screenshot_20260816-213434.jpg)


### A.2 Pelanggan — dengan akun

Alur pada tangkapan layar berikut mengikuti satu sesi utuh: masuk dengan
akun Google, memilih resto, memesan, membayar, lalu memeriksa pesanan
dan riwayatnya.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Halaman awal** | Memilih masuk sebagai Pelanggan atau Merchant-POS Merchant; mengatur tema sebelum masuk; membuka Tentang Merchant-POS |
| **Ajakan login** | Masuk dengan Gmail, atau melewatinya dan tetap memesan sebagai tamu |
| **Menu utama** | Tujuh pintu: Pesan, Profil, Riwayat, Kotak Masuk (berikut penanda belum dibaca), Tampilan, Tes Notifikasi, Keluar |
| **Mau Pesan Di Mana?** | Scan QR meja, atau memilih resto dari daftar |
| **Pilih Resto** | Mencari resto dari nama atau alamat; melihat yang terdekat berikut jaraknya; membuka lokasinya di peta |
| **Menu resto** | Melihat banner promo, membuka kategori, menambah menu ke keranjang; banner ikut tergulir bersama menunya |
| **Dialog menu** | Memilih level/varian, menulis catatan, mengatur jumlah, melihat subtotalnya berubah |
| **Keranjang** | Memilih Dine In atau Take Away, mengisi nomor meja dan nama, melihat rincian biaya service dan PPN, memilih QRIS atau Tunai |
| **Bayar dengan QRIS** | Memindai QR berbingkai Merchant-POS, melihat masa berlakunya, menyimpan QR ke galeri |
| **Pesanan diterima (tunai)** | Membaca nomor pesanan yang disebutkan di kasir, dan hitung mundur 30 menit sebelum pesanannya hangus |
| **Struk** | Melihat rincian menu, biaya, dan cara bayar; menyimpan atau membagikannya |
| **Pesanan Saya** | Memantau status dapur dan pembayaran; membatalkan pesanan yang belum dibayar |
| **Riwayat Saya** | Melihat seluruh pesanan lintas tanggal dan resto |
| **Profil** | Mengubah nama, nomor telepon, dan foto; email terkunci karena dari akun Google |
| **Kotak Masuk** | Membaca pemberitahuan versi baru dan promo dari resto yang pernah dipesan |
| **Tampilan** | Berganti mode terang, gelap, atau mengikuti setelan HP |


**Mode Terang** — 18 tangkapan

!!ss[Halaman awal — masuk sebagai Pelanggan](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215350.jpg)
!!ss[Ajakan login Gmail, dengan pilihan "Lewati, Pesan Tanpa Login"](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215354.jpg)
!!ss[Menyiapkan data setelah login](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215403.jpg)
!!ss[Menu utama pelanggan — Pesan, Profil, Riwayat, Kotak Masuk, Tampilan, Tes Notifikasi, Keluar](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215409.jpg)
!!ss[Mau Pesan Di Mana? — pemindai QR meja terbuka di bawah](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215412.jpg)
!!ss[Mau Pesan Di Mana? — Scan QR Meja atau Pilih Resto](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215416.jpg)
!!ss[Pilih Resto — daftar terdekat dengan jarak, lalu semua resto, bisa dicari](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215421.jpg)
!!ss[Menu resto — banner promo di atas, kategori terlipat, keranjang masih kosong](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215430.jpg)
!!ss[Kategori Makanan terbuka — foto, nama, harga, tombol tambah](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215434.jpg)
!!ss[Detail menu — level pedas, catatan opsional, jumlah, subtotal](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215438.jpg)
!!ss[Menu setelah item ditambahkan — bilah keranjang muncul di bawah](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215444.jpg)
!!ss[Keranjang — Dine In/Take Away, nomor meja & nama wajib, rincian biaya service dan PPN, pilihan QRIS/Tunai](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215448.jpg)
!!ss[Keranjang dengan nomor meja terisi](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215454.jpg)
!!ss[Keranjang dengan cara bayar Tunai — tombol berubah jadi "Pesan & Bayar di Kasir"](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215504.jpg)
!!ss[Pesanan Diterima (tunai) — nomor pesanan, nominal, hitung mundur 30 menit sebelum pesanan hangus](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215509.jpg)
!!ss[Pesanan Saya — pesanan yang belum dibayar bisa dibatalkan sendiri](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215515.jpg)
!!ss[Lengkapi Profil — foto, nama, email terkunci, nomor telepon opsional](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215522.jpg)
!!ss[Riwayat Saya — semua pesanan lintas resto, dengan tombol batal pada yang belum dibayar](gambar/capture/Lightmode/Customer-Login/Screenshot_20260816-215526.jpg)


**Mode Gelap** — 22 tangkapan

!!ss[Halaman awal dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212736.jpg)
!!ss[Tentang Merchant-POS — tautan situs dan penjelasan fitur per peran](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212742.jpg)
!!ss[Ajakan login Gmail dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212748.jpg)
!!ss[Menyiapkan data setelah login](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212800_Google Play services.jpg)
!!ss[Menyiapkan data (lanjutan)](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212808_Google Play services.jpg)
!!ss[Menu utama pelanggan dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212818.jpg)
!!ss[Mau Pesan Di Mana?](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212822.jpg)
!!ss[Pilih Resto — daftar terdekat dan semua resto](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212826.jpg)
!!ss[Menu resto dengan banner promo — banner ikut tergulir bersama daftar menu](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212835.jpg)
!!ss[Banner promo diketuk — syarat dan periode promonya dibuka penuh](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212842.jpg)
!!ss[Kategori Makanan terbuka](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212902.jpg)
!!ss[Kategori Minuman terbuka](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212907.jpg)
!!ss[Keranjang berisi dua item, lengkap dengan pilihan level per item](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212935.jpg)
!!ss[Bayar dengan QRIS — QR berbingkai Merchant-POS, hitung mundur, simpan ke galeri](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212946.jpg)
!!ss[Pembayaran Berhasil — pesanan diteruskan ke kasir](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-212955.jpg)
!!ss[Struk Pembayaran — rincian item, biaya service, PPN, metode; bisa disimpan atau dibagikan](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213006.jpg)
!!ss[Pesanan Saya — status dapur dan status bayar terpisah, termasuk yang dibatalkan](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213013.jpg)
!!ss[Lengkapi Profil dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213025.jpg)
!!ss[Riwayat Saya dalam mode gelap](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213030.jpg)
!!ss[Kotak Masuk pelanggan — tab Update Aplikasi dan General, yang belum dibaca bertanda titik](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213035.jpg)
!!ss[Pemilih tampilan: terang, gelap, atau ikut setelan HP — berlaku di perangkat ini saja](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213056.jpg)
!!ss[Konfirmasi keluar dari akun](gambar/capture/Darkmode/Customer-Login/Screenshot_20260816-213105.jpg)


### A.3 Kasir

Kasir memegang dua antrean sekaligus: pesanan yang dia ketik sendiri di
meja kasir, dan pesanan yang dikirim pelanggan dari HP-nya lalu memilih
bayar tunai. Keduanya bertemu di layar yang sama.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Menu kasir** | Tujuh pintu: Input Pesanan, Pending Payment (berikut jumlah yang menunggu), Riwayat Kasir, Saldo & Pengeluaran, Setor Saldo Cash, Kotak Masuk, Diskon |
| **Input Pesanan** | Memilih menu per kategori; sisa stok tampil di pojok kartu — angka yang tidak pernah dilihat pelanggan |
| **Dialog menu** | Memilih level/varian, menulis catatan, mengatur jumlah; deskripsi dan sisa stok ikut terlihat |
| **Checkout** | Memilih Dine In atau Take Away; Dine In meminta nomor meja, Take Away meminta nama pelanggan; tombol pembayaran mati sampai yang wajib terisi; diskon sudah terhitung dan menurunkan nominal DIBAYAR |
| **Bayar QRIS di kasir** | Menampilkan QR berbingkai Merchant-POS, dan mencetak QR itu untuk diserahkan ke pelanggan |
| **Dialog pembayaran tunai** | Memakai pilihan nominal cepat atau papan angka; kembalian dihitung sendiri; tombol terima mati selama uangnya kurang |
| **Struk** | Mencetak struk lengkap berikut nama kasir, uang bayar, dan kembaliannya |
| **Pending Payment** | Melihat pesanan pelanggan yang menunggu dibayar berikut sisa waktunya; membuka rinciannya; memilih cara terima pembayaran — Tunai, QRIS, atau Transfer — walau pelanggannya tadi memilih tunai |
| **Riwayat Kasir** | Rekap per hari berikut rincian per cara bayar, dan mencetak ulang struk |
| **Saldo & Pengeluaran** | Melihat saldo total, cash dan non-cash, petty cash, dan rekening resto; mengajukan Top Up Petty Cash yang menunggu persetujuan Finance |
| **Setor Saldo Cash** | Melihat tunai di laci berikut rinciannya; mengisi formulir setoran dengan rekening tujuan yang terisi sendiri dari Pengaturan Pembayaran, dan melampirkan buktinya |
| **Diskon** | Membuat dan mengubah promo — per menu, bundling, atau minimum belanja; tiap menu diberi syarat jumlahnya sendiri, Minimal atau Tepat |


**Mode Terang** — 18 tangkapan

!!ss[Halaman awal — masuk sebagai Merchant-POS Merchant](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215927.jpg)
!!ss[Memilih akun Google karyawan](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215931_Google Play services.jpg)
!!ss[Menu kasir — Input Pesanan, Pending Payment (2 menunggu), Riwayat Kasir, Saldo, Setor, Kotak Masuk, Diskon](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215939.jpg)
!!ss[Input Pesanan — kategori Makanan terbuka; angka di pojok kartu adalah sisa stok](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215946.jpg)
!!ss[Kategori Minuman ikut terbuka](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215949.jpg)
!!ss[Checkout — tombol bayar mati sampai nomor meja diisi; diskon sudah terhitung dan menurunkan nominal DIBAYAR](gambar/capture/Lightmode/Kasir/Screenshot_20260816-215957.jpg)
!!ss[Nomor meja dan nama pelanggan terisi — ketiga tombol pembayaran menyala](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220007.jpg)
!!ss[Bayar dengan QRIS di meja kasir — QR berbingkai Merchant-POS dan tombol Cetak QR untuk Customer](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220014.jpg)
!!ss[Pembayaran berhasil — struk lengkap berikut nama kasirnya, siap dicetak](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220021.jpg)
!!ss[Pending Payment — dua pesanan menunggu, masing-masing dengan sisa waktu bayarnya](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220026.jpg)
!!ss[Memilih cara terima pembayaran: Tunai, QRIS, atau Transfer](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220037.jpg)
!!ss[Dialog pembayaran tunai — pilihan nominal cepat; tombol terima mati selama uangnya kurang](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220048.jpg)
!!ss[Uang diterima diisi — kembaliannya dihitung otomatis](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220051.jpg)
!!ss[Pesanan lunas hilang dari antrean; pemberitahuan menyebutkan kembaliannya](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220055.jpg)
!!ss[Riwayat Kasir — rekap per hari berikut rincian per cara bayar dan tombol cetak ulang struk](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220102.jpg)
!!ss[Saldo & Pengeluaran — saldo total, saldo cash dan non-cash, petty cash, rekening resto](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220107.jpg)
!!ss[Setor Saldo Cash — tunai di laci berikut rinciannya dan riwayat setoran](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220110.jpg)
!!ss[Diskon — kartu promo berikut lencana Berjalan dan masa berlakunya](gambar/capture/Lightmode/Kasir/Screenshot_20260816-220115.jpg)


**Mode Gelap** — 32 tangkapan

!!ss[Halaman awal, tema gelap](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213818.jpg)
!!ss[Memilih akun Google karyawan](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213826_Google Play services.jpg)
!!ss[Menu kasir](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213831.jpg)
!!ss[Input Pesanan — kategori masih terlipat](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213836.jpg)
!!ss[Kedua kategori terbuka berikut sisa stok tiap menu](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213839.jpg)
!!ss[Dialog menu — deskripsi, sisa stok, level, catatan, dan jumlah](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213846.jpg)
!!ss[Dialog minuman — tiga kelompok level sekaligus](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213850.jpg)
!!ss[Checkout Dine In — tombol bayar mati sebelum nomor meja diisi](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213856.jpg)
!!ss[Checkout Take Away — yang diminta nama pelanggan, bukan nomor meja](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213901.jpg)
!!ss[Nama pelanggan terisi — tombol pembayaran menyala](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213912.jpg)
!!ss[Dialog pembayaran tunai — papan angka terbuka, tombol terima masih mati](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213919.jpg)
!!ss[Uang diterima diisi — kembalian muncul dan tombol terima menyala](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213925.jpg)
!!ss[Dialog yang sama dilihat utuh](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213939.jpg)
!!ss[Kembalian Rp 38.950 untuk uang Rp 100.000](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213943.jpg)
!!ss[Struk — memuat uang bayar dan kembaliannya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-213951.jpg)
!!ss[Layar pelanggan setelah memilih bayar tunai — nomor pesanan dan hitung mundur](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214038.jpg)
!!ss[Menu kasir — penanda Pending Payment berubah jadi 1](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214057.jpg)
!!ss[Pending Payment — satu pesanan tamu menunggu dibayar](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214100.jpg)
!!ss[Rincian pesanan sebelum uangnya diterima](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214105.jpg)
!!ss[Memilih cara terima pembayaran](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214111.jpg)
!!ss[Dialog pembayaran tunai untuk pesanan dari HP pelanggan](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214119.jpg)
!!ss[Uang diterima diisi berikut kembaliannya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214124.jpg)
!!ss[Antrean kosong setelah dilunasi](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214128.jpg)
!!ss[Riwayat Kasir — pesanan tadi ikut masuk rekap hari ini](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214136.jpg)
!!ss[Saldo & Pengeluaran](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214142.jpg)
!!ss[Top Up Petty Cash — kasir mengajukan, menunggu persetujuan Finance](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214156.jpg)
!!ss[Pengajuan tercatat sebagai Pending dan ditandai di kartu Petty Cash](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214204.jpg)
!!ss[Setor Saldo Cash — tunai di laci berikut rinciannya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214210.jpg)
!!ss[Formulir setoran — rekening tujuan terisi dari Pengaturan Pembayaran, bukti bisa dilampirkan](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214222.jpg)
!!ss[Setoran tercatat Pending dan mengurangi tunai di laci](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214229.jpg)
!!ss[Diskon — daftar promo resto](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214243.jpg)
!!ss[Ubah Diskon — dasar promo, potongan, dan masa berlakunya](gambar/capture/Darkmode/Kasir/Screenshot_20260816-214248.jpg)


### A.4 Dapur (Chef)

Layar dapur hanya empat tab, dan urutannya adalah urutan hidup sebuah
pesanan. Yang belum dibayar berhenti di tab pertama dan tidak pernah
sampai ke antrean masak — bahan tidak terpakai untuk pesanan yang
uangnya belum tentu datang.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Tab Menunggu Bayar** | Melihat pesanan yang belum dilunasi; sengaja tanpa tombol masak |
| **Tab Baru** | Melihat pesanan siap dimasak, dikelompokkan Dine In dan Take Away; menekan Mulai Masak |
| **Tab Diproses** | Membuka daftar centang per menu; menyimpan progres sebagian, atau menutup pesanan begitu seluruh menunya tercentang |
| **Tab Selesai** | Melihat pesanan yang sudah beres, dikelompokkan per tanggal dan tertutup secara bawaan |
| **Pemilih tema** | Berganti terang, gelap, atau ikut setelan HP langsung dari layar dapur |


**Mode Terang** — 9 tangkapan

!!ss[Halaman awal](gambar/capture/Lightmode/Chef/Screenshot_20260816-220755.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Lightmode/Chef/Screenshot_20260816-220802.jpg)
!!ss[Tab Menunggu Bayar — kosong; pesanan yang belum dibayar berhenti di sini, bukan di antrean masak](gambar/capture/Lightmode/Chef/Screenshot_20260816-220807.jpg)
!!ss[Tab Baru — pesanan siap dimasak, dikelompokkan Dine In dan Take Away, berikut tombol Mulai Masak](gambar/capture/Lightmode/Chef/Screenshot_20260816-220810.jpg)
!!ss[Tab Diproses — belum ada yang dikerjakan](gambar/capture/Lightmode/Chef/Screenshot_20260816-220818.jpg)
!!ss[Tab Selesai — dikelompokkan per tanggal dan tertutup secara bawaan](gambar/capture/Lightmode/Chef/Screenshot_20260816-220821.jpg)
!!ss[Pesanan berpindah ke Diproses — tombolnya berubah jadi Cek Menu & Selesai](gambar/capture/Lightmode/Chef/Screenshot_20260816-220832.jpg)
!!ss[Daftar centang per menu — seluruhnya tercentang, pesanan siap ditutup](gambar/capture/Lightmode/Chef/Screenshot_20260816-220837.jpg)
!!ss[Tab Selesai — pesanan hari ini beserta rinciannya](gambar/capture/Lightmode/Chef/Screenshot_20260816-220841.jpg)


**Mode Gelap** — 8 tangkapan

!!ss[Halaman awal, tema gelap](gambar/capture/Darkmode/Chef/Screenshot_20260816-213602.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Darkmode/Chef/Screenshot_20260816-213612_Google Play services.jpg)
!!ss[Tab Menunggu Bayar](gambar/capture/Darkmode/Chef/Screenshot_20260816-213619.jpg)
!!ss[Tab Baru — dua pesanan menunggu dimasak](gambar/capture/Darkmode/Chef/Screenshot_20260816-213623.jpg)
!!ss[Tab Diproses](gambar/capture/Darkmode/Chef/Screenshot_20260816-213635.jpg)
!!ss[Daftar centang — baru sebagian dicentang, tombolnya jadi Simpan Progres](gambar/capture/Darkmode/Chef/Screenshot_20260816-213640.jpg)
!!ss[Seluruh menu tercentang — tombolnya berubah jadi Tandai Pesanan Selesai](gambar/capture/Darkmode/Chef/Screenshot_20260816-213647.jpg)
!!ss[Tab Selesai](gambar/capture/Darkmode/Chef/Screenshot_20260816-213701.jpg)


### A.5 Admin

Admin mengurus isi restonya — menu, harga, banner, QR meja — dan ikut
memegang antrean pembayaran bersama kasir. Yang tidak dia pegang adalah
angka akuntansinya: Info Pembayaran dan Mapping GL milik Finance.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Menu admin** | Kasir, Kelola Produk, Pesanan Masuk, Pending Payment, Riwayat Kasir, Pengaturan, Saldo, Kirim Pengumuman, Diskon |
| **Kelola Produk — tab Produk** | Menambah dan mengubah menu; menandai habis lewat saklar di barisnya, tanpa membuka formulirnya |
| **Tab Kategori** | Menyusun kategori menu |
| **Tab Level** | Mengubah dan menambah kelompok varian milik resto ini — lima kelompok bawaan sudah terisi |
| **Pesanan Masuk** | Melihat seluruh pesanan resto berikut status bayar dan status dapurnya |
| **Pending Payment** | Antrean yang sama dengan kasir: menerima pembayaran Tunai, QRIS, atau Transfer; QR-nya bisa dicetak untuk pelanggan |
| **Pengaturan → Info Resto** | Mengubah nama dan alamat; menggeser pin di pratinjau peta; memilih cara makan yang dilayani — Dine In, Take Away, atau keduanya |
| **Pengaturan → Banner Promo** | Menambah dan mengubah banner berikut gambar, judul, keterangan, urutan tampil, masa berlaku, dan saklar aktif |
| **Pengaturan → QR Meja** | Membuat kartu QR satu meja dengan pratinjau langsung, atau sekaligus banyak meja lalu Download Semua |
| **Pengaturan → Info Pembayaran** | Melihat saja — yang mengubahnya Finance atau Owner |
| **Saldo & Pengeluaran** | Melihat saldo dan petty cash; pengajuan yang menunggu persetujuan Finance ikut terlihat berikut penandanya |
| **Setor Saldo Cash** | Melihat setoran yang sudah dikonfirmasi maupun yang masih menunggu approval |
| **Kirim Pengumuman** | Menulis pengumuman dan memilih sasarannya: Karyawan, Customer, atau Semua |
| **Diskon** | Membuat promo per menu, bundling beberapa menu sekaligus, atau minimum belanja; tiap menu diberi syarat jumlahnya sendiri (Minimal atau Tepat), lalu bentuk potongan dan masa berlakunya |


**Mode Terang** — 19 tangkapan

!!ss[Halaman awal](gambar/capture/Lightmode/Admin/Screenshot_20260816-220213.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Lightmode/Admin/Screenshot_20260816-220220.jpg)
!!ss[Menu admin — Kasir, Kelola Produk, Pesanan Masuk, Pending Payment, Riwayat Kasir, Pengaturan, Saldo](gambar/capture/Lightmode/Admin/Screenshot_20260816-220225.jpg)
!!ss[Kelola Produk tab Produk — saklar di tiap baris menandai habis tanpa membuka formulirnya](gambar/capture/Lightmode/Admin/Screenshot_20260816-220230.jpg)
!!ss[Tab Kategori](gambar/capture/Lightmode/Admin/Screenshot_20260816-220234.jpg)
!!ss[Tab Level — lima kelompok bawaan berikut pilihannya, bisa diubah dan ditambah](gambar/capture/Lightmode/Admin/Screenshot_20260816-220236.jpg)
!!ss[Pending Payment — admin memegang antrean yang sama dengan kasir](gambar/capture/Lightmode/Admin/Screenshot_20260816-220240.jpg)
!!ss[Memilih cara terima pembayaran](gambar/capture/Lightmode/Admin/Screenshot_20260816-220243.jpg)
!!ss[Pelunasan lewat QRIS — QR-nya bisa dicetak untuk diserahkan ke pelanggan](gambar/capture/Lightmode/Admin/Screenshot_20260816-220248.jpg)
!!ss[Antrean kosong; pemberitahuan menyebutkan pesanan lunas lewat QRIS](gambar/capture/Lightmode/Admin/Screenshot_20260816-220255.jpg)
!!ss[Pengaturan — Info Resto, Banner Promo, QR Meja, Info Pembayaran, dan blok Tampilan](gambar/capture/Lightmode/Admin/Screenshot_20260816-220332.jpg)
!!ss[Info Resto — pratinjau peta lokasi dan saklar cara makan yang dilayani](gambar/capture/Lightmode/Admin/Screenshot_20260816-220336.jpg)
!!ss[Banner Promo — daftar banner berikut urutan tampil dan tombol aktif/nonaktif](gambar/capture/Lightmode/Admin/Screenshot_20260816-220340.jpg)
!!ss[Generator QR Meja mode satu meja — pratinjau kartunya berubah saat nomornya diketik](gambar/capture/Lightmode/Admin/Screenshot_20260816-220347.jpg)
!!ss[Info Pembayaran — hanya bisa dilihat; yang mengubah adalah Finance](gambar/capture/Lightmode/Admin/Screenshot_20260816-220350.jpg)
!!ss[Saldo & Pengeluaran](gambar/capture/Lightmode/Admin/Screenshot_20260816-220355.jpg)
!!ss[Setor Saldo Cash — setoran yang sudah dikonfirmasi Finance](gambar/capture/Lightmode/Admin/Screenshot_20260816-220359.jpg)
!!ss[Kirim Pengumuman — pemilih sasaran Karyawan, Customer, atau Semua](gambar/capture/Lightmode/Admin/Screenshot_20260816-220403.jpg)
!!ss[Diskon](gambar/capture/Lightmode/Admin/Screenshot_20260816-220407.jpg)


**Mode Gelap** — 22 tangkapan

!!ss[Halaman awal, tema gelap](gambar/capture/Darkmode/Admin/Screenshot_20260816-214457.jpg)
!!ss[Masuk sebagai karyawan](gambar/capture/Darkmode/Admin/Screenshot_20260816-214503_Google Play services.jpg)
!!ss[Menu admin](gambar/capture/Darkmode/Admin/Screenshot_20260816-214510.jpg)
!!ss[Kelola Produk tab Produk](gambar/capture/Darkmode/Admin/Screenshot_20260816-214520.jpg)
!!ss[Tab Kategori](gambar/capture/Darkmode/Admin/Screenshot_20260816-214523.jpg)
!!ss[Tab Level](gambar/capture/Darkmode/Admin/Screenshot_20260816-214526.jpg)
!!ss[Pesanan Masuk — seluruh pesanan resto berikut status bayar dan status dapurnya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214537.jpg)
!!ss[Riwayat Kasir](gambar/capture/Darkmode/Admin/Screenshot_20260816-214545.jpg)
!!ss[Pengaturan](gambar/capture/Darkmode/Admin/Screenshot_20260816-214550.jpg)
!!ss[Info Resto berikut pratinjau petanya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214556.jpg)
!!ss[Banner Promo](gambar/capture/Darkmode/Admin/Screenshot_20260816-214603.jpg)
!!ss[Ubah Banner — gambar, judul, keterangan, dan masa berlakunya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214608.jpg)
!!ss[Generator QR Meja mode satu meja](gambar/capture/Darkmode/Admin/Screenshot_20260816-214621.jpg)
!!ss[Mode banyak meja — cukup mengisi jumlah mejanya, lalu Download Semua](gambar/capture/Darkmode/Admin/Screenshot_20260816-214640.jpg)
!!ss[Info Pembayaran](gambar/capture/Darkmode/Admin/Screenshot_20260816-214644.jpg)
!!ss[Saldo & Pengeluaran — pengajuan petty cash yang menunggu persetujuan ikut terlihat](gambar/capture/Darkmode/Admin/Screenshot_20260816-214654.jpg)
!!ss[Rincian petty cash — pengajuan Pending diberi penanda tersendiri](gambar/capture/Darkmode/Admin/Screenshot_20260816-214700.jpg)
!!ss[Setor Saldo Cash — setoran yang masih menunggu approval Finance](gambar/capture/Darkmode/Admin/Screenshot_20260816-214711.jpg)
!!ss[Kirim Pengumuman](gambar/capture/Darkmode/Admin/Screenshot_20260816-214735.jpg)
!!ss[Diskon](gambar/capture/Darkmode/Admin/Screenshot_20260816-214740.jpg)
!!ss[Ubah Diskon berbasis menu — beberapa menu dipilih sekaligus untuk bundling](gambar/capture/Darkmode/Admin/Screenshot_20260816-214752.jpg)
!!ss[Bagian bawah formulir diskon — bentuk potongan dan masa berlakunya](gambar/capture/Darkmode/Admin/Screenshot_20260816-214755.jpg)


### A.6 Keuangan (Finance)

Finance tidak menyentuh pesanan sama sekali. Yang dia pegang adalah dua
titik tempat uang berpindah tangan — setoran tunai ke rekening dan top
up petty cash — dan keduanya sengaja dibuat menunggu persetujuannya.
Selama menunggu, uangnya duduk di akun suspense: sudah tidak ada di
laci, tapi belum diakui masuk.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Menu Finance** | Berpindah resto lewat pemilih di atas — semua angka mengikutinya; penanda merah menunjukkan menu yang sedang menunggu persetujuan |
| **Pemasukan** | Melihat total semua waktu, dirinci per hari dengan pecahan Tunai/QRIS/Transfer |
| **Saldo & Pengeluaran** | Melihat saldo total dan pecahan Cash/Non Cash; menyetujui atau menolak top up petty cash; mencatat pengeluaran; melipat bagian Petty Cash dan Riwayat Pengeluaran |
| **Dialog persetujuan** | Membaca perpindahan yang akan terjadi — dari GL Suspense ke GL tujuannya — sebelum menyetujui, dan menambahkan catatan |
| **Setor Saldo Cash** | Melihat tunai di laci berikut rinciannya; mengonfirmasi atau menolak setoran kasir setelah mencocokkan nominalnya di rekening |
| **Mapping GL Account** | Menetapkan nomor akun untuk tiap cara bayar, petty cash, pajak, service, total saldo, suspense, gateway, dan diskon; mengatur tarif PPN dan biaya service |
| **Pencairan Gateway** | Mencatat dana penyedia pembayaran yang masuk rekening berikut potongan MDR-nya |
| **Jurnal GL** | Membaca jejak audit tiap pergerakan: nomor akun, arah debit/kredit, referensi pesanan, dan pelepasan titipan suspense saat sesuatu disetujui; mencetak atau mengekspornya |
| **Laporan Transaksi** | Memilih rentang tanggal, melihat saldo awal dan akhir, mengekspor PDF |
| **Pengaturan Pembayaran** | Melihat data QRIS dan rekening transfer resto |


**Mode Terang** — 10 tangkapan

!!ss[Halaman awal — masuk sebagai Merchant-POS Merchant](gambar/capture/Lightmode/Finance/Screenshot_20260816-220502.jpg)
!!ss[Menyiapkan data resto setelah masuk](gambar/capture/Lightmode/Finance/Screenshot_20260816-220510.jpg)
!!ss[Pemasukan — total semua waktu, dirinci per hari dengan pecahan Tunai/QRIS](gambar/capture/Lightmode/Finance/Screenshot_20260816-220515.jpg)
!!ss[Menu Finance dengan pemilih resto: semua angka mengikuti resto yang dipilih](gambar/capture/Lightmode/Finance/Screenshot_20260816-220518.jpg)
!!ss[Saldo & Pengeluaran — saldo total, pecahan Cash/Non Cash, Petty Cash & Riwayat Pengeluaran yang bisa dilipat](gambar/capture/Lightmode/Finance/Screenshot_20260816-220521.jpg)
!!ss[Setor Saldo Cash — tunai di laci, rincian yang sudah disetor & dipindah, riwayat setoran](gambar/capture/Lightmode/Finance/Screenshot_20260816-220524.jpg)
!!ss[Mapping GL Account — akun pemasukan per metode bayar dan akun Petty Cash](gambar/capture/Lightmode/Finance/Screenshot_20260816-220527.jpg)
!!ss[Mapping GL Account (lanjutan) — tarif PPN 11% & service 5%, GL Total Saldo, GL Suspense](gambar/capture/Lightmode/Finance/Screenshot_20260816-220531.jpg)
!!ss[Pencairan Gateway — dana penyedia pembayaran yang masuk rekening berikut potongan MDR](gambar/capture/Lightmode/Finance/Screenshot_20260816-220534.jpg)
!!ss[Jurnal GL — saldo GL Total, total debit & kredit, tiap baris dengan nomor akun dan referensi pesanan](gambar/capture/Lightmode/Finance/Screenshot_20260816-220539.jpg)


**Mode Gelap** — 17 tangkapan

!!ss[Halaman awal dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-214907.jpg)
!!ss[Menyiapkan data resto](gambar/capture/Darkmode/Finance/Screenshot_20260816-214910_Google Play services.jpg)
!!ss[Menyiapkan data resto (lanjutan)](gambar/capture/Darkmode/Finance/Screenshot_20260816-214924.jpg)
!!ss[Pemasukan dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-214932.jpg)
!!ss[Menu Finance dengan penanda merah pada menu yang menunggu persetujuan](gambar/capture/Darkmode/Finance/Screenshot_20260816-214936.jpg)
!!ss[Saldo & Pengeluaran — top up petty cash menunggu persetujuan, dengan tombol Setuju/Tolak](gambar/capture/Darkmode/Finance/Screenshot_20260816-214952.jpg)
!!ss[Dialog Setuju top up — menjelaskan perpindahan dari GL Suspense Petty Cash ke GL Petty Cash](gambar/capture/Darkmode/Finance/Screenshot_20260816-214957.jpg)
!!ss[Saldo & Pengeluaran setelah top up disetujui](gambar/capture/Darkmode/Finance/Screenshot_20260816-215003.jpg)
!!ss[Setor Saldo Cash — setoran berstatus Pending menunggu konfirmasi Finance](gambar/capture/Darkmode/Finance/Screenshot_20260816-215019.jpg)
!!ss[Dialog Konfirmasi setoran — mengingatkan mencocokkan nominal di rekening lebih dulu](gambar/capture/Darkmode/Finance/Screenshot_20260816-215026.jpg)
!!ss[Setor Saldo Cash setelah dikonfirmasi — status berubah Completed](gambar/capture/Darkmode/Finance/Screenshot_20260816-215031.jpg)
!!ss[Mapping GL Account dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-215042.jpg)
!!ss[Mapping GL Account (lanjutan) — tarif pajak, GL Total Saldo, GL Suspense](gambar/capture/Darkmode/Finance/Screenshot_20260816-215048.jpg)
!!ss[Pencairan Gateway dalam mode gelap](gambar/capture/Darkmode/Finance/Screenshot_20260816-215052.jpg)
!!ss[Jurnal GL — jejak audit persetujuan: titipan suspense dilepas, dana pindah ke akun tujuan](gambar/capture/Darkmode/Finance/Screenshot_20260816-215058.jpg)
!!ss[Laporan Transaksi — rentang tanggal, saldo awal & akhir, ekspor PDF](gambar/capture/Darkmode/Finance/Screenshot_20260816-215103.jpg)
!!ss[Pengaturan Pembayaran — QRIS dan rekening transfer, hanya bisa dilihat oleh Finance](gambar/capture/Darkmode/Finance/Screenshot_20260816-215107.jpg)


### A.7 Owner

Owner tidak punya layar khusus miliknya sendiri. Yang dia punya adalah
seluruhnya: tiap layar kasir, dapur, admin, dan Finance terbuka untuknya
tanpa perlu ditambahkan peran satu per satu. Menunya karena itu
dikelompokkan tiga — dan pengelompokan itulah yang membedakan
tampilannya dari peran lain.

| Layar | Yang bisa dilakukan di sana |
|---|---|
| **Pemilih resto** | Berpindah antar resto yang dimilikinya; seluruh isi menu mengikuti yang dipilih |
| **Kelompok PENJUALAN** | Kasir/Input Pesanan, Pesanan Masuk, Layar Dapur, Pending Payment, Riwayat Kasir |
| **Kelompok KEUANGAN** | Pemasukan, Saldo & Pengeluaran, Setor Saldo Cash, Mapping GL Account, Pencairan Gateway, Jurnal GL — sama persis dengan yang dipegang Finance, termasuk hak menyetujui |
| **Kelompok PENGELOLAAN** | Kelola Produk, Pengaturan (termasuk mengubah Info Pembayaran), Kirim Pengumuman, Kotak Masuk berikut jumlah belum dibaca, Diskon, dan Keluar |


**Mode Terang** — 6 tangkapan

!!ss[Halaman awal — masuk sebagai Merchant-POS Merchant](gambar/capture/Lightmode/Owner/Screenshot_20260816-220640.jpg)
!!ss[Menyiapkan data resto setelah masuk](gambar/capture/Lightmode/Owner/Screenshot_20260816-220647.jpg)
!!ss[Pemilih resto — Owner dengan lebih dari satu resto berpindah dari sini](gambar/capture/Lightmode/Owner/Screenshot_20260816-220652.jpg)
!!ss[Menu Owner, kelompok PENJUALAN — Kasir, Pesanan Masuk, Layar Dapur, Pending Payment, Riwayat Kasir](gambar/capture/Lightmode/Owner/Screenshot_20260816-220657.jpg)
!!ss[Kelompok KEUANGAN — akses penuh seperti Finance, termasuk Jurnal GL](gambar/capture/Lightmode/Owner/Screenshot_20260816-220701.jpg)
!!ss[Kelompok PENGELOLAAN — Kelola Produk, Pengaturan, Kirim Pengumuman, Kotak Masuk, Diskon, Keluar](gambar/capture/Lightmode/Owner/Screenshot_20260816-220706.jpg)


**Mode Gelap** — 5 tangkapan

!!ss[Halaman awal dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215153.jpg)
!!ss[Menyiapkan data resto](gambar/capture/Darkmode/Owner/Screenshot_20260816-215159.jpg)
!!ss[Kelompok PENJUALAN dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215204.jpg)
!!ss[Kelompok KEUANGAN dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215208.jpg)
!!ss[Kelompok PENGELOLAAN dalam mode gelap](gambar/capture/Darkmode/Owner/Screenshot_20260816-215213.jpg)

*Dokumen ini disusun dari aplikasi versi 2.12.0. Sisi teknisnya —
arsitektur, tabel, keamanan baris, prasyarat basis data — ada di
`SPESIFIKASI-KAATAGO`.*
