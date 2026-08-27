import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../utils/id_time.dart';
import 'customer_receipt_screen.dart';

/// Normalises an order's payment into 'cash' | 'qris' | 'transfer'.
/// Orders written before the payment-method keys were lowercased still
/// carry the display labels, so both spellings are accepted.
String _methodKey(CustomerOrder o) {
  switch (o.paymentMethod) {
    case 'QRIS':
    case 'qris':
      return 'qris';
    case 'Transfer':
    case 'transfer':
      return 'transfer';
    default:
      return 'cash';
  }
}

const _methodLabels = {'cash': 'Tunai', 'qris': 'QRIS', 'transfer': 'Transfer'};

/// One day of Kasir/Admin sales plus the totals for its summary header —
/// the day's take, and how much of it came in as cash vs QRIS vs
/// transfer, which is what a shift close actually needs.
class _DayGroup {
  final DateTime day;
  final List<CustomerOrder> orders;
  final int total;
  final Map<String, int> byMethod;

  _DayGroup(this.day, this.orders)
      : total = orders.fold(0, (sum, o) => sum + o.total),
        byMethod = {
          for (final m in _methodLabels.keys)
            m: orders.where((o) => _methodKey(o) == m).fold(0, (s, o) => s + o.total),
        };
}

/// Sales rung up through Kasir/Admin, grouped by day.
///
/// Reads the shared `orders` table rather than this device's local
/// database: a shift close has to show every sale the resto took, not
/// just the ones typed on one phone, and it has to survive a phone being
/// replaced.
///
/// Yang menentukan sebuah pesanan masuk ke sini bukan siapa yang
/// mengetiknya, tapi apakah uangnya lewat laci kasir. Pesanan mandiri
/// yang dibayar QRIS tetap tidak ikut — uangnya langsung ke rekening,
/// dan memasukkannya hanya akan membuat angka yang sedang dicocokkan
/// tidak lagi cocok dengan isi laci. Tapi pesanan mandiri yang dibayar
/// tunai di meja kasir justru sebaliknya: uangnya ada di laci, jadi
/// meninggalkannya di luar akan membuat lacinya terlihat kelebihan.
class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});

  List<_DayGroup> _groupByDay(List<CustomerOrder> orders) {
    final byDay = <DateTime, List<CustomerOrder>>{};
    for (final o in orders) {
      final wib = o.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDay.putIfAbsent(day, () => []).add(o);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a)); // newest first
    return days.map((d) => _DayGroup(d, byDay[d]!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dayFmt = DateFormat('EEEE, dd MMM yyyy', 'id_ID');
    final timeFmt = DateFormat('HH:mm', 'id_ID');
    final restoId = context.watch<AuthProvider>().restoId;

    if (restoId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Kasir')),
        body: const Center(child: Text('Akun ini belum punya Merchant ID.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Kasir')),
      body: StreamBuilder<List<CustomerOrder>>(
        stream: OrderRepository().watchAll(restoId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat transaksi.\n${snapshot.error}',
                  textAlign: TextAlign.center),
            );
          }

          final orders = (snapshot.data ?? [])
              .where((o) => o.source == OrderSource.kasir || o.settledAtCounter)
              .toList();
          if (orders.isEmpty) {
            return const Center(child: Text('Belum ada transaksi kasir.'));
          }

          final groups = _groupByDay(orders);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: false,
                  title: Text(
                    dayFmt.format(group.day),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${currency.format(group.total)} • ${group.orders.length} transaksi',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _methodLabels.entries
                              .where((e) => group.byMethod[e.key]! > 0)
                              .map((e) => '${e.value} ${currency.format(group.byMethod[e.key]!)}')
                              .join(' · '),
                          style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
                        ),
                      ],
                    ),
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: group.orders.map((o) {
                    final hasCashier = o.cashierName != null && o.cashierName!.isNotEmpty;
                    return ListTile(
                      dense: true,
                      title: Text(currency.format(o.total)),
                      subtitle: Text(
                        '${timeFmt.format(o.createdAt.toWib())} • '
                        '${_methodLabels[_methodKey(o)]} • '
                        '#${o.id.substring(0, 8).toUpperCase()}'
                        '${hasCashier ? '\nOleh ${o.cashierName}' : ''}',
                      ),
                      isThreeLine: hasCashier,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${o.items.length} item',
                              style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 12.5)),
                          const SizedBox(width: 4),
                          Icon(Icons.print_outlined, size: 18, color: MerchantPosTheme.mutedOf(context)),
                        ],
                      ),
                      // Struk hilang, printer macet, pelanggan minta
                      // salinan untuk klaim kantor — semuanya berakhir di
                      // sini, dan sebelumnya tidak ada jalan keluarnya
                      // selain membuat transaksi palsu.
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CustomerReceiptScreen(order: o, forStaff: true),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
