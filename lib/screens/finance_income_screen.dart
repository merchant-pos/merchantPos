import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../utils/id_time.dart';

/// Resto-wide daily income summary for Finance — pulls every PAID order
/// from Supabase `orders` (both Kasir walk-in sales and customer
/// self-orders, across every device), grouped by day, with a Cash/QRIS/
/// Transfer breakdown per day. Unlike the Kasir's local "Riwayat
/// Transaksi" (this device's SQLite only), this is the authoritative
/// resto-wide picture Finance needs.
class FinanceIncomeScreen extends StatefulWidget {
  /// Resto yang dibukukan. Kosong berarti resto tempat orangnya bekerja.
  ///
  /// Diisi hanya oleh menu Finance Super Admin, yang membukukan Merchant-POS
  /// sendiri — penyewa platform yang memakai mesin pembukuan yang sama
  /// persis dengan resto.
  final String? restoId;

  const FinanceIncomeScreen({super.key, this.restoId});

  @override
  State<FinanceIncomeScreen> createState() => _FinanceIncomeScreenState();
}

class _DayIncome {
  final DateTime day;
  final List<CustomerOrder> orders;
  final int total;
  final Map<String, int> byMethod; // 'cash' | 'qris' | 'transfer'

  _DayIncome(this.day, this.orders)
      : total = orders.fold(0, (sum, o) => sum + o.total),
        byMethod = {
          for (final m in ['cash', 'qris', 'transfer'])
            m: orders.where((o) => _methodKey(o) == m).fold(0, (s, o) => s + o.total),
        };
}

/// Normalizes an order's payment into one of 'cash' | 'qris' | 'transfer'
/// — matching `gl_accounts.payment_method` so income can be grouped the
/// same way it's booked to GL. Customer self-orders always write 'qris'
/// directly now; Kasir sales write the lowercase key too going forward
/// (see cart_provider.dart), but this still recognizes the old
/// capitalized labels ('QRIS'/'Transfer'/'Tunai') so orders recorded
/// before that change still group correctly.
String _methodKey(CustomerOrder o) {
  switch (o.paymentMethod) {
    case 'QRIS':
    case 'qris':
      return 'qris';
    case 'Transfer':
    case 'transfer':
      return 'transfer';
    case 'Tunai':
    case 'cash':
      return 'cash';
  }
  // Pesanan mandiri lama tidak pernah mengisi payment_method, dan saat
  // itu QRIS memang satu-satunya pilihannya. Tebakan ini hanya berlaku
  // untuk baris yang benar-benar bungkam — pesanan mandiri yang menyebut
  // 'cash' sekarang berarti dibayar di meja kasir, dan menghitungnya
  // sebagai QRIS akan membuat Finance mencari mutasi yang tidak ada.
  return o.source == OrderSource.customer ? 'qris' : 'cash';
}

class _FinanceIncomeScreenState extends State<FinanceIncomeScreen> {
  final _orderRepo = OrderRepository();
  List<CustomerOrder> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final restoId = widget.restoId ?? context.read<AuthProvider>().restoId!;
    final all = await _orderRepo.watchAll(restoId).first;
    if (!mounted) return;
    setState(() {
      _orders = all.where((o) => o.paymentStatus == OrderPaymentStatus.paid).toList();
      _loading = false;
    });
  }

  List<_DayIncome> _groupByDay() {
    final byDay = <DateTime, List<CustomerOrder>>{};
    for (final o in _orders) {
      final wib = o.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDay.putIfAbsent(day, () => []).add(o);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => _DayIncome(d, byDay[d]!)).toList();
  }

  static const _methodLabels = {'cash': 'Tunai', 'qris': 'QRIS', 'transfer': 'Transfer'};

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dayFmt = DateFormat('EEEE, dd MMM yyyy', 'id_ID');
    final groups = _groupByDay();
    final grandTotal = _orders.fold(0, (sum, o) => sum + o.total);

    return Scaffold(
      appBar: AppBar(title: const Text('Pemasukan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('Belum ada pemasukan.'))
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF10B981), Color(0xFF0F766E)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.trending_up, color: Colors.white.withOpacity(0.85), size: 18),
                              const SizedBox(width: 6),
                              Text('Total Pemasukan (semua waktu)',
                                  style: TextStyle(color: Colors.white.withOpacity(0.85))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(currency.format(grandTotal),
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: groups.length,
                        itemBuilder: (context, i) {
                          final g = groups[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ExpansionTile(
                              initiallyExpanded: false,
                              title: Text(dayFmt.format(g.day),
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Total: ${currency.format(g.total)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: _methodLabels.keys
                                          .where((m) => g.byMethod[m]! > 0)
                                          .map((m) => Chip(
                                                visualDensity: VisualDensity.compact,
                                                label: Text(
                                                  '${_methodLabels[m]}: ${currency.format(g.byMethod[m])}',
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                              childrenPadding: const EdgeInsets.only(bottom: 8),
                              children: g.orders.map((o) {
                                return ListTile(
                                  dense: true,
                                  title: Text(currency.format(o.total)),
                                  subtitle: Text(
                                    '${DateFormat('HH:mm').format(o.createdAt.toWib())} • '
                                    '${_methodLabels[_methodKey(o)]} • #${o.id.substring(0, 8).toUpperCase()}',
                                  ),
                                  trailing: Text('${o.items.length} item'),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
