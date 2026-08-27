/// Sapaan di hub customer, disesuaikan dengan jam.
///
/// Satu daftar sapaan untuk sepanjang hari terasa janggal: "perut udah
/// bunyi belum?" jam sembilan malam beda rasanya dengan jam tujuh pagi.
/// Menyesuaikannya dengan waktu makan membuat aplikasinya terasa seperti
/// tahu sedang jam berapa — dan kebetulan juga menyarankan hal yang
/// memang sedang dicari orang saat itu.
library;

/// Potongan hari, dibagi mengikuti kebiasaan makan di Indonesia dan
/// bukan pembagian pagi/siang/malam yang kaku.
enum MealTime { sarapan, makanSiang, sore, makanMalam, tengahMalam }

MealTime mealTimeFor(int hour) {
  if (hour >= 4 && hour < 10) return MealTime.sarapan;
  if (hour >= 10 && hour < 15) return MealTime.makanSiang;
  if (hour >= 15 && hour < 18) return MealTime.sore;
  if (hour >= 18 && hour < 23) return MealTime.makanMalam;
  return MealTime.tengahMalam;
}

const _lines = {
  MealTime.sarapan: [
    'Sarapan dulu yuk, biar harinya nggak lemes 🍳',
    'Pagi-pagi enaknya yang anget-anget nih',
    'Belum sarapan? Jangan bohong deh 👀',
    'Mulai hari dengan yang enak dulu ☕',
    'Perut kosong bikin mood ikut kosong lho',
  ],
  MealTime.makanSiang: [
    'Jam makan siang! Mau yang mana hari ini?',
    'Istirahat bentar, isi perut dulu 🍛',
    'Siang-siang gini paling pas yang berkuah',
    'Jangan skip makan siang ya, nanti nyesel',
    'Waktunya rehat sejenak dan makan enak',
  ],
  MealTime.sore: [
    'Sore-sore paling enak jajan sama yang seger 🧋',
    'Ngopi dulu nggak nih?',
    'Butuh amunisi sore biar melek lagi ☕',
    'Cemilan sore itu bukan dosa kok',
    'Yang seger-seger dulu, baru lanjut lagi',
  ],
  MealTime.makanMalam: [
    'Makan malam mau yang apa nih? 🍽️',
    'Sudah waktunya makan malam, jangan ditunda',
    'Tutup hari dengan makanan yang enak',
    'Malam-malam gini enaknya yang gurih',
    'Lapar habis seharian? Wajar banget',
  ],
  MealTime.tengahMalam: [
    'Masih melek? Perut ikut begadang juga ya 🌙',
    'Lapar tengah malam itu nyata adanya',
    'Malam panjang butuh teman makan',
    'Belum tidur, tapi udah laper duluan?',
    'Diam-diam pesan, nggak ada yang tahu 🤫',
  ],
};

/// Sapaan untuk [now].
///
/// [seed] menentukan baris mana yang dipilih dalam satu potongan hari —
/// diambil dari tanggal, bukan acak, supaya sapaannya tidak berganti
/// setiap layar digambar ulang.
String greetingFor(DateTime now) {
  final options = _lines[mealTimeFor(now.hour)]!;
  final dayOfYear = now.difference(DateTime(now.year)).inDays;
  return options[dayOfYear % options.length];
}
