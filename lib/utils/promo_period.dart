/// Masa berlaku sebuah promo — dipakai banner promo maupun diskon.
///
/// Satu aturan, dua fitur. Keduanya menjanjikan hal yang sama kepada
/// pelanggan ("promo ini berlaku sampai tanggal sekian"), dan dua
/// perhitungan terpisah untuk janji yang sama akan berpisah pada
/// perubahan berikutnya.
///
/// Tanggal, bukan waktu. Resto berpikir dalam hari — "promo sampai 31
/// Agustus" berarti sampai tutup toko tanggal 31, bukan sampai pukul
/// 00:00 tanggal 31. Menyimpannya sebagai timestamp membuat promonya
/// mati satu hari lebih cepat daripada yang diumumkan.
class PromoPeriod {
  /// Mulai berlaku. Null berarti berlaku sejak dibuat.
  final DateTime? startsOn;

  /// Hari terakhir berlaku, ikut dihitung. Null berarti tanpa batas
  /// akhir.
  final DateTime? endsOn;

  const PromoPeriod({this.startsOn, this.endsOn});

  /// Sedang berlaku pada [now].
  bool isLive([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    if (startsOn != null && today.isBefore(_dateOnly(startsOn!))) return false;
    // Hari terakhirnya ikut berlaku penuh: yang ditulis "sampai 31
    // Agustus" harus masih bisa dipakai sepanjang tanggal 31.
    if (endsOn != null && today.isAfter(_dateOnly(endsOn!))) return false;
    return true;
  }

  /// Belum mulai — sudah dijadwalkan, tapi harinya belum tiba.
  bool isScheduled([DateTime? now]) {
    if (startsOn == null) return false;
    return _dateOnly(now ?? DateTime.now()).isBefore(_dateOnly(startsOn!));
  }

  bool isExpired([DateTime? now]) {
    if (endsOn == null) return false;
    return _dateOnly(now ?? DateTime.now()).isAfter(_dateOnly(endsOn!));
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Tanggal paling awal yang boleh dipilih sebagai mulai.
///
/// Hari ini, bukan kemarin. Promo yang mulai berlaku di masa lalu tidak
/// pernah bisa benar: transaksi kemarin sudah tercatat dan sudah
/// dijurnal tanpa diskonnya, dan menambahkan promo mundur berarti
/// pembukuan yang sudah ditutup tidak lagi cocok dengan daftar
/// promonya.
DateTime earliestStart([DateTime? now]) =>
    PromoPeriod._dateOnly(now ?? DateTime.now());

/// Tanggal paling awal yang boleh dipilih sebagai berakhir.
///
/// Besok — bukan hari ini. Promo yang berakhir hari ini juga adalah
/// promo yang tidak pernah sempat dipakai orang, dan itu selalu bukan
/// yang dimaksud orang yang mengisinya.
DateTime earliestEnd(DateTime? startsOn, [DateTime? now]) {
  final base = startsOn ?? (now ?? DateTime.now());
  return PromoPeriod._dateOnly(base).add(const Duration(days: 1));
}

/// Keterangan masa berlaku yang salah, atau null kalau sah.
String? validatePeriod({DateTime? startsOn, DateTime? endsOn, DateTime? now}) {
  final today = PromoPeriod._dateOnly(now ?? DateTime.now());
  if (startsOn != null && PromoPeriod._dateOnly(startsOn).isBefore(today)) {
    return 'Tanggal mulai tidak boleh sebelum hari ini.';
  }
  if (endsOn != null) {
    final end = PromoPeriod._dateOnly(endsOn);
    if (!end.isAfter(today)) {
      return 'Tanggal berakhir harus setelah hari ini.';
    }
    if (startsOn != null && !end.isAfter(PromoPeriod._dateOnly(startsOn))) {
      return 'Tanggal berakhir harus setelah tanggal mulai.';
    }
  }
  return null;
}
