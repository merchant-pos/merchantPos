import 'package:intl/intl.dart';

import '../models/discount.dart';

/// Satu promo, dijelaskan dalam kalimat yang bisa dibaca pemesan.
///
/// Dipisah dari widgetnya supaya bisa diuji sebagai teks biasa. Kalimat
/// yang salah di sini bukan salah tampilan — ia janji yang tidak akan
/// ditepati mesin kasir, dan yang menanggung selisihnya kasir di depan
/// pelanggan.
class DeskripsiDiskon {
  /// Nama promonya, apa adanya dari yang menyusun.
  final String judul;

  /// Berapa yang dipotong. "Potongan 10%" atau "Potongan Rp 5.000".
  final String potongan;

  /// Apa yang harus dibeli supaya dapat.
  final String syarat;

  /// Menu lain yang harus ikut dibeli. Kosong berarti promonya berdiri
  /// sendiri di menu ini.
  final List<String> paket;

  /// "Sampai 31 Agu 2026", atau null kalau tidak ada batas akhirnya.
  final String? sampai;

  const DeskripsiDiskon({
    required this.judul,
    required this.potongan,
    required this.syarat,
    this.paket = const [],
    this.sampai,
  });
}

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tgl = DateFormat('d MMM yyyy', 'id_ID');

/// Menjelaskan promo-promo yang mengenai [productId].
///
/// Yang tidak menyentuh menu ini dibuang — termasuk promo minimum
/// belanja, yang memang tidak menempel pada menu mana pun dan akan
/// terbaca sebagai janji yang salah kalau ditempelkan di sini.
List<DeskripsiDiskon> deskripsiDiskon({
  required List<Discount> diskon,
  required String productId,
  Map<String, String> namaMenu = const {},
}) {
  final hasil = <DeskripsiDiskon>[];

  for (final d in diskon) {
    if (d.basis != DiscountBasis.products) continue;
    final item = d.items.where((i) => i.productId == productId).firstOrNull;
    if (item == null) continue;

    hasil.add(DeskripsiDiskon(
      judul: d.name,
      potongan: d.kind == DiscountKind.percent
          ? 'Potongan ${d.value}%'
          : 'Potongan ${_rp.format(d.value)}',
      syarat: _syarat(item),
      paket: [
        for (final lain in d.items)
          if (lain.productId != productId)
            // Menu yang namanya tidak dikenal tetap disebut jumlahnya.
            // Menyembunyikannya membuat paket bersyarat terbaca seperti
            // promo satu menu — dan pemesan baru tahu bedanya di kasir.
            '${namaMenu[lain.productId] ?? 'menu lain'} '
                '(${_jumlah(lain)})',
      ],
      sampai: d.endsOn == null ? null : 'Sampai ${_tgl.format(d.endsOn!)}',
    ));
  }

  return hasil;
}

String _syarat(DiscountItem item) {
  final dasar = item.mode == QtyMode.exactly
      ? 'Beli tepat ${item.qty} pcs'
      : 'Beli minimal ${item.qty} pcs';

  if (item.targets.isEmpty) return dasar;

  // Sasarannya disebut satu per satu, tidak diringkas jadi "beberapa
  // bagian". Yang membacanya sedang memutuskan mau menambahkan topping
  // yang mana — dan itu jawaban yang tidak bisa diringkas.
  final sasaran = item.targets.map((t) => t.label).join(', ');
  return '$dasar — yang dipotong $sasaran';
}

String _jumlah(DiscountItem item) => item.mode == QtyMode.exactly
    ? 'tepat ${item.qty} pcs'
    : 'minimal ${item.qty} pcs';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
