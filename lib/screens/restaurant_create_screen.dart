import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../utils/resto_location.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/edit_action_bar.dart';
import '../widgets/resto_location_field.dart';
import '../widgets/logo_picker.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';

/// Super Admin only: creates a brand-new restaurant row (a new tenant),
/// or — when [existing] is passed — edits one (from the "List Resto"
/// screen). Regular Admins can edit their own resto's info
/// (RestaurantInfoScreen) but can't create new ones or edit others —
/// only Super Admin has that RLS privilege.
///
/// Creating a new resto has nothing to accidentally overwrite, so it's
/// directly editable. Editing an existing one opens view-only (all
/// fields greyed) until "Edit" is tapped.
class RestaurantCreateScreen extends StatefulWidget {
  final Restaurant? existing;

  const RestaurantCreateScreen({super.key, this.existing});

  @override
  State<RestaurantCreateScreen> createState() => _RestaurantCreateScreenState();
}

/// Drops a trailing ".0" so a rate of 11 shows as "11", not "11.0".
String _pctText(double value) =>
    value == 0 ? '' : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class _RestaurantCreateScreenState extends State<RestaurantCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _ppnCtrl;
  late final TextEditingController _serviceCtrl;
  final _gatewayAccountCtrl = TextEditingController();
  String? _category;
  bool _dineIn = true;
  bool _takeAway = true;
  bool _snapshotDineIn = true;
  bool _snapshotTakeAway = true;
  double? _latitude;
  double? _longitude;
  bool _locating = false;
  String? _existingLogo;
  File? _pickedLogo;
  bool _logoRemoved = false;
  final _repo = RestaurantRepository();
  bool _saving = false;
  late bool _editing;

  /// What Batal restores. Unused when creating — cancelling a brand-new
  /// resto just leaves the form.
  Map<String, String?> _snapshot = const {};

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _idCtrl = TextEditingController(text: r?.id ?? '');
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _addressCtrl = TextEditingController(text: r?.address ?? '');
    _phoneCtrl = TextEditingController(text: r?.phone ?? '');
    // Resto baru berangkat dari tarif yang paling lazim dipakai
    // restoran di Indonesia, sama dengan bawaan kolomnya di database.
    // Nol terlihat aman, tapi artinya menjual tanpa memuat pajak sampai
    // ada yang ingat menyetelnya — dan selisih itu tidak bisa ditagih
    // ulang ke pelanggan yang sudah pulang.
    _ppnCtrl = TextEditingController(text: _pctText(r?.ppnPercent ?? 11));
    _serviceCtrl = TextEditingController(text: _pctText(r?.servicePercent ?? 5));
    _category = r?.category;
    _latitude = r?.latitude;
    _longitude = r?.longitude;
    _dineIn = r?.dineInEnabled ?? true;
    _takeAway = r?.takeAwayEnabled ?? true;
    _existingLogo = r?.logoBase64;
    _editing = !_isEditing;
    if (_isEditing) _loadGatewayAccount(r!.id);
  }

  /// Pengenal sub-akun Xendit resto ini.
  ///
  /// Tempatnya di sini, bukan di Pengaturan Pembayaran milik Finance.
  /// Sub-akun dibuat di akun Xendit Merchant-POS dan pengenalnya ditentukan
  /// Xendit, bukan restonya — orang resto tidak punya cara mengetahui
  /// nilainya, tidak punya cara memeriksa benar atau salahnya, dan
  /// salah ketik satu huruf mengirim seluruh pembayaran QRIS-nya ke
  /// sub-akun resto lain. Yang memasangnya harus orang yang sama dengan
  /// yang membuatnya.
  Future<void> _loadGatewayAccount(String restoId) async {
    try {
      final row = await Supabase.instance.client
          .from('resto_payment_accounts')
          .select('account_id')
          .eq('resto_id', restoId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() =>
          _gatewayAccountCtrl.text = row['account_id'] as String? ?? '');
    } catch (_) {
      // Tabelnya belum dimigrasi. Sisa formulirnya tetap harus jalan.
    }
  }

  Future<void> _saveGatewayAccount(String restoId) async {
    final id = _gatewayAccountCtrl.text.trim();
    final table = Supabase.instance.client.from('resto_payment_accounts');
    if (id.isEmpty) {
      await table.delete().eq('resto_id', restoId);
      return;
    }
    await table.upsert({
      'resto_id': restoId,
      'account_id': id,
      'updated_by': Supabase.instance.client.auth.currentUser?.email,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'resto_id');
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _ppnCtrl.dispose();
    _serviceCtrl.dispose();
    _gatewayAccountCtrl.dispose();
    super.dispose();
  }

  String? _slugify(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'(^-+)|(-+$)'), '');
    return slug.isEmpty ? null : slug;
  }

  /// Logo state at the moment Edit was tapped, alongside the text
  /// fields, so Batal also undoes an upload or a staged removal.
  double? _snapshotLat;
  double? _snapshotLng;
  File? _snapshotPickedLogo;
  String? _snapshotExistingLogo;
  bool _snapshotLogoRemoved = false;

  void _startEdit() {
    _snapshot = {
      'name': _nameCtrl.text,
      'address': _addressCtrl.text,
      'phone': _phoneCtrl.text,
      'ppn': _ppnCtrl.text,
      'service': _serviceCtrl.text,
      'category': _category,
    };
    _snapshotDineIn = _dineIn;
    _snapshotTakeAway = _takeAway;
    _snapshotLat = _latitude;
    _snapshotLng = _longitude;
    _snapshotPickedLogo = _pickedLogo;
    _snapshotExistingLogo = _existingLogo;
    _snapshotLogoRemoved = _logoRemoved;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    if (!_isEditing) {
      Navigator.of(context).pop();
      return;
    }
    _nameCtrl.text = _snapshot['name'] ?? '';
    _addressCtrl.text = _snapshot['address'] ?? '';
    _phoneCtrl.text = _snapshot['phone'] ?? '';
    _ppnCtrl.text = _snapshot['ppn'] ?? '';
    _serviceCtrl.text = _snapshot['service'] ?? '';
    _category = _snapshot['category'];
    _dineIn = _snapshotDineIn;
    _takeAway = _snapshotTakeAway;
    _latitude = _snapshotLat;
    _longitude = _snapshotLng;
    _pickedLogo = _snapshotPickedLogo;
    _existingLogo = _snapshotExistingLogo;
    _logoRemoved = _snapshotLogoRemoved;
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = _idCtrl.text.trim();

    setState(() => _saving = true);
    try {
      if (!_isEditing) {
        final existing = await _repo.getOnce(id);
        if (existing != null) {
          if (!mounted) return;
          showAppToast(context, 'ID "$id" sudah dipakai merchant lain, pakai ID lain.');
          setState(() => _saving = false);
          return;
        }
      }

      String? logoBase64 = _existingLogo;
      if (_pickedLogo != null) {
        logoBase64 = base64Encode(await _pickedLogo!.readAsBytes());
      } else if (_logoRemoved) {
        logoBase64 = null;
      }

      await _repo.save(Restaurant(
        id: id,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        ppnPercent: double.tryParse(_ppnCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        servicePercent: double.tryParse(_serviceCtrl.text.trim().replaceAll(',', '.')) ?? 0,
        category: _category,
        latitude: _latitude,
        longitude: _longitude,
        dineInEnabled: _dineIn,
        takeAwayEnabled: _takeAway,
        logoBase64: logoBase64,
        // Preserve the existing active/inactive status when editing —
        // that's managed separately via the switch on List Resto, not
        // this form.
        active: widget.existing?.active ?? true,
      ));

      // Sesudah restonya tersimpan, bukan sebelum: barisnya menunjuk
      // restaurants(id), dan menulisnya lebih dulu akan ditolak kunci
      // asingnya saat resto baru dibuat.
      await _saveGatewayAccount(id);

      if (!mounted) return;
      showAppToast(context, _isEditing ? 'Merchant "$id" diperbarui.' : 'Merchant "$id" berhasil dibuat.');
      if (_isEditing) {
        setState(() {
          _saving = false;
          _editing = false;
        });
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Merchant' : 'Buat Merchant Baru'),
        actions: [
          if (_isEditing && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                enabled: _editing,
                decoration: InputDecoration(
                  label: requiredLabel('Nama merchant'),
                  filled: !_editing,
                  fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                ),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) => validateName(v, label: 'Nama merchant'),
                onChanged: (v) {
                  if (_isEditing) return; // don't reshuffle an existing id
                  // Auto-fill a slug id from the name, but let the user
                  // still hand-edit it (e.g. if they want it shorter).
                  final auto = _slugify(v);
                  if (auto != null) _idCtrl.text = auto;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idCtrl,
                // Selalu terkunci: nilainya dibangkitkan dari nama resto,
                // dan sebagai kunci utama ia tidak boleh berubah setelah
                // dibuat. Membiarkannya bisa diketik hanya membuka pintu
                // untuk id yang bentrok atau salah ketik.
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'ID merchant (dibuat otomatis)',
                  helperText: 'Mengikuti nama merchant — dipakai internal, tidak bisa diubah',
                  filled: true,
                  fillColor: MerchantPosTheme.disabledFillOf(context),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(v.trim())) {
                    return 'Cuma huruf kecil, angka, dan strip';
                  }
                  return null;
                },
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: InputDecoration(
                  labelText: 'Kategori (opsional)',
                  filled: !_editing,
                  fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                ),
                items: kRestaurantCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: _editing ? (v) => setState(() => _category = v) : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ppnCtrl,
                      enabled: _editing,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: rateFormatters,
                      decoration: InputDecoration(
                        labelText: 'PPN (%)',
                        filled: !_editing,
                        fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                      ),
                      validator: (v) => validateRate(v, label: 'PPN'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _serviceCtrl,
                      enabled: _editing,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: rateFormatters,
                      decoration: InputDecoration(
                        labelText: 'Service (%)',
                        filled: !_editing,
                        fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                      ),
                      validator: (v) => validateRate(v, label: 'Biaya service'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Harga menu ditampilkan sudah termasuk keduanya. Service hanya '
                'dikenakan untuk Dine In.',
                style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              const SizedBox(height: 20),
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
                'Yang dimatikan tidak muncul sebagai pilihan saat checkout, '
                'baik di kasir maupun di HP pelanggan.',
                style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Dine In'),
                subtitle: const Text('Makan di tempat, pakai nomor meja',
                    style: TextStyle(fontSize: 11.5)),
                value: _dineIn,
                // Mematikan yang terakhir menyala tidak diizinkan.
                // Resto tanpa satu pun cara makan tidak bisa menerima
                // pesanan apa pun — itu bukan pengaturan, itu resto yang
                // tutup, dan untuk itu sudah ada tombol Aktif/Nonaktif di
                // List Resto.
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
              const SizedBox(height: 20),
              TextFormField(
                controller: _gatewayAccountCtrl,
                enabled: _editing,
                decoration: InputDecoration(
                  labelText: 'ID Akun Xendit (opsional)',
                  filled: !_editing,
                  fillColor: _editing ? null : MerchantPosTheme.disabledFillOf(context),
                  helperText: 'Sub-akun merchant ini di Xendit. Dana QRIS cair '
                      'langsung ke rekening yang terdaftar di sub-akun itu. '
                      'Kosongkan kalau belum dibuat.',
                  helperMaxLines: 4,
                ),
              ),
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
                  saveLabel: _isEditing ? 'Simpan Perubahan' : 'Buat Merchant',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
