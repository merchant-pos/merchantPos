import 'package:flutter/material.dart';


/// Bulatan merah berisi angka — penanda "ada yang belum kamu urus".
///
/// Selalu merah, tidak mengikuti warna kartunya. Itu memang disengaja:
/// yang membuat penanda ini bekerja bukan bentuknya, tapi kenyataan
/// bahwa di seluruh aplikasi cuma benda inilah yang berwarna merah
/// pekat — mata menemukannya tanpa perlu membaca satu pun tulisan.
class CountBadge extends StatelessWidget {
  final int count;

  /// Di atas angka ini ditulis "99+". Angka empat digit di dalam bulatan
  /// kecil tidak terbaca, dan bedanya 132 dengan 217 pun tidak mengubah
  /// apa yang harus dilakukan orangnya.
  final int max;

  final double fontSize;

  const CountBadge({super.key, required this.count, this.max = 99, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final text = count > max ? '$max+' : '$count';
    return Container(
      constraints: BoxConstraints(minWidth: fontSize * 1.9),
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: fontSize * 0.18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(fontSize * 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withOpacity(0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          height: 1.25,
        ),
      ),
    );
  }
}
