import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/balance_topup.dart';

void main() {
  final sql = File('supabase/balance_topup.sql').readAsStringSync();
  final layar =
      File('lib/screens/finance_balance_screen.dart').readAsStringSync();
  final pemetaan =
      File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();

  group('akun modal', () {
    test('punya akunnya sendiri, bukan menumpang pendapatan', () {
      // Resto yang menyetor modal besar tidak boleh terlihat seperti
      // resto yang laris.
      expect(sql, contains("'capital'"));
      expect(sql, contains("'1100003', 'GL Setoran Modal'"));
      expect(sql, contains("'1940001', 'GL Setoran Modal'"));
    });

    test('merchant platform tidak kebagian nomor merchant', () {
      expect(sql, contains('coalesce(r.is_platform, false) = false'));
    });

    test('masuk daftar metode yang diizinkan', () {
      expect(sql, contains("'voucher_redeem',\n     'capital'"));
    });

    test('muncul di Pemetaan GL untuk semua yang punya pembukuan', () {
      expect(pemetaan, contains("const _capitalMethod = 'capital';"));
      expect(pemetaan, contains("title: 'GL Modal'"));
      // Bukan akun khusus platform — resto juga menerima setoran modal.
      final blok = pemetaan.substring(
          pemetaan.indexOf('const _platformOnlyMethods'),
          pemetaan.indexOf('};', pemetaan.indexOf('const _platformOnlyMethods')));
      expect(blok, isNot(contains('_capitalMethod')));
    });
  });

  group('jurnalnya', () {
    test('satu baris kredit ke akun modalnya sendiri', () {
      // Sempat ditulis berpasangan dengan debit GL Total Saldo — dan
      // pasangan yang saling menghapus membuat setoran modal tidak
      // menaikkan saldo sama sekali, karena saldo adalah selisih
      // seluruh kredit dan debit.
      final blok = sql.substring(sql.indexOf('function log_balance_topup'));
      expect(blok, contains("'capital', new.id::text, new.amount, 'credit'"));
      expect(blok, isNot(contains("'debit'")));
      expect(blok, isNot(contains("'total_balance'")));
    });

    test('jenis rujukannya masuk daftar batasan', () {
      expect(sql, contains("'voucher', 'capital'"));
    });

    test('ditulis pemicu, bukan aplikasi', () {
      // Dua baris jurnal yang dikirim aplikasi bisa sampai satu dan
      // gagal satu, dan pembukuan timpang sebelah lebih sulit ditemukan
      // daripada pembukuan yang kosong.
      expect(sql, contains('after insert on balance_topups'));
      final repo =
          File('lib/db/balance_topup_repository.dart').readAsStringSync();
      expect(repo, isNot(contains('gl_journal_entries')));
    });
  });

  group('siapa boleh mencatat', () {
    test('kasir melihat tapi tidak menambah', () {
      // Baris yang menaikkan saldo tanpa uang sungguhan adalah cara
      // paling rapi menutupi selisih laci.
      final baca = sql.substring(sql.indexOf('"balance_topups: read"'),
          sql.indexOf('"balance_topups: write"'));
      expect(baca, contains("'kasir'"));
      final tulis = sql.substring(sql.indexOf('"balance_topups: write"'));
      expect(tulis.substring(0, 300), isNot(contains("'kasir'")));
    });

    test('tidak ada yang boleh mengubah atau menghapus', () {
      expect(sql, contains('for insert with check'));
      expect(sql, isNot(contains('for all using')));
    });
  });

  group('di layar', () {
    test('setoran menambah saldo non-tunai, bukan berdiri sendiri', () {
      // Dua angka yang tidak bertemu di layar yang sama adalah yang
      // pertama membuat orang berhenti mempercayai halamannya.
      expect(layar, contains('_nonCashIncome +\n      _topupTotal -'));
      expect(layar, contains('int get _incomeBalance => _cashBalance + _nonCashBalance;'));
    });

    test('penyetornya wajib disebut', () {
      expect(layar, contains("'Sebutkan penyetornya'"));
    });

    test('kasir tidak melihat tombolnya', () {
      expect(layar, contains('action: _canManageFunds'));
    });

    test('tidak menawarkan pilihan masuk ke mana', () {
      // Modal selalu menambah saldo utama; menawarkan pilihan lain cuma
      // membuka jalan mencatatnya di tempat yang salah.
      final form = layar.substring(layar.indexOf('class _FormModal'));
      expect(form, isNot(contains('DropdownButtonFormField')));
    });
  });

  group('modelnya', () {
    test('terbaca dari baris database', () {
      final t = BalanceTopup.fromMap({
        'id': 'abc',
        'resto_id': 'r1',
        'amount': 5000000,
        'source': 'Pak Budi',
        'note': 'Modal awal',
        'created_at': '2026-08-18T10:00:00Z',
      });
      expect(t.amount, 5000000);
      expect(t.source, 'Pak Budi');
      expect(t.punyaBukti, isFalse);
    });
  });

  group('wording masuk', () {
    test('Karyawan Merchant sudah jadi MerchantPOS Merchant', () {
      final pilih =
          File('lib/screens/role_choice_screen.dart').readAsStringSync();
      expect(pilih, contains("context.tr('MerchantPOS Merchant')"));
      expect(pilih, isNot(contains('Karyawan Merchant')));
    });
  });
}
