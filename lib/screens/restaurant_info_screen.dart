import '../models/opening_hours.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../utils/resto_location.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/edit_action_bar.dart';
import '../widgets/resto_location_field.dart';
import '../widgets/logo_picker.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';

/// Lets the Admin update this restaurant's category and address —
/// shown to customers at the top of their self-order screen once they
/// scan a table QR. The name itself is read-only here; only Super Admin
/// can rename a resto (via List Resto), since it's the merchant's
/// identifying label across the whole platform.
///
/// Opens in view-only mode (all fields greyed out) — tap "Edit" to make
/// Kategori/Alamat editable, so nothing gets changed by accident just by
/// opening this screen.
class RestaurantInfoScreen extends StatefulWidget {
  const RestaurantInfoScreen({super.key});

  @override
  State<RestaurantInfoScreen> createState() => _RestaurantInfoScreenState();
}

class _RestaurantInfoScreenState extends State<RestaurantInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  /// Fasilitas yang tersedia di tempat ini.
  final List<String> _fasilitas = [];

  /// Jam buka per hari. Hari yang tidak ada di sini berarti tutup.
  final Map<int, (String, String)> _jam = {};
  final _fasilitasBaru = TextEditingController();

  /// Yang paling sering dipakai, ditawarkan sebagai ketukan cepat.
  ///
  /// Bukan daftar tertutup — yang punya sesuatu di luar ini tetap bisa
  /// mengetiknya sendiri. Daftar yang menghambat pemiliknya
  /// menggambarkan tempatnya sendiri lebih buruk daripada daftar yang
  /// sesekali salah ketik.
  static const _fasilitasUmum = [
    'AC',
    'Smoking Area',
    'Kids Friendly',
    'Live Music',
    'WiFi Gratis',
    'Parkir Luas',
    'Mushola',
    'Toilet',
    'Colokan Listrik',
    'Ramah Difabel',
  ];
  final _repo = RestaurantRepository();
  bool _loading = true;
  bool _editing = false;
  /// Rates are Finance's to set (Mapping GL Account), not the Admin's —
  /// carried through unchanged so saving info here can't reset them.
  double? _latitude;
  double? _longitude;
  bool _locating = false;

  double _ppnPercent = 0;
  double _servicePercent = 0;

  bool _saving = false;

  /// Captured when Edit is tapped so Batal can restore it verbatim.
  Map<String, Object?> _snapshot = const {};
  String? _selectedCategory;

  /// The logo is a single shared column — an Admin can replace or remove
  /// one uploaded by Super Admin, and vice versa.
  /// Carried through save untouched. Without it the upsert would default
  /// active back to true, letting an Admin silently reactivate a resto
  /// that Super Admin had switched off.
  bool _active = true;

  /// Cara makan yang dilayani resto ini.
  ///
  /// Bisa diubah admin restonya sendiri, bukan cuma Super Admin: yang
  /// tahu mejanya sedang direnovasi atau dapurnya berhenti membungkus
  /// adalah orang di tempat itu, dan menunggu Super Admin berarti
  /// pesanan yang tidak bisa dilayani terus masuk sampai dia sempat.
  ///
  /// Ikut disimpan apa adanya walau tidak disentuh — toMap() selalu
  /// mengirim kedua kolomnya, jadi tanpa dimuat lebih dulu, menyimpan
  /// perubahan alamat saja sudah menyalakan ulang keduanya.
  bool _dineIn = true;
  bool _takeAway = true;
  bool _snapshotDineIn = true;
  bool _snapshotTakeAway = true;

  String? _existingLogo;
  File? _pickedLogo;
  bool _logoRemoved = false;
  File? _snapshotPickedLogo;
  String? _snapshotExistingLogo;
  bool _snapshotLogoRemoved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final restoId = context.read<AuthProvider>().restoId!;
    final resto = await _repo.getOnce(restoId);
    if (resto != null) {
      _nameCtrl.text = resto.name;
      _addressCtrl.text = resto.address;
      _latitude = resto.latitude;
      _longitude = resto.longitude;
      _ppnPercent = resto.ppnPercent;
      _servicePercent = resto.servicePercent;
      _phoneCtrl.text = resto.phone ?? '';
      _fasilitas
        ..clear()
        ..addAll(resto.facilities);
      _jam
        ..clear()
        ..addAll(resto.openingHours.perHari);
      _selectedCategory = resto.category;
      _existingLogo = resto.logoBase64;
      _active = resto.active;
      _dineIn = resto.dineInEnabled;
      _takeAway = resto.takeAwayEnabled;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _fasilitasBaru.dispose();
    super.dispose();
  }

  void _startEdit() {
    _snapshot = {
      'address': _addressCtrl.text,
      'lat': _latitude,
      'lng': _longitude,
      'phone': _phoneCtrl.text,
      'category': _selectedCategory,
    };
    _snapshotDineIn = _dineIn;
    _snapshotTakeAway = _takeAway;
    _snapshotPickedLogo = _pickedLogo;
    _snapshotExistingLogo = _existingLogo;
    _snapshotLogoRemoved = _logoRemoved;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _addressCtrl.text = _snapshot['address'] as String? ?? '';
    _latitude = _snapshot['lat'] as double?;
    _longitude = _snapshot['lng'] as double?;
    _phoneCtrl.text = _snapshot['phone'] as String? ?? '';
    _selectedCategory = _snapshot['category'] as String?;
    _dineIn = _snapshotDineIn;
    _takeAway = _snapshotTakeAway;
    _pickedLogo = _snapshotPickedLogo;
    _existingLogo = _snapshotExistingLogo;
    _logoRemoved = _snapshotLogoRemoved;
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

  /// Mengambil titik dari GPS lalu mengisi alamatnya sekalian.
  ///
  /// Alamatnya hanya diisikan kalau kolomnya masih kosong: alamat hasil
  /// pembacaan peta berhenti di tingkat jalan, sedangkan yang sudah
  /// diketik biasanya memuat "ruko blok C nomor 4" — justru bagian yang
  /// dicari orang yang mau datang, dan tidak boleh tertimpa.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    final toast = AppToast.of(context);
    try {
      final position = await currentPosition();
      final address = await addressOf(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        if (address != null && _addressCtrl.text.trim().isEmpty) {
          _addressCtrl.text = address;
        }
        _locating = false;
      });
      toast.show(address == null
              ? 'Lokasi tersimpan. Alamatnya silakan diisi manual.'
              : 'Lokasi & alamat terisi. Silakan lengkapi detailnya.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      toast.show('$e');
    }
  }

  /// Menerima koordinat atau tautan Google Maps yang ditempel.
  ///
  /// Berguna saat yang mengisi tidak sedang berada di restonya — mereka
  /// tinggal meminta pemiliknya "share lokasi" lalu menempelkannya.
  Future<void> _pasteCoordinates() async {
    final toast = AppToast.of(context);
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Tempel Koordinat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tempel koordinat (mis. -6.2088, 106.8456) atau tautan Google Maps '
              'yang dibagikan.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(isDense: true, hintText: 'lat, lng'),
              maxLines: 2,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Pakai Titik Ini',
            onConfirm: () => Navigator.pop(dialogContext, ctrl.text),
          ),
        ],
      ),
    );
    if (result == null) return;

    final point = parseCoordinates(result);
    if (!mounted) return;
    if (point == null) {
      toast.show('Koordinat tidak terbaca. Contoh: -6.2088, 106.8456');
      return;
    }

    setState(() {
      _latitude = point.latitude;
      _longitude = point.longitude;
    });

    final address = await addressOf(point.latitude, point.longitude);
    if (!mounted || address == null || _addressCtrl.text.trim().isNotEmpty) return;
    setState(() => _addressCtrl.text = address);
  }

  /// Menambahkan fasilitas yang diketik sendiri.
  ///
  /// Yang sama diabaikan diam-diam, tanpa pesan galat: mengetik ulang
  /// sesuatu yang sudah ada bukan kesalahan yang perlu ditegur.
  void _tambahFasilitas() {
    final teks = _fasilitasBaru.text.trim();
    if (teks.isEmpty) return;
    setState(() {
      if (!_fasilitas.any((f) => f.toLowerCase() == teks.toLowerCase())) {
        _fasilitas.add(teks);
      }
      _fasilitasBaru.clear();
    });
  }

  /// Satu baris jam buka: hari, saklarnya, dan dua jamnya.
  Widget _barisJam(int hari) {
    final ada = _jam.containsKey(hari);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                Checkbox(
                  value: ada,
                  visualDensity: VisualDensity.compact,
                  onChanged: !_editing
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              // Jam bawaannya diisi supaya yang
                              // mencentang tidak menyimpan hari buka
                              // tanpa jam sama sekali.
                              _jam[hari] = ('08:00', '22:00');
                            } else {
                              _jam.remove(hari);
                            }
                          }),
                ),
                Expanded(
                  child: Text(OpeningHours.namaHari[hari]!,
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          Expanded(
            child: !ada
                ? Text('Tutup',
                    style: TextStyle(
                        fontSize: 13, color: MerchantPosTheme.mutedOf(context)))
                : Row(
                    children: [
                      Expanded(child: _pilihJam(hari, buka: true)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('–'),
                      ),
                      Expanded(child: _pilihJam(hari, buka: false)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pilihJam(int hari, {required bool buka}) {
    final nilai = buka ? _jam[hari]!.$1 : _jam[hari]!.$2;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 38),
      ),
      onPressed: !_editing
          ? null
          : () async {
              final bagian = nilai.split(':');
              final awal = TimeOfDay(
                hour: int.tryParse(bagian.first) ?? 8,
                minute: int.tryParse(bagian.last) ?? 0,
              );
              final pilih =
                  await showTimePicker(context: context, initialTime: awal);
              if (pilih == null || !mounted) return;
              final teks = '${pilih.hour.toString().padLeft(2, '0')}:'
                  '${pilih.minute.toString().padLeft(2, '0')}';
              setState(() {
                final lama = _jam[hari]!;
                _jam[hari] = buka ? (teks, lama.$2) : (lama.$1, teks);
              });
            },
      child: Text(nilai, style: const TextStyle(fontSize: 13)),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final toast = AppToast.of(context);
    final restoId = context.read<AuthProvider>().restoId!;
    setState(() => _saving = true);
    try {
      String? logoBase64 = _existingLogo;
      if (_pickedLogo != null) {
        logoBase64 = base64Encode(await _pickedLogo!.readAsBytes());
      } else if (_logoRemoved) {
        logoBase64 = null;
      }

      await _repo.update(Restaurant(
        id: restoId,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        ppnPercent: _ppnPercent,
        servicePercent: _servicePercent,
        category: _selectedCategory,
        logoBase64: logoBase64,
        active: _active,
        dineInEnabled: _dineIn,
        takeAwayEnabled: _takeAway,
        facilities: List<String>.from(_fasilitas),
        openingHours: OpeningHours(Map<int, (String, String)>.from(_jam)),
      ));
      // Keep local state in step with what was just written, so a second
      // edit round doesn't re-upload or resurrect a removed logo.
      _existingLogo = logoBase64;
      _pickedLogo = null;
      _logoRemoved = false;
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      toast.show('Info merchant disimpan');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast.show('Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Info Merchant'),
        actions: [
          if (!_loading && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Bukan isian yang dimatikan, tapi keterangan biasa.
                    //
                    // Nama resto tidak pernah bisa diubah dari halaman
                    // ini oleh siapa pun, jadi kotak isian yang selalu
                    // abu-abu cuma menjanjikan sesuatu yang tidak
                    // pernah terjadi. Label mengambangnya juga yang
                    // terpotong di tepi atas begitu daftarnya tergulir
                    // — label semacam itu memang selalu terpotong di
                    // area gulir, dan di sini ia tidak perlu ada.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: MerchantPosTheme.disabledFillOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: MerchantPosTheme.borderOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nama Merchant',
                            style: TextStyle(
                              fontSize: 12,
                              color: MerchantPosTheme.mutedOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _nameCtrl.text,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hanya Merchant-POS Admin yang bisa ubah nama merchant, '
                      'silahkan hubungi Merchant-POS Admin jika ada perubahan '
                      'nama merchant',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: MerchantPosTheme.mutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        label: requiredLabel('Kategori Merchant'),
                        filled: !_editing,
                        fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                      ),
                      isExpanded: true,
                      items: kRestaurantCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: _editing ? (value) => setState(() => _selectedCategory = value) : null,
                      validator: (v) => v == null ? 'Wajib dipilih' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressCtrl,
                      enabled: _editing,
                      decoration: InputDecoration(
                        label: requiredLabel('Alamat'),
                        filled: !_editing,
                        fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                      ),
                      maxLines: 2,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      enabled: _editing,
                      decoration: InputDecoration(
                        labelText: 'Nomor HP (opsional)',
                        helperText: 'Ditampilkan di struk',
                        filled: !_editing,
                        fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: phoneFormatters,
                      validator: (v) => validatePhone(v, required: false),
                    ),
                    const SizedBox(height: 16),
                    RestoLocationField(
                      latitude: _latitude,
                      longitude: _longitude,
                      enabled: _editing,
                      busy: _locating,
                      onUseCurrent: _useCurrentLocation,
                      onPaste: _pasteCoordinates,
                      onClear: () => setState(() {
                        _latitude = null;
                        _longitude = null;
                      }),
                      onPicked: (lat, lng) => setState(() {
                        _latitude = lat;
                        _longitude = lng;
                      }),
                    ),
                    const SizedBox(height: 20),
                    const Text('Cara Makan yang Dilayani',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      'Yang dimatikan tidak muncul sebagai pilihan saat '
                      'checkout, baik di kasir maupun di HP pelanggan.',
                      style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Dine In'),
                      subtitle: const Text('Makan di tempat, pakai nomor meja',
                          style: TextStyle(fontSize: 11.5)),
                      value: _dineIn,
                      // Yang terakhir menyala tidak bisa dimatikan —
                      // resto tanpa satu pun cara makan tidak bisa
                      // menerima pesanan sama sekali. Untuk berhenti
                      // berjualan sudah ada tombol Aktif/Nonaktif.
                      onChanged: !_editing || !_takeAway
                          ? null
                          : (v) => setState(() => _dineIn = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Take Away'),
                      subtitle: const Text('Dibungkus, pakai nama pemesan',
                          style: TextStyle(fontSize: 11.5)),
                      value: _takeAway,
                      onChanged: !_editing || !_dineIn
                          ? null
                          : (v) => setState(() => _takeAway = v),
                    ),
                    const SizedBox(height: 22),
                    const Text('Jam Buka',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      'Hari yang tidak dicentang berarti tutup. Ditampilkan '
                      'ke pelanggan di Info Merchant.',
                      style: TextStyle(
                          fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 8),
                    for (var h = 1; h <= 7; h++) _barisJam(h),
                    const SizedBox(height: 22),
                    const Text('Fasilitas',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      'Ditampilkan ke pelanggan saat memilih tempat. Yang '
                      'membuat orang memilih satu tempat dibanding lainnya '
                      'sering bukan menunya.',
                      style: TextStyle(
                          fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 10),
                    if (_fasilitas.isEmpty && !_editing)
                      Text('Belum ada fasilitas yang dicantumkan.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: MerchantPosTheme.mutedOf(context)))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in _fasilitas)
                            Chip(
                              label: Text(f,
                                  style: const TextStyle(fontSize: 12.5)),
                              onDeleted: _editing
                                  ? () => setState(() => _fasilitas.remove(f))
                                  : null,
                            ),
                        ],
                      ),
                    if (_editing) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _fasilitasBaru,
                                textCapitalization: TextCapitalization.words,
                                onSubmitted: (_) => _tambahFasilitas(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Tulis fasilitas lain',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 104,
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(104, 44),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: _tambahFasilitas,
                              child: const Text('Tambah'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Yang sering dipakai',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: MerchantPosTheme.mutedOf(context))),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in _fasilitasUmum)
                            if (!_fasilitas.contains(f))
                              ActionChip(
                                label: Text(f,
                                    style: const TextStyle(fontSize: 12)),
                                onPressed: () =>
                                    setState(() => _fasilitas.add(f)),
                              ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    LogoPicker(
                      existingBase64: _existingLogo,
                      picked: _pickedLogo,
                      removed: _logoRemoved,
                      enabled: _editing,
                      onChanged: ({File? picked, bool removed = false}) => setState(() {
                        _pickedLogo = picked;
                        _logoRemoved = removed;
                      }),
                    ),
                    const SizedBox(height: 24),
                    if (_editing)
                      EditActionBar(
                        onCancel: _cancelEdit,
                        onSave: _save,
                        saving: _saving,
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Titik lokasi resto pada layar Info Resto.
