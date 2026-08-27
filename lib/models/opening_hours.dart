import 'dart:convert';

/// Jam buka sebuah merchant, per hari.
///
/// Hari yang tidak punya entri berarti tutup — itu lebih jujur daripada
/// menyimpan "00:00–00:00" yang bisa terbaca sebagai buka 24 jam.
class OpeningHours {
  /// 1 = Senin … 7 = Minggu, mengikuti penomoran ISO — sama dengan
  /// `DateTime.weekday`, jadi tidak ada penyesuaian yang bisa meleset.
  final Map<int, (String buka, String tutup)> perHari;

  const OpeningHours(this.perHari);

  static const kosong = OpeningHours({});

  static const namaHari = {
    1: 'Senin',
    2: 'Selasa',
    3: 'Rabu',
    4: 'Kamis',
    5: 'Jumat',
    6: 'Sabtu',
    7: 'Minggu',
  };

  bool get adaIsinya => perHari.isNotEmpty;

  /// Sedang buka sekarang.
  ///
  /// Jam tutup yang lebih kecil daripada jam buka berarti melewati
  /// tengah malam — warung yang buka 18:00 sampai 02:00 tidak boleh
  /// dianggap tutup sepanjang malam.
  bool bukaPada(DateTime waktu) {
    final jam = perHari[waktu.weekday];
    if (jam == null) return false;
    final sekarang = waktu.hour * 60 + waktu.minute;
    final mulai = _menit(jam.$1);
    final selesai = _menit(jam.$2);
    if (mulai == null || selesai == null) return false;
    if (selesai > mulai) return sekarang >= mulai && sekarang < selesai;
    return sekarang >= mulai || sekarang < selesai;
  }

  static int? _menit(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final j = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (j == null || m == null) return null;
    return j * 60 + m;
  }

  Map<String, dynamic> toJson() => {
        for (final e in perHari.entries)
          e.key.toString(): {'buka': e.value.$1, 'tutup': e.value.$2},
      };

  factory OpeningHours.fromRaw(Object? raw) {
    Object? data = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return kosong;
      try {
        data = jsonDecode(raw);
      } catch (_) {
        return kosong;
      }
    }
    if (data is! Map) return kosong;

    final hasil = <int, (String, String)>{};
    for (final e in data.entries) {
      final hari = int.tryParse(e.key.toString());
      final isi = e.value;
      if (hari == null || hari < 1 || hari > 7 || isi is! Map) continue;
      final buka = isi['buka']?.toString() ?? '';
      final tutup = isi['tutup']?.toString() ?? '';
      if (buka.isEmpty || tutup.isEmpty) continue;
      hasil[hari] = (buka, tutup);
    }
    return OpeningHours(hasil);
  }
}
