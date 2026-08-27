import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/customer_order.dart';

CustomerOrder _order({
  required OrderSource source,
  required OrderPaymentStatus status,
  String? method,
  int total = 50000,
  int? cashReceived,
  String? settledBy,
}) {
  return CustomerOrder(
    id: 'abcdef12-3456-7890-abcd-ef1234567890',
    createdAt: DateTime.utc(2026, 8, 14, 3),
    items: const [],
    total: total,
    paymentStatus: status,
    customerLabel: 'tamu@example.com',
    restoId: 'merchant-1',
    source: source,
    paymentMethod: method,
    cashReceived: cashReceived,
    settledBy: settledBy,
  );
}

void main() {
  group('isPendingCashPayment', () {
    test('pesanan mandiri tunai yang belum dibayar masuk antrean', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
          method: 'cash',
        ).isPendingCashPayment,
        isTrue,
      );
    });

    test('yang sudah dibayar keluar dari antrean', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.paid,
          method: 'cash',
        ).isPendingCashPayment,
        isFalse,
      );
    });

    test('pesanan QRIS yang belum dibayar bukan urusan kasir', () {
      // Yang ini diselesaikan pelanggan sendiri di layar QRIS-nya.
      // Memunculkannya di Pending Payment akan membuat kasir menagih
      // uang tunai untuk tagihan yang sedang dibayar lewat QR.
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
          method: 'qris',
        ).isPendingCashPayment,
        isFalse,
      );
    });

    test('pesanan lama tanpa cara bayar tidak ikut tertagih', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
        ).isPendingCashPayment,
        isFalse,
      );
    });

    test('pesanan yang diinput kasir tidak masuk antrean', () {
      // Kasir menerima uangnya di tempat saat mencatatnya. Yang pending
      // di sana adalah data setengah jadi, bukan tagihan yang menunggu.
      expect(
        _order(
          source: OrderSource.kasir,
          status: OrderPaymentStatus.pending,
          method: 'cash',
        ).isPendingCashPayment,
        isFalse,
      );
    });
  });

  group('changeDue', () {
    test('belum ada uang diterima berarti belum ada kembalian', () {
      expect(
        _order(source: OrderSource.customer, status: OrderPaymentStatus.pending)
            .changeDue,
        isNull,
      );
    });

    test('kembalian dihitung dari uang diterima dikurangi total', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
        total: 47000,
        cashReceived: 50000,
      );
      expect(order.changeDue, 3000);
    });

    test('uang pas berarti kembalian nol, bukan null', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
        total: 50000,
        cashReceived: 50000,
      );
      expect(order.changeDue, 0);
    });
  });

  group('serialisasi', () {
    test('cash_received ikut terbaca dan tertulis', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
        cashReceived: 100000,
      );
      expect(order.toMap()['cash_received'], 100000);

      final parsed = CustomerOrder.fromMap({
        'id': 'x',
        'created_at': DateTime.utc(2026, 8, 14).toIso8601String(),
        'items': const [],
        'total': 50000,
        'payment_status': 'paid',
        'customer_label': 'a@b.com',
        'resto_id': 'merchant-1',
        'source': 'customer',
        'payment_method': 'cash',
        'cash_received': 100000,
      });
      expect(parsed.cashReceived, 100000);
      expect(parsed.changeDue, 50000);
    });

    test('pesanan tanpa uang diterima tidak mengirim kolomnya', () {
      final map = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.pending,
        method: 'cash',
      ).toMap();
      // Bukan sekadar rapi: mengirim null akan menimpa nominal yang
      // sudah tercatat kalau baris yang sama pernah dilunasi.
      expect(map.containsKey('cash_received'), isFalse);
    });
  });

  group('settledAtCounter', () {
    test('pesanan mandiri tunai yang sudah dibayar masuk riwayat kasir', () {
      // Uangnya lewat laci, jadi harus ikut dihitung saat tutup shift.
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.paid,
          method: 'cash',
        ).settledAtCounter,
        isTrue,
      );
    });

    test('pesanan mandiri QRIS tidak ikut, walau sudah dibayar', () {
      // Uangnya langsung ke rekening; memasukkannya akan membuat laci
      // terlihat kurang sebanyak nominal itu.
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.paid,
          method: 'qris',
        ).settledAtCounter,
        isFalse,
      );
    });

    test('yang belum dibayar belum masuk riwayat', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
          method: 'cash',
        ).settledAtCounter,
        isFalse,
      );
    });

    test('satu pesanan tidak bisa menunggu dan selesai sekaligus', () {
      // Dua daftar ini saling mengisi: apa yang hilang dari Pending
      // Payment harus muncul di Riwayat Transaksi, tidak boleh ada di
      // keduanya dan tidak boleh lenyap dari keduanya.
      //
      // Kecuali yang hangus — itu memang tidak berada di keduanya, dan
      // itulah maksudnya: uangnya tidak pernah berpindah, jadi tidak
      // ada yang perlu ditagih dan tidak ada yang perlu dilaporkan.
      for (final status in [OrderPaymentStatus.pending, OrderPaymentStatus.paid]) {
        final order = _order(
          source: OrderSource.customer,
          status: status,
          method: 'cash',
        );
        expect(order.isPendingCashPayment && order.settledAtCounter, isFalse);
        expect(order.isPendingCashPayment || order.settledAtCounter, isTrue);
      }
    });

    test('pesanan hangus tidak masuk antrean kasir maupun riwayat', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.expired,
        method: 'cash',
      );
      expect(order.isExpired, isTrue);
      expect(order.isPendingCashPayment, isFalse);
      expect(order.settledAtCounter, isFalse);
    });

    test('tenggang bayarnya 30 menit sejak pesanannya dibuat', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.pending,
        method: 'cash',
      );
      expect(
        order.paymentDeadline.difference(order.createdAt),
        const Duration(minutes: 30),
      );
    });
  });

  group('masuk Riwayat Kasir', () {
    test('dilunasi di kasir dengan QRIS tetap masuk', () {
      // Inilah yang hilang: sejak Pending Payment bisa mengganti cara
      // bayar, cara bayarnya berubah jadi qris dan tebakan lamanya
      // ("tunai berarti dibayar di kasir") tidak lagi cocok. Uangnya
      // diterima, transaksinya lenyap dari riwayat.
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'qris',
        settledBy: 'kasir@contoh.com',
      );

      expect(order.settledAtCounter, isTrue);
    });

    test('dilunasi di kasir dengan transfer juga masuk', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'transfer',
        settledBy: 'kasir@contoh.com',
      );

      expect(order.settledAtCounter, isTrue);
    });

    test('pesanan QRIS yang dibayar sendiri lewat HP tidak ikut', () {
      // Tidak pernah menyentuh meja kasir. Memasukkannya berarti
      // menggelembungkan rekap shift dengan uang yang tidak lewat laci.
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'qris',
      );

      expect(order.settledAtCounter, isFalse);
    });

    test('baris lama tanpa penanda tetap dikenali dari cara bayarnya', () {
      // Semua yang lama dilunasi tunai — satu-satunya cara saat itu —
      // jadi tebakan lamanya masih benar untuk mereka.
      final lama = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
      );

      expect(lama.settledAtCounter, isTrue);
    });
  });
}
