import '../models/gl_journal_entry.dart';

/// Menghitung saldo dari baris jurnal.
///
/// Ditaruh di satu berkas karena dua layar memakainya — Jurnal GL dan
/// Saldo & Pengeluaran. Dua perhitungan terpisah akan berpisah, dan
/// yang terlihat adalah dua layar yang menyebut angka berbeda untuk
/// uang yang sama (TSD §11.1b).

/// Pasangan pembatalan: baris pembatal dan baris yang dibatalkannya
/// sama-sama berhenti dihitung.
String _kunciPasangan(GlJournalEntry e) =>
    '${e.referenceType}|${e.referenceId}|${e.glCode}';

/// Baris yang masih berlaku — bukan pembatalan, dan bukan yang dibatalkan.
List<GlJournalEntry> barisBerlaku(List<GlJournalEntry> semua) {
  final dibatalkan =
      semua.where((e) => e.isReversal).map(_kunciPasangan).toSet();
  return semua
      .where((e) => !e.isReversal && !dibatalkan.contains(_kunciPasangan(e)))
      .toList();
}

/// Saldo pembukuan Merchant-POS sendiri.
///
/// Total kredit dikurangi total debit atas **seluruh buku**, bukan atas
/// satu akun tertentu.
///
/// Dua aturan sebelumnya sama-sama salah, dan cara gagalnya berbeda.
///
/// Yang pertama menjumlah berdasarkan daftar jenis transaksi. Daftar
/// begitu harus ditambahi tiap kali ada fitur baru yang memindahkan
/// uang — dan saat voucher terbit, jenisnya belum ada di sana.
///
/// Yang kedua menjumlah pergerakan akun GL Total Saldo saja, dengan
/// anggapan setiap uang bebas Merchant-POS lewat akun itu. Ternyata tidak:
/// pendapatan langganan dikreditkan langsung ke GL Pendapatan
/// Langganan, tidak pernah menyentuh GL Total Saldo. Yang lewat sana
/// hanya voucher, jadi saldonya berbunyi minus sebesar voucher yang
/// terbit.
///
/// Aturan sekarang tidak menganggap apa pun tentang akun mana yang
/// dipakai. Transaksi yang cuma memindahkan uang antar-kantong menulis
/// satu debit dan satu kredit yang saling menghapus, jadi ia tidak
/// mengubah saldo — dan memang seharusnya tidak. Yang menaikkan saldo
/// adalah kredit tanpa pasangan debit, yang menurunkannya sebaliknya.
int saldoPlatform(List<GlJournalEntry> semua, [String? kodeTotalSaldoUsang]) {
  var saldo = 0;
  for (final e in barisBerlaku(semua)) {
    saldo += e.entryType == JournalEntryType.credit ? e.amount : -e.amount;
  }
  return saldo;
}

/// Seluruh uang masuk yang tercatat — jumlah sisi kredit.
int pemasukanPlatform(List<GlJournalEntry> semua,
        [String? kodeTotalSaldoUsang]) =>
    barisBerlaku(semua)
        .where((e) => e.entryType == JournalEntryType.credit)
        .fold(0, (jumlah, e) => jumlah + e.amount);

/// Seluruh uang keluar yang tercatat — jumlah sisi debit.
int pengeluaranPlatform(List<GlJournalEntry> semua,
        [String? kodeTotalSaldoUsang]) =>
    barisBerlaku(semua)
        .where((e) => e.entryType == JournalEntryType.debit)
        .fold(0, (jumlah, e) => jumlah + e.amount);
