import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/gl_journal_entry.dart';
import 'package:merchant_pos/utils/saldo_jurnal.dart';

const _total = '1100040';

GlJournalEntry _baris({
  required String glCode,
  required int amount,
  required JournalEntryType type,
  String referenceType = 'billing',
  String referenceId = 'X',
  bool isReversal = false,
}) =>
    GlJournalEntry(
      id: '$referenceId-$glCode-${type.name}-$amount',
      restoId: 'merchantpos',
      entryDate: DateTime(2026, 8, 18),
      entryTime: '10:00:00',
      glCode: glCode,
      glName: 'GL',
      referenceType: referenceType,
      referenceId: referenceId,
      amount: amount,
      entryType: type,
      isReversal: isReversal,
      createdAt: DateTime(2026, 8, 18),
    );

void main() {
  group('saldo MerchantPOS', () {
    test('kredit menambah, debit mengurangi', () {
      final j = [
        _baris(glCode: _total, amount: 230000, type: JournalEntryType.credit),
        _baris(
            glCode: _total,
            amount: 115000,
            type: JournalEntryType.debit,
            referenceId: 'DISC'),
      ];
      expect(saldoPlatform(j, _total), 115000);
    });

    test('seluruh buku dihitung, bukan satu akun saja', () {
      // Pendapatan langganan dikreditkan ke GL Pendapatan Langganan dan
      // tidak pernah menyentuh GL Total Saldo. Menghitung akun itu saja
      // membuat seluruh pendapatan hilang dari saldonya.
      final j = [
        _baris(glCode: '1100001', amount: 230000, type: JournalEntryType.credit),
        _baris(
            glCode: '1100002',
            amount: 115000,
            type: JournalEntryType.debit,
            referenceType: 'billing_discount',
            referenceId: 'DISC'),
      ];
      expect(saldoPlatform(j, _total), 115000);
    });

    test('data sungguhan yang dulu berbunyi minus', () {
      // Persis isi buku MerchantPOS saat saldonya salah tampil −100:
      // satu-satunya baris di GL Total Saldo adalah debit voucher.
      final j = [
        _baris(glCode: '1100001', amount: 230000, type: JournalEntryType.credit),
        _baris(
            glCode: '1100002',
            amount: 115000,
            type: JournalEntryType.debit,
            referenceType: 'billing_discount',
            referenceId: 'D'),
        _baris(
            glCode: _total,
            amount: 100,
            type: JournalEntryType.debit,
            referenceType: 'voucher',
            referenceId: 'V1'),
        _baris(
            glCode: '1100073',
            amount: 100,
            type: JournalEntryType.credit,
            referenceType: 'voucher',
            referenceId: 'V1'),
        _baris(
            glCode: '1100073',
            amount: 10,
            type: JournalEntryType.debit,
            referenceType: 'voucher',
            referenceId: 'V2'),
        _baris(
            glCode: '1100074',
            amount: 10,
            type: JournalEntryType.credit,
            referenceType: 'voucher',
            referenceId: 'V2'),
      ];
      expect(saldoPlatform(j, _total), 115000);
    });

    test('perpindahan antar kantong tidak mengubah saldo', () {
      // Voucher terbit memindahkan uang, tidak menghilangkannya.
      final j = [
        _baris(
            glCode: _total,
            amount: 1000000,
            type: JournalEntryType.debit,
            referenceType: 'voucher',
            referenceId: 'V'),
        _baris(
            glCode: '1100073',
            amount: 1000000,
            type: JournalEntryType.credit,
            referenceType: 'voucher',
            referenceId: 'V'),
      ];
      expect(saldoPlatform(j, _total), 0);
    });

    test('voucher yang benar-benar dipakai mengurangi saldo', () {
      // Saat dipakai, sisi MerchantPOS cuma didebit — kreditnya jatuh ke
      // buku restonya, yang bukan bagian dari buku ini.
      final j = [
        _baris(glCode: '1100001', amount: 230000, type: JournalEntryType.credit),
        _baris(
            glCode: '1100074',
            amount: 10000,
            type: JournalEntryType.debit,
            referenceType: 'voucher',
            referenceId: 'V'),
      ];
      expect(saldoPlatform(j, _total), 220000);
    });

    test('pembatalan membuang kedua barisnya', () {
      final asli = _baris(
          glCode: _total, amount: 50000, type: JournalEntryType.credit,
          referenceId: 'A');
      final batal = _baris(
          glCode: _total, amount: 50000, type: JournalEntryType.debit,
          referenceId: 'A', isReversal: true);
      expect(saldoPlatform([asli, batal], _total), 0);
    });

    test('uang masuk dan keluar dilaporkan terpisah', () {
      final j = [
        _baris(glCode: _total, amount: 230000, type: JournalEntryType.credit),
        _baris(
            glCode: _total,
            amount: 115000,
            type: JournalEntryType.debit,
            referenceId: 'DISC'),
      ];
      expect(pemasukanPlatform(j, _total), 230000);
      expect(pengeluaranPlatform(j, _total), 115000);
    });

    test('jurnal kosong berarti nol, bukan galat', () {
      expect(saldoPlatform(const [], _total), 0);
    });
  });

  group('dua layar memakai aturan yang sama', () {
    test('keduanya memanggil helper yang sama', () {
      // Dua perhitungan terpisah akan berpisah, dan yang terlihat
      // adalah dua layar yang menyebut angka berbeda untuk uang yang
      // sama (TSD §11.1b).
      final saldo =
          File('lib/screens/finance_balance_screen.dart').readAsStringSync();
      final jurnal =
          File('lib/screens/finance_journal_screen.dart').readAsStringSync();
      expect(saldo, contains('saldoPlatform('));
      expect(jurnal, contains('saldoPlatform('));
    });
  });

  group('merchant terdekat', () {
    test('radiusnya 5 km', () {
      final layar =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      expect(layar, contains('const _nearbyRadiusKm = 5.0;'));
      expect(layar, contains('km <= _nearbyRadiusKm'));
    });

    test('yang di luar radius tetap ada di daftar semua', () {
      final layar =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      // Penyaringan radius hanya di _nearby; _matching tidak menyaring.
      final nearby = layar.substring(layar.indexOf('List<Restaurant> get _nearby'));
      final matching = layar.substring(
          layar.indexOf('List<Restaurant> get _matching'),
          layar.indexOf('List<Restaurant> get _nearby'));
      expect(nearby, contains('_nearbyRadiusKm'));
      expect(matching, isNot(contains('_nearbyRadiusKm')));
    });
  });
}
