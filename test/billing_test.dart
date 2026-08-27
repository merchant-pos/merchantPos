import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/billing.dart';

BillingState _state({
  bool locked = false,
  int? daysLeft,
  InvoiceStatus? status = InvoiceStatus.unpaid,
  int price = 150000,
  bool active = true,
  String? invoiceId = 'INV-ABC',
}) =>
    BillingState(
      locked: locked,
      daysLeft: daysLeft,
      invoiceStatus: status,
      monthlyPrice: price,
      active: active,
      invoiceId: invoiceId,
      amount: price,
      dueDate: DateTime(2026, 9, 1),
    );

void main() {
  group('pengingat tagihan', () {
    test('muncul tepat H-3, tidak lebih awal', () {
      expect(_state(daysLeft: 4).perluDiingatkan, isFalse);
      expect(_state(daysLeft: 3).perluDiingatkan, isTrue);
    });

    test('masih muncul pada hari jatuh tempo', () {
      expect(_state(daysLeft: 0).perluDiingatkan, isTrue);
    });

    test('tetap muncul sesudah lewat tempo', () {
      // Justru di sinilah pengingatnya paling dibutuhkan — berhenti
      // mengingatkan tepat saat keadaannya memburuk adalah kebalikan
      // dari yang dimaksud.
      final lewat = _state(daysLeft: -2);
      expect(lewat.perluDiingatkan, isTrue);
      expect(lewat.lewatTempo, isTrue);
    });

    test('tidak muncul kalau tagihannya sudah lunas', () {
      expect(_state(daysLeft: 1, status: InvoiceStatus.paid).perluDiingatkan,
          isFalse);
    });

    test('tidak muncul kalau dibebaskan', () {
      expect(_state(daysLeft: 1, status: InvoiceStatus.waived).perluDiingatkan,
          isFalse);
    });

    test('merchant gratis tidak pernah diingatkan', () {
      expect(_state(daysLeft: 0, price: 0).perluDiingatkan, isFalse);
    });

    test('langganan yang dimatikan tidak pernah diingatkan', () {
      expect(_state(daysLeft: 0, active: false).perluDiingatkan, isFalse);
    });

    test('tanpa tagihan terbuka, tidak ada yang diingatkan', () {
      expect(_state(daysLeft: 0, invoiceId: null).perluDiingatkan, isFalse);
    });

    test('keadaan tenang tidak mengingatkan apa pun', () {
      expect(BillingState.tenang.perluDiingatkan, isFalse);
      expect(BillingState.tenang.locked, isFalse);
    });
  });

  group('bentuk data', () {
    test('status yang tidak dikenal jatuh ke belum dibayar', () {
      final inv = BillingInvoice.fromMap({
        'id': 'INV-1',
        'resto_id': 'r1',
        'period_start': '2026-08-01',
        'period_end': '2026-08-31',
        'due_date': '2026-09-01',
        'amount': 150000,
        'status': 'entah-apa',
      });
      expect(inv.status, InvoiceStatus.unpaid);
      expect(inv.open, isTrue);
    });

    test('tiap status punya labelnya sendiri', () {
      final semua = InvoiceStatus.values.map((s) => kInvoiceStatusLabels[s]);
      expect(semua.toSet().length, InvoiceStatus.values.length);
    });

    test('hanya belum dibayar dan menunggu verifikasi yang terhitung terbuka',
        () {
      BillingInvoice inv(InvoiceStatus s) => BillingInvoice(
            id: 'x',
            restoId: 'r1',
            periodStart: DateTime(2026, 8, 1),
            periodEnd: DateTime(2026, 8, 31),
            dueDate: DateTime(2026, 9, 1),
            amount: 1,
            status: s,
          );
      expect(
        [for (final s in InvoiceStatus.values) if (inv(s).open) s],
        [InvoiceStatus.unpaid, InvoiceStatus.review],
      );
    });

    test('setelan bawaan merchant baru adalah gratis', () {
      const s = RestoBilling(restoId: 'r1');
      expect(s.gratis, isTrue);
      expect(s.billingDay, 1);
      expect(s.graceDays, 1);
    });
  });

  group('aturan penguncian di SQL', () {
    // Penguncian yang sebenarnya hidup di database, bukan di Dart —
    // layar yang terkunci hanyalah layar. Yang diperiksa di sini adalah
    // berkas SQL-nya sendiri.
    final sql = File('supabase/billing.sql').readAsStringSync();

    test('penguncian dipasang sebagai kebijakan RESTRICTIVE', () {
      // Kebijakan permissive digabung dengan OR — menambah satu lagi
      // justru MELONGGARKAN aksesnya, dan kunci yang dipasang begitu
      // tidak mengunci apa pun.
      expect(sql, contains('as restrictive for insert'));
      expect(sql, contains('as restrictive for update'));
    });

    test('pesanan dan katalog sama-sama dikunci', () {
      expect(sql, contains('"orders: billing lock"'));
      expect(sql, contains('"products: billing lock"'));
    });

    test('Super Admin tidak pernah terkunci', () {
      expect(sql, contains('when is_super_admin() then false'));
    });

    test('yang sudah mengunggah bukti tidak dikunci', () {
      // Mengunci orang yang sudah membayar adalah kesalahan yang paling
      // mahal di seluruh fitur ini.
      expect(sql, contains("t.status = 'unpaid'"));
    });

    test('merchant gratis tidak pernah dikunci', () {
      expect(sql, contains('s.monthly_price > 0'));
    });

    test('penguncian menghormati tenggang', () {
      expect(sql, contains('current_date > t.due_date + s.grace_days'));
    });

    test('tanggal tagih dibatasi 1-28', () {
      // "Tanggal 31" tidak ada di Februari, dan menggesernya diam-diam
      // membuat tagihan datang di hari yang tidak dijanjikan.
      expect(sql, contains('billing_day between 1 and 28'));
    });

    test('satu tagihan per merchant per periode', () {
      expect(sql, contains('unique (resto_id, period_start)'));
    });

    test('merchant tidak bisa menyatakan dirinya lunas', () {
      // submit_billing_payment hanya boleh menaikkan ke 'review'.
      final fungsi = sql.substring(sql.indexOf('function submit_billing_payment'),
          sql.indexOf('function review_billing_payment'));
      expect(fungsi, contains("status = 'review'"));
      expect(fungsi, isNot(contains("status = 'paid'")));
    });

    test('hanya Super Admin yang memutuskan lunas', () {
      final fungsi = sql.substring(sql.indexOf('function review_billing_payment'));
      expect(fungsi, contains('if not is_super_admin() then'));
    });

    test('merchant baru langsung punya barisnya, dan gratis', () {
      expect(sql, contains('after insert on restaurants'));
      expect(sql, contains('values (new.id, 0, 1)'));
    });
  });

  group('Virtual Account', () {
    final sql = File('supabase/billing_va.sql').readAsStringSync();
    final fn = File('supabase/functions/create-billing-va/index.ts')
        .readAsStringSync();
    final hook = File('supabase/functions/xendit-billing-webhook/index.ts')
        .readAsStringSync();

    test('VA langganan TIDAK memakai sub-akun merchant', () {
      // Ini kesalahan yang paling mahal dan paling sunyi di seluruh
      // fitur: dengan for-user-id terpasang, resto membayar tagihan
      // langganan ke rekeningnya sendiri. Tagihannya tetap lunas,
      // uangnya tidak pernah sampai, dan tidak ada galat apa pun.
      expect(fn, isNot(contains('"for-user-id"')));
      expect(fn, contains('Sengaja TIDAK ada for-user-id'));
    });

    test('nominalnya dibaca dari database, bukan dari aplikasi', () {
      expect(fn, contains('expected_amount: inv.amount'));
      expect(fn, isNot(contains('body.amount')));
    });

    test('VA tertutup dan sekali pakai', () {
      // Tertutup: transfer kurang seribu tidak masuk diam-diam lalu
      // meninggalkan tagihan yang tidak lunas.
      // Sekali pakai: transfer bulan depan tidak mendarat di tagihan
      // bulan ini.
      expect(fn, contains('is_closed: true'));
      expect(fn, contains('is_single_use: true'));
    });

    test('VA yang masih hidup dipakai ulang', () {
      expect(fn, contains('reused: true'));
    });

    test('webhook memeriksa token callback lebih dulu', () {
      final sebelumBaca = hook.substring(0, hook.indexOf('req.json()'));
      expect(sebelumBaca, contains('x-callback-token'));
    });

    test('kurang bayar tidak melunasi', () {
      expect(sql, contains('if p_amount < v_inv.amount then'));
      expect(sql, contains("return 'underpaid'"));
    });

    test('callback berulang tidak menimpa catatan pelunasan', () {
      expect(sql, contains("if v_inv.status in ('paid', 'waived') then"));
      expect(sql, contains("return 'already_paid'"));
    });

    test('tiap sebab kegagalan punya jawabannya sendiri', () {
      // Ketiganya sama-sama berarti "tidak dilunasi", tapi menunjuk ke
      // arah yang berbeda saat ditelusuri. Menyatukannya di bawah satu
      // pesan membuat penelusuran uang berangkat ke arah yang salah —
      // dan ini catatan yang dibaca justru saat ada uang yang tidak
      // jelas rimbanya.
      for (final kode in ['paid', 'already_paid', 'not_found', 'underpaid']) {
        expect(sql, contains("return '$kode'"), reason: 'SQL: $kode');
        expect(hook, contains('$kode:'), reason: 'webhook: $kode');
      }
    });

    test('tagihan tidak ditemukan tidak dilaporkan sebagai kurang bayar', () {
      expect(hook, contains('tagihannya tidak dikenali'));
    });

    test('jalur pelunasan dibedakan mesin dan manusia', () {
      expect(sql, contains("paid_via in ('xendit_va', 'manual', 'waived')"));
      expect(sql, contains("paid_via = 'xendit_va'"));
      expect(sql, contains("when p_accept then 'manual'"));
    });

    test('daftar bank di Dart sama dengan di database', () {
      // Kode bank yang tidak dikenal ditolak Xendit, dan yang melihat
      // penolakannya adalah resto yang sedang mencoba membayar.
      for (final b in kBankVA) {
        expect(sql, contains("'$b'"), reason: 'bank $b tidak ada di SQL');
        expect(fn, contains('"$b"'), reason: 'bank $b tidak ada di fungsi edge');
      }
    });

    test('description tidak pernah dikirim ke Xendit', () {
      // Sebagian bank menolaknya mentah-mentah — Mandiri menjawab
      // DESCRIPTION_NOT_SUPPORTED_ERROR — dan yang mana saja berbeda per
      // bank dan bisa berubah kapan pun di sisi Xendit. Kolomnya sendiri
      // tidak pernah dibaca siapa pun.
      final badan = fn.substring(fn.indexOf('external_id: inv.id'),
          fn.indexOf('const body = await res.json()'));
      expect(badan, isNot(contains('description:')));
    });

    test('galat penyedia disaring jadi satu kalimat', () {
      // Jawaban selain 2xx dilempar sebagai FunctionException, jadi
      // pemeriksaan data['error'] tidak pernah sampai — dan yang tampil
      // di layar adalah seluruh bungkusnya.
      final repo = File('lib/db/billing_repository.dart').readAsStringSync();
      expect(repo, contains('on FunctionException catch'));
      expect(repo, contains('_pesanGalat'));
    });

    test('simulasi hanya hidup di mode uji', () {
      // Ditolak Xendit sendiri pada kunci produksi, dan ditolak lagi di
      // sini sebelum sempat dikirim. Tidak ada penanda yang bisa
      // tertinggal menyala di rilis: mengganti kuncinya sudah cukup.
      expect(fn, contains('Simulasi hanya tersedia di mode uji'));
      expect(fn, contains('secret.startsWith("xnd_development_")'));
    });

    test('nominal simulasi dibaca dari tagihannya', () {
      // VA-nya tertutup di nominal itu; simulasi dengan angka lain hanya
      // menghasilkan penolakan yang membingungkan penguji.
      expect(fn, contains('JSON.stringify({ amount: inv.amount })'));
    });

    test('mode uji dijawab server, bukan ditebak aplikasi', () {
      final layar =
          File('lib/screens/billing_screen.dart').readAsStringSync();
      expect(fn, contains('test_mode: testMode'));
      expect(layar, contains("hasil['test_mode'] == true"));
    });

    test('VA berlaku sampai sesudah jatuh tempo', () {
      // VA yang mati tepat di tanggal jatuh tempo menutup pintu justru
      // pada hari orang paling mungkin membayarnya.
      expect(fn, contains('kedaluwarsa.getDate() + 7'));
    });

    test('VA kedaluwarsa tidak lagi dianggap hidup', () {
      final inv = BillingInvoice(
        id: 'INV-1',
        restoId: 'r1',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
        dueDate: DateTime(2026, 9, 1),
        amount: 150000,
        vaNumber: '8808123456',
        vaBank: 'BCA',
        vaExpiresAt: DateTime(2020, 1, 1),
      );
      expect(inv.vaHidup, isFalse);
    });

    test('VA yang belum kedaluwarsa dianggap hidup', () {
      final inv = BillingInvoice(
        id: 'INV-1',
        restoId: 'r1',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
        dueDate: DateTime(2026, 9, 1),
        amount: 150000,
        vaNumber: '8808123456',
        vaBank: 'BCA',
        vaExpiresAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(inv.vaHidup, isTrue);
    });
  });

}
