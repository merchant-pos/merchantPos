import 'dart:convert';
import 'dart:typed_data';

/// Mengubah base64 jadi byte, dan mengingat hasilnya.
///
/// `base64Decode` mengembalikan Uint8List **baru** tiap kali dipanggil.
/// `MemoryImage` membandingkan dirinya lewat identitas byte itu, jadi
/// byte baru berarti kunci cache gambar yang baru: Flutter mendekode
/// ulang gambarnya dari nol, dan selama sekejap itu tempatnya kosong.
///
/// Di layar yang jarang dibangun ulang, itu tidak terasa. Di layar
/// kasir ia dibangun ulang tiap kali keranjang berubah — jadi tiap kali
/// menambah satu item, seluruh foto menu berkedip sekaligus. Banner
/// promo lebih parah lagi: gambarnya dipakai dua kali dalam satu susunan
/// (latar kabur dan gambar depannya), jadi didekode dua kali per build.
///
/// Dengan ingatan ini, byte yang sama dikembalikan lagi — kunci
/// cache-nya tetap, dan gambarnya tidak pernah didekode dua kali.
///
/// Isinya dibatasi. Foto menu memang kecil karena sudah dikecilkan saat
/// diunggah, tapi ingatan yang tidak pernah dibuang akan tumbuh terus
/// selama aplikasinya hidup — dan yang menemukannya adalah tablet kasir
/// yang tidak pernah dimatikan berhari-hari.
class _IngatanGambar {
  static const _maks = 120;

  static final _isi = <String, Uint8List>{};

  /// Urutan pemakaian, terlama di depan.
  static final _urutan = <String>[];

  static Uint8List ambil(String base64) {
    final ada = _isi[base64];
    if (ada != null) {
      // Yang baru dipakai dipindah ke belakang, supaya yang dibuang
      // nanti benar-benar yang paling lama tidak tersentuh — bukan yang
      // kebetulan masuk paling awal.
      _urutan.remove(base64);
      _urutan.add(base64);
      return ada;
    }

    final byte = base64Decode(base64);
    _isi[base64] = byte;
    _urutan.add(base64);

    while (_urutan.length > _maks) {
      _isi.remove(_urutan.removeAt(0));
    }
    return byte;
  }
}

/// Byte gambar dari base64, dengan hasil yang diingat.
///
/// Dipakai di tiap tempat yang menggambar base64 berulang kali — foto
/// menu, banner promo, logo resto. Yang sekali gambar dan tidak pernah
/// dibangun ulang boleh memakai `base64Decode` biasa.
Uint8List byteGambar(String base64) => _IngatanGambar.ambil(base64);
