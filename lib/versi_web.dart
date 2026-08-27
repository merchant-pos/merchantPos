/// Versi konsol web, terpisah dari versi aplikasi.
///
/// Keduanya memang tidak pernah sejalan. APK terbit sesekali lewat
/// release.sh dan nomornya menempel pada berkas yang sudah terpasang di
/// HP orang; konsol web terbit tiap push dan yang dibuka orang selalu
/// yang terakhir. Memakai satu nomor untuk keduanya berarti nomor itu
/// berbohong tentang salah satunya — dan yang paling sering ditanya
/// saat ada yang aneh adalah "kamu pakai versi berapa?".
///
/// Dinaikkan tangan, sama seperti catatan rilis. Yang menaikkannya tahu
/// apakah perubahan kemarin layak disebut versi baru; penghitung
/// otomatis tidak.
const kVersiWeb = '1.0.0';

/// Yang ditulis di kaki sidebar.
String get labelVersiWeb => 'Web v$kVersiWeb';
