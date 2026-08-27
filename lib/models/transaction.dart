import 'order_type.dart';

class TransactionItem {
  final String productId;
  final String productName;
  final int price;
  final int quantity;

  /// Selected level(s) (e.g. "Level Pedas: Pedas") plus any free-text
  /// note, combined into one display string — see [CartItem.noteSummary].
  final String? notes;

  TransactionItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.notes,
  });

  int get subtotal => price * quantity;

  Map<String, dynamic> toMap(String transactionId) {
    return {
      'transactionId': transactionId,
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'notes': notes,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      price: map['price'] as int,
      quantity: map['quantity'] as int,
      notes: map['notes'] as String?,
    );
  }
}

enum PaymentMethod { cash, qris, transfer }

class PosTransaction {
  final String id;

  /// Nomor antrean harian restonya, sama dengan yang dilihat pelanggan.
  ///
  /// Struk yang menyebut nomor berbeda dari yang diteriakkan kasir
  /// adalah struk yang tidak bisa dipakai mencocokkan apa pun.
  final int? orderNo;
  final DateTime createdAt;
  final List<TransactionItem> items;
  final PaymentMethod paymentMethod;
  final int total;
  final OrderType orderType;

  /// Who to call out when the order's ready — mandatory for
  /// [OrderType.takeAway] (there's no table to deliver it to), unused
  /// for dine-in.
  final String? customerName;

  /// Name of the Kasir/Admin who rang this sale up — shown on the
  /// receipt and in Riwayat Transaksi so a day's takings can be traced
  /// back to whoever was on shift.
  final String? cashierName;

  /// How much cash the customer handed over. Only set for
  /// [PaymentMethod.cash] — QRIS and transfer are always exact, so there
  /// is nothing to give back.
  final int? cashReceived;

  /// How [total] splits into revenue, service charge and PPN. Stored
  /// rather than recomputed so a receipt reprinted later still shows the
  /// figures that were actually charged, even if the resto has changed
  /// its rates since.
  final int? baseAmount;
  final int? serviceAmount;
  final int? ppnAmount;

  PosTransaction({
    required this.id,
    this.orderNo,
    required this.createdAt,
    required this.items,
    required this.paymentMethod,
    required this.total,
    this.orderType = OrderType.dineIn,
    this.customerName,
    this.cashierName,
    this.cashReceived,
    this.baseAmount,
    this.serviceAmount,
    this.ppnAmount,
  });

  /// Change owed back. Null unless this was a cash sale.
  int? get changeDue => cashReceived == null ? null : cashReceived! - total;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'paymentMethod': paymentMethod.name,
      'total': total,
      'orderType': orderType.dbValue,
      'customerName': customerName,
      'cashierName': cashierName,
      'cashReceived': cashReceived,
      'baseAmount': baseAmount,
      'serviceAmount': serviceAmount,
      'ppnAmount': ppnAmount,
      'orderNo': orderNo,
    };
  }

  /// Nomor yang siap ditampilkan, mis. "#014".
  String get nomorTampil =>
      orderNo == null ? '' : '#${orderNo.toString().padLeft(3, '0')}';

  bool get punyaNomor => orderNo != null;

  /// Salinan dengan nomor antreannya terisi.
  ///
  /// Nomornya baru diketahui sesudah pesanannya tersimpan di server,
  /// sementara struknya sudah terbentuk sebelum itu.
  PosTransaction denganNomor(int nomor) => PosTransaction(
        id: id,
        orderNo: nomor,
        createdAt: createdAt,
        items: items,
        paymentMethod: paymentMethod,
        total: total,
        orderType: orderType,
        customerName: customerName,
        cashierName: cashierName,
        cashReceived: cashReceived,
        baseAmount: baseAmount,
        serviceAmount: serviceAmount,
        ppnAmount: ppnAmount,
      );

  factory PosTransaction.fromMap(
    Map<String, dynamic> map,
    List<TransactionItem> items,
  ) {
    return PosTransaction(
      id: map['id'] as String,
      // Dua sumber, dua nama kolom: baris sqflite memakai `orderNo`,
      // baris Supabase memakai `order_no`. Keduanya dibaca di sini
      // supaya struk lama maupun baru sama-sama menemukan nomornya.
      orderNo: (map['orderNo'] as num?)?.toInt() ??
          (map['order_no'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      items: items,
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == map['paymentMethod'],
      ),
      total: map['total'] as int,
      orderType: OrderTypeDb.fromDb(map['orderType'] as String?),
      customerName: map['customerName'] as String?,
      cashierName: map['cashierName'] as String?,
      cashReceived: map['cashReceived'] as int?,
      baseAmount: map['baseAmount'] as int?,
      serviceAmount: map['serviceAmount'] as int?,
      ppnAmount: map['ppnAmount'] as int?,
    );
  }
}
