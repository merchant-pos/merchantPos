import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt_data.dart';

/// The receipt itself, drawn like a printed thermal slip: white paper,
/// black ink, dashed rules, monospaced figures so the amounts line up in
/// a column.
///
/// Deliberately monochrome — a receipt is a record, not part of the app's
/// chrome, and the same layout is what gets rasterised into the PNG a
/// customer saves. Keeping both identical means the copy in their gallery
/// looks like the one they saw on screen.
class ReceiptView extends StatelessWidget {
  final ReceiptData data;

  const ReceiptView({super.key, required this.data});

  static const _ink = Color(0xFF111111);
  static const _inkSoft = Color(0xFF666666);
  static const _rule = Color(0xFFBBBBBB);

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.decimalPattern('id_ID');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          color: _ink,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _dashed(),
            for (final (label, value) in data.headerRows) _row(label, value),
            _dashed(),
            for (final line in data.lines) _item(line, currency),
            _dashed(),
            _row('Subtotal', currency.format(data.subtotal), soft: true),
            if ((data.serviceAmount ?? 0) > 0)
              _row('Biaya Service', currency.format(data.serviceAmount!), soft: true),
            if ((data.ppnAmount ?? 0) > 0)
              _row('PPN', currency.format(data.ppnAmount!), soft: true),
            _row('${data.itemCount} item', '', soft: true),
            const Divider(height: 18, thickness: 1, color: _ink),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL',
                    style: TextStyle(
                        fontFamily: null, fontSize: 14, fontWeight: FontWeight.bold, color: _ink)),
                Text('Rp ${currency.format(data.total)}',
                    style: const TextStyle(
                        fontFamily: null, fontSize: 20, fontWeight: FontWeight.bold, color: _ink)),
              ],
            ),
            if (data.cashReceived != null) ...[
              const SizedBox(height: 6),
              _row('Uang Bayar', currency.format(data.cashReceived!)),
              _row('Kembalian', currency.format(data.changeDue!)),
            ],
            _dashed(),
            for (final (label, value) in data.footerRows) _row(label, value),
            if (data.paid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: _ink),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: _ink),
                    SizedBox(width: 5),
                    Text('PEMBAYARAN BERHASIL',
                        style: TextStyle(
                            fontFamily: null,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                            color: _ink)),
                  ],
                ),
              ),
            ],
            if (data.inclusiveNote != null) ...[
              const SizedBox(height: 10),
              Text(
                data.inclusiveNote!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9.5, height: 1.35, color: _inkSoft),
              ),
            ],
            const SizedBox(height: 14),
            const Center(
              child: Text('Terima kasih sudah memesan!',
                  style: TextStyle(fontSize: 10.5, color: _inkSoft)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final logo = data.restoLogoBase64;
    final hasLogo = logo != null && logo.isNotEmpty;

    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _rule),
            image: hasLogo
                ? DecorationImage(image: MemoryImage(base64Decode(logo)), fit: BoxFit.cover)
                : null,
          ),
          child: hasLogo
              ? null
              : const Icon(Icons.storefront_outlined, size: 26, color: _ink),
        ),
        const SizedBox(height: 8),
        Text(
          data.restoName,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: null, fontSize: 17, fontWeight: FontWeight.bold, color: _ink),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('powered by', style: TextStyle(fontSize: 10, color: _inkSoft)),
            const SizedBox(width: 4),
            Image.asset('assets/icon/merchantpos_icon.png', width: 13, height: 13),
            const SizedBox(width: 4),
            const Text('Merchant-POS',
                style: TextStyle(fontFamily: null, fontSize: 10, color: _inkSoft)),
          ],
        ),
        if (data.restoAddress != null && data.restoAddress!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            data.restoAddress!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, height: 1.4, color: _inkSoft),
          ),
        ],
        if (data.restoPhone != null && data.restoPhone!.trim().isNotEmpty)
          Text(
            data.restoPhone!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, height: 1.4, color: _inkSoft),
          ),
      ],
    );
  }

  Widget _dashed() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: _DashedRule(),
      );

  Widget _row(String label, String value, {bool soft = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _inkSoft)),
        Text(value, style: TextStyle(fontSize: 12, color: soft ? _inkSoft : _ink)),
      ],
    );
  }

  Widget _item(ReceiptLine line, NumberFormat currency) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(line.name)),
              const SizedBox(width: 10),
              Text(currency.format(line.subtotal)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              '${line.quantity} x ${currency.format(line.unitPrice)}'
              '${line.note != null && line.note!.isNotEmpty ? ' · ${line.note}' : ''}',
              style: const TextStyle(fontSize: 10.5, color: _inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dashed horizontal rule. Flutter has no dashed border, and a real
/// receipt's perforated look is most of what makes this read as one.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 3.0;
        const gap = 3.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(width: dash, height: 1, color: ReceiptView._rule),
          ),
        );
      },
    );
  }
}
