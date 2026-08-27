/// Alamat konsol web Merchant-POS.
///
/// Dipakai sebagai isi QR meja, jadi mengubahnya membuat seluruh stiker
/// yang sudah tercetak menunjuk ke tempat yang salah. Kalau alamatnya
/// pindah, jalur lama harus tetap dilayani — bukan sekadar dialihkan
/// sekali lalu dilupakan.
const kAlamatWeb = 'https://merchant-pos.github.io/';

/// Isi QR meja: tautan, bukan teks biasa.
///
/// Bentuk lamanya `RESTO:<id>|TABLE:<n>` hanya berarti sesuatu bagi
/// pemindai di dalam aplikasi Merchant-POS. Dipindai kamera bawaan HP — yang
/// dipakai hampir semua orang yang belum memasang aplikasinya — hasilnya
/// cuma sebaris teks aneh tanpa satu pun tombol untuk melanjutkan.
///
/// Sebagai tautan, kamera bawaan menawarkan membukanya, dan yang membuka
/// langsung sampai di menu meja itu tanpa memasang apa pun.
String tautanMeja(String restoId, String meja) {
  final u = Uri.parse(kAlamatWeb);
  return u.replace(queryParameters: {
    ...u.queryParameters,
    'resto': restoId,
    'meja': meja,
  }).toString();
}

/// Membaca isi QR meja, bentuk baru maupun lama.
///
/// Bentuk lamanya tetap diterima selamanya. Stiker yang sudah tertempel
/// di meja tidak ikut berubah saat aplikasinya diperbarui, dan merchant
/// yang mencetaknya tahun lalu tidak punya alasan mencetak ulang —
/// menolaknya berarti membuat meja yang tadinya bisa dipakai jadi tidak
/// bisa, tanpa satu pun perubahan di meja itu.
({String restoId, String meja})? bacaTautanMeja(String mentah) {
  final teks = mentah.trim();

  final lama = RegExp(r'^RESTO:([^|]+)\|TABLE:(.+)$').firstMatch(teks);
  if (lama != null) {
    return (restoId: lama.group(1)!.trim(), meja: lama.group(2)!.trim());
  }

  final u = Uri.tryParse(teks);
  if (u == null || !u.hasScheme) return null;
  final resto = u.queryParameters['resto']?.trim();
  final meja = u.queryParameters['meja']?.trim();
  if (resto == null || resto.isEmpty || meja == null || meja.isEmpty) {
    return null;
  }
  return (restoId: resto, meja: meja);
}
