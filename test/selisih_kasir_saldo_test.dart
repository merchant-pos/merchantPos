import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/cash_deposit.dart';
import 'package:merchant_pos/models/cash_variance.dart';
import 'package:merchant_pos/models/petty_cash_entry.dart';
import 'package:merchant_pos/utils/cash_balance.dart';

CashVariance selisih({required int jumlah, bool lunas = false}) => CashVariance(
      id: 'v1',
      restoId: 'r1',
      shiftId: 's1',
      employeeEmail: 'andi@toko.com',
      amount: jumlah,
      lunas: lunas,
      createdAt: DateTime(2026, 8, 22),
    );

void main() {
  const kosongSetor = <CashDeposit>[];
  const kosongPetty = <PettyCashEntry>[];

  group('Saldo Cash memperhitungkan selisih kasir', () {
    test('tanpa selisih, angkanya tidak berubah', () {
      expect(
        cashOnHand(
            cashIncome: 1000000,
            deposits: kosongSetor,
            pettyCash: kosongPetty),
        1000000,
      );
    });

    // Uangnya memang tidak ada di laci. Selama ini Saldo Cash menyebut
    // jumlah yang lebih besar daripada yang bisa dihitung tangan.
    test('selisih yang belum dibayar dikurangkan', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: kosongSetor,
          pettyCash: kosongPetty,
          selisih: [selisih(jumlah: 50000)],
        ),
        950000,
      );
    });

    // Uangnya sudah kembali ke laci. Mengurangkannya dua kali berarti
    // menghukum kasir yang justru sudah membayar.
    test('yang sudah dilunasi tidak dikurangkan lagi', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: kosongSetor,
          pettyCash: kosongPetty,
          selisih: [selisih(jumlah: 50000, lunas: true)],
        ),
        1000000,
      );
    });

    test('beberapa tagihan dijumlahkan', () {
      expect(
        selisihBelumDibayar([
          selisih(jumlah: 50000),
          selisih(jumlah: 25000),
          selisih(jumlah: 10000, lunas: true),
        ]),
        75000,
      );
    });

    test('selisih berdampingan dengan setoran dan petty cash', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: [
            CashDeposit(
              id: 'd1',
              restoId: 'r1',
              amount: 300000,
              createdBy: 'andi@toko.com',
              createdAt: DateTime(2026, 8, 22),
            ),
          ],
          pettyCash: kosongPetty,
          selisih: [selisih(jumlah: 50000)],
        ),
        650000,
      );
    });
  });
}
