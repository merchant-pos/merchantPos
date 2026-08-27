import 'package:flutter/material.dart';

/// Label isian wajib, dengan bintang merah di belakangnya.
///
/// Dipakai lewat `label:`, bukan `labelText:` — keduanya tidak bisa
/// dipasang bersamaan, dan bintangnya harus berwarna berbeda dari
/// labelnya sendiri.
///
/// Merahnya sengaja sama dengan warna pesan galat. Orang tidak membaca
/// tanda bintang sebagai "wajib" karena ada yang mengajarinya; dia
/// membacanya begitu karena warnanya sama dengan yang muncul saat dia
/// melewatkannya.
///
/// Yang tidak diberi tanda berarti benar-benar opsional. Menandai
/// hampir semua isian membuat tandanya berhenti berarti apa-apa — dan
/// yang paling dirugikan justru isian yang memang boleh dikosongkan,
/// karena orang jadi mengisinya asal-asalan.
Widget requiredLabel(String text) {
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: text),
        const TextSpan(
          text: ' *',
          style: TextStyle(
            color: Color(0xFFEF4444),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
