import '../db/balance_topup_repository.dart';
import '../models/balance_topup.dart';
import '../models/billing.dart';
import '../models/gl_journal_entry.dart';
import '../db/gl_account_repository.dart';
import '../db/gl_journal_repository.dart';
import '../utils/saldo_jurnal.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/expense_gl_account_repository.dart';
import '../db/cash_deposit_repository.dart';
import '../db/cashier_shift_repository.dart';
import '../db/expense_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../models/cash_deposit.dart';
import '../models/cash_variance.dart';
import '../models/customer_order.dart';
import '../models/expense.dart';
import '../models/expense_gl_account.dart';
import '../models/petty_cash_entry.dart';
import '../providers/auth_provider.dart';
import '../utils/cash_balance.dart';
import '../utils/id_time.dart';
import '../utils/photo_picker.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/journal_detail_dialog.dart';
import '../utils/rupiah_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/count_badge.dart';
import '../widgets/required_label.dart';
import '../utils/lebar_web.dart';

/// Saldo Total = Saldo Penghasilan + Saldo Petty Cash − Saldo Pengeluaran.
///
/// - Saldo Penghasilan: sum of paid orders (all the resto's Cash/QRIS/
///   Transfer income — GL Penghasilan), minus whatever's been withdrawn
///   out of it into Petty Cash.
/// - Saldo Petty Cash: a small manually-managed float, topped up either by
///   withdrawing from Saldo Penghasilan or a manual entry (needed on day
///   one, before any income exists yet).
/// - Saldo Pengeluaran: sum of all recorded expenses (GL Pengeluaran,
///   tagged to whichever expense GL account — e.g. GL Operational).
///
/// Everything here is computed on the fly from `orders`/`expenses`/
/// `petty_cash_entries` rather than stored, so it's always consistent
/// with the underlying data.
class FinanceBalanceScreen extends StatefulWidget {
  /// Resto yang dibukukan. Kosong berarti resto tempat orangnya bekerja.
  ///
  /// Diisi hanya oleh menu Finance Super Admin, yang membukukan Merchant-POS
  /// sendiri — penyewa platform yang memakai mesin pembukuan yang sama
  /// persis dengan resto.
  final String? restoId;

  const FinanceBalanceScreen({super.key, this.restoId});

  @override
  State<FinanceBalanceScreen> createState() => _FinanceBalanceScreenState();
}

class _FinanceBalanceScreenState extends State<FinanceBalanceScreen> {
  final _orderRepo = OrderRepository();
  final _expenseRepo = ExpenseRepository();
  final _expenseGlRepo = ExpenseGlAccountRepository();
  final _pettyCashRepo = PettyCashRepository();
  final _depositRepo = CashDepositRepository();
  final _topupRepo = BalanceTopupRepository();

  /// Terbuka atau tertutupnya seluruh bagian, bukan cuma satu harinya.
  ///
  /// Dua bagian ini tumbuh terus dan tidak pernah menyusut. Kartu harian
  /// sudah bisa dilipat sendiri-sendiri, tapi puluhan judul hari yang
  /// tetap berbaris tetap saja mendorong Setoran dan Saldo Total jauh ke
  /// bawah layar — padahal itu yang dicari orang saat membuka layar ini.
  /// Melipat bagiannya sekali ketuk mengembalikannya ke satu layar.
  bool _pettyCashOpen = true;
  bool _topupOpen = true;
  bool _expensesOpen = true;

  int _cashIncome = 0;
  List<CashVariance> _selisih = const [];
  int _nonCashIncome = 0;
  List<CashDeposit> _deposits = [];
  List<Expense> _expenses = [];
  List<ExpenseGlAccount> _expenseGlAccounts = [];
  List<PettyCashEntry> _pettyCashEntries = [];
  String? _bankName;
  String? _accountNumber;
  String? _accountHolder;
  bool _loading = true;
  String? _loadError;

  String get _restoId =>
      widget.restoId ?? context.read<AuthProvider>().restoId!;

  /// Yang dibukukan adalah Merchant-POS sendiri, bukan sebuah resto.
  ///
  /// Bedanya bukan kosmetik. Merchant-POS tidak punya pesanan, laci kasir,
  /// atau setoran bank — seluruh uangnya bergerak lewat jurnal:
  /// langganan masuk, diskon dan voucher keluar. Menghitungnya dengan
  /// cara resto membuat layar ini berbunyi Rp 0 selamanya, sementara
  /// Jurnal GL di sebelahnya menyebut angka yang sebenarnya.
  bool get _untukPlatform => widget.restoId == kPlatformRestoId;

  /// Jurnal Merchant-POS, dan nomor akun GL Total Saldo-nya.
  List<GlJournalEntry> _jurnal = const [];
  String? _kodeTotalSaldo;

  /// Setoran modal — uang masuk yang bukan hasil penjualan.
  List<BalanceTopup> _topups = const [];

  int get _topupTotal => _topups.fold(0, (jumlah, t) => jumlah + t.amount);

  /// Kasir gets this screen too, but only to see the balances and write
  /// down what they spent out of the float. Topping Petty Cash up moves
  /// money out of income, and deleting rewrites the GL journal — both
  /// stay with Finance/Admin, and the database enforces it as well (see
  /// supabase/kasir_balance_access.sql), so hiding the controls here
  /// just avoids offering something that would fail.
  /// Menyetujui, mengonfirmasi, dan menghapus tetap milik Finance (dan
  /// Owner, yang memang memegang semuanya). Admin disamakan dengan
  /// kasir: keduanya mengajukan, bukan memutuskan — persetujuan atas
  /// permintaan sendiri tidak berarti apa-apa.
  bool get _canManageFunds {
    final auth = context.read<AuthProvider>();
    return !auth.isKasir && !auth.isAdmin;
  }

  /// Kasir memegang uang lacinya dan sering kehabisan kembalian di tengah
  /// shift; memintanya menunggu Finance datang hanya membuat pencatatan
  /// dilewati. Yang dijaga bukan haknya mengajukan, tapi persetujuannya.
  bool get _needsApproval {
    final auth = context.read<AuthProvider>();
    return auth.isKasir || auth.isAdmin;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Mencatat setoran modal.
  ///
  /// Nama penyetor wajib. Setoran tanpa penyetor adalah uang yang tidak
  /// bisa dipertanggungjawabkan ke siapa pun — dan yang menanyakannya
  /// setahun kemudian tidak akan menemukan jawabannya di mana pun.
  Future<void> _tambahModal() async {
    final tersimpan = await showDialog<bool>(
      context: context,
      builder: (_) => _FormModal(restoId: _restoId),
    );
    if (tersimpan == true) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final restoId = _restoId;

      if (_untukPlatform) {
        final jurnal = await GlJournalRepository().getForResto(restoId);
        final akun = await GlAccountRepository().getForResto(restoId);
        if (!mounted) return;
        setState(() {
          _jurnal = jurnal;
          _kodeTotalSaldo = akun
              .where((g) =>
                  g.paymentMethod == 'total_balance' && g.glCode.isNotEmpty)
              .firstOrNull
              ?.glCode;
          _expenses = const [];
          _expenseGlAccounts = const [];
          _pettyCashEntries = const [];
          _deposits = const [];
          _loading = false;
        });
        // Pengeluaran dan petty cash Merchant-POS tetap dimuat — keduanya
        // dipakai, cuma sumber pemasukannya yang berbeda.
        final biaya = await _expenseRepo.getForResto(restoId);
        final akunBiaya = await _expenseGlRepo.getForResto(restoId);
        final petty = await _pettyCashRepo.getForResto(restoId);
        final setoran = await _topupRepo.getForResto(restoId);
        if (!mounted) return;
        setState(() {
          _expenses = biaya;
          _expenseGlAccounts = akunBiaya;
          _pettyCashEntries = petty;
          _topups = setoran;
        });
        return;
      }

      final results = await Future.wait([
        _orderRepo.watchAll(restoId).first,
        _expenseRepo.getForResto(restoId),
        _expenseGlRepo.getForResto(restoId),
        _pettyCashRepo.getForResto(restoId),
        Supabase.instance.client.from('settings').select().eq('resto_id', restoId).limit(1),
        _depositRepo.getForResto(restoId),
        _topupRepo.getForResto(restoId),
        // Selisih kasir yang belum dilunasi. Uangnya tidak ada di laci,
        // jadi Saldo Cash tidak boleh menghitungnya sebagai ada.
        CashierShiftRepository().selisih(restoId).catchError(
            (_) => <CashVariance>[]),
      ]);
      if (!mounted) return;
      final orders = (results[0] as List<CustomerOrder>)
          .where((o) => o.paymentStatus == OrderPaymentStatus.paid);
      final settingsRows = results[4] as List<Map<String, dynamic>>;
      final settings = settingsRows.isNotEmpty ? settingsRows.first : null;
      // Tunai dipisah dari yang lain karena sifatnya beda: uangnya ada
      // di laci dan harus disetor, sementara QRIS/transfer sudah masuk
      // rekening. Pesanan lama tanpa payment_method dianggap non-tunai —
      // itu semuanya self-order QRIS.
      setState(() {
        _cashIncome = orders
            .where((o) => o.paymentMethod == 'cash')
            .fold(0, (sum, o) => sum + o.total);
        _nonCashIncome = orders
            .where((o) => o.paymentMethod != 'cash')
            .fold(0, (sum, o) => sum + o.total);
        _deposits = results[5] as List<CashDeposit>;
        _topups = results[6] as List<BalanceTopup>;
        _selisih = results[7] as List<CashVariance>;
        _expenses = results[1] as List<Expense>;
        _expenseGlAccounts = results[2] as List<ExpenseGlAccount>;
        _pettyCashEntries = results[3] as List<PettyCashEntry>;
        _bankName = settings?['bank_name'] as String?;
        _accountNumber = settings?['account_number'] as String?;
        _accountHolder = settings?['account_holder'] as String?;
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

  int get _expenseBalance => _expenses.fold(0, (sum, e) => sum + e.amount);

  /// Pengajuan yang ditolak tidak dihitung: uangnya dikembalikan ke
  /// sumbernya. Yang masih menunggu tetap dihitung, karena sejak
  /// diajukan uangnya memang sudah diambil dari sana.
  int _pettyCashFrom(PettyCashSource source) => _pettyCashEntries
      .where((e) => e.source == source && e.status != PettyCashStatus.rejected)
      .fold(0, (sum, e) => sum + e.amount);

  /// Uang tunai yang sudah keluar dari laci lewat setoran. Berpindah
  /// tempat, bukan hilang — karena itu ia dikurangkan dari Saldo Cash
  /// tapi tidak dari Saldo Total.
  ///
  /// Setoran yang ditolak tidak dihitung: uangnya dikembalikan menjadi
  /// tanggung jawab laci kasir. Yang masih menunggu persetujuan tetap
  /// dihitung, karena fisiknya memang sudah tidak ada di laci.
  int get _depositedTotal => depositedFromDrawer(_deposits);

  /// Bagian dari setoran yang masih mengendap di GL Suspense.
  int get _pendingDeposits =>
      _deposits.where((d) => d.isPending).fold(0, (sum, d) => sum + d.amount);

  /// Yang seharusnya masih ada di laci kasir sekarang.
  int get _cashBalance => cashOnHand(
        cashIncome: _cashIncome,
        deposits: _deposits,
        pettyCash: _pettyCashEntries,
        selisih: _selisih,
      );

  /// Setoran modal ikut di sini: uangnya mendarat di rekening, bukan di
  /// laci. Menaruhnya di luar Cash/Non Cash membuat kedua kartu itu
  /// berhenti berjumlah sama dengan Penghasilan — dan dua angka yang
  /// tidak bertemu di layar yang sama adalah yang pertama membuat orang
  /// berhenti mempercayai seluruh halamannya.
  int get _nonCashBalance =>
      _nonCashIncome +
      _topupTotal -
      _pettyCashFrom(PettyCashSource.incomeWithdrawal);

  /// Hanya yang sudah disetujui yang dihitung sebagai saldo petty cash.
  /// Pengajuan yang masih menunggu nilainya mengendap di GL Suspense
  /// Petty Cash — uangnya sudah keluar dari sumbernya, tapi belum boleh
  /// dibelanjakan.
  int get _pettyCashToppedUp => _pettyCashEntries
      .where((e) => e.isApproved)
      .fold(0, (sum, e) => sum + e.amount);

  int get _pettyCashPending =>
      _pettyCashEntries.where((e) => e.isPending).fold(0, (sum, e) => sum + e.amount);

  /// Penghasilan yang belum berpindah ke mana-mana: tunai yang masih di
  /// laci ditambah non-tunai yang masih utuh.
  ///
  /// Setoran modal sudah termasuk lewat [_nonCashBalance].
  int get _incomeBalance => _cashBalance + _nonCashBalance;

  /// Every expense is paid from Petty Cash, so this bucket is shown net
  /// of them — which is why the total below just adds the two rather than
  /// subtracting expenses again (that would double-count them).
  int get _pettyCashBalance => _pettyCashToppedUp - _expenseBalance;

  /// Setoran ikut dihitung: uangnya pindah ke rekening resto, bukan
  /// keluar dari resto. Tanpa baris ini setiap setoran akan terlihat
  /// seperti kehilangan uang.
  int get _totalBalance {
    // Saldo Merchant-POS dihitung dari pergerakan akun GL Total Saldo —
    // sumber yang sama persis dengan layar Jurnal GL, supaya keduanya
    // tidak pernah menyebut angka berbeda untuk uang yang sama.
    if (_untukPlatform) {
      final kode = _kodeTotalSaldo;
      if (kode == null) return 0;
      return saldoPlatform(_jurnal, kode) - _expenseBalance;
    }
    return _incomeBalance + _pettyCashBalance + _depositedTotal;
  }

  /// Uang masuk ke pembukuan Merchant-POS: langganan yang dibayar resto.
  int get _pemasukanPlatform {
    final kode = _kodeTotalSaldo;
    return kode == null ? 0 : pemasukanPlatform(_jurnal, kode);
  }

  /// Uang keluar dari saldo bebas Merchant-POS: diskon langganan, dan dana
  /// yang dialokasikan ke voucher.
  int get _keluarPlatform {
    final kode = _kodeTotalSaldo;
    return kode == null ? 0 : pengeluaranPlatform(_jurnal, kode);
  }

  List<_DayGroup<Expense>> _groupByDay(List<Expense> items) {
    final byDay = <DateTime, List<Expense>>{};
    for (final e in items) {
      final wib = e.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => _DayGroup(d, byDay[d]!, byDay[d]!.fold(0, (s, e) => s + e.amount))).toList();
  }

  List<_DayGroup<PettyCashEntry>> _groupPettyCashByDay() {
    final byDay = <DateTime, List<PettyCashEntry>>{};
    for (final e in _pettyCashEntries) {
      final wib = e.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => _DayGroup(d, byDay[d]!, byDay[d]!.fold(0, (s, e) => s + e.amount))).toList();
  }

  Future<void> _addExpense() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddExpenseDialog(
        restoId: _restoId,
        glAccounts: _expenseGlAccounts,
        availablePettyCash: _pettyCashBalance,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteExpense(Expense e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text(
          '${e.description}\n\n'
          'Jurnal GL-nya tidak dihapus — akan dicatat sebagai baris pembatalan.',
        ),
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
    await _expenseRepo.delete(e.id);
    _load();
  }

  /// Menyetujui atau menolak pengajuan top up dari kasir.
  Future<void> _reviewPettyCash(PettyCashEntry e, PettyCashStatus status) async {
    final approving = status == PettyCashStatus.approved;
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final reviewer = context.read<AuthProvider>().user?.email ?? 'Finance';
    final noteCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(approving ? Icons.verified_outlined : Icons.block,
            size: 38, color: approving ? const Color(0xFF10B981) : Colors.red),
        title: Text(approving ? 'Setujui top up?' : 'Tolak top up?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (approving) ...[
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pastikan uang tunainya benar-benar sudah diterima kas kecil '
                        'sebesar ${currency.format(e.amount)}.',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              approving
                  ? 'Setelah disetujui, ${currency.format(e.amount)} dipindah dari '
                      'GL Suspense Petty Cash ke GL Petty Cash dan statusnya menjadi '
                      'Completed.'
                  : '${currency.format(e.amount)} akan dikembalikan ke sumbernya '
                      '(${kPettyCashSourceLabels[e.source]!.replaceFirst('Withdraw dari ', '')}).',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: approving ? 'Catatan (opsional)' : 'Alasan penolakan',
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: approving ? 'Setuju' : 'Tolak',
            destructive: !approving,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _pettyCashRepo.review(e.id,
          status: status, reviewedBy: reviewer, note: noteCtrl.text);
      _load();
    } catch (err) {
      if (!mounted) return;
      showAppToast(context, 'Gagal memproses: $err', isError: true);
    }
  }

  Future<void> _addPettyCash() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddPettyCashDialog(
        restoId: _restoId,
        availableCash: _cashBalance,
        availableNonCash: _nonCashBalance,
        needsApproval: _needsApproval,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deletePettyCashEntry(PettyCashEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus entri Petty Cash?'),
        content: Text(
          '${kPettyCashSourceLabels[e.source]}'
          '${e.description != null && e.description!.isNotEmpty ? '\n${e.description}' : ''}'
          '\n\nJurnal GL-nya tidak dihapus — akan dicatat sebagai baris pembatalan.',
        ),
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
    await _pettyCashRepo.delete(e.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Saldo & Pengeluaran')),
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _totalBalance >= 0
                                ? [const Color(0xFF10B981), const Color(0xFF0F766E)]
                                : [const Color(0xFFEF4444), const Color(0xFFB91C1C)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_totalBalance >= 0
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444))
                                  .withOpacity(0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_balance_wallet_outlined,
                                      color: Colors.white.withOpacity(0.85), size: 18),
                                  const SizedBox(width: 6),
                                  Text('Saldo Total',
                                      style: TextStyle(color: Colors.white.withOpacity(0.85))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                currency.format(_totalBalance),
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Divider(height: 24, color: Colors.white.withOpacity(0.3)),
                              Text(
                                _untukPlatform
                                    ? 'Pergerakan GL Total Saldo — langganan '
                                        'masuk, diskon & voucher keluar '
                                        '(pengeluaran sudah dikurangi)'
                                    : 'Penghasilan + Petty Cash + Setoran '
                                        '(pengeluaran sudah dikurangi)',
                                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Merchant-POS tidak punya laci kasir. Memecah
                      // penghasilannya jadi tunai dan non-tunai berarti
                      // dua angka nol yang menyuruh orang mencari uang
                      // yang tidak pernah ada bentuk fisiknya.
                      if (!_untukPlatform) ...[
                        // Penghasilan dipecah dulu ke Cash/Non Cash sebelum
                        // kartu ringkasnya: angka tunai adalah yang paling
                        // sering dicari — itulah yang harus cocok dengan isi
                        // laci saat tutup toko.
                        _IncomeSplitCard(
                          cashBalance: _cashBalance,
                          nonCashBalance: _nonCashBalance,
                          deposited: _depositedTotal,
                          pending: _pendingDeposits,
                          currency: currency,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _BalanceMiniCard(
                              icon: Icons.trending_up,
                              label: _untukPlatform ? 'Uang Masuk' : 'Penghasilan',
                              value: currency.format(_untukPlatform
                                  ? _pemasukanPlatform
                                  : _incomeBalance),
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalanceMiniCard(
                              icon: Icons.savings_outlined,
                              label: _pettyCashPending > 0
                                  ? 'Petty Cash (${currency.format(_pettyCashPending)} pending)'
                                  : 'Petty Cash',
                              value: currency.format(_pettyCashBalance),
                              color: const Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalanceMiniCard(
                              icon: Icons.trending_down,
                              // Untuk Merchant-POS yang dihitung bukan cuma
                              // pengeluaran operasional: diskon langganan
                              // dan dana yang dialokasikan ke voucher juga
                              // keluar dari saldo bebasnya.
                              label: _untukPlatform ? 'Uang Keluar' : 'Pengeluaran',
                              value: '- ${currency.format(_untukPlatform
                                  ? _keluarPlatform + _expenseBalance
                                  : _expenseBalance)}',
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      if (_bankName != null &&
                          _bankName!.isNotEmpty &&
                          _accountNumber != null &&
                          _accountNumber!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Rekening Bank', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFEC4899).withOpacity(0.12),
                              child: const Icon(Icons.account_balance_outlined, color: Color(0xFFEC4899)),
                            ),
                            title: Text(_bankName!, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '$_accountNumber'
                              '${_accountHolder != null && _accountHolder!.isNotEmpty ? '\na.n. $_accountHolder' : ''}',
                            ),
                            isThreeLine: _accountHolder != null && _accountHolder!.isNotEmpty,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Modal berdiri sendiri di atas Petty Cash. Uang
                      // yang masuk dari luar tidak berhubungan dengan
                      // kas kecil, dan menyelipkannya ke sana membuat
                      // dua alur yang berbeda tampak seperti satu.
                      _SectionHeader(
                        title: 'Setoran Modal',
                        open: _topupOpen,
                        count: _topups.length,
                        onToggle: () => setState(() => _topupOpen = !_topupOpen),
                        action: _canManageFunds
                            ? _PillButton(
                                icon: Icons.savings_outlined,
                                label: 'Top Up Saldo',
                                color: const Color(0xFF14B8A6),
                                onTap: _tambahModal,
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 8),
                      if (!_topupOpen)
                        const SizedBox.shrink()
                      else if (_topups.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Belum ada setoran modal.',
                            style: TextStyle(color: MerchantPosTheme.mutedOf(context)),
                          ),
                        )
                      else
                        for (final t in _topups)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color(0xFF14B8A6).withOpacity(0.12),
                                child: const Icon(Icons.savings_outlined,
                                    color: Color(0xFF14B8A6)),
                              ),
                              title: Text(currency.format(t.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                'Dari ${t.source}'
                                '${t.note != null && t.note!.isNotEmpty ? ' · ${t.note}' : ''}'
                                '\n${DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(t.createdAt.toWib())}',
                              ),
                              isThreeLine: true,
                            ),
                          ),
                      const SizedBox(height: 24),
                      _SectionHeader(
                        title: 'Petty Cash',
                        open: _pettyCashOpen,
                        count: _pettyCashEntries.length,
                        onToggle: () =>
                            setState(() => _pettyCashOpen = !_pettyCashOpen),
                        action: _PillButton(
                            icon: Icons.add_circle_outline,
                            // Kasir mengajukan, Finance menambahkan
                            // langsung — labelnya menyebutkan bedanya
                            // supaya kasir tidak mengira saldonya sudah
                            // bertambah.
                            label: _needsApproval ? 'Ajukan Top Up' : 'Top Up',
                            color: const Color(0xFF059669),
                            onTap: _addPettyCash,
                          ),
                      ),
                      const SizedBox(height: 8),
                      if (!_pettyCashOpen)
                        const SizedBox.shrink()
                      else if (_pettyCashEntries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Belum ada Petty Cash tercatat.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ..._groupPettyCashByDay().map((group) {
                          final pendingInDay =
                              group.items.where((e) => e.isPending).length;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              // Hari yang menyimpan pengajuan terbuka
                              // sendiri. Aturan "semua tertutup" ada
                              // supaya daftar panjang tidak jadi dinding
                              // teks; hari yang menunggu keputusan bukan
                              // daftar yang sedang dibaca, tapi pekerjaan
                              // yang sedang dicari.
                              initiallyExpanded: pendingInDay > 0,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        DateFormat('EEEE, dd MMM yyyy', 'id_ID')
                                            .format(group.day),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  if (pendingInDay > 0) ...[
                                    const SizedBox(width: 8),
                                    CountBadge(count: pendingInDay),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                  pendingInDay > 0
                                      ? '+ ${currency.format(group.total)} · $pendingInDay menunggu persetujuan'
                                      : '+ ${currency.format(group.total)}',
                                  style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                              childrenPadding: const EdgeInsets.only(bottom: 4),
                              children: group.items
                                  .map((e) => Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.savings_outlined),
                                        title: Row(
                                          children: [
                                            Flexible(
                                              child: Text(kPettyCashSourceLabels[e.source]!,
                                                  overflow: TextOverflow.ellipsis),
                                            ),
                                            if (!e.isApproved) ...[
                                              const SizedBox(width: 6),
                                              _StatusChip(status: e.status),
                                            ],
                                          ],
                                        ),
                                        subtitle: Text(
                                          '${DateFormat('HH:mm').format(e.createdAt.toWib())} • ${e.createdBy}'
                                          '${e.description != null && e.description!.isNotEmpty ? ' • ${e.description}' : ''}',
                                        ),
                                        trailing: Text('+ ${currency.format(e.amount)}',
                                            style: const TextStyle(
                                                color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                                        // Ketuk membuka pembukuan di balik
                                        // baris ini. "Petty cash bertambah"
                                        // saja tidak bisa dijawab kalau ada
                                        // yang bertanya dari akun mana.
                                        onTap: () => showJournalDetail(
                                          context,
                                          restoId: _restoId,
                                          referenceId: e.id,
                                          title: kPettyCashSourceLabels[e.source]!,
                                          subtitle: currency.format(e.amount),
                                        ),
                                        onLongPress:
                                            _canManageFunds ? () => _deletePettyCashEntry(e) : null,
                                          ),
                                          if (e.isPending && _canManageFunds)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: FilledButton.icon(
                                                      icon: const Icon(Icons.check, size: 16),
                                                      label: const Text('Setuju'),
                                                      style: FilledButton.styleFrom(
                                                        backgroundColor: const Color(0xFF10B981),
                                                        minimumSize: const Size.fromHeight(36),
                                                      ),
                                                      onPressed: () => _reviewPettyCash(
                                                          e, PettyCashStatus.approved),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: OutlinedButton.icon(
                                                      icon: const Icon(Icons.close, size: 16),
                                                      label: const Text('Tolak'),
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: Colors.red,
                                                        side: const BorderSide(color: Colors.red),
                                                        minimumSize: const Size.fromHeight(36),
                                                      ),
                                                      onPressed: () => _reviewPettyCash(
                                                          e, PettyCashStatus.rejected),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ))
                                  .toList(),
                            ),
                          );
                        }),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        title: 'Riwayat Pengeluaran',
                        open: _expensesOpen,
                        count: _expenses.length,
                        onToggle: () =>
                            setState(() => _expensesOpen = !_expensesOpen),
                        action: _PillButton(
                          icon: Icons.remove_circle_outline,
                          label: 'Catat',
                          color: const Color(0xFFEF4444),
                          onTap: _addExpense,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!_expensesOpen)
                        const SizedBox.shrink()
                      else if (_expenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Belum ada pengeluaran tercatat.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ..._groupByDay(_expenses).map((group) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              initiallyExpanded: false,
                              title: Text(DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(group.day),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('- ${currency.format(group.total)}',
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                              childrenPadding: const EdgeInsets.only(bottom: 4),
                              children: group.items
                                  .map((e) => ListTile(
                                        dense: true,
                                        leading: e.receiptBase64 != null
                                            ? GestureDetector(
                                                onTap: () => Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => _ReceiptViewer(
                                                      base64Image: e.receiptBase64!,
                                                      description: e.description,
                                                    ),
                                                  ),
                                                ),
                                                child: _ReceiptThumb(base64Image: e.receiptBase64!),
                                              )
                                            : const Icon(Icons.receipt_long_outlined),
                                        title: Text(e.description),
                                        subtitle: Text(
                                          '${DateFormat('HH:mm').format(e.createdAt.toWib())} • ${e.createdBy}'
                                          '${e.glCode != null ? ' • GL ${e.glCode}' : ''}'
                                          '${e.receiptBase64 != null ? ' • ada bukti' : ''}',
                                        ),
                                        trailing: Text('- ${currency.format(e.amount)}',
                                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                        // Ketuk membuka jurnal GL-nya; foto
                                        // notanya dibuka lewat thumbnail di
                                        // kiri. Sebelumnya ketukan hanya
                                        // berfungsi kalau kebetulan ada foto,
                                        // yang membuat separuh baris terasa
                                        // mati.
                                        onTap: () => showJournalDetail(
                                          context,
                                          restoId: _restoId,
                                          referenceId: e.id,
                                          title: e.description,
                                          subtitle: currency.format(e.amount),
                                        ),
                                        onLongPress:
                                            _canManageFunds ? () => _deleteExpense(e) : null,
                                      ))
                                  .toList(),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

/// Small solid pill sitting beside a section heading — the action that
/// belongs to that section. Replaces a floating action button, which
/// covered the last rows of whatever list it hovered over.
/// Judul bagian yang bisa dilipat, berikut tombol aksinya.
///
/// Tombolnya tetap terlihat saat bagiannya tertutup — mencatat
/// pengeluaran baru tidak ada hubungannya dengan sedang membaca atau
/// tidak daftar yang lama, dan menyembunyikannya berarti memaksa satu
/// ketukan tambahan hanya untuk sampai ke tombol yang sudah ada di
/// tempatnya.
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool open;
  final int count;
  final VoidCallback onToggle;
  final Widget action;

  const _SectionHeader({
    required this.title,
    required this.open,
    required this.count,
    required this.onToggle,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: open ? 0 : -0.25,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                  const SizedBox(width: 4),
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  // Jumlahnya disebut justru saat tertutup: bagian yang
                  // dilipat tidak boleh terlihat sama dengan bagian yang
                  // memang kosong.
                  if (!open && count > 0) ...[
                    const SizedBox(width: 6),
                    Text('($count)',
                        style: TextStyle(
                            fontSize: 12, color: MerchantPosTheme.mutedOf(context))),
                  ],
                ],
              ),
            ),
          ),
        ),
        action,
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceMiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BalanceMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.85))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ReceiptThumb extends StatelessWidget {
  final String base64Image;

  const _ReceiptThumb({required this.base64Image});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        base64Decode(base64Image),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        // A corrupt blob would otherwise throw mid-paint and take the
        // whole expense list down with it.
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

/// Small circular button floated over the receipt thumbnail — a plain
/// IconButton would be invisible against a photo.
class _ReceiptAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ReceiptAction({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withOpacity(0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, zoomable look at a stored receipt.
class _ReceiptViewer extends StatelessWidget {
  final String base64Image;
  final String description;

  const _ReceiptViewer({required this.base64Image, required this.description});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(description, style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(
            base64Decode(base64Image),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              'Gambar tidak bisa ditampilkan.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayGroup<T> {
  final DateTime day;
  final List<T> items;
  final int total;

  _DayGroup(this.day, this.items, this.total);
}

/// Records an expense, always drawn from the Petty Cash float — capped at
/// [availablePettyCash] so the balance can't go negative. Top up Petty
/// Cash first if there isn't enough in it.
class _AddExpenseDialog extends StatefulWidget {
  final String restoId;
  final List<ExpenseGlAccount> glAccounts;
  final int availablePettyCash;

  const _AddExpenseDialog({
    required this.restoId,
    required this.glAccounts,
    required this.availablePettyCash,
  });

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _glCode;
  File? _receipt;
  final _repo = ExpenseRepository();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _attachReceipt() async {
    final picked = await pickProofPhoto(context);
    if (picked != null && mounted) setState(() => _receipt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      String? receiptBase64;
      if (_receipt != null) {
        receiptBase64 = base64Encode(await _receipt!.readAsBytes());
      }
      await _repo.create(Expense(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        description: _descCtrl.text.trim(),
        glCode: _glCode,
        receiptBase64: receiptBase64,
        createdBy: auth.user?.email ?? 'Finance',
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    const accentColor = Color(0xFF059669); // Petty Cash's colour throughout the app
    final noFunds = widget.availablePettyCash <= 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Catat Pengeluaran',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text('Uang keluar dari saldo merchant',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: noFunds
                        ? Colors.orange.withOpacity(0.08)
                        : accentColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: noFunds
                            ? Colors.orange.withOpacity(0.3)
                            : accentColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(noFunds ? Icons.warning_amber_outlined : Icons.savings_outlined,
                          size: 15, color: noFunds ? Colors.orange.shade800 : accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          noFunds
                              ? 'Saldo Petty Cash kosong — top up dulu sebelum mencatat pengeluaran.'
                              : 'Dipotong dari Petty Cash • tersedia ${currency.format(widget.availablePettyCash)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: noFunds ? Colors.orange.shade800 : accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: InputDecoration(label: requiredLabel('Jumlah'), prefixText: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  validator: (v) {
                    final n = parseRupiah(v ?? '');
                    if (n == null || n <= 0) return 'Wajib diisi, angka > 0';
                    if (n > widget.availablePettyCash) {
                      return 'Melebihi Petty Cash '
                          '(maks ${currency.format(widget.availablePettyCash)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: InputDecoration(label: requiredLabel('Deskripsi')),
                  maxLines: 2,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                if (widget.glAccounts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _glCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'GL Account (opsional)'),
                    items: widget.glAccounts
                        .map((g) => DropdownMenuItem(
                              value: g.glCode,
                              child: Text('${g.glCode} — ${g.glName}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _glCode = v),
                  ),
                ],
                const SizedBox(height: 14),
                Text('Bukti Pengeluaran (opsional)',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: MerchantPosTheme.mutedOf(context))),
                const SizedBox(height: 8),
                if (_receipt == null)
                  OutlinedButton.icon(
                    onPressed: _attachReceipt,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Lampirkan Foto Nota'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Image.file(
                          _receipt!,
                          width: double.infinity,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Row(
                            children: [
                              _ReceiptAction(
                                icon: Icons.edit_outlined,
                                tooltip: 'Ganti foto',
                                onTap: _attachReceipt,
                              ),
                              const SizedBox(width: 6),
                              _ReceiptAction(
                                icon: Icons.close,
                                tooltip: 'Hapus foto',
                                onTap: () => setState(() => _receipt = null),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        // Tanpa warna sendiri.
                        //
                        // accentColor menandai bagiannya — ungu untuk
                        // Petty Cash, hijau untuk penarikan — dan itu
                        // berguna pada ikon dan kotak keterangannya.
                        // Pada tombol simpan ia jadi hal lain: warna
                        // tombol adalah bahasa yang sudah dipakai
                        // seluruh aplikasi untuk membedakan tindakan
                        // biasa dari yang merusak, dan hijau di sini
                        // membuat satu tombol simpan tampak beda jenis
                        // dari semua tombol simpan lainnya.
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Funds Petty Cash either by withdrawing from Saldo Penghasilan (capped
/// at [availableIncome] so it can't go negative) or a manual top-up entry
/// (needed on day one, before any income exists to withdraw from).
class _AddPettyCashDialog extends StatefulWidget {
  final String restoId;
  /// Dipisah karena keduanya benar-benar dompet yang berbeda: menarik
  /// dari tunai mengurangi uang di laci, menarik dari non-tunai
  /// mengurangi saldo rekening. Satu angka gabungan akan membolehkan
  /// penarikan tunai yang uangnya sebenarnya tidak ada di laci.
  final int availableCash;
  final int availableNonCash;

  /// Diajukan oleh kasir: tersimpan sebagai permintaan, belum menambah
  /// saldo petty cash sampai Finance menyetujuinya.
  final bool needsApproval;

  const _AddPettyCashDialog({
    required this.restoId,
    required this.availableCash,
    required this.availableNonCash,
    this.needsApproval = false,
  });

  @override
  State<_AddPettyCashDialog> createState() => _AddPettyCashDialogState();
}

class _AddPettyCashDialogState extends State<_AddPettyCashDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  PettyCashSource _source = PettyCashSource.cashWithdrawal;
  final _repo = PettyCashRepository();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      await _repo.create(PettyCashEntry(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        source: _source,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        createdBy: auth.user?.email ?? 'Finance',
        createdAt: DateTime.now(),
        status: widget.needsApproval ? PettyCashStatus.pending : PettyCashStatus.approved,
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final isWithdrawal = _source != PettyCashSource.manual;
    final available = _source == PettyCashSource.cashWithdrawal
        ? widget.availableCash
        : widget.availableNonCash;
    final accentColor = isWithdrawal ? const Color(0xFF10B981) : const Color(0xFF059669);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.savings_outlined, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Top Up Petty Cash',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text(
                              widget.needsApproval
                                  ? 'Diajukan dulu, menunggu approval Finance'
                                  : 'Tambah saldo kas kecil',
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: MerchantPosTheme.softFillOf(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SourceTab(
                          icon: Icons.payments_outlined,
                          label: 'Cash',
                          selected: _source == PettyCashSource.cashWithdrawal,
                          color: const Color(0xFF0EA5E9),
                          onTap: () =>
                              setState(() => _source = PettyCashSource.cashWithdrawal),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _SourceTab(
                          icon: Icons.qr_code_2,
                          label: 'Non Cash',
                          selected: _source == PettyCashSource.incomeWithdrawal,
                          color: const Color(0xFF0D9488),
                          onTap: () =>
                              setState(() => _source = PettyCashSource.incomeWithdrawal),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _SourceTab(
                          icon: Icons.edit_outlined,
                          label: 'Manual',
                          selected: _source == PettyCashSource.manual,
                          color: const Color(0xFF059669),
                          onTap: () => setState(() => _source = PettyCashSource.manual),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWithdrawal) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 15, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${kPettyCashSourceLabels[_source]!.replaceFirst('Withdraw dari ', '')} '
                            'tersedia: ${currency.format(available)}',
                            style: TextStyle(
                                fontSize: 12.5, color: accentColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: InputDecoration(
                    label: requiredLabel('Jumlah'),
                    prefixText: 'Rp ',
                  ),
                  keyboardType: TextInputType.number,
                  // Pemisah ribuan seperti kolom nominal lainnya. Tanpa
                  // ini validatornya menolak "50.000" yang diketik orang
                  // secara wajar, padahal penyimpanannya sendiri sudah
                  // membaca lewat parseRupiah.
                  inputFormatters: [ThousandsInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  validator: (v) {
                    final n = parseRupiah(v ?? '');
                    if (n == null || n <= 0) return 'Wajib diisi, angka > 0';
                    // Top up manual tidak dibatasi: itu modal segar dari
                    // luar, bukan pemindahan dari saldo yang sudah ada.
                    if (isWithdrawal && n > available) {
                      return 'Melebihi ${kPettyCashSourceLabels[_source]!.replaceFirst('Withdraw dari ', '')} '
                          '(maks ${currency.format(available)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        // Tanpa warna sendiri.
                        //
                        // accentColor menandai bagiannya — ungu untuk
                        // Petty Cash, hijau untuk penarikan — dan itu
                        // berguna pada ikon dan kotak keterangannya.
                        // Pada tombol simpan ia jadi hal lain: warna
                        // tombol adalah bahasa yang sudah dipakai
                        // seluruh aplikasi untuk membedakan tindakan
                        // biasa dari yang merusak, dan hijau di sini
                        // membuat satu tombol simpan tampak beda jenis
                        // dari semua tombol simpan lainnya.
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SourceTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : MerchantPosTheme.mutedOf(context)),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : MerchantPosTheme.mutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Memecah Saldo Penghasilan jadi tunai dan non-tunai.
///
/// Keduanya terlihat sama di laporan, tapi tidak di kenyataan: yang tunai
/// masih berupa lembaran di laci dan menjadi tanggung jawab kasir sampai
/// disetorkan, sedangkan QRIS dan transfer sudah aman di rekening. Satu
/// angka gabungan menyembunyikan persis perbedaan itu.
class _IncomeSplitCard extends StatelessWidget {
  final int cashBalance;
  final int nonCashBalance;
  final int deposited;
  final int pending;
  final NumberFormat currency;

  const _IncomeSplitCard({
    required this.cashBalance,
    required this.nonCashBalance,
    required this.deposited,
    required this.pending,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MerchantPosTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MerchantPosTheme.softFillOf(context)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _half(
                  context,
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF0EA5E9),
                  label: 'Saldo Cash',
                  hint: 'Ada di laci kasir',
                  value: cashBalance,
                ),
              ),
              Container(width: 1, height: 46, color: MerchantPosTheme.softFillOf(context)),
              Expanded(
                child: _half(
                  context,
                  icon: Icons.qr_code_2,
                  color: const Color(0xFF0D9488),
                  label: 'Saldo Non Cash',
                  hint: 'QRIS & transfer',
                  value: nonCashBalance,
                ),
              ),
            ],
          ),
          if (deposited > 0) ...[
            const Divider(height: 18),
            Row(
              children: [
                Icon(Icons.account_balance_outlined, size: 15, color: MerchantPosTheme.mutedOf(context)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Sudah disetor ke rekening',
                    style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                  ),
                ),
                Text(
                  currency.format(deposited),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (pending > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.pending_actions, size: 15, color: Color(0xFFB45309)),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Menunggu approval (GL Suspense)',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                  ),
                  Text(
                    currency.format(pending),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _half(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String hint,
    required int value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            currency.format(value),
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
          ),
          Text(hint, style: TextStyle(fontSize: 10.5, color: MerchantPosTheme.mutedOf(context))),
        ],
      ),
    );
  }
}

/// Penanda status persetujuan pada baris top up petty cash.
class _StatusChip extends StatelessWidget {
  final PettyCashStatus status;

  const _StatusChip({required this.status});

  static const _colors = {
    PettyCashStatus.pending: Color(0xFFF59E0B),
    PettyCashStatus.approved: Color(0xFF10B981),
    PettyCashStatus.rejected: Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        kPettyCashStatusLabels[status]!,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// Formulir setoran modal.
///
/// Sengaja sederhana: nominal, dari siapa, keterangan, dan bukti kalau
/// ada. Yang tidak ada di sini adalah pilihan "masuk ke mana" — modal
/// selalu menambah saldo utama, dan menawarkan pilihan lain cuma
/// membuka jalan mencatatnya di tempat yang salah.
class _FormModal extends StatefulWidget {
  final String restoId;

  const _FormModal({required this.restoId});

  @override
  State<_FormModal> createState() => _FormModalState();
}

class _FormModalState extends State<_FormModal> {
  final _repo = BalanceTopupRepository();
  final _formKey = GlobalKey<FormState>();
  final _nominal = TextEditingController();
  final _dari = TextEditingController();
  final _catatan = TextEditingController();
  String? _bukti;
  bool _menyimpan = false;

  @override
  void dispose() {
    for (final c in [_nominal, _dari, _catatan]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pilihBukti() async {
    final file = await pickProofPhoto(context);
    if (file == null || !mounted) return;
    final bytes = await File(file.path).readAsBytes();
    if (!mounted) return;
    setState(() => _bukti = base64Encode(bytes));
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      await _repo.add(
        restoId: widget.restoId,
        amount: parseRupiah(_nominal.text) ?? 0,
        source: _dari.text.trim(),
        note: _catatan.text.trim(),
        proofBase64: _bukti,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      AppToast.show(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Top Up Saldo'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Uang masuk dari luar penjualan — setoran investor atau '
                'modal awal. Tercatat di jurnal sebagai GL Setoran Modal, '
                'terpisah dari pendapatan.',
                style: TextStyle(
                    fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nominal,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  label: requiredLabel('Nominal'),
                  prefixText: 'Rp ',
                ),
                validator: (v) =>
                    (parseRupiah(v ?? '') ?? 0) > 0 ? null : 'Isi nominalnya',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dari,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  label: requiredLabel('Dari'),
                  hintText: 'Nama investor atau penyetor',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Sebutkan penyetornya' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _catatan,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                ),
              ),
              const SizedBox(height: 14),
              if (_bukti == null)
                OutlinedButton.icon(
                  onPressed: _pilihBukti,
                  icon: const Icon(Icons.attach_file, size: 17),
                  label: const Text('Lampirkan Bukti (opsional)'),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Bukti terlampir')),
                    TextButton(
                      onPressed: () => setState(() => _bukti = null),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          busy: _menyimpan,
          onConfirm: _simpan,
          onCancel: () => Navigator.pop(context, false),
        ),
      ],
    );
  }
}
