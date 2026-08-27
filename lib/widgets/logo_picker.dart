import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

/// "Logo Resto" field, shared by Super Admin's create/edit form and the
/// Admin's Info Resto screen so both behave identically.
///
/// The logo is a single shared column, so whoever uploaded it, the other
/// role can replace or remove it — [onChanged] reports the new state and
/// the parent decides when to persist.
///
/// [existingBase64] is what's already stored; [picked] is a freshly
/// chosen file not yet saved. When [removed] is true the stored logo is
/// staged for deletion — which is why this can't just be "null means
/// none": null-because-untouched and null-because-cleared have to save
/// differently.
class LogoPicker extends StatelessWidget {
  final String? existingBase64;
  final File? picked;
  final bool removed;
  final bool enabled;
  final void Function({File? picked, bool removed}) onChanged;

  const LogoPicker({
    super.key,
    required this.existingBase64,
    required this.picked,
    required this.removed,
    required this.enabled,
    required this.onChanged,
  });

  ImageProvider? get _preview {
    if (picked != null) return FileImage(picked!);
    if (!removed && existingBase64 != null && existingBase64!.isNotEmpty) {
      return MemoryImage(base64Decode(existingBase64!));
    }
    return null;
  }

  Future<void> _pick(BuildContext context) async {
    // Logos are flat artwork, so 600px at 80% keeps edges crisp without
    // bloating the row the way a photo would.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 80,
    );
    if (picked == null) return;
    onChanged(picked: File(picked.path), removed: false);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final hasLogo = preview != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logo Merchant',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: MerchantPosTheme.mutedOf(context))),
        const SizedBox(height: 8),
        Row(
          children: [
            GestureDetector(
              onTap: enabled ? () => _pick(context) : null,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: MerchantPosTheme.softFillOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MerchantPosTheme.borderOf(context)),
                  image: hasLogo
                      ? DecorationImage(image: preview, fit: BoxFit.cover)
                      : null,
                ),
                child: hasLogo
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 28, color: MerchantPosTheme.mutedOf(context)),
                          const SizedBox(height: 4),
                          Text('Belum ada',
                              style: TextStyle(fontSize: 10, color: MerchantPosTheme.mutedOf(context))),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (enabled) ...[
                    OutlinedButton.icon(
                      onPressed: () => _pick(context),
                      icon: Icon(hasLogo ? Icons.edit_outlined : Icons.upload_outlined, size: 17),
                      label: Text(hasLogo ? 'Ganti Logo' : 'Upload Logo'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                        foregroundColor: MerchantPosTheme.brand,
                      ),
                    ),
                    if (hasLogo) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => onChanged(picked: null, removed: true),
                        icon: const Icon(Icons.delete_outline, size: 17),
                        label: const Text('Hapus Logo'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade200),
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      hasLogo ? 'Logo terpasang' : 'Belum ada logo',
                      style: TextStyle(fontSize: 13, color: MerchantPosTheme.mutedOf(context)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
