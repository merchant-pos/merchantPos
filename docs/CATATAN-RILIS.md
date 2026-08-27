# Catatan Rilis Merchant-POS

Yang dibacakan ke kotak masuk tiap rilis. Ditulis tangan, bukan
dibangkitkan dari daftar commit — daftar yang ditulis mesin berisi hal
yang tidak dimengerti pembacanya, dan pengumuman yang tidak dimengerti
berhenti dibaca pada rilis berikutnya.

## Dua aturan yang berbeda

**Fitur baru disebut satu per satu.** Poin besar saja, ditulis dari
sudut pandang yang memakai — bukan "menambahkan RPC report_menu_sales",
tapi "laporan menu terlaris untuk Owner dan Admin". Orang berhenti
membaca pengumuman yang tidak memberi tahu apa yang sekarang bisa dia
lakukan.

**Perbaikan bug dirangkum jadi satu baris**, tanpa dirinci:

```
- Perbaikan bug dan penyempurnaan tampilan
```

Merinci bug berarti mengumumkan ke semua orang — termasuk yang tidak
berkepentingan baik — apa saja yang pernah bisa ditembus, dilewati, atau
dibuat berhenti bekerja di aplikasi ini. "Tombol Batal dulu membuat
dialog tidak bisa ditutup" terbaca sebagai keterbukaan; yang dibacanya
adalah peta.

Yang tetap dirinci: perubahan perilaku yang sudah terlanjur dipakai
orang. Kalau sebuah angka sekarang dihitung berbeda, atau sebuah tombol
pindah tempat, itu bukan perbaikan yang disembunyikan — itu hal yang
akan membingungkan kalau tidak diberitahukan.

Rinciannya tetap ditulis lengkap di pesan commit dan di TSD. Yang
dibatasi pengumumannya, bukan catatannya.

Formatnya dibaca `scripts/release.sh`: judul `## <versi>`, lalu
poin-poinnya. Versi yang tidak punya bagiannya di sini tetap terbit,
hanya pengumumannya memakai kalimat umum.


## 1.0.0

- Rilis pertama Merchant-POS
- Kasir, dapur, dan pesan-sendiri dari meja lewat QR
- Pembukuan merchant: pemasukan, saldo, setoran, jurnal GL, dan laporan
- Konsol web untuk Owner, Admin, Finance, dan Merchant-POS Admin
- Perbaikan bug dan penyempurnaan tampilan
