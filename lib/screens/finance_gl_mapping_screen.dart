import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/expense_gl_account_repository.dart';
import '../db/gl_account_repository.dart';
import '../models/billing.dart';
import '../models/expense_gl_account.dart';
import '../models/gl_account.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/edit_action_bar.dart';
import '../widgets/dialog_actions.dart';
import '../models/restaurant.dart';
import '../db/restaurant_repository.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';

const _paymentMethods = ['cash', 'qris', 'transfer'];
const _paymentLabels = {'cash': 'Tunai', 'qris': 'QRIS', 'transfer': 'Transfer'};
const _paymentIcons = {
  'cash': Icons.payments_outlined,
  'qris': Icons.qr_code_2,
  'transfer': Icons.account_balance_outlined,
};

// Not real payment methods — reuses the same gl_accounts table to map the
// GL codes the Petty Cash journal needs (see supabase/petty_cash_journal
// .sql): 'income_aggregate' is credited when a top-up withdraws from
// Saldo Penghasilan, 'petty_cash' is debited on every top-up.
const _pettyCashMethods = ['income_aggregate', 'petty_cash'];
const _pettyCashLabels = {
  'income_aggregate': 'GL Penghasilan',
  'petty_cash': 'GL Petty Cash',
};
const _pettyCashHints = {
  'income_aggregate': 'Sumber dana saat withdraw',
  'petty_cash': 'Kas kecil, sumber semua pengeluaran',
};
const _pettyCashIcons = {
  'income_aggregate': Icons.trending_up,
  'petty_cash': Icons.savings_outlined,
};

// The umbrella account every other balance rolls up into — reported as
// the summary header on the Jurnal GL screen rather than duplicating a
// row for every movement.
const _totalBalanceMethod = 'total_balance';

// Penampungan sementara setoran tunai yang belum disetujui Finance.
// Uangnya sudah keluar dari laci kasir tapi belum diakui masuk kas resto,
// dan tanpa akun sendiri ia akan menghilang dari pembukuan selama masa
// tunggu itu.
const _suspenseMethod = 'suspense';

// Suspense untuk pengajuan top up petty cash. Sengaja terpisah dari
// suspense setoran bank: keduanya menunggu persetujuan orang yang
// berbeda dan menuju akun yang berbeda, jadi menyatukannya membuat
// Finance harus memilah sendiri isi satu akun untuk tahu berapa yang
// tertahan di masing-masing alur.
const _suspensePettyMethod = 'suspense_petty';

// Potongan penyedia pembayaran (MDR). Uang yang tidak pernah sampai ke
// rekening resto tapi tetap harus tercatat — tanpa akun ini, selisih
// antara yang dibayar pelanggan dan yang cair ke bank tidak punya nama,
// dan pembukuannya tidak akan pernah bisa ditutup.
const _gatewayFeeMethod = 'gateway_fee';

// Potongan harga yang diberikan ke pelanggan. Pengurang pendapatan,
// bukan biaya: diskon tidak pernah jadi uang yang keluar dari resto, ia
// adalah uang yang tidak pernah masuk. Tanpa akunnya sendiri, penjualan
// tercatat sebesar harga daftar sementara uang yang diterima lebih
// kecil, dan selisihnya muncul sebagai kas yang hilang tanpa sebab.
const _discountMethod = 'discount';

// Dua akun berikut hanya dipakai pembukuan MerchantPOS sendiri — resto tidak
// menagih siapa pun. Ditampilkan hanya saat layar ini dibuka untuk
// penyewa platform.
const _subscriptionMethod = 'subscription';
const _subscriptionDiscountMethod = 'subscription_discount';

// Dua kantong voucher, juga milik MerchantPOS sendiri. Dipisah karena
// keduanya menjawab pertanyaan yang berbeda: 'voucher' menahan dana yang
// sudah diumumkan tapi belum ada yang menebus, 'voucher_redeem' menahan
// yang sudah menggantung di tangan pelanggan. Menyatukannya membuat
// keduanya tidak bisa dibedakan justru saat yang ditanya adalah berapa
// yang masih bisa ditarik kembali.
const _voucherMethod = 'voucher';
const _voucherRedeemMethod = 'voucher_redeem';

// Uang masuk dari luar penjualan: setoran investor, atau modal awal
// pemilik resto. Punya akunnya sendiri supaya laporan penjualan tidak
// memuat uang yang tidak pernah dijual — tanpa itu, resto yang menyetor
// modal besar akan terlihat seperti resto yang laris.
//
// Berlaku untuk resto maupun MerchantPOS: keduanya bisa menerima setoran
// modal, dan keduanya perlu membedakannya dari pendapatan.
const _capitalMethod = 'capital';

// Selisih uang laci saat shift kasir ditutup. Titipan, bukan pendapatan
// dan bukan biaya: yang kurang sedang ditagihkan kepada kasirnya, dan
// yang lebih belum jelas berasal dari penjualan mana. Tanpa akunnya
// sendiri, selisih itu tidak punya tempat di pembukuan sama sekali — dan
// Saldo Cash menyebut angka yang lebih besar daripada uang yang benar
// benar bisa dihitung tangan.
const _cashVarianceMethod = 'cash_variance';

// PPN and service charge collected are money owed onward, not revenue,
// so they're journaled to their own accounts instead of being folded
// into the payment-method income mapping.
const _taxMethods = ['ppn', 'service'];
const _taxLabels = {'ppn': 'GL PPN', 'service': 'GL Biaya Service'};
const _taxHints = {
  'ppn': 'PPN yang dipungut dari penjualan',
  'service': 'Biaya service yang dipungut (Dine In)',
};
const _taxIcons = {'ppn': Icons.receipt_long_outlined, 'service': Icons.room_service_outlined};
const _taxColor = Color(0xFF8B5CF6);

const _allMethods = [
  ..._paymentMethods,
  ..._pettyCashMethods,
  ..._taxMethods,
  _totalBalanceMethod,
  _suspenseMethod,
  _suspensePettyMethod,
  _gatewayFeeMethod,
  _discountMethod,
  _subscriptionMethod,
  _subscriptionDiscountMethod,
  _voucherMethod,
  _voucherRedeemMethod,
  _capitalMethod,
  _cashVarianceMethod,
];

/// Akun yang hanya ada di pembukuan MerchantPOS sendiri.
///
/// Resto tidak menagih langganan dan tidak menerbitkan voucher, jadi
/// menghitungnya untuk mereka membuat penanda "belum dipetakan"
/// berbunyi selamanya — dan peringatan yang tidak pernah bisa
/// dihilangkan mengajari orang mengabaikan seluruh penandanya.
const _platformOnlyMethods = {
  _subscriptionMethod,
  _subscriptionDiscountMethod,
  _voucherMethod,
  _voucherRedeemMethod,
};

/// Drops a trailing ".0" so a rate of 11 shows as "11", not "11.00".
String _pctText(double value) =>
    value == 0 ? '' : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// Blank means "not charged" rather than being an error — plenty of
/// restos run without a service charge.
double _parseRate(String raw) =>
    double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;

const _incomeColor = Color(0xFF10B981);
const _pettyCashColor = Color(0xFF6366F1);
const _totalColor = Color(0xFF14B8A6);
const _expenseColor = Color(0xFFEF4444);

/// Lets Finance set which GL (General Ledger) account each kind of money
/// movement is booked to: income per payment method, the Petty Cash pair,
/// the umbrella Total Saldo account, plus a free-form chart of expense
/// categories offered as the GL tag when recording an expense in
/// [FinanceBalanceScreen].
///
/// Opens read-only — the mapping is shown as plain rows rather than a
/// wall of greyed-out inputs, which is far easier to scan. Tapping Edit
/// swaps every row into a compact code+name field pair.
class FinanceGlMappingScreen extends StatefulWidget {
  /// Resto yang dibukukan. Kosong berarti resto tempat orangnya bekerja.
  ///
  /// Diisi hanya oleh menu Finance Super Admin, yang membukukan MerchantPOS
  /// sendiri — penyewa platform yang memakai mesin pembukuan yang sama
  /// persis dengan resto.
  final String? restoId;

  const FinanceGlMappingScreen({super.key, this.restoId});

  @override
  State<FinanceGlMappingScreen> createState() => _FinanceGlMappingScreenState();
}

class _FinanceGlMappingScreenState extends State<FinanceGlMappingScreen> {
  final _repo = GlAccountRepository();
  final _expenseGlRepo = ExpenseGlAccountRepository();
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _codeCtrls = {
    for (final m in _allMethods) m: TextEditingController(),
  };
  final Map<String, TextEditingController> _nameCtrls = {
    for (final m in _allMethods) m: TextEditingController(),
  };
  /// The rates themselves, edited alongside the accounts they're booked
  /// to — a rate with no GL to land in is only half a setup, so keeping
  /// the two apart made it easy to configure one and forget the other.
  final _ppnRateCtrl = TextEditingController();
  final _serviceRateCtrl = TextEditingController();
  final _restoRepo = RestaurantRepository();

  List<ExpenseGlAccount> _expenseAccounts = [];
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _loadError;

  /// Every controller's text as it was when Edit was tapped, so Batal
  /// can restore all of them rather than leaving unsaved edits visible.
  Map<String, String> _snapshot = const {};

  String get _restoId =>
      widget.restoId ?? context.read<AuthProvider>().restoId!;

  /// Layar ini dibuka untuk pembukuan MerchantPOS sendiri.
  ///
  /// Dua akun langganan hanya berarti di sana — resto tidak menagih
  /// siapa pun, dan menampilkan kolom yang tidak akan pernah dipakai
  /// membuat halaman ini lebih panjang tanpa jadi lebih berguna.
  bool get _untukPlatform => _restoId == kPlatformRestoId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _codeCtrls.values) {
      c.dispose();
    }
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    _ppnRateCtrl.dispose();
    _serviceRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final restoId = _restoId;
      final results = await Future.wait([
        _repo.getForResto(restoId),
        _expenseGlRepo.getForResto(restoId),
        _restoRepo.getOnce(restoId),
      ]);
      if (!mounted) return;
      for (final a in results[0] as List<GlAccount>) {
        _codeCtrls[a.paymentMethod]?.text = a.glCode;
        _nameCtrls[a.paymentMethod]?.text = a.glName;
      }
      final resto = results[2] as Restaurant?;
      _ppnRateCtrl.text = _pctText(resto?.ppnPercent ?? 0);
      _serviceRateCtrl.text = _pctText(resto?.servicePercent ?? 0);
      setState(() {
        _expenseAccounts = results[1] as List<ExpenseGlAccount>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  /// How many of the fixed mapping slots are filled in — surfaced in the
  /// header so Finance can see at a glance whether anything's missing
  /// (an unmapped account silently skips journaling).
  int get _mappedCount =>
      _metodeLayarIni.where((m) => _codeCtrls[m]!.text.trim().isNotEmpty).length;

  /// Akun yang benar-benar berlaku di layar ini.
  ///
  /// Akun langganan dan voucher hanya ada di pembukuan MerchantPOS — lihat
  /// [_platformOnlyMethods].
  List<String> get _metodeLayarIni => _untukPlatform
      ? _allMethods
      : [
          for (final m in _allMethods)
            if (!_platformOnlyMethods.contains(m)) m,
        ];

  void _startEdit() {
    _snapshot = {
      for (final m in _allMethods) ...{
        'code_$m': _codeCtrls[m]!.text,
        'name_$m': _nameCtrls[m]!.text,
      },
      'rate_ppn': _ppnRateCtrl.text,
      'rate_service': _serviceRateCtrl.text,
    };
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    for (final m in _allMethods) {
      _codeCtrls[m]!.text = _snapshot['code_$m'] ?? '';
      _nameCtrls[m]!.text = _snapshot['name_$m'] ?? '';
    }
    _ppnRateCtrl.text = _snapshot['rate_ppn'] ?? '';
    _serviceRateCtrl.text = _snapshot['rate_service'] ?? '';
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = _restoId;
    setState(() => _saving = true);
    try {
      for (final method in _allMethods) {
        final code = _codeCtrls[method]!.text.trim();
        final name = _nameCtrls[method]!.text.trim();
        if (code.isEmpty && name.isEmpty) continue; // leave unmapped methods alone
        await _repo.upsert(GlAccount(
          restoId: restoId,
          paymentMethod: method,
          glCode: code,
          glName: name,
        ));
      }

      await _restoRepo.setTaxRates(
        restoId,
        ppnPercent: _parseRate(_ppnRateCtrl.text),
        servicePercent: _parseRate(_serviceRateCtrl.text),
      );

      if (!mounted) return;
      setState(() => _editing = false);
      showAppToast(context, 'Mapping GL Account tersimpan.');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addExpenseGlAccount() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _expenseColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.trending_down, color: _expenseColor),
        ),
        title: const Text('Tambah GL Pengeluaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(label: requiredLabel('Kode GL Account')),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(label: requiredLabel('Nama GL Account')),
              inputFormatters: nameFormatters,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Tambah',
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) return;
    try {
      await _expenseGlRepo.create(_restoId, code, name);
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menambah: $e', isError: true);
    }
  }

  Future<void> _deleteExpenseGlAccount(ExpenseGlAccount a) async {
    // A GL that already has expenses booked against it can't be removed —
    // the database enforces this (FK ON DELETE RESTRICT), we just explain
    // it here rather than letting a raw constraint error surface.
    final inUse = await _expenseGlRepo.usageCount(_restoId, a.glCode);
    if (!mounted) return;
    if (inUse > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.lock_outline, size: 40, color: Colors.orange),
          title: const Text('Tidak Bisa Dihapus'),
          content: Text(
            'GL ${a.glCode} — ${a.glName} sudah dipakai oleh $inUse pengeluaran.\n\n'
            'Menghapusnya akan memutus riwayat jurnal yang sudah tercatat. '
            'Hapus dulu pengeluaran yang memakai GL ini kalau memang perlu dihapus.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mengerti')),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus GL Account?'),
        content: Text('${a.glCode} — ${a.glName}'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _expenseGlRepo.delete(a.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menghapus: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Mapping GL Account'),
        actions: [
          if (!_loading && _loadError == null && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      // Nothing to show in view mode — the app bar's back arrow already
      // covers leaving, so the bar only appears while editing.
      bottomNavigationBar: (_loading || _loadError != null || !_editing)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: EditActionBar(
                  onCancel: _cancelEdit,
                  onSave: _save,
                  saving: _saving,
                  saveLabel: 'Simpan Mapping',
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text('Gagal memuat data:\n$_loadError', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      _StatusBanner(
                        editing: _editing,
                        mapped: _mappedCount,
                        total: _metodeLayarIni.length,
                      ),
                      const SizedBox(height: 16),
                      _GlSectionCard(
                        icon: Icons.trending_up,
                        color: _incomeColor,
                        title: 'GL Pemasukan',
                        subtitle: 'Akun tujuan pemasukan per metode bayar',
                        children: [
                          for (final m in _paymentMethods)
                            _GlAccountRow(
                              icon: _paymentIcons[m]!,
                              label: _paymentLabels[m]!,
                              color: _incomeColor,
                              codeCtrl: _codeCtrls[m]!,
                              nameCtrl: _nameCtrls[m]!,
                              editing: _editing,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.savings_outlined,
                        color: _pettyCashColor,
                        title: 'GL Petty Cash',
                        subtitle: 'Dipakai saat top up & saat mencatat pengeluaran',
                        children: [
                          for (final m in _pettyCashMethods)
                            _GlAccountRow(
                              icon: _pettyCashIcons[m]!,
                              label: _pettyCashLabels[m]!,
                              hint: _pettyCashHints[m],
                              color: _pettyCashColor,
                              codeCtrl: _codeCtrls[m]!,
                              nameCtrl: _nameCtrls[m]!,
                              editing: _editing,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.percent,
                        color: _taxColor,
                        title: 'Pajak & Biaya Service',
                        subtitle: 'Tarif dan GL-nya, dipisah dari GL pemasukan',
                        children: [
                          _TaxRateRow(
                            ppnCtrl: _ppnRateCtrl,
                            serviceCtrl: _serviceRateCtrl,
                            editing: _editing,
                          ),
                          for (final m in _taxMethods)
                            _GlAccountRow(
                              icon: _taxIcons[m]!,
                              label: _taxLabels[m]!,
                              hint: _taxHints[m],
                              color: _taxColor,
                              codeCtrl: _codeCtrls[m]!,
                              nameCtrl: _nameCtrls[m]!,
                              editing: _editing,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.account_tree_outlined,
                        color: _totalColor,
                        title: 'GL Total Saldo',
                        subtitle: 'Akun payung, jadi ringkasan di Jurnal GL',
                        children: [
                          _GlAccountRow(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Total Saldo',
                            color: _totalColor,
                            codeCtrl: _codeCtrls[_totalBalanceMethod]!,
                            nameCtrl: _nameCtrls[_totalBalanceMethod]!,
                            editing: _editing,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.pending_actions,
                        color: const Color(0xFFF59E0B),
                        title: 'GL Suspense',
                        subtitle: 'Titipan yang belum disetujui Finance',
                        children: [
                          _GlAccountRow(
                            icon: Icons.account_balance_outlined,
                            label: 'GL Suspense Setoran',
                            hint: 'Setoran tunai ke bank, menunggu approval',
                            color: const Color(0xFFF59E0B),
                            codeCtrl: _codeCtrls[_suspenseMethod]!,
                            nameCtrl: _nameCtrls[_suspenseMethod]!,
                            editing: _editing,
                          ),
                          _GlAccountRow(
                            icon: Icons.savings_outlined,
                            label: 'GL Suspense Petty Cash',
                            hint: 'Pengajuan top up kasir, menunggu approval',
                            color: const Color(0xFFF59E0B),
                            codeCtrl: _codeCtrls[_suspensePettyMethod]!,
                            nameCtrl: _nameCtrls[_suspensePettyMethod]!,
                            editing: _editing,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.credit_card_outlined,
                        color: const Color(0xFFEC4899),
                        title: 'GL Payment Gateway',
                        subtitle: 'Potongan penyedia saat dana dicairkan',
                        children: [
                          _GlAccountRow(
                            icon: Icons.percent,
                            label: 'GL Biaya MDR',
                            hint: 'Potongan penyedia — selisih yang dibayar '
                                'pelanggan dengan yang cair ke rekening',
                            color: const Color(0xFFEC4899),
                            codeCtrl: _codeCtrls[_gatewayFeeMethod]!,
                            nameCtrl: _nameCtrls[_gatewayFeeMethod]!,
                            editing: _editing,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.savings_outlined,
                        color: const Color(0xFF14B8A6),
                        title: 'GL Modal',
                        subtitle: 'Uang masuk dari luar penjualan',
                        children: [
                          _GlAccountRow(
                            icon: Icons.savings_outlined,
                            label: 'GL Setoran Modal',
                            hint: 'Setoran investor atau modal awal — '
                                'menambah saldo, bukan pendapatan',
                            color: const Color(0xFF14B8A6),
                            codeCtrl: _codeCtrls[_capitalMethod]!,
                            nameCtrl: _nameCtrls[_capitalMethod]!,
                            editing: _editing,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.point_of_sale,
                        color: const Color(0xFFF59E0B),
                        title: 'GL Selisih Kasir',
                        subtitle: 'Selisih uang laci saat shift ditutup',
                        children: [
                          _GlAccountRow(
                            icon: Icons.point_of_sale,
                            label: 'GL Selisih Kasir',
                            hint: 'Kurang jadi tagihan kasir, lebih dicatat '
                                'sampai penjualannya ketemu',
                            color: const Color(0xFFF59E0B),
                            codeCtrl: _codeCtrls[_cashVarianceMethod]!,
                            nameCtrl: _nameCtrls[_cashVarianceMethod]!,
                            editing: _editing,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.local_offer_outlined,
                        color: const Color(0xFF10B981),
                        title: 'GL Diskon',
                        subtitle: 'Pengurang pendapatan, bukan biaya',
                        children: [
                          _GlAccountRow(
                            icon: Icons.local_offer_outlined,
                            label: 'GL Diskon Penjualan',
                            hint: 'Potongan promo — uang yang tidak pernah '
                                'masuk, bukan uang yang keluar',
                            color: const Color(0xFF10B981),
                            codeCtrl: _codeCtrls[_discountMethod]!,
                            nameCtrl: _nameCtrls[_discountMethod]!,
                            editing: _editing,
                          ),
                        ],
                      ),
                      if (_untukPlatform) ...[
                        const SizedBox(height: 14),
                        _GlSectionCard(
                          icon: Icons.workspace_premium_outlined,
                          color: const Color(0xFF6366F1),
                          title: 'GL Langganan',
                          subtitle: 'Pendapatan MerchantPOS dari biaya langganan merchant',
                          children: [
                            _GlAccountRow(
                              icon: Icons.trending_up,
                              label: 'GL Pendapatan Langganan',
                              hint: 'Dicatat sebesar harga daftar, sebelum '
                                  'potongan',
                              color: const Color(0xFF6366F1),
                              codeCtrl: _codeCtrls[_subscriptionMethod]!,
                              nameCtrl: _nameCtrls[_subscriptionMethod]!,
                              editing: _editing,
                            ),
                            _GlAccountRow(
                              icon: Icons.local_offer_outlined,
                              label: 'GL Diskon Langganan',
                              hint: 'Potongan harga langganan untuk merchant '
                                  'tertentu',
                              color: const Color(0xFF6366F1),
                              codeCtrl:
                                  _codeCtrls[_subscriptionDiscountMethod]!,
                              nameCtrl:
                                  _nameCtrls[_subscriptionDiscountMethod]!,
                              editing: _editing,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _GlSectionCard(
                          icon: Icons.card_giftcard_outlined,
                          color: const Color(0xFFF59E0B),
                          title: 'GL Voucher',
                          subtitle: 'Promo MerchantPOS — dananya keluar sejak '
                              'vouchernya diterbitkan',
                          children: [
                            _GlAccountRow(
                              icon: Icons.confirmation_number_outlined,
                              label: 'GL Voucher',
                              hint: 'Sudah diterbitkan, belum ada yang '
                                  'menebus',
                              color: const Color(0xFFF59E0B),
                              codeCtrl: _codeCtrls[_voucherMethod]!,
                              nameCtrl: _nameCtrls[_voucherMethod]!,
                              editing: _editing,
                            ),
                            _GlAccountRow(
                              icon: Icons.redeem_outlined,
                              label: 'GL Voucher Redeem',
                              hint: 'Sudah ditebus pelanggan, menunggu '
                                  'dipakai atau hangus',
                              color: const Color(0xFFF59E0B),
                              codeCtrl: _codeCtrls[_voucherRedeemMethod]!,
                              nameCtrl: _nameCtrls[_voucherRedeemMethod]!,
                              editing: _editing,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _GlSectionCard(
                        icon: Icons.trending_down,
                        color: _expenseColor,
                        title: 'GL Pengeluaran',
                        subtitle: 'Kategori biaya — muncul saat mencatat pengeluaran',
                        trailing: Text(
                          '${_expenseAccounts.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: _expenseColor, fontSize: 15),
                        ),
                        children: [
                          if (_expenseAccounts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('Belum ada GL pengeluaran.',
                                  style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 13)),
                            )
                          else
                            ..._expenseAccounts.map((a) => _ExpenseGlRow(
                                  account: a,
                                  onDelete: () => _deleteExpenseGlAccount(a),
                                )),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _addExpenseGlAccount,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Tambah GL Pengeluaran'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _expenseColor,
                                side: BorderSide(color: _expenseColor.withOpacity(0.5)),
                                minimumSize: const Size.fromHeight(44),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Tells the user which mode they're in and whether any mapping slot is
/// still empty — an unmapped account silently produces no journal rows,
/// which is easy to miss otherwise.
class _StatusBanner extends StatelessWidget {
  final bool editing;
  final int mapped;
  final int total;

  const _StatusBanner({required this.editing, required this.mapped, required this.total});

  @override
  Widget build(BuildContext context) {
    final complete = mapped == total;
    final color = editing
        ? MerchantPosTheme.brand
        : (complete ? _incomeColor : Colors.orange.shade800);
    final icon = editing
        ? Icons.edit_outlined
        : (complete ? Icons.verified_outlined : Icons.info_outline);
    final text = editing
        ? 'Mode edit — ubah kode & nama GL, lalu tekan Simpan.'
        : (complete
            ? 'Semua $total akun sudah dipetakan.'
            : '$mapped dari $total akun dipetakan. Yang kosong tidak akan masuk jurnal.');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One titled group of GL rows, with a coloured icon badge header — the
/// same visual language as the hub menu tiles elsewhere in the app.
class _GlSectionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  const _GlSectionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 1),
                      Text(subtitle,
                          style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context))),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: MerchantPosTheme.softFillOf(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}

/// A single mapping slot. Read-only it's just a label and the mapped
/// account (or a clear "Belum diatur"); in edit mode it becomes a narrow
/// code field beside a wider name field, which keeps the whole screen
/// about half as tall as stacked full-width inputs would.
class _GlAccountRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final Color color;
  final TextEditingController codeCtrl;
  final TextEditingController nameCtrl;
  final bool editing;

  const _GlAccountRow({
    required this.icon,
    required this.label,
    this.hint,
    required this.color,
    required this.codeCtrl,
    required this.nameCtrl,
    required this.editing,
  });

  @override
  Widget build(BuildContext context) {
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final unset = code.isEmpty && name.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text('• $hint',
                      style: TextStyle(fontSize: 11, color: MerchantPosTheme.mutedOf(context)),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (editing)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Kode',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nama akun',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            )
          else if (unset)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.remove_circle_outline, size: 14, color: Colors.orange.shade800),
                  const SizedBox(width: 7),
                  Text('Belum diatur',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MerchantPosTheme.softFillOf(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      code.isEmpty ? '—' : code,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: color,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Tanpa nama' : name,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: name.isEmpty ? Colors.grey : MerchantPosTheme.textOf(context),
                        fontStyle: name.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpenseGlRow extends StatelessWidget {
  final ExpenseGlAccount account;
  final VoidCallback onDelete;

  const _ExpenseGlRow({required this.account, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: MerchantPosTheme.softFillOf(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _expenseColor.withOpacity(0.13),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                account.glCode,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _expenseColor,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(account.glName,
                  style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
              tooltip: 'Hapus',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// The two rates, sitting above the accounts they're booked to.
///
/// Read-only they render as plain figures — a percentage is a single
/// number and a boxed input for it reads as heavier than it is.
class _TaxRateRow extends StatelessWidget {
  final TextEditingController ppnCtrl;
  final TextEditingController serviceCtrl;
  final bool editing;

  const _TaxRateRow({
    required this.ppnCtrl,
    required this.serviceCtrl,
    required this.editing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: _taxColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _taxColor.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _rate(
                  context,
                  label: 'PPN',
                  hint: 'Ditambahkan ke harga menu',
                  controller: ppnCtrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _rate(
                  context,
                  label: 'Biaya Service',
                  hint: 'Dine In saja',
                  controller: serviceCtrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Harga menu yang dilihat customer sudah termasuk PPN. Biaya service '
            'ditambahkan saat checkout. Kosongkan atau isi 0 kalau tidak dipakai.',
            style: TextStyle(fontSize: 11, color: MerchantPosTheme.mutedOf(context), height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _rate(
    BuildContext context, {
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _taxColor,
          ),
        ),
        const SizedBox(height: 2),
        if (editing)
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: rateFormatters,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: '%',
              hintText: '0',
            ),
            // Bentuk setengah jadi seperti "11." ditolak di sini: Dart
            // membacanya sebagai 11, jadi mengandalkan tryParse saja
            // membuatnya lolos dan tersimpan.
            validator: (v) => validateRate(v, label: label),
          )
        else
          Text(
            controller.text.trim().isEmpty ? '0%' : '${controller.text.trim()}%',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        const SizedBox(height: 2),
        Text(hint, style: TextStyle(fontSize: 10.5, color: MerchantPosTheme.mutedOf(context))),
      ],
    );
  }
}
