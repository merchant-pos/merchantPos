import 'package:flutter/material.dart';

/// The Batal/Simpan pair shown while a screen is in edit mode.
///
/// Screens that open read-only render nothing at all in view mode — there
/// used to be a "Kembali" button there, but the app bar's back arrow
/// already does that, so it was just taking up space on every form.
///
/// Cancel is expected to restore whatever was on screen before Edit was
/// tapped, not merely flip the flag — see each screen's `_cancelEdit`.
class EditActionBar extends StatelessWidget {
  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final bool saving;
  final String saveLabel;

  const EditActionBar({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saving = false,
    this.saveLabel = 'Simpan',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            // Blocked mid-save so a half-written record can't be
            // abandoned in an ambiguous state.
            onPressed: saving ? null : onCancel,
            child: const Text('Batal'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(saveLabel),
          ),
        ),
      ],
    );
  }
}
