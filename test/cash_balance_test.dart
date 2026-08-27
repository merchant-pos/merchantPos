import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/cash_deposit.dart';
import 'package:merchant_pos/models/petty_cash_entry.dart';
import 'package:merchant_pos/utils/cash_balance.dart';

CashDeposit _setoran(int amount, DepositStatus status) => CashDeposit(
      id: 'd-$amount-${status.name}',
      restoId: 'r1',
      amount: amount,
      status: status,
      createdBy: 'kasir@contoh.com',
      createdAt: DateTime(2026, 8, 14),
    );

PettyCashEntry _petty(
  int amount,
  PettyCashStatus status, {
  PettyCashSource source = PettyCashSource.cashWithdrawal,
}) =>
    PettyCashEntry(
      id: 'p-$amount-${status.name}',
      restoId: 'r1',
      amount: amount,
      source: source,
      status: status,
      createdBy: 'kasir@contoh.com',
      createdAt: DateTime(2026, 8, 14),
    );

void main() {
  group('cashOnHand', () {
    test('pengajuan petty cash yang ditolak tidak mengurangi laci', () {
      // Inilah selisih yang sempat muncul: Saldo & Pengeluaran membuang
      // yang ditolak, Setor Saldo Cash tidak — dan keduanya sama-sama
      // mengaku menyebut "tunai di laci".
      final tunai = cashOnHand(
        cashIncome: 303620,
        deposits: [_setoran(123689, DepositStatus.approved)],
        pettyCash: [
          _petty(10000, PettyCashStatus.approved),
          _petty(10000, PettyCashStatus.rejected),
        ],
      );

      expect(tunai, 303620 - 123689 - 10000);
    });

    test('yang masih menunggu keputusan tetap dikurangi', () {
      // Fisik uangnya sudah keluar dari laci sejak diajukan, apa pun
      // keputusannya nanti.
      final tunai = cashOnHand(
        cashIncome: 100000,
        deposits: [_setoran(20000, DepositStatus.pending)],
        pettyCash: [_petty(5000, PettyCashStatus.pending)],
      );

      expect(tunai, 75000);
    });

    test('setoran yang ditolak dikembalikan ke laci', () {
      final tunai = cashOnHand(
        cashIncome: 100000,
        deposits: [
          _setoran(20000, DepositStatus.approved),
          _setoran(30000, DepositStatus.rejected),
        ],
        pettyCash: const [],
      );

      expect(tunai, 80000);
    });

    test('petty cash dari sumber lain tidak menyentuh laci', () {
      // Withdraw dari saldo non-tunai dan top up manual tidak pernah
      // lewat laci kasir.
      final tunai = cashOnHand(
        cashIncome: 100000,
        deposits: const [],
        pettyCash: [
          _petty(50000, PettyCashStatus.approved,
              source: PettyCashSource.incomeWithdrawal),
          _petty(25000, PettyCashStatus.approved,
              source: PettyCashSource.manual),
        ],
      );

      expect(tunai, 100000);
    });
  });
}
