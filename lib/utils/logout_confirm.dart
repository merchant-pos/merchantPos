import 'package:flutter/material.dart';

import '../widgets/dialog_actions.dart';

/// Shared "Yakin ingin keluar?" confirmation dialog, used by every
/// screen's Logout button so the behavior is consistent app-wide.
/// Returns true only if the user explicitly tapped "Keluar".
Future<bool> confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.logout, size: 40, color: Colors.red),
      title: const Text('Keluar?'),
      content: const Text(
        'Kamu yakin ingin keluar dari akun ini?',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Keluar',
          destructive: true,
          onConfirm: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
