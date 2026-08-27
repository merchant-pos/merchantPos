import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats a money field with thousand separators as it's typed, so
/// 1000000 reads as 1.000.000 instead of a wall of zeroes nobody can
/// count at a glance — which matters most at the counter, where a
/// mistyped digit becomes real money.
///
/// Only digits survive; the separators are presentation. Read the value
/// back with [parseRupiah], never `int.parse` on the raw text.
class ThousandsInputFormatter extends TextInputFormatter {
  static final _fmt = NumberFormat.decimalPattern('id_ID');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Price deltas may be negative (a smaller size costing less), so a
    // leading minus survives; everything else is stripped.
    final negative = newValue.text.trimLeft().startsWith('-');
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return TextEditingValue(
        text: negative ? '-' : '',
        selection: TextSelection.collapsed(offset: negative ? 1 : 0),
      );
    }

    // Strip leading zeroes so "0500" doesn't stick around as "0.500".
    final value = int.tryParse(digits);
    if (value == null) return oldValue;

    final formatted = '${negative ? '-' : ''}${_fmt.format(value)}';
    // Keep the caret at the end: with separators being inserted and
    // removed mid-string, preserving the original offset would land it
    // in the wrong place more often than not.
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Reads a field formatted by [ThousandsInputFormatter] back to a plain
/// integer. Returns null when nothing usable was typed.
int? parseRupiah(String text) {
  final negative = text.trimLeft().startsWith('-');
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final value = int.tryParse(digits);
  return value == null ? null : (negative ? -value : value);
}

/// Formats an int for pre-filling a money field (editing an existing
/// price, for instance) so it matches what the formatter would produce.
String formatRupiahInput(int? value) {
  if (value == null) return '';
  final formatted = ThousandsInputFormatter._fmt.format(value.abs());
  return value < 0 ? '-$formatted' : formatted;
}
