import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_order.dart';

/// Supabase-backed repository for orders. This is the bridge between
/// Kasir/Customer (who place orders) and Chef (who tracks kitchen status)
/// — an order written here shows up live everywhere it's watched, via
/// Postgres realtime subscriptions.
class OrderRepository {
  final _client = Supabase.instance.client;

  Future<String> create(CustomerOrder order) async {
    final row = await _client.from('orders').insert(order.toMap()).select().single();
    return row['id'] as String;
  }

  /// Membuat pesanan dan mengembalikan nomor antreannya.
  ///
  /// Nomornya diberikan pemicu di basis data, jadi baru diketahui
  /// sesudah barisnya benar-benar tersimpan — tidak bisa ditebak di
  /// aplikasi tanpa mengulangi pencacahannya, dan pencacah kedua adalah
  /// nomor kembar saat dua kasir menutup transaksi bersamaan.
  Future<int?> createReturningNo(CustomerOrder order) async {
    final row = await _client.from('orders').insert(order.toMap()).select().single();
    return (row['order_no'] as num?)?.toInt();
  }

  /// Confirms the customer's (dummy) QRIS payment. Goes through the
  /// `mark_order_paid` RPC (SECURITY DEFINER) instead of a direct table
  /// UPDATE — a guest customer has no employee RLS privileges to update
  /// `orders` directly, and the RPC's own guardrails (source='customer',
  /// pending→paid only) keep this safe without reopening that up.
  Future<void> markPaid(String orderId) async {
    await _client.rpc('mark_order_paid', params: {'p_order_id': orderId});
  }

  /// Pesanan mandiri yang pelanggannya memilih bayar tunai di kasir dan
  /// belum dilunasi — isi layar Pending Payment.
  ///
  /// Sengaja dibatasi ke `source = customer`: pesanan yang diinput kasir
  /// sudah dibayar di tempat begitu dicatat, jadi kalau ada yang masih
  /// pending di sana itu bukan antrean pembayaran melainkan data
  /// setengah jadi yang tidak boleh ikut ditagihkan di sini.
  Stream<List<CustomerOrder>> watchPendingCashPayments(String restoId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map((r) => CustomerOrder.fromMap(r))
            .where((o) => o.isPendingCashPayment)
            .toList());
  }

  /// Berapa pesanan yang menunggu dibayar di kasir — isi penanda merah
  /// di kartu menunya.
  Future<int> pendingCashPaymentCount(String restoId) async {
    return await _client
        .from('orders')
        .count(CountOption.exact)
        .eq('resto_id', restoId)
        .eq('source', 'customer')
        .eq('payment_status', 'pending')
        .eq('payment_method', 'cash');
  }

  /// Melunasi pesanan tunai di meja kasir.
  ///
  /// Uang yang diterima ikut disimpan supaya struk yang dicetak ulang
  /// nanti tetap bisa menyebut kembaliannya. Kembaliannya sendiri tidak
  /// disimpan — selalu bisa dihitung ulang, dan dua angka yang saling
  /// terikat hanya membuka peluang keduanya tidak lagi cocok.
  Future<void> settleCashPayment(
    String orderId, {
    required int cashReceived,
    String? settledBy,
  }) async {
    await _client.from('orders').update({
      'payment_status': OrderPaymentStatus.paid.name,
      'cash_received': cashReceived,
      'settled_by': settledBy ?? 'kasir',
      'settled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Melunasi pesanan dengan cara bayar selain yang dipilih pelanggan.
  ///
  /// Pelanggan memilih "bayar tunai di kasir" dari HP-nya, lalu sampai
  /// di kasir dan ternyata uangnya kurang, atau memang lebih suka
  /// membayar dengan QRIS. Tanpa ini, satu-satunya jalan keluarnya
  /// adalah membatalkan pesanan lalu mengetiknya ulang dari awal —
  /// pesanan yang sudah dimasak dapur, dengan nomor yang sudah
  /// disebutkan pelanggannya.
  ///
  /// [method] ditulis juga ke kolom cara bayarnya, bukan hanya status
  /// lunasnya: pemicu di database membaca kolom itu untuk menentukan GL
  /// mana yang dikredit. Uang QRIS yang tercatat di GL Kas berarti laci
  /// yang tidak pernah cocok, dan mutasi bank yang tidak pernah
  /// ditemukan pasangannya.
  Future<void> settlePayment(
    String orderId, {
    required String method,
    int? cashReceived,
    String? settledBy,
  }) async {
    await _client.from('orders').update({
      'payment_status': OrderPaymentStatus.paid.name,
      'payment_method': method,
      if (cashReceived != null) 'cash_received': cashReceived,
      // Ditulis apa pun cara bayarnya. Inilah yang menentukan pesanan
      // ini masuk Riwayat Kasir — bukan lagi cara bayarnya, yang justru
      // baru saja diganti di layar ini.
      'settled_by': settledBy ?? 'kasir',
      'settled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Membatalkan pesanan atas permintaan pelanggannya sendiri.
  ///
  /// Mengembalikan null kalau berhasil, atau alasan penolakannya dalam
  /// kalimat yang layak dibaca orang. Aturannya ditegakkan di database,
  /// bukan di sini: layar ini bisa saja memakai data yang sudah basi —
  /// dapur mungkin mulai memasak tepat saat tombolnya ditekan.
  Future<String?> cancelMyOrder(
    String orderId, {
    String? sessionId,
    String? email,
  }) async {
    final result = await _client.rpc('cancel_my_order', params: {
      'p_order_id': orderId,
      'p_session_id': sessionId,
      'p_email': email,
    });
    return result as String?;
  }

  /// Aliran langsung satu pesanan.
  ///
  /// Dipakai layar pembayaran untuk mengetahui pesanannya sudah lunas
  /// tanpa perlu menanyakannya berulang. Dengan gateway sungguhan,
  /// yang menyatakan lunas adalah webhook penyedia — jadi HP-nya
  /// memang harus menunggu kabar, bukan memutuskan sendiri.
  Stream<CustomerOrder?> watchOne(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? null : CustomerOrder.fromMap(rows.first));
  }

  Future<void> updateKitchenStatus(String orderId, KitchenStatus status) async {
    await _client.from('orders').update({'kitchen_status': status.name}).eq('id', orderId);
  }

  /// Menyimpan menu mana saja yang sudah dicentang dapur, sekaligus
  /// status barunya.
  ///
  /// Keduanya ditulis dalam satu perintah supaya tidak pernah ada
  /// keadaan antara: pesanan yang sudah tercentang penuh tapi statusnya
  /// masih "dimasak" karena update kedua gagal di tengah jalan.
  Future<void> updateChecklist(
    String orderId, {
    required Set<int> itemsDone,
    required KitchenStatus status,
  }) async {
    await _client.from('orders').update({
      'items_done': itemsDone.toList()..sort(),
      'kitchen_status': status.name,
    }).eq('id', orderId);
  }

  /// Live stream of all orders for one restaurant, newest first. Used by
  /// the Admin/Chef "Pesanan Masuk" screens.
  Stream<List<CustomerOrder>> watchAll(String restoId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }

  /// Live stream of orders belonging to one customer session (the "parent"
  /// id assigned right after scanning a table QR) — used by the customer's
  /// own order-status screen so they can track progress without an account.
  Stream<List<CustomerOrder>> watchBySession(String sessionId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }

  /// Hands this device's guest orders over to the email that just logged
  /// in, and reports how many were taken. Returns 0 — claiming nothing —
  /// when that email already has orders of its own, which is how the two
  /// histories stay unmerged for a returning customer.
  ///
  /// Goes through the `claim_guest_orders` RPC because customers can't
  /// UPDATE `orders` directly under RLS; the RPC reads the target email
  /// from the caller's own session rather than trusting an argument.
  Future<int> claimGuestOrders(List<String> orderIds) async {
    if (orderIds.isEmpty) return 0;
    final result = await _client.rpc(
      'claim_guest_orders',
      params: {'p_order_ids': orderIds},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// One-shot fetch of specific orders by id, newest first — backs a
  /// guest's history, where the ids come from device-local storage (see
  /// [GuestOrderStore]) rather than an account. Not a stream: Supabase
  /// realtime only filters streams by equality, and this needs `in`.
  Future<List<CustomerOrder>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('orders')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return rows.map((r) => CustomerOrder.fromMap(r)).toList();
  }

  /// Live stream of every order ever placed under this email — across
  /// every restaurant/table/session. Used by a logged-in customer's
  /// "Riwayat Saya" screen, since login (not device-local storage) is
  /// what lets their history follow them anywhere.
  Stream<List<CustomerOrder>> watchByCustomerEmail(String email) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_label', email)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }
}
