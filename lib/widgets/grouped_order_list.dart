import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';

import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../utils/id_time.dart';
import 'order_card.dart';

/// Renders [orders] grouped by date (newest first, WIB calendar day),
/// then by Dine In / Take Away within each date — shared between the
/// Admin's "Pesanan Masuk" screen and each status tab on the Chef's
/// screen so both read the same way.
///
/// [actionsFor], if provided, is passed through to each [OrderCard] as
/// its trailing actions slot (the Chef's "Mulai Masak"/"Selesai" buttons).
class GroupedOrderList extends StatelessWidget {
  final List<CustomerOrder> orders;
  final Widget? Function(CustomerOrder order)? actionsFor;

  /// Layar dapur membiarkan rincian terbuka pada antrean yang sedang
  /// dikerjakan — isinya justru yang harus dimasak. Di tempat lain
  /// dimulai tertutup, karena orang sedang menelusuri banyak pesanan
  /// untuk mencari satu.
  final bool expandItems;

  /// Membungkus tiap tanggal jadi kelompok yang bisa dilipat. Dipakai
  /// pada daftar yang isinya menumpuk tanpa batas — pesanan selesai
  /// kemarin, minggu lalu, bulan lalu — di mana yang dicari hampir
  /// selalu satu hari tertentu, bukan semuanya sekaligus.
  final bool collapsibleDays;

  const GroupedOrderList({
    super.key,
    required this.orders,
    this.actionsFor,
    this.expandItems = true,
    this.collapsibleDays = false,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEEE, dd MMMM yyyy', 'id_ID');

    final sorted = [...orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final byDate = <DateTime, List<CustomerOrder>>{};
    for (final o in sorted) {
      final wib = o.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDate.putIfAbsent(day, () => []).add(o);
    }
    final dateKeys = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: dateKeys.length,
      itemBuilder: (context, index) {
        final day = dateKeys[index];
        final dayOrders = byDate[day]!;
        final dineIn = dayOrders.where((o) => o.orderType == OrderType.dineIn).toList();
        final takeAway = dayOrders.where((o) => o.orderType == OrderType.takeAway).toList();

        final sections = <Widget>[
              if (dineIn.isNotEmpty) ...[
                _TypeHeader(icon: Icons.restaurant_outlined, label: 'Dine In', count: dineIn.length),
                ...dineIn.map((o) => OrderCard(
                      order: o,
                      actions: actionsFor?.call(o),
                      initiallyExpanded: expandItems,
                    )),
              ],
              if (takeAway.isNotEmpty) ...[
                _TypeHeader(
                    icon: Icons.shopping_bag_outlined, label: 'Take Away', count: takeAway.length),
                ...takeAway.map((o) => OrderCard(
                      order: o,
                      actions: actionsFor?.call(o),
                      initiallyExpanded: expandItems,
                    )),
              ],
        ];

        if (collapsibleDays) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: MerchantPosTheme.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MerchantPosTheme.borderOf(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              // Menghilangkan garis pemisah bawaan ExpansionTile, yang
              // bertabrakan dengan garis tepi kartunya sendiri.
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                title: Text(
                  dateFmt.format(day),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                subtitle: Text(
                  '${dayOrders.length} pesanan',
                  style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                children: sections,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  dateFmt.format(day),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              ...sections,
            ],
          ),
        );
      },
    );
  }
}

class _TypeHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _TypeHeader({required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: MerchantPosTheme.mutedOf(context)),
          const SizedBox(width: 6),
          Text(
            '$label ($count)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: MerchantPosTheme.mutedOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
