import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import '../utils/promo_period.dart';

/// Dua pemilih tanggal — mulai dan berakhir — dengan batas yang sudah
/// ditegakkan di pemilihnya sendiri.
///
/// Batasnya dipasang di `firstDate`, bukan diperiksa setelah dipilih.
/// Kalender yang membiarkan orang menekan tanggal kemarin lalu menolak
/// pilihannya dengan pesan galat sudah membuang waktunya dua kali —
/// dan yang kedua terasa seperti tuduhan.
class PromoPeriodFields extends StatelessWidget {
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool enabled;
  final void Function(DateTime? startsOn, DateTime? endsOn) onChanged;

  const PromoPeriodFields({
    super.key,
    required this.startsOn,
    required this.endsOn,
    required this.onChanged,
    this.enabled = true,
  });

  Future<void> _pickStart(BuildContext context) async {
    final first = earliestStart();
    final picked = await showDatePicker(
      context: context,
      initialDate: startsOn ?? first,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365 * 3)),
      helpText: 'Mulai berlaku',
    );
    if (picked == null) return;
    // Tanggal berakhir yang jadi lebih awal daripada mulai dibuang, bukan
    // digeser diam-diam: yang menggesernya harus orang yang tahu promo
    // itu maunya sampai kapan.
    final end = (endsOn != null && !endsOn!.isAfter(picked)) ? null : endsOn;
    onChanged(picked, end);
  }

  Future<void> _pickEnd(BuildContext context) async {
    final first = earliestEnd(startsOn);
    final picked = await showDatePicker(
      context: context,
      initialDate: endsOn != null && endsOn!.isAfter(first) ? endsOn! : first,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365 * 3)),
      helpText: 'Berakhir',
    );
    if (picked == null) return;
    onChanged(startsOn, picked);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'id_ID');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Masa Berlaku',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(
          'Kosongkan kalau berlaku terus. Tanggal mulai tidak bisa mundur '
          'ke belakang, dan tanggal berakhir minimal besok.',
          style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DateBox(
                label: 'Mulai',
                value: startsOn == null ? 'Sekarang' : fmt.format(startsOn!),
                enabled: enabled,
                onTap: () => _pickStart(context),
                onClear: startsOn == null ? null : () => onChanged(null, endsOn),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DateBox(
                label: 'Berakhir',
                value: endsOn == null ? 'Tanpa batas' : fmt.format(endsOn!),
                enabled: enabled,
                onTap: () => _pickEnd(context),
                onClear: endsOn == null ? null : () => onChanged(startsOn, null),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateBox({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          enabled: enabled,
          suffixIcon: onClear != null && enabled
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Kosongkan',
                  onPressed: onClear,
                )
              : const Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }
}

/// Lencana kecil yang menyebut promo sedang berjalan, terjadwal, atau
/// sudah lewat.
///
/// Ada karena daftar promo yang semuanya terlihat sama membuat orang
/// menganggap yang belum mulai sudah berjalan — lalu menjanjikannya ke
/// pelanggan.
class PeriodBadge extends StatelessWidget {
  final PromoPeriod period;
  final bool active;

  const PeriodBadge({super.key, required this.period, this.active = true});

  @override
  Widget build(BuildContext context) {
    final (String label, MaterialColor color) = switch (true) {
      _ when !active => ('Nonaktif', Colors.grey),
      _ when period.isExpired() => ('Sudah lewat', Colors.red),
      _ when period.isScheduled() => ('Terjadwal', Colors.orange),
      _ => ('Berjalan', Colors.green),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color.shade700,
        ),
      ),
    );
  }
}
