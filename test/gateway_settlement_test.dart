import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/gateway_settlement.dart';

GatewaySettlement _s({required int gross, required int fee, required int net}) =>
    GatewaySettlement(
      id: 's1',
      restoId: 'merchant-1',
      settledOn: DateTime.utc(2026, 8, 17),
      grossAmount: gross,
      feeAmount: fee,
      netAmount: net,
      createdAt: DateTime.utc(2026, 8, 17),
    );

void main() {
  group('selisih pencairan', () {
    test('pencairan normal tidak menyisakan selisih', () {
      expect(_s(gross: 1000000, fee: 7000, net: 993000).discrepancy, 0);
    });

    test('kurang dari yang seharusnya terbaca sebagai selisih positif', () {
      // Angka inilah yang jadi bahan pertanyaan ke penyedia. Kalau neto
      // dihitung ulang dari bruto dikurangi biaya, selisih ini tidak
      // akan pernah terlihat — dan yang hilang justru buktinya.
      expect(_s(gross: 1000000, fee: 7000, net: 990000).discrepancy, 3000);
    });

    test('lebih dari yang seharusnya terbaca sebagai selisih negatif', () {
      expect(_s(gross: 1000000, fee: 7000, net: 995000).discrepancy, -2000);
    });
  });

  group('serialisasi', () {
    test('tanggal dikirim sebagai tanggal saja, tanpa jam', () {
      // Kolomnya bertipe date. Mengirim stempel waktu penuh membuat
      // pencairan yang dicatat lewat tengah malam WIB tercatat di hari
      // yang salah.
      final map = _s(gross: 1000, fee: 7, net: 993).toMap();
      expect(map['settled_on'], '2026-08-17');
    });

    test('ketiga nominalnya dikirim apa adanya', () {
      final map = _s(gross: 1000000, fee: 7000, net: 990000).toMap();
      expect(map['gross_amount'], 1000000);
      expect(map['fee_amount'], 7000);
      expect(map['net_amount'], 990000);
    });
  });
}
