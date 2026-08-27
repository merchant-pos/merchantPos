import '../utils/gambar_base64.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

import '../models/level_option.dart';
import '../models/discount.dart';
import '../models/product.dart';
import '../models/product_badge.dart';
import '../models/product_review.dart';
import '../utils/deskripsi_diskon.dart';
import '../utils/tax_calculator.dart';
import 'dialog_actions.dart';
import 'product_badge_chips.dart';

/// What [QuantityDialog] hands back once "Tambah ke Keranjang" is tapped:
/// the quantity, one chosen option per the product's level group (e.g.
/// spice/sugar level), and an optional free-text note — used by
/// customer/kasir/admin alike when adding a line to the cart.
class QuantityDialogResult {
  final int quantity;
  final Map<String, String> selectedLevels;
  final List<String> selectedToppings;
  final String? notes;

  const QuantityDialogResult({
    required this.quantity,
    required this.selectedLevels,
    this.selectedToppings = const [],
    this.notes,
  });
}

/// Popup shown when a product card is tapped: lets the cashier/customer
/// type/adjust the quantity, pick a level per variant group (e.g. Level
/// Pedas, Level Gula) the product offers, add an optional note, and see
/// the computed subtotal (qty × unit price) live before it's added to
/// the cart.
class QuantityDialog extends StatefulWidget {
  final Product product;
  final int initialQuantity;
  final Map<String, String>? initialLevels;

  /// Topping yang sudah dipilih sebelumnya — dipakai saat baris
  /// keranjang disunting kembali.
  final List<String>? initialToppings;
  final String? initialNotes;

  /// Resto's PPN rate — figures here must match the menu prices the
  /// customer just tapped, which are shown inclusive of PPN.
  final double ppnPercent;

  /// Menampilkan sisa stok. Mati untuk pelanggan — lihat
  /// [ProductGridCard.showStock].
  final bool showStock;

  /// True when reopened on a line already in the cart. Changes the
  /// confirm label from "Tambah" to "Simpan" and offers a delete, so
  /// removing something you added by mistake doesn't require fiddling
  /// the quantity down to zero.
  final bool editing;

  /// Bintang dan angka terjual menu ini, kalau sudah dimuat layarnya.
  final ProductStats? stats;

  /// Sedang kena promo hari ini.
  final bool sedangDiskon;

  /// Promo yang mengenai menu ini, untuk dijelaskan isinya.
  ///
  /// Label DISKON di kartunya cuma memberi tahu ada potongan, tidak
  /// berapa dan tidak syaratnya. Yang sudah tertarik lalu mengetuk
  /// menunya justru sedang menanyakan dua hal itu — dan sebelumnya
  /// jawabannya baru muncul di layar bayar, saat pesanannya sudah
  /// terlanjur disusun.
  final List<Discount> diskon;

  /// Nama menu lain, untuk menyebut isi paket bundling.
  final Map<String, String> namaMenu;

  const QuantityDialog({
    super.key,
    required this.product,
    this.initialQuantity = 1,
    this.initialLevels,
    this.initialToppings,
    this.initialNotes,
    this.ppnPercent = 0,
    this.editing = false,
    this.showStock = false,
    this.stats,
    this.sedangDiskon = false,
    this.diskon = const [],
    this.namaMenu = const {},
  });

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  int _quantity = 1;
  late Map<String, String> _selectedLevels;

  /// Topping yang dipilih. Kosong secara bawaan — topping adalah
  /// tambahan, dan tambahan yang tercentang sendiri berarti pelanggan
  /// membayar sesuatu yang tidak pernah dia minta.
  late Set<String> _selectedToppings;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity < 1 ? 1 : widget.initialQuantity;
    _qtyCtrl = TextEditingController(text: '$_quantity');
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
    // Default every level group to its first option so a selection is
    // always present without the pemesan needing to touch each dropdown.
    _selectedLevels = {
      for (final group in widget.product.levelGroups)
        group: widget.initialLevels?[group] ??
            LevelGroupRegistry.firstOptionOf(group) ??
            '',
    };
    _selectedToppings = {...?widget.initialToppings};
  }

  /// Batas topping sudah tercapai — sisanya dimatikan, bukan
  /// disembunyikan. Pilihan yang lenyap membuat orang mengira menunya
  /// berubah; pilihan yang meredup memberi tahu ada batas.
  bool get _batasTercapai =>
      _selectedToppings.length >= widget.product.effectiveMaxToppings;

  /// Sisa stok hanya untuk yang berhak melihatnya, dan hanya kalau
  /// restonya memang menghitungnya.
  String get _stockNote =>
      widget.showStock && widget.product.stock > 0
          ? ' • Stok: ${widget.product.stock}'
          : '';

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Batas atas jumlah pesanan.
  ///
  /// Angka stok cuma membatasi kalau restonya memang mengisinya. Yang
  /// membiarkannya 0 bukan berarti tidak punya barang — dia cuma tidak
  /// menghitungnya, dan dulu itu membuat semua jumlah terkunci di 1.
  int get _maxQuantity =>
      widget.product.stock > 0 ? widget.product.stock : 999;

  void _setQuantity(int value) {
    final clamped = value.clamp(1, _maxQuantity);
    setState(() {
      _quantity = clamped;
      _qtyCtrl.text = '$_quantity';
      _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
    });
  }

  int _withPpn(int amount) => menuPrice(
        amount,
        ppnPercent: widget.ppnPercent,
        ppnExempt: widget.product.ppnExempt,
      );

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    // Extra price from whichever level options are currently selected
    // (e.g. "Ukuran: Large") — added on top of the base price per item.
    final priceDelta = _selectedLevels.entries.fold<int>(
          0,
          (sum, e) => sum + widget.product.priceDeltaFor(e.key, e.value),
        ) +
        _selectedToppings.fold<int>(
          0,
          (sum, t) => sum + widget.product.toppingPrice(t),
        );
    // Priced the way the customer sees it on the menu: original + PPN.
    // The pre-tax figures are what gets stored on the order; this is
    // display only, so the dialog can't quote a different number than
    // the grid card the customer tapped.
    // Rounded on the combined figure, exactly as the cart does it, so
    // the subtotal shown here can't be a rupiah off what gets added.
    final unitPrice = _withPpn(widget.product.price + priceDelta);
    final shownBase = _withPpn(widget.product.price);
    final shownDelta = unitPrice - shownBase;
    final subtotal = unitPrice * _quantity;

    return AlertDialog(
      title: Text(widget.product.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.product.photoBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                // 4:3, bukan tinggi tetap 120.
                //
                // Tinggi tetap pada kotak selebar dialog memotong
                // fotonya jadi pita — yang tersisa cuma sejalur tengah
                // gambarnya, dan makanannya jadi tidak dikenali. Dengan
                // perbandingan sisi, tingginya ikut lebar dialognya di
                // layar mana pun.
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(
                    byteGambar(widget.product.photoBase64!),
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (widget.product.photoBase64 != null) const SizedBox(height: 12),
            Text(
              priceDelta == 0
                  ? '${currency.format(shownBase)} / item$_stockNote'
                  : '${currency.format(unitPrice)} / item (dasar ${currency.format(shownBase)} + ${currency.format(shownDelta)})$_stockNote',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            // Label dan bintang diulang di sini, tidak dianggap sudah
            // terbaca di kartunya. Inilah layar tempat orang benar-benar
            // memutuskan — dan yang membukanya dari keranjang tidak
            // pernah melihat kartunya sama sekali.
            () {
              final badges = [
                ...badgeDariKodeList(widget.product.badges),
                if (widget.sedangDiskon) ProductBadge.diskon,
              ];
              if (badges.isEmpty && widget.stats == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final b in urutkanBadge(badges))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: kBadgeWarna[b],
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          kBadgeLabel[b]!,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ProductStatsLine(stats: widget.stats, fontSize: 11.5),
                  ],
                ),
              );
            }(),
            () {
              final promo = deskripsiDiskon(
                diskon: widget.diskon,
                productId: widget.product.id,
                namaMenu: widget.namaMenu,
              );
              if (promo.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [for (final p in promo) _KartuPromo(promo: p)],
                ),
              );
            }(),
            if (widget.product.description != null && widget.product.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.product.description!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (widget.product.levelGroups.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final group in widget.product.levelGroups) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(group,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _selectedLevels[group],
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: LevelGroupRegistry.optionsOf(group)
                      .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedLevels[group] = value);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (widget.product.toppings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.product.maxToppings > 0
                      ? 'Topping (maks. ${widget.product.maxToppings})'
                      : 'Topping (opsional)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in widget.product.toppings)
                    FilterChip(
                      label: Text(t.price == 0
                          ? t.name
                          : '${t.name} +${currency.format(_withPpn(t.price))}'),
                      selected: _selectedToppings.contains(t.name),
                      // Yang sudah dipilih tetap bisa dilepas walau
                      // batasnya tercapai — kalau ikut mati, satu-satunya
                      // jalan mengubah pilihan adalah menutup dialognya.
                      onSelected: _batasTercapai &&
                              !_selectedToppings.contains(t.name)
                          ? null
                          : (pilih) => setState(() {
                                if (pilih) {
                                  _selectedToppings.add(t.name);
                                } else {
                                  _selectedToppings.remove(t.name);
                                }
                              }),
                    ),
                ],
              ),
              if (_batasTercapai && widget.product.maxToppings > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Sudah ${widget.product.maxToppings} topping — lepas satu '
                    'dulu untuk mengganti.',
                    style: TextStyle(
                        fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
                  ),
                ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Catatan (opsional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Contoh: tanpa bawang, pisah kuah, dll',
                // Lebih pudar dan tidak tebal — ini contoh, bukan isi.
                //
                // Teks contoh yang sepekat teks sungguhan terbaca
                // seperti catatan yang sudah tertulis: kasir
                // membacakannya ke dapur, dan dapur menyiapkan pesanan
                // "pisah kuah" yang tidak pernah diminta siapa pun.
                hintStyle: TextStyle(
                  color: MerchantPosTheme.mutedOf(context).withOpacity(0.7),
                  fontWeight: FontWeight.normal,
                  fontSize: 13.5,
                ),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: () => _setQuantity(_quantity - 1),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _qtyCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(border: InputBorder.none),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) _setQuantity(parsed);
                    },
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: () => _setQuantity(_quantity + 1),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontSize: 16)),
                Text(
                  currency.format(subtotal),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogActions(
              confirmLabel: widget.editing ? 'Simpan Perubahan' : 'Tambah ke Keranjang',
              onConfirm: () => Navigator.of(context).pop(QuantityDialogResult(
                quantity: _quantity,
                selectedLevels: _selectedLevels,
                selectedToppings: _selectedToppings.toList(),
                notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
              )),
              onCancel: () => Navigator.of(context).pop(),
            ),
            if (widget.editing)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus dari keranjang'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(
                  const QuantityDialogResult(quantity: 0, selectedLevels: {}),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Satu promo yang mengenai menu ini, dijelaskan isinya.
///
/// Diletakkan di dialog pesan, bukan di kartu menu: kartu selebar
/// setengah layar tidak muat menampung syarat jumlah dan daftar isi
/// paket, dan memaksakannya berarti kalimat terpotong — yang justru
/// lebih menyesatkan daripada tidak ada.
class _KartuPromo extends StatelessWidget {
  final DeskripsiDiskon promo;

  const _KartuPromo({required this.promo});

  @override
  Widget build(BuildContext context) {
    const merah = Color(0xFFDC2626);
    final muted = MerchantPosTheme.mutedOf(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: merah.withOpacity(0.07),
        border: Border.all(color: merah.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sell_outlined, size: 15, color: merah),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  promo.judul,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: merah),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(promo.potongan,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(promo.syarat,
              style: TextStyle(fontSize: 12, color: muted, height: 1.35)),
          if (promo.paket.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Harus dibeli bersama: ${promo.paket.join(', ')}',
              style: TextStyle(fontSize: 12, color: muted, height: 1.35),
            ),
          ],
          if (promo.sampai != null) ...[
            const SizedBox(height: 4),
            Text(promo.sampai!,
                style: TextStyle(fontSize: 11.5, color: muted)),
          ],
        ],
      ),
    );
  }
}
