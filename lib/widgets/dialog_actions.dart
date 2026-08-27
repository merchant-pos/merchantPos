import 'package:flutter/material.dart';

/// Standard action layout for confirmation dialogs: the action being
/// confirmed sits on top as a full-width button, with "Batal" centered
/// underneath it.
///
/// AlertDialog's own `actions` row wraps into a column as soon as the
/// labels don't fit — and when it does, it stacks them in list order,
/// which put Batal *above* the thing you actually came to do. Laying it
/// out ourselves keeps the order intentional at every width.
///
/// Use it as the dialog's single action:
/// ```dart
/// actionsAlignment: MainAxisAlignment.center,
/// actions: [DialogActions(confirmLabel: 'Hapus', onConfirm: ..., destructive: true)],
/// ```
class DialogActions extends StatelessWidget {
  final String confirmLabel;
  final VoidCallback? onConfirm;

  /// Defaults to popping the dialog with `false`, which is what nearly
  /// every caller wants.
  final VoidCallback? onCancel;
  final String cancelLabel;

  /// Colours the confirm button red — for deletes and other actions that
  /// can't be undone.
  final bool destructive;

  /// Swaps the confirm button for a spinner and blocks both buttons,
  /// for dialogs that save before closing.
  final bool busy;

  const DialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
    this.cancelLabel = 'Batal',
    this.destructive = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: busy ? null : onConfirm,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(confirmLabel),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            // Menutup tanpa nilai, bukan dengan `false`.
            //
            // Dialog ini dipakai juga oleh showDialog<String>,
            // showDialog<int>, dan sejenisnya. Menutupnya dengan `false`
            // di sana melempar "type 'bool' is not a subtype of type
            // 'String?'" dari dalam Navigator — dan dialognya bahkan
            // tidak jadi tertutup, jadi yang menekan Batal terjebak di
            // depan galat yang tidak menyebut-nyebut tombol Batal.
            //
            // Yang memeriksa hasilnya dengan `== true` tidak terpengaruh:
            // null maupun false sama-sama bukan true.
            onPressed: busy ? null : (onCancel ?? () => Navigator.pop(context)),
            child: Text(cancelLabel),
          ),
        ),
      ],
    );
  }
}
