import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/discount_repository.dart';
import '../models/discount.dart';
import '../models/level_option.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../theme.dart';
import '../utils/promo_period.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/promo_period_fields.dart';
import '../widgets/required_label.dart';
import '../widgets/responsive.dart';

/// Menu Diskon — kasir, admin, dan owner.
///
/// Dua bentuk yang benar-benar berbeda, sengaja dalam satu daftar:
/// diskon yang menempel pada menu tertentu (satu menu, atau beberapa
/// sekaligus untuk bundling), dan diskon yang menempel pada nilai
/// tagihan.
class DiscountScreen extends StatefulWidget {
  const DiscountScreen({super.key});

  @override
  State<DiscountScreen> createState() => _DiscountScreenState();
}

class _DiscountScreenState extends State<DiscountScreen> {
  final _repo = DiscountRepository();
  final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<Discount> _discounts = [];
  bool _loading = true;
  String? _error;

  String? get _restoId => context.read<AuthProvider>().restoId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final restoId = _restoId;
    if (restoId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.getForResto(restoId);
      if (!mounted) return;
      setState(() {
        _discounts = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _edit({Discount? existing}) async {
    final restoId = _restoId;
    if (restoId == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _DiscountFormScreen(existing: existing, restoId: restoId),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Discount d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline, size: 38, color: Colors.red),
        title: Text('Hapus "${d.name}"?'),
        content: const Text(
          'Transaksi yang sudah memakai diskon ini tidak berubah — '
          'potongannya sudah tercatat di strukmya masing-masing.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.delete(d.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diskon')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Gagal memuat: $_error',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _load, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : _discounts.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ResponsiveCenter(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              16, 14, 16, kFabSafeBottom),
                          itemCount: _discounts.length,
                          itemBuilder: (context, i) => _DiscountCard(
                            discount: _discounts[i],
                            currency: _currency,
                            onEdit: () => _edit(existing: _discounts[i]),
                            onDelete: () => _delete(_discounts[i]),
                            onToggle: (v) async {
                              await _repo.setActive(_discounts[i].id, v);
                              _load();
                            },
                          ),
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Diskon Baru'),
      ),
    );
  }
}

class _DiscountCard extends StatelessWidget {
  final Discount discount;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _DiscountCard({
    required this.discount,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'id_ID');
    final periode = [
      if (discount.startsOn != null) 'mulai ${fmt.format(discount.startsOn!)}',
      if (discount.endsOn != null) 'sampai ${fmt.format(discount.endsOn!)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(discount.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  PeriodBadge(
                      period: discount.period, active: discount.active),
                  Switch(
                    value: discount.active,
                    onChanged: onToggle,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: MerchantPosTheme.brandOf(context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      discount.kind == DiscountKind.percent
                          ? '${discount.value}%'
                          : currency.format(discount.value),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: MerchantPosTheme.brandOf(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      discount.basis == DiscountBasis.minPurchase
                          ? 'Belanja ${discount.compare == MinCompare.atLeast ? '≥' : '>'} '
                              '${currency.format(discount.minPurchase)}'
                          : discount.items.length == 1
                              ? discount.items.first.label
                              : '${discount.items.length} menu · semua harus ada',
                      style: TextStyle(
                          fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 19, color: Colors.red),
                    tooltip: 'Hapus',
                    onPressed: onDelete,
                  ),
                ],
              ),
              if (periode.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(periode,
                    style: TextStyle(
                        fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined,
                size: 60, color: MerchantPosTheme.mutedOf(context).withOpacity(0.4)),
            const SizedBox(height: 14),
            Text('Belum ada diskon',
                style: TextStyle(
                    fontSize: 15, color: MerchantPosTheme.mutedOf(context))),
            const SizedBox(height: 6),
            Text(
              'Bisa untuk menu tertentu — satu atau beberapa sekaligus untuk '
              'bundling — atau untuk seluruh tagihan yang mencapai nilai '
              'minimum.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: MerchantPosTheme.mutedOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulir satu aturan diskon.
class _DiscountFormScreen extends StatefulWidget {
  final Discount? existing;
  final String restoId;

  const _DiscountFormScreen({this.existing, required this.restoId});

  @override
  State<_DiscountFormScreen> createState() => _DiscountFormScreenState();
}

class _DiscountFormScreenState extends State<_DiscountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = DiscountRepository();

  @override
  void initState() {
    super.initState();
    // Daftar produknya dimuat sendiri kalau belum ada isinya.
    //
    // Sebelumnya layar ini menumpang daftar yang diisi layar lain —
    // Input Pesanan atau Kelola Produk. Dari hub Admin itu kebetulan
    // selalu benar, karena Kelola Produk hampir selalu dibuka lebih
    // dulu. Dari hub Kasir tidak: yang membuka Diskon langsung
    // disambut "Belum ada produk di resto ini", lalu menyimpulkan
    // restonya memang belum punya menu.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final products = context.read<ProductProvider>();
      if (products.products.isNotEmpty) return;
      setState(() => _memuatProduk = true);
      try {
        await products.syncWithResto(widget.restoId);
      } finally {
        if (mounted) setState(() => _memuatProduk = false);
      }
    });
  }

  /// Sedang menarik daftar produknya.
  ///
  /// Dibedakan dari "kosong" dengan sengaja: keduanya terlihat sama di
  /// layar, tapi yang satu berarti tunggu sebentar dan yang satu lagi
  /// berarti buat produknya dulu. Menyamakannya membuat orang menyerah
  /// pada layar yang sebenarnya sedang bekerja.
  bool _memuatProduk = false;

  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _valueCtrl = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.kind == DiscountKind.percent
            ? '${widget.existing!.value}'
            : formatRupiahInput(widget.existing!.value),
  );
  late final _minCtrl = TextEditingController(
    text: widget.existing == null || widget.existing!.minPurchase == 0
        ? ''
        : formatRupiahInput(widget.existing!.minPurchase),
  );

  late DiscountBasis _basis = widget.existing?.basis ?? DiscountBasis.products;
  late DiscountKind _kind = widget.existing?.kind ?? DiscountKind.percent;
  late MinCompare _compare = widget.existing?.compare ?? MinCompare.atLeast;
  /// Menu yang ikut promo, berikut syarat jumlahnya masing-masing.
  /// Urutannya dipertahankan supaya barisnya tidak melompat-lompat
  /// setiap kali salah satu angkanya diubah.
  late final List<DiscountItem> _items = [...?widget.existing?.items];
  late DateTime? _startsOn = widget.existing?.startsOn;
  late DateTime? _endsOn = widget.existing?.endsOn;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_basis == DiscountBasis.products && _items.isEmpty) {
      showAppToast(context, 'Pilih minimal satu menu.', isError: true);
      return;
    }

    final periodError = validatePeriod(startsOn: _startsOn, endsOn: _endsOn);
    if (periodError != null) {
      showAppToast(context, periodError, isError: true);
      return;
    }

    final value = _kind == DiscountKind.percent
        ? int.tryParse(_valueCtrl.text.trim()) ?? 0
        : parseRupiah(_valueCtrl.text) ?? 0;

    setState(() => _saving = true);
    try {
      await _repo.save(Discount(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        restoId: widget.restoId,
        name: _nameCtrl.text.trim(),
        basis: _basis,
        kind: _kind,
        value: value,
        items: _basis == DiscountBasis.products ? _items : const [],
        minPurchase: _basis == DiscountBasis.minPurchase
            ? (parseRupiah(_minCtrl.text) ?? 0)
            : 0,
        compare: _compare,
        startsOn: _startsOn,
        endsOn: _endsOn,
        active: widget.existing?.active ?? true,
        createdBy: context.read<AuthProvider>().user?.email,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  /// Menyamakan daftar promo dengan menu yang baru dipilih.
  ///
  /// Yang sudah ada dipertahankan berikut aturannya — jumlah dan sasaran
  /// yang sudah disetel tidak boleh hilang hanya karena pemilihnya
  /// dibuka lagi untuk menambah satu menu.
  void _samakanPilihan(Set<String> dipilih) {
    setState(() {
      _items.removeWhere((i) => !dipilih.contains(i.productId));
      for (final id in dipilih) {
        if (_items.every((i) => i.productId != id)) {
          _items.add(DiscountItem(productId: id));
        }
      }
    });
  }

  Future<void> _pilihMenu(List<Product> products) async {
    final hasil = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => _MenuPickerScreen(
          products: products,
          terpilih: {for (final i in _items) i.productId},
        ),
      ),
    );
    if (hasil != null) _samakanPilihan(hasil);
  }

  Future<void> _aturMenu(Product product, int index) async {
    final hasil = await showModalBottomSheet<DiscountItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AturanMenuSheet(product: product, item: _items[index]),
    );
    if (hasil != null) setState(() => _items[index] = hasil);
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductProvider>().products;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Diskon Baru' : 'Ubah Diskon'),
      ),
      body: Form(
        key: _formKey,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Section(
                icon: Icons.sell_outlined,
                title: 'Nama Diskon',
                child: TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Paket Hemat Siang',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
              ),
              const SizedBox(height: 12),

              _Section(
                icon: Icons.rule_outlined,
                title: 'Berlaku Untuk',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<DiscountBasis>(
                      segments: [
                        for (final b in DiscountBasis.values)
                          ButtonSegment(
                              value: b, label: Text(kDiscountBasisLabels[b]!)),
                      ],
                      selected: {_basis},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _basis = v.first),
                    ),
                    const SizedBox(height: 14),
                    if (_basis == DiscountBasis.products)
                      _MenuTerpilih(
                        products: products,
                        memuat: _memuatProduk,
                        items: _items,
                        onPilih: () => _pilihMenu(products),
                        onAtur: _aturMenu,
                        onHapus: (i) => setState(() => _items.removeAt(i)),
                      )
                    else
                      _MinPurchaseFields(
                        controller: _minCtrl,
                        compare: _compare,
                        onCompareChanged: (v) => setState(() => _compare = v),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _Section(
                icon: Icons.percent,
                title: 'Potongan',
                child: Column(
                  children: [
                    SegmentedButton<DiscountKind>(
                      segments: const [
                        ButtonSegment(
                            value: DiscountKind.percent, label: Text('Persen')),
                        ButtonSegment(
                            value: DiscountKind.amount, label: Text('Rupiah')),
                      ],
                      selected: {_kind},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() {
                        _kind = v.first;
                        _valueCtrl.clear();
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _valueCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: _kind == DiscountKind.amount
                          ? [ThousandsInputFormatter()]
                          : null,
                      decoration: InputDecoration(
                        label: requiredLabel(
                            _kind == DiscountKind.percent ? 'Persen' : 'Nominal'),
                        hintText:
                            _kind == DiscountKind.percent ? '10' : '5.000',
                        prefixText: _kind == DiscountKind.amount ? 'Rp ' : null,
                        suffixText: _kind == DiscountKind.percent ? '%' : null,
                        // Tanpa ini, "Rp" dan "%" hanya muncul setelah
                        // ada isinya. Flutter menyembunyikan prefix dan
                        // suffix selama labelnya belum mengambang — jadi
                        // kolom kosong berisi petunjuk "5.000" terbaca
                        // seperti kolom yang sudah berisi lima ribu,
                        // tanpa satu pun tanda bahwa itu rupiah.
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        if (raw.isEmpty) return 'Wajib diisi';
                        if (_kind == DiscountKind.percent) {
                          final n = int.tryParse(raw);
                          if (n == null) return 'Harus angka';
                          if (n < 1 || n > 100) return 'Antara 1 sampai 100';
                        } else {
                          final n = parseRupiah(raw) ?? 0;
                          if (n <= 0) return 'Harus lebih dari 0';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _Section(
                icon: Icons.event_outlined,
                child: PromoPeriodFields(
                  startsOn: _startsOn,
                  endsOn: _endsOn,
                  onChanged: (s, e) => setState(() {
                    _startsOn = s;
                    _endsOn = e;
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
      // Tombolnya menetap di bawah, bukan ikut menggulung ke ujung
      // daftar. Formulir ini bisa panjang sekali begitu menunya banyak,
      // dan tombol simpan yang harus dicari dengan menggulir adalah
      // cara paling mudah membuat orang mengira isiannya belum lengkap.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ResponsiveCenter(
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Simpan'),
          ),
        ),
      ),
    );
  }
}

/// Satu blok formulir di dalam kartunya sendiri.
///
/// Formulir ini punya empat urusan yang benar-benar berbeda, dan
/// sebelumnya keempatnya berbaris sebagai satu kolom panjang yang
/// dipisah hanya oleh judul kecil. Kartu membuat batasnya terlihat
/// tanpa harus dibaca.
class _Section extends StatelessWidget {
  final IconData icon;
  final String? title;
  final Widget child;

  const _Section({required this.icon, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: MerchantPosTheme.brandOf(context)),
              const SizedBox(width: 8),
              Expanded(
                child: title == null
                    ? child
                    : Text(title!,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
            ],
          ),
          if (title != null) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }
}

/// Ringkasan menu yang ikut promo.
///
/// Daftar seluruh menu resto tidak lagi tinggal di formulir ini. Yang
/// dulu ada di sini adalah daftar bergulir di dalam halaman bergulir,
/// dan tiap menu yang dicentang membentangkan tiga kendali sekaligus di
/// tempatnya — sehingga memilih dua menu saja sudah membuat halamannya
/// tidak terbaca. Sekarang yang tampil hanya yang sudah dipilih, satu
/// baris masing-masing, dengan aturannya diringkas jadi satu kalimat.
class _MenuTerpilih extends StatelessWidget {
  final List<Product> products;
  final bool memuat;
  final List<DiscountItem> items;
  final VoidCallback onPilih;
  final void Function(Product product, int index) onAtur;
  final ValueChanged<int> onHapus;

  const _MenuTerpilih({
    required this.products,
    required this.memuat,
    required this.items,
    required this.onPilih,
    required this.onAtur,
    required this.onHapus,
  });

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);

    if (products.isEmpty) {
      return Row(
        children: [
          if (memuat) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: muted),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              memuat
                  ? 'Memuat daftar menu…'
                  : 'Belum ada produk di merchant ini.',
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          Text('Belum ada menu yang dipilih.',
              style: TextStyle(color: muted, fontSize: 12.5))
        else ...[
          if (items.length > 1) ...[
            Text(
              'Semua menu di bawah harus ada di keranjang. Kalau salah '
              'satu kurang, promonya tidak berlaku.',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
            const SizedBox(height: 10),
          ],
          for (var i = 0; i < items.length; i++)
            () {
              final item = items[i];
              final product = products.firstWhere(
                (p) => p.id == item.productId,
                orElse: () => products.first,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: MerchantPosTheme.softFillOf(context),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onAtur(product, i),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(ringkasanAturan(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5, color: muted)),
                              ],
                            ),
                          ),
                          Icon(Icons.tune, size: 16, color: muted),
                          IconButton(
                            icon: const Icon(Icons.close, size: 17),
                            visualDensity: VisualDensity.compact,
                            color: muted,
                            tooltip: 'Keluarkan dari promo',
                            onPressed: () => onHapus(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
        const SizedBox(height: 2),
        OutlinedButton.icon(
          onPressed: onPilih,
          icon: const Icon(Icons.add, size: 17),
          label: Text(items.isEmpty ? 'Pilih Menu' : 'Ubah Pilihan Menu'),
        ),
      ],
    );
  }
}

/// Aturan satu menu, diringkas jadi satu kalimat pendek.
String ringkasanAturan(DiscountItem item) {
  final jumlah = '${kQtyModeLabels[item.mode]} ${item.qty} pcs';
  final sasaran = item.targetLabel ?? 'seluruh harga menu';
  return '$jumlah · $sasaran';
}

/// Pemilih menu di halamannya sendiri, lengkap dengan pencarian.
///
/// Berdiri sendiri karena daftar menu sebuah merchant bisa puluhan
/// baris, dan daftar sepanjang itu tidak punya tempat di tengah
/// formulir tanpa menjadi kotak bergulir — yang berarti dua gulungan
/// bersarang, dan tidak ada cara memberitahu jari mana yang sedang
/// menggulung yang mana.
class _MenuPickerScreen extends StatefulWidget {
  final List<Product> products;
  final Set<String> terpilih;

  const _MenuPickerScreen({required this.products, required this.terpilih});

  @override
  State<_MenuPickerScreen> createState() => _MenuPickerScreenState();
}

class _MenuPickerScreenState extends State<_MenuPickerScreen> {
  late final Set<String> _terpilih = {...widget.terpilih};
  String _cari = '';

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    final kunci = _cari.trim().toLowerCase();
    final tampil = kunci.isEmpty
        ? widget.products
        : [
            for (final p in widget.products)
              if (p.name.toLowerCase().contains(kunci) ||
                  p.category.toLowerCase().contains(kunci))
                p,
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Menu'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _cari = v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 19),
                hintText: 'Cari menu…',
              ),
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: tampil.isEmpty
            ? Center(
                child: Text('Menu tidak ditemukan.',
                    style: TextStyle(color: muted)))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: tampil.length,
                itemBuilder: (_, i) {
                  final p = tampil[i];
                  return CheckboxListTile(
                    value: _terpilih.contains(p.id),
                    title: Text(p.name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(p.category,
                        style: TextStyle(fontSize: 11.5, color: muted)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _terpilih.add(p.id);
                      } else {
                        _terpilih.remove(p.id);
                      }
                    }),
                  );
                },
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ResponsiveCenter(
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _terpilih),
            child: Text(_terpilih.isEmpty
                ? 'Selesai'
                : 'Pakai ${_terpilih.length} Menu'),
          ),
        ),
      ),
    );
  }
}

/// Aturan satu menu, disetel di lembar yang terbuka dari bawah.
///
/// Dipisahkan dari daftar supaya tiga kendali yang berbeda artinya —
/// berapa yang harus dibeli, dibandingkan bagaimana, dan bagian mana
/// yang dipotong — punya ruang untuk diberi judul masing-masing alih
/// alih berdesakan dalam satu baris selebar 200 piksel.
class _AturanMenuSheet extends StatefulWidget {
  final Product product;
  final DiscountItem item;

  const _AturanMenuSheet({required this.product, required this.item});

  @override
  State<_AturanMenuSheet> createState() => _AturanMenuSheetState();
}

class _AturanMenuSheetState extends State<_AturanMenuSheet> {
  late DiscountItem _item = widget.item;

  bool _punya(DiscountTarget t) => _item.targets.contains(t);

  void _ubahSasaran(DiscountTarget t, bool dipilih) {
    final daftar = [..._item.targets];
    daftar.remove(t);
    if (dipilih) daftar.add(t);
    setState(() => _item = _item.copyWith(targets: daftar));
  }

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: MerchantPosTheme.borderOf(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.product.name,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),

          Text('Berapa yang harus dibeli',
              style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<QtyMode>(
                  segments: [
                    for (final m in QtyMode.values)
                      ButtonSegment(value: m, label: Text(kQtyModeLabels[m]!)),
                  ],
                  selected: {_item.mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => _item = _item.copyWith(mode: v.first)),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle:
                        WidgetStateProperty.all(const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _StepperJumlah(
                qty: _item.qty,
                onChanged: (n) => setState(() => _item = _item.copyWith(qty: n)),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Text('Bagian mana yang dipotong',
              style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 2),
          Text(
            'Boleh lebih dari satu. Yang dicentang dijumlahkan, bukan '
            'dipilih salah satu.',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: MerchantPosTheme.borderOf(context)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                // Seluruh harga menu berdiri sendiri: mencentangnya
                // mematikan sisanya, karena ia sudah mencakup semuanya.
                // Membiarkan keduanya tercentang berarti tambahan harga
                // dipotong dua kali.
                CheckboxListTile(
                  dense: true,
                  value: _item.targets.isEmpty,
                  title: const Text('Seluruh harga menu',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: Text('Termasuk topping dan tambahan yang dipilih '
                      'pemesan', style: TextStyle(fontSize: 11, color: muted)),
                  onChanged: (v) {
                    if (v != true) return;
                    setState(() => _item = _item.copyWith(targets: const []));
                  },
                ),
                const Divider(height: 1),
                _BarisSasaran(
                  judul: 'Harga menu utama',
                  keterangan: 'Hanya harga menunya, tanpa tambahan apa pun',
                  target: const DiscountTarget.menuUtama(),
                  dipilih: _punya(const DiscountTarget.menuUtama()),
                  onUbah: _ubahSasaran,
                ),
                for (final g in widget.product.levelGroups)
                  for (final o in LevelGroupRegistry.optionsOf(g))
                    if (widget.product.priceDeltaFor(g, o) > 0)
                      _BarisSasaran(
                        judul: '$g: $o',
                        keterangan: 'Tambahan '
                            '${formatRupiahInput(widget.product.priceDeltaFor(g, o))}',
                        target: DiscountTarget.level(g, o),
                        dipilih: _punya(DiscountTarget.level(g, o)),
                        onUbah: _ubahSasaran,
                      ),
                for (final t in widget.product.toppings)
                  if (t.price > 0)
                    _BarisSasaran(
                      judul: 'Topping ${t.name}',
                      keterangan: 'Tambahan ${formatRupiahInput(t.price)}',
                      target: DiscountTarget.topping(t.name),
                      dipilih: _punya(DiscountTarget.topping(t.name)),
                      onUbah: _ubahSasaran,
                    ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => Navigator.pop(context, _item),
            child: const Text('Simpan Aturan'),
          ),
        ],
      ),
    );
  }
}

/// Kurang, angka, tambah — tanpa papan ketik.
///
/// Jumlah dalam promo hampir selalu satu digit, dan memunculkan papan
/// ketik angka untuk mengubah 1 jadi 2 berarti menutupi separuh lembar
/// yang sedang diisi.
class _StepperJumlah extends StatelessWidget {
  final int qty;
  final ValueChanged<int> onChanged;

  const _StepperJumlah({required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 17),
            visualDensity: VisualDensity.compact,
            onPressed: qty > 1 ? () => onChanged(qty - 1) : null,
          ),
          SizedBox(
            width: 26,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 17),
            visualDensity: VisualDensity.compact,
            onPressed: qty < 99 ? () => onChanged(qty + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Satu baris centang di daftar sasaran.
class _BarisSasaran extends StatelessWidget {
  final String judul;
  final String keterangan;
  final DiscountTarget target;
  final bool dipilih;
  final void Function(DiscountTarget target, bool dipilih) onUbah;

  const _BarisSasaran({
    required this.judul,
    required this.keterangan,
    required this.target,
    required this.dipilih,
    required this.onUbah,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      value: dipilih,
      title: Text(judul, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(keterangan,
          style: TextStyle(fontSize: 11, color: MerchantPosTheme.mutedOf(context))),
      onChanged: (v) => onUbah(target, v == true),
    );
  }
}

class _MinPurchaseFields extends StatelessWidget {
  final TextEditingController controller;
  final MinCompare compare;
  final ValueChanged<MinCompare> onCompareChanged;

  const _MinPurchaseFields({
    required this.controller,
    required this.compare,
    required this.onCompareChanged,
  });

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsInputFormatter()],
          decoration: InputDecoration(
            label: requiredLabel('Nilai Minimum'),
            prefixText: 'Rp ',
          ),
          validator: (v) {
            final n = parseRupiah(v ?? '') ?? 0;
            return n <= 0 ? 'Harus lebih dari 0' : null;
          },
        ),
        const SizedBox(height: 14),
        // Pembandingnya opsional dalam arti bawaan sudah dipilihkan (≥),
        // tapi tetap ditampilkan: transaksi yang nilainya pas di batas
        // adalah yang paling sering jadi perselisihan di meja kasir, dan
        // menebaknya diam-diam berarti kasir yang menanggung jawabannya.
        Text('Cara membandingkan', style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 8),
        SegmentedButton<MinCompare>(
          segments: [
            for (final c in MinCompare.values)
              ButtonSegment(value: c, label: Text(kMinCompareLabels[c]!)),
          ],
          selected: {compare},
          showSelectedIcon: false,
          onSelectionChanged: (v) => onCompareChanged(v.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11.5)),
          ),
        ),
      ],
    );
  }
}
