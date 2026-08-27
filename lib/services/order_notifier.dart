import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import 'notification_service.dart';

/// Siapa yang sedang mendengarkan, dan karena itu pesanan mana yang
/// pantas membunyikan HP-nya.
enum OrderWatchRole {
  /// Pesanannya sendiri, dikenali dari email atau session id.
  customer,

  /// Pesanan yang dia input sendiri lewat aplikasi kasir/admin.
  cashier,

  /// Semua pesanan yang baru masuk ke resto ini.
  chef,
}

/// Membunyikan notifikasi saat pesanan berpindah keadaan.
///
/// Aturannya beda per peran, karena yang dianggap kabar penting juga
/// beda: customer peduli pesanannya sendiri mulai dimasak, dapur peduli
/// ada pesanan baru masuk, kasir peduli pesanan yang dia layani sudah
/// siap diantar.
///
/// Cara kerjanya membandingkan potret sebelum dan sesudah dari stream
/// realtime yang memang sudah dipakai layar-layarnya — bukan menambah
/// koneksi baru. Potret pertama sengaja tidak membunyikan apa pun: saat
/// aplikasi dibuka, seluruh riwayat datang sekaligus, dan tanpa
/// penjagaan ini HP akan berbunyi berkali-kali untuk pesanan kemarin.
class OrderNotifier {
  final OrderWatchRole role;
  final String restoId;

  /// Untuk [OrderWatchRole.customer]: pesanan miliknya dikenali lewat
  /// salah satu dari keduanya (email kalau login, session kalau tamu).
  final String? customerEmail;
  final String? sessionId;

  /// Untuk [OrderWatchRole.cashier]: email petugas yang sedang login,
  /// supaya notifikasinya hanya soal pesanan yang dia input sendiri.
  final String? cashierEmail;

  OrderNotifier({
    required this.role,
    required this.restoId,
    this.customerEmail,
    this.sessionId,
    this.cashierEmail,
  });

  StreamSubscription<List<CustomerOrder>>? _sub;

  /// Keadaan terakhir yang sudah diberitakan, per id pesanan.
  final Map<String, KitchenStatus> _lastStatus = {};
  bool _primed = false;

  /// Id notifikasi harus int dan stabil per pesanan, supaya kabar baru
  /// menimpa kabar lama alih-alih menumpuk jadi lima baris untuk satu
  /// pesanan yang sama.
  int _notifId(String orderId) => orderId.hashCode & 0x7fffffff;

  Future<void> start() async {
    await NotificationService.instance.init();
    _sub?.cancel();
    _sub = OrderRepository().watchAll(restoId).listen(
      _onOrders,
      onError: (e) => debugPrint('[Notif] stream pesanan gagal: $e'),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _onOrders(List<CustomerOrder> orders) {
    final mine = orders.where(_isMine).toList();

    if (!_primed) {
      for (final o in mine) {
        _lastStatus[o.id] = o.kitchenStatus;
      }
      _primed = true;
      return;
    }

    for (final o in mine) {
      final before = _lastStatus[o.id];
      _lastStatus[o.id] = o.kitchenStatus;

      if (before == null) {
        // Pesanan yang belum pernah terlihat: baru masuk.
        _announceNew(o);
        continue;
      }
      if (before != o.kitchenStatus) _announceStatus(o);
    }
  }

  bool _isMine(CustomerOrder o) {
    switch (role) {
      case OrderWatchRole.chef:
        return true;
      case OrderWatchRole.cashier:
        // Pesanan yang masuk lewat kasir/admin, dan memang dia sendiri
        // yang input — bukan rekan sesama kasir di shift yang sama.
        return o.source != OrderSource.customer &&
            cashierEmail != null &&
            o.customerLabel == cashierEmail;
      case OrderWatchRole.customer:
        if (customerEmail != null && o.customerLabel == customerEmail) return true;
        return sessionId != null && o.sessionId == sessionId;
    }
  }

  void _announceNew(CustomerOrder o) {
    // Hanya dapur yang perlu tahu soal pesanan baru. Bagi customer dan
    // kasir, pesanan baru itu justru yang barusan mereka buat sendiri —
    // memberitahukannya kembali cuma jadi gema.
    if (role != OrderWatchRole.chef) return;

    final where = o.tableNumber != null && o.tableNumber!.isNotEmpty
        ? 'Meja ${o.tableNumber}'
        : (o.customerName?.trim().isNotEmpty == true
            ? 'Take Away · ${o.customerName!.trim()}'
            : 'Take Away');
    final items = o.items.fold<int>(0, (sum, i) => sum + i.quantity);

    NotificationService.instance.showNewOrder(
      id: _notifId(o.id),
      title: 'Pesanan baru masuk',
      body: '$where · $items item · #${_ref(o.id)}',
    );
  }

  void _announceStatus(CustomerOrder o) {
    final ref = _ref(o.id);
    final where = o.tableNumber != null && o.tableNumber!.isNotEmpty
        ? 'Meja ${o.tableNumber}'
        : 'Take Away';

    final (title, body) = switch ((role, o.kitchenStatus)) {
      (OrderWatchRole.customer, KitchenStatus.onProgress) => (
          'Pesanan kamu lagi dimasak 👨‍🍳',
          'Dapur sudah mulai. Tunggu sebentar ya — #$ref',
        ),
      (OrderWatchRole.customer, KitchenStatus.done) => (
          'Pesanan kamu siap! 🎉',
          'Selamat menikmati — #$ref',
        ),
      (OrderWatchRole.cashier, KitchenStatus.onProgress) => (
          'Pesanan $ref mulai dimasak',
          '$where · dapur sudah menerima',
        ),
      (OrderWatchRole.cashier, KitchenStatus.done) => (
          'Pesanan $ref siap diantar',
          '$where · sudah bisa diambil dari dapur',
        ),
      // Dapur yang menggerakkan statusnya sendiri, jadi tidak perlu
      // diberi tahu soal perubahan yang baru saja dia buat.
      _ => (null, null),
    };

    if (title == null || body == null) return;
    NotificationService.instance.showOrderStatus(
      id: _notifId(o.id),
      title: title,
      body: body,
    );
  }

  String _ref(String id) =>
      id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
}
