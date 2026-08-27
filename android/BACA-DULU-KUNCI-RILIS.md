# Kunci penandatangan rilis belum ada

Salinan ini sengaja tidak membawa kunci milik KaataGo. Dua aplikasi yang
ditandatangani kunci yang sama tidak akan gagal dibangun — tapi kunci
rilis adalah identitas aplikasinya di mata Android dan Play Store, dan
sekali dipakai bersama, memisahkannya kemudian berarti salah satu harus
terbit sebagai aplikasi yang berbeda dan kehilangan seluruh
pemasangannya.

Selama berkas ini masih ada, `flutter build apk --release` tetap
berjalan memakai kunci debug — cukup untuk mencoba, tidak cukup untuk
dibagikan ke orang.

## Membuatnya

Jalankan sendiri, dan simpan kata sandinya di tempat yang tidak ikut
masuk git:

```
keytool -genkey -v -keystore android/app/merchantpos-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias merchantpos
```

Lalu buat `android/key.properties`:

```
storePassword=<kata sandi keystore>
keyPassword=<kata sandi kunci>
keyAlias=merchantpos
storeFile=merchantpos-release.jks
```

Keduanya sudah tercantum di `.gitignore`, jadi tidak akan ikut
ter-commit.

## Sesudah kuncinya jadi

Sidik jari SHA-1 kunci ini harus didaftarkan di Firebase untuk package
`com.gamskahfi.merchantpos`, kalau tidak login Google akan ditolak:

```
keytool -list -v -keystore android/app/merchantpos-release.jks -alias merchantpos
```
