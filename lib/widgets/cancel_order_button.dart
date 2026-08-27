import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import 'app_toast.dart';
import 'dialog_actions.dart';

/// Tombol batalkan pesanan, untuk dipakai di mana pun pelanggan melihat
/// pesanannya sendiri.
///
/// Satu widget, bukan disalin ke tiap layar. Pelanggan menemui
/// pesanannya di dua tempat — "Pesanan Saya" saat masih duduk di
/// restonya, dan "Riwayat" sesudahnya — dan tombol yang cuma ada di
/// salah satunya adalah fitur yang dianggap tidak ada. Dua salinan yang
/// terpisah juga berarti dua aturan yang lambat laun berbeda.
class CancelOrderButton extends StatefulWidget {
  final CustomerOrder order;

  /// Dipanggil setelah pembatalan berhasil. Layar yang memakai aliran
  /// realtime tidak perlu mengisinya — barisnya berubah sendiri.
  final VoidCallback? onCancelled;

  const CancelOrderButton({
    super.key,
    required this.order,
    this.onCancelled,
  });

  @override
  State<CancelOrderButton> createState() => _CancelOrderButtonState();
}

class _CancelOrderButtonState extends State<CancelOrderButton> {
  final _repo = OrderRepository();
  bool _busy = false;

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.cancel_outlined, size: 38, color: Colors.red),
        title: const Text('Batalkan pesanan ini?'),
        content: const Text(
          'Pesanan akan ditarik dan tidak perlu dibayar. Kalau mau pesan '
          'lagi, tinggal buat pesanan baru.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            cancelLabel: 'Tidak Jadi',
            confirmLabel: 'Batalkan',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    final sessionId =
        widget.order.sessionId ?? context.read<TableSessionProvider>().sessionId;
    final email = context.read<AuthProvider>().user?.email;
    try {
      final error = await _repo.cancelMyOrder(
        widget.order.id,
        sessionId: sessionId,
        email: email,
      );
      if (!mounted) return;
      if (error != null) {
        // Ditolak database — biasanya karena dapur mulai memasak tepat
        // di sela ketukan tadi. Alasannya disampaikan apa adanya: yang
        // membacanya sedang berdiri di resto dan butuh tahu langkah
        // berikutnya, bukan sekadar tahu bahwa gagal.
        showAppToast(context, error, isError: true);
      } else {
        showAppToast(context, 'Pesanan dibatalkan.');
        widget.onCancelled?.call();
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal membatalkan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tombolnya hanya ada selagi benar-benar bisa dipakai. Tombol yang
    // selalu tampil lalu menolak saat ditekan membuat orang mengira
    // aplikasinya rusak — padahal yang terjadi cuma dapur sudah mulai
    // memasak.
    if (!widget.order.canBeCancelledByCustomer) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cancel_outlined, size: 16),
        label: const Text('Batalkan Pesanan'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size.fromHeight(38),
        ),
        onPressed: _busy ? null : _cancel,
      ),
    );
  }
}
