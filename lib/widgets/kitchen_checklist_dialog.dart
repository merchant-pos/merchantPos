import 'package:flutter/material.dart';

import '../models/customer_order.dart';
import '../theme.dart';
import 'dialog_actions.dart';
import '../utils/lebar_web.dart';

/// Mencentang menu satu per satu sebelum pesanan dinyatakan selesai.
///
/// Tombol "Selesai" yang langsung menutup pesanan membuat satu menu yang
/// terlewat tetap tercatat selesai, dan baru ketahuan saat customer
/// bertanya. Dengan daftar centang, dapur harus melihat tiap barisnya
/// sekali — termasuk opsi seperti "tidak pedas" yang gampang tertukar
/// antara dua baris menu yang sama.
///
/// Boleh ditutup separuh jalan: yang sudah dicentang tersimpan, pesanan
/// tetap berstatus dimasak, dan sisanya bisa dilanjutkan kapan saja.
class KitchenChecklistDialog extends StatefulWidget {
  final CustomerOrder order;

  const KitchenChecklistDialog({super.key, required this.order});

  @override
  State<KitchenChecklistDialog> createState() => _KitchenChecklistDialogState();
}

class _KitchenChecklistDialogState extends State<KitchenChecklistDialog> {
  late Set<int> _done;

  @override
  void initState() {
    super.initState();
    _done = {...widget.order.itemsDone};
  }

  int get _total => widget.order.items.length;
  bool get _allDone => _done.length >= _total;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final where = order.tableNumber != null && order.tableNumber!.isNotEmpty
        ? 'Meja ${order.tableNumber}'
        : 'Take Away';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MerchantPosTheme.brand.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.checklist_rtl, color: MerchantPosTheme.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cek Menu Sebelum Selesai',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('$where · ${_ref(order.id)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_allDone ? const Color(0xFF10B981) : MerchantPosTheme.brand).withOpacity(0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _allDone
                    ? 'Semua menu sudah dicek — pesanan siap ditutup.'
                    : '${_done.length} dari $_total menu sudah dicek.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _allDone ? const Color(0xFF046C4E) : MerchantPosTheme.brandDark,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < _total; i++) _line(i, order.items[i]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DialogActions(
              confirmLabel: _allDone ? 'Tandai Pesanan Selesai' : 'Simpan Progres',
              onConfirm: () => Navigator.pop(context, _done),
              onCancel: () => Navigator.pop(context),
              cancelLabel: 'Tutup',
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(int index, CustomerOrderItem item) {
    final checked = _done.contains(index);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        checked ? _done.remove(index) : _done.add(index);
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: checked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => setState(() {
                checked ? _done.remove(index) : _done.add(index);
              }),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.quantity}× ${item.productName}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      // Dicoret, bukan dipudarkan saja: pada daftar
                      // panjang, warna abu-abu saja terlalu mudah
                      // terlewat sekilas pandang.
                      decoration: checked ? TextDecoration.lineThrough : null,
                      color: checked ? MerchantPosTheme.mutedOf(context) : MerchantPosTheme.textOf(context),
                    ),
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text(
                      item.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: checked ? MerchantPosTheme.mutedOf(context) : Colors.orange.shade800,
                        fontWeight: checked ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ref(String id) =>
      id.length >= 6 ? '#${id.substring(0, 6).toUpperCase()}' : '#$id';
}
