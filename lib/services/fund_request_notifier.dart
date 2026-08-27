import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../db/cash_deposit_repository.dart';
import '../db/petty_cash_repository.dart';
import '../models/cash_deposit.dart';
import '../models/petty_cash_entry.dart';
import 'notification_service.dart';

/// Memberitahu pengaju saat setoran tunai atau top up petty cash-nya
/// sudah diputus Finance.
///
/// Yang diberitahu hanya orang yang mengajukan, dikenali dari
/// [employeeEmail] pada kolom `created_by`. Finance tidak perlu dikabari
/// soal keputusan yang baru saja dia buat sendiri, dan kasir sebelah
/// tidak punya urusan dengan setoran laci orang lain.
///
/// Sama seperti [OrderNotifier], cara kerjanya membandingkan potret
/// sebelum dan sesudah dari aliran realtime. Potret pertama sengaja
/// tidak membunyikan apa pun: saat aplikasi dibuka, seluruh riwayat
/// datang sekaligus, dan tanpa penjagaan ini HP akan berbunyi untuk
/// setiap setoran yang sudah lama selesai.
class FundRequestNotifier {
  final String restoId;
  final String employeeEmail;

  FundRequestNotifier({required this.restoId, required this.employeeEmail});

  StreamSubscription<List<CashDeposit>>? _depositSub;
  StreamSubscription<List<PettyCashEntry>>? _pettySub;

  final Map<String, DepositStatus> _lastDeposit = {};
  final Map<String, PettyCashStatus> _lastPetty = {};
  bool _depositPrimed = false;
  bool _pettyPrimed = false;

  static final _currency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  /// Id notifikasi harus int dan stabil per pengajuan, supaya kabar baru
  /// menimpa kabar lama alih-alih menumpuk. Setoran dan petty cash
  /// dibedakan supaya dua pengajuan berbeda tidak saling menimpa kalau
  /// id-nya kebetulan berpapasan setelah dipendekkan.
  int _notifId(String prefix, String id) => '$prefix:$id'.hashCode & 0x7fffffff;

  Future<void> start() async {
    await NotificationService.instance.init();
    await stop();

    _depositSub = CashDepositRepository().watchForResto(restoId).listen(
          _onDeposits,
          onError: (e) => debugPrint('[Notif] stream setoran gagal: $e'),
        );
    _pettySub = PettyCashRepository().watchForResto(restoId).listen(
          _onPetty,
          onError: (e) => debugPrint('[Notif] stream petty cash gagal: $e'),
        );
  }

  Future<void> stop() async {
    await _depositSub?.cancel();
    await _pettySub?.cancel();
    _depositSub = null;
    _pettySub = null;
  }

  void _onDeposits(List<CashDeposit> rows) {
    final mine = rows.where((r) => r.createdBy == employeeEmail);

    if (!_depositPrimed) {
      for (final r in mine) {
        _lastDeposit[r.id] = r.status;
      }
      _depositPrimed = true;
      return;
    }

    for (final r in mine) {
      final before = _lastDeposit[r.id];
      _lastDeposit[r.id] = r.status;
      // Pengajuan yang belum pernah terlihat itu yang baru saja dia buat
      // sendiri — dan status barunya pasti masih menunggu.
      if (before == null || before == r.status) continue;

      final amount = _currency.format(r.amount);
      final (title, body) = switch (r.status) {
        DepositStatus.approved => (
            'Setoran tunai dikonfirmasi ✅',
            '$amount sudah masuk rekening merchant.',
          ),
        DepositStatus.rejected => (
            'Setoran tunai ditolak',
            '$amount dikembalikan ke Saldo Cash'
                '${_reason(r.reviewNote)}',
          ),
        // Kembali ke menunggu bukan alur yang ada; tidak ada yang perlu
        // dikabarkan untuk keadaan yang tidak seharusnya terjadi.
        DepositStatus.pending => (null, null),
      };
      if (title == null || body == null) continue;

      NotificationService.instance.showFundReview(
        id: _notifId('setor', r.id),
        title: title,
        body: body,
      );
    }
  }

  void _onPetty(List<PettyCashEntry> rows) {
    final mine = rows.where((r) => r.createdBy == employeeEmail);

    if (!_pettyPrimed) {
      for (final r in mine) {
        _lastPetty[r.id] = r.status;
      }
      _pettyPrimed = true;
      return;
    }

    for (final r in mine) {
      final before = _lastPetty[r.id];
      _lastPetty[r.id] = r.status;
      if (before == null || before == r.status) continue;

      final amount = _currency.format(r.amount);
      final (title, body) = switch (r.status) {
        PettyCashStatus.approved => (
            'Top up petty cash disetujui ✅',
            '$amount sudah masuk saldo petty cash.',
          ),
        PettyCashStatus.rejected => (
            'Top up petty cash ditolak',
            '$amount tidak jadi ditambahkan'
                '${_reason(r.reviewNote)}',
          ),
        PettyCashStatus.pending => (null, null),
      };
      if (title == null || body == null) continue;

      NotificationService.instance.showFundReview(
        id: _notifId('petty', r.id),
        title: title,
        body: body,
      );
    }
  }

  /// Alasan penolakan ditempelkan kalau Finance menuliskannya. Ditolak
  /// tanpa sebab adalah yang paling sering memicu orang bertanya lewat
  /// jalur lain, jadi kalau sebabnya ada, di sinilah tempatnya terbaca.
  String _reason(String? note) =>
      note == null || note.trim().isEmpty ? '.' : ' — ${note.trim()}';
}
