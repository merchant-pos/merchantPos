import 'order_type.dart';

class CustomerOrderItem {
  final String productId;
  final String productName;
  final int price;
  final int quantity;

  /// Selected level(s) (e.g. "Level Pedas: Pedas") plus any free-text
  /// note, combined into one display string — see [CartItem.noteSummary].
  /// Shown to the Chef/Admin so they know how to prep this line.
  final String? notes;

  CustomerOrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.notes,
  });

  int get subtotal => price * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
        if (notes != null) 'notes': notes,
      };

  factory CustomerOrderItem.fromMap(Map<String, dynamic> map) {
    return CustomerOrderItem(
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      price: (map['price'] as num).toInt(),
      quantity: (map['quantity'] as num).toInt(),
      notes: map['notes'] as String?,
    );
  }
}

/// [expired] — pesanan tunai dari HP pelanggan yang tidak pernah
/// dilunasi di kasir sampai tenggangnya habis. Dibatalkan oleh database,
/// bukan oleh siapa pun yang menekan tombol.
///
/// [cancelled] — ditarik sendiri oleh pelanggannya sebelum dibayar.
/// Dibedakan dari [expired] dengan sengaja: yang satu pesanan yang
/// ditinggalkan, yang satu lagi pesanan yang dibatalkan. Resto yang
/// membaca angkanya nanti berhak tahu bedanya.
enum OrderPaymentStatus { pending, paid, expired, cancelled }

/// Who placed the order — shown to the Chef so they know whether it came
/// from a walk-in rung up by a cashier, or a customer's own phone.
enum OrderSource { customer, kasir }

/// Kitchen prep status, tracked by the Chef and mirrored live to the
/// customer's order-status screen.
/// Keadaan pesanan di dapur.
///
/// `cancelled` ditulis pemicu saat pembayarannya batal atau hangus —
/// bukan dipilih chef. Tanpa nilai itu, kolomnya berhenti di nilai
/// terakhirnya dan tiap layar harus ingat sendiri untuk mengabaikannya.
enum KitchenStatus { waiting, onProgress, done, cancelled }

/// An order visible in the shared "Pesanan Masuk" feed: either a
/// self-service order placed by a customer (always paid via QRIS), or a
/// mirror of a sale rung up by an Employee Kasir (any payment method).
class CustomerOrder {
  final String id;

  /// Nomor antrean harian resto ini.
  ///
  /// Dimulai dari 1 tiap hari dan berdiri sendiri di tiap resto. UUID
  /// pesanannya cukup untuk mesin, tapi tidak untuk orang: kasir tidak
  /// bisa memanggil "pesanan 8f3a1c2e" ke ruangan, dan pelanggan tidak
  /// bisa mengingatnya sampai makanannya datang.
  ///
  /// Diberikan server saat pesanannya dibuat — apa pun status bayarnya,
  /// termasuk yang masih menunggu QRIS. Null hanya pada pesanan yang
  /// dibuat sebelum penomoran ini dipasang.
  final int? orderNo;

  final DateTime createdAt;
  final List<CustomerOrderItem> items;
  final int total;
  final OrderPaymentStatus paymentStatus;
  final String customerLabel; // email, or "Tamu" if not logged in
  final OrderSource source;
  final String? paymentMethod; // e.g. "Tunai", "QRIS", "Transfer" — kasir only

  /// This resto's Mapping GL Account code for [paymentMethod] (or QRIS,
  /// for customer self-orders) — kept in sync by a database trigger, not
  /// set from the app. Null if that GL isn't configured yet. See
  /// supabase/orders_gl_code.sql.
  final String? glCode;
  final String? tableNumber;
  final String? sessionId; // groups a customer's orders after scanning a table QR
  final KitchenStatus kitchenStatus;

  /// Nomor baris [items] yang sudah dicentang selesai oleh dapur.
  ///
  /// Nomor baris, bukan productId: satu produk bisa muncul beberapa kali
  /// sebagai baris terpisah dengan opsi berbeda, dan productId tidak
  /// membedakannya. Urutan [items] tidak pernah berubah setelah pesanan
  /// dibuat, jadi nomornya aman dijadikan penanda.
  final Set<int> itemsDone;
  final String restoId; // which restaurant this order belongs to
  final OrderType orderType; // dine-in or take-away, chosen at checkout

  /// Who to call out when the order's ready for pickup — mandatory for
  /// take-away (there's no table to deliver it to), unused for dine-in.
  final String? customerName;

  /// Name of the Kasir/Admin who entered this order. Null for a customer
  /// self-order — nobody entered it on their behalf.
  final String? cashierName;

  /// How [total] splits into revenue, service charge and PPN — stored on
  /// the order so the journal can credit three separate GL accounts and
  /// a reprint shows the original figures.
  final int? baseAmount;
  final int? serviceAmount;
  final int? ppnAmount;

  /// Uang yang diserahkan pelanggan saat melunasi di meja kasir. Null
  /// selama pesanannya belum dibayar tunai di sana.
  final int? cashReceived;

  /// Potongan yang benar-benar diberikan pada pesanan ini.
  ///
  /// Disimpan di barisnya sendiri, bukan dihitung ulang dari aturan
  /// diskonnya: aturannya bisa diubah atau dihapus besok, sementara
  /// struk hari ini harus tetap menyebut angka yang sama selamanya.
  final int discountAmount;
  final String? discountId;
  final String? discountName;

  /// Voucher MerchantPOS yang dipakai. Potongannya ditanggung MerchantPOS, bukan
  /// restonya — karena itu disimpan terpisah dari discount_amount, yang
  /// milik promo resto sendiri. Menyatukan keduanya membuat "berapa yang
  /// kami tanggung bulan ini" tidak punya jawaban.
  final String? voucherClaimId;
  final String? voucherCode;
  final int voucherAmount;

  CustomerOrder({
    required this.id,
    this.orderNo,
    required this.createdAt,
    required this.items,
    required this.total,
    required this.paymentStatus,
    required this.customerLabel,
    required this.restoId,
    this.source = OrderSource.customer,
    this.paymentMethod,
    this.glCode,
    this.tableNumber,
    this.sessionId,
    this.kitchenStatus = KitchenStatus.waiting,
    Set<int>? itemsDone,
    this.orderType = OrderType.dineIn,
    this.customerName,
    this.cashierName,
    this.baseAmount,
    this.serviceAmount,
    this.ppnAmount,
    this.cashReceived,
    this.discountAmount = 0,
    this.discountId,
    this.discountName,
    this.voucherClaimId,
    this.voucherCode,
    this.voucherAmount = 0,
    this.settledBy,
    this.settledAt,
  }) : itemsDone = itemsDone ?? const {};

  /// Maps to Postgres `orders` table columns (snake_case). `id` and
  /// `created_at` are left out — assigned by the database on insert.
  Map<String, dynamic> toMap() => {
        'items': items.map((i) => i.toMap()).toList(),
        'total': total,
        'payment_status': paymentStatus.name,
        'customer_label': customerLabel,
        'source': source.name,
        'resto_id': restoId,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (tableNumber != null) 'table_number': tableNumber,
        if (sessionId != null) 'session_id': sessionId,
        'kitchen_status': kitchenStatus.name,
        'order_type': orderType.dbValue,
        if (customerName != null) 'customer_name': customerName,
        if (cashierName != null) 'cashier_name': cashierName,
        if (baseAmount != null) 'base_amount': baseAmount,
        if (serviceAmount != null) 'service_amount': serviceAmount,
        if (ppnAmount != null) 'ppn_amount': ppnAmount,
        if (cashReceived != null) 'cash_received': cashReceived,
        'discount_amount': discountAmount,
        if (discountId != null) 'discount_id': discountId,
        if (discountName != null) 'discount_name': discountName,
        'voucher_amount': voucherAmount,
        if (voucherClaimId != null) 'voucher_claim_id': voucherClaimId,
        if (voucherCode != null) 'voucher_code': voucherCode,
      };

  /// Pesanan yang dipesan sendiri dari HP, dipilih bayar tunai, dan
  /// belum dilunasi di kasir — inilah yang mengisi layar Pending Payment
  /// dan menyalakan penanda merahnya.
  bool get isPendingCashPayment =>
      source == OrderSource.customer &&
      paymentStatus == OrderPaymentStatus.pending &&
      paymentMethod == 'cash';

  /// Pesanan mandiri yang uangnya belum diterima — apa pun cara
  /// bayarnya.
  ///
  /// Lebih luas daripada [isPendingCashPayment], dan itu disengaja.
  /// Yang dipakai layar dapur adalah pertanyaan "sudah dibayar atau
  /// belum", bukan "akan dibayar dengan apa": pesanan QRIS yang
  /// ditinggal tanpa dibayar sama belum lunasnya dengan yang memilih
  /// bayar tunai di kasir, dan memakai penanda yang lebih sempit
  /// membuatnya jatuh ke antrean "Baru" seolah sudah beres.
  bool get isAwaitingPayment =>
      source == OrderSource.customer &&
      paymentStatus == OrderPaymentStatus.pending;

  /// Batas waktu melunasi pesanan tunai di kasir.
  ///
  /// Tanpa batas, pesanan yang orangnya berubah pikiran — atau tidak
  /// pernah datang — menggantung selamanya di layar kasir dan di dapur,
  /// dan tiap hari sisanya menumpuk sedikit lagi. Setengah jam cukup
  /// panjang untuk berjalan ke kasir sambil mengantre, dan cukup pendek
  /// supaya antrean layarnya tetap terbaca.
  static const paymentWindow = Duration(minutes: 30);

  /// Kapan pesanan ini hangus kalau belum dibayar juga.
  DateTime get paymentDeadline => createdAt.add(paymentWindow);

  /// Sisa waktu membayar. Negatif berarti tenggangnya sudah lewat dan
  /// pembatalannya tinggal menunggu giliran tugas terjadwal berikutnya.
  Duration get paymentRemaining => paymentDeadline.difference(DateTime.now());

  /// Pesanan yang dibatalkan karena tidak dibayar.
  ///
  /// Diperiksa terpisah supaya tidak ikut terbawa ke layar dapur: sudah
  /// tidak menunggu dibayar lagi, tapi juga bukan pesanan yang harus
  /// dimasak.
  bool get isExpired => paymentStatus == OrderPaymentStatus.expired;

  bool get isCancelled => paymentStatus == OrderPaymentStatus.cancelled;

  /// Sudah tidak berjalan lagi — entah hangus atau dibatalkan. Tidak
  /// muncul di dapur, tidak menunggu dibayar, tidak masuk laporan.
  bool get isVoid => isExpired || isCancelled;

  /// Masih bisa ditarik pelanggannya sendiri.
  ///
  /// Batasnya sama dengan yang ditegakkan di database: miliknya, belum
  /// dibayar, dan dapur belum mulai memasak. Yang terakhir bukan soal
  /// kerumitan teknis — bahan yang sudah terpakai adalah kerugian yang
  /// nyata, dan yang menanggungnya bukan pihak yang menekan tombolnya.
  bool get canBeCancelledByCustomer =>
      source == OrderSource.customer &&
      paymentStatus == OrderPaymentStatus.pending &&
      kitchenStatus == KitchenStatus.waiting;

  /// Siapa yang menerima pembayarannya di meja kasir, dan kapan.
  ///
  /// Null untuk pesanan yang dibayar sendiri lewat HP — tidak ada
  /// siapa pun yang menerimanya.
  final String? settledBy;
  final DateTime? settledAt;

  /// Pesanan mandiri yang uangnya diterima di meja kasir.
  ///
  /// Ini yang membuatnya berhak masuk Riwayat Kasir walau bukan pesanan
  /// yang diinput kasir: uangnya benar-benar lewat laci, jadi harus ikut
  /// dihitung saat tutup shift.
  ///
  /// Dulu dikenali dengan menebak — "cara bayarnya tunai berarti
  /// dibayar di kasir". Tebakan itu benar selama tunai satu-satunya
  /// cara melunasi di sana. Sejak Pending Payment bisa mengganti cara
  /// bayar ke QRIS atau transfer, tebakannya jadi salah: cara bayarnya
  /// berubah, tebakannya tidak cocok, dan pesanannya lenyap dari
  /// Riwayat Kasir tepat setelah uangnya diterima.
  ///
  /// [settledBy] yang menggantikannya. Tebakan lamanya disimpan sebagai
  /// cadangan untuk baris yang terlanjur dilunasi sebelum kolom itu
  /// ada — semuanya tunai, jadi masih benar untuk mereka.
  bool get settledAtCounter =>
      source == OrderSource.customer &&
      paymentStatus == OrderPaymentStatus.paid &&
      (settledBy != null || paymentMethod == 'cash');

  /// Kembalian yang harus diserahkan, atau null kalau uangnya belum
  /// diterima. Dihitung, tidak disimpan — supaya tidak pernah ada
  /// kembalian tersimpan yang tidak lagi cocok dengan totalnya.
  int? get changeDue => cashReceived == null ? null : cashReceived! - total;

  /// Nomor yang siap ditampilkan, mis. "#014".
  ///
  /// Tiga digit supaya deretannya rata di layar dapur dan di struk —
  /// resto yang tembus seribu pesanan sehari tinggal memakai empat.
  String get nomorTampil =>
      orderNo == null ? '' : '#${orderNo.toString().padLeft(3, '0')}';

  bool get punyaNomor => orderNo != null;

  /// Pesanan ini sudah dibatalkan atau hangus.
  ///
  /// Keduanya berarti sama bagi yang memesan: makanannya tidak akan
  /// datang. Bedanya hanya siapa yang menghentikannya.
  bool get dibatalkan =>
      paymentStatus == OrderPaymentStatus.cancelled ||
      paymentStatus == OrderPaymentStatus.expired;

  factory CustomerOrder.fromMap(Map<String, dynamic> data) {
    return CustomerOrder(
      id: data['id'] as String,
      createdAt: DateTime.parse(data['created_at'] as String),
      items: (data['items'] as List<dynamic>)
          .map((i) => CustomerOrderItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      total: (data['total'] as num).toInt(),
      paymentStatus: OrderPaymentStatus.values.firstWhere(
        (e) => e.name == data['payment_status'],
        orElse: () => OrderPaymentStatus.pending,
      ),
      customerLabel: data['customer_label'] as String? ?? 'Tamu',
      source: OrderSource.values.firstWhere(
        (e) => e.name == data['source'],
        orElse: () => OrderSource.customer,
      ),
      paymentMethod: data['payment_method'] as String?,
      glCode: data['gl_code'] as String?,
      tableNumber: data['table_number']?.toString(),
      sessionId: data['session_id'] as String?,
      itemsDone: {
        for (final v in (data['items_done'] as List<dynamic>? ?? const []))
          (v as num).toInt(),
      },
      kitchenStatus: KitchenStatus.values.firstWhere(
        (e) => e.name == data['kitchen_status'],
        orElse: () => KitchenStatus.waiting,
      ),
      restoId: data['resto_id'] as String? ?? '',
      orderNo: (data['order_no'] as num?)?.toInt(),
      orderType: OrderTypeDb.fromDb(data['order_type'] as String?),
      customerName: data['customer_name'] as String?,
      cashierName: data['cashier_name'] as String?,
      baseAmount: (data['base_amount'] as num?)?.toInt(),
      serviceAmount: (data['service_amount'] as num?)?.toInt(),
      ppnAmount: (data['ppn_amount'] as num?)?.toInt(),
      cashReceived: (data['cash_received'] as num?)?.toInt(),
      discountAmount: (data['discount_amount'] as num?)?.toInt() ?? 0,
      discountId: data['discount_id'] as String?,
      discountName: data['discount_name'] as String?,
      voucherClaimId: data['voucher_claim_id'] as String?,
      voucherCode: data['voucher_code'] as String?,
      voucherAmount: (data['voucher_amount'] as num?)?.toInt() ?? 0,
      settledBy: data['settled_by'] as String?,
      settledAt: data['settled_at'] == null
          ? null
          : DateTime.parse(data['settled_at'] as String),
    );
  }
}
