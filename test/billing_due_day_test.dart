import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/billing.dart';

/// Aturan tanggal tagih hidup di SQL, jadi yang diperiksa di sini
/// berkasnya sendiri — plus akibatnya di sisi aplikasi.
void main() {
  final sql = File('supabase/billing_due_day.sql').readAsStringSync();
  final layar =
      File('lib/screens/super_admin_billing_screen.dart').readAsStringSync();
  final pdf = File('lib/utils/invoice_pdf.dart').readAsStringSync();

  group('tanggal tagih akhir bulan', () {
    test('29, 30, dan 31 boleh dipilih', () {
      expect(sql, contains('check (billing_day between 1 and 31)'));
      expect(layar, contains('for (var d = 1; d <= 31; d++)'));
    });

    test('dipotong ke hari terakhir bulan yang lebih pendek', () {
      expect(sql, contains('least('));
      expect(sql, contains("date_trunc('month', p_month)\n                        + interval '1 month - 1 day'"));
    });

    test('umur bulannya dihitung, bukan didaftar', () {
      // Tabel hari-per-bulan benar sampai seseorang lupa tahun kabisat.
      expect(sql, isNot(contains('when 2 then 28')));
    });

    test('bulan berikutnya dihitung ulang, bukan digeser', () {
      // 31 Januari yang digeser satu bulan bukan 28 Februari di semua
      // penanggalan.
      expect(sql, contains("_billing_day_in_month(\n           p_day, (date_trunc('month', p_from) + interval '1 month')::date)"));
    });

    test('contoh perhitungannya ditulis di berkasnya', () {
      for (final contoh in ['2026-02-28', '2028-02-29', '2026-04-30']) {
        expect(sql, contains(contoh), reason: contoh);
      }
    });
  });

  group('jatuh tempo berikutnya', () {
    test('dihitung server, bukan disalin ke Dart', () {
      expect(sql, contains('next_due_date date'));
      final model = File('lib/models/billing.dart').readAsStringSync();
      expect(model, contains("map['next_due_date']"));
    });

    test('yang masih menunggak dihitung dari tagihan itu', () {
      // Menyebut tanggal yang lebih jauh sementara ada yang belum lunas
      // membuat resto mengira dia punya waktu sampai tanggal itu.
      expect(sql, contains('when t.id is not null'));
    });

    test('merchant gratis atau nonaktif tidak punya tanggal berikutnya', () {
      expect(sql, contains("coalesce(s.monthly_price, 0) = 0\n        then null"));
    });

    test('tipe kembaliannya dibuang dulu sebelum diganti', () {
      // create or replace tidak bisa mengubah tipe kembalian.
      expect(sql, contains('drop function if exists resto_billing_state(text);'));
    });

    test('setiap berkas yang membuatnya ikut membuangnya dulu', () {
      // Berkas lama yang dijalankan sesudah berkas baru akan gagal
      // dengan 42P13 — dan berkas yang tidak aman dijalankan ulang
      // berhenti jadi berkas yang bisa dipercaya (TSD §11.2).
      for (final f in Directory('supabase').listSync()) {
        if (f is! File || !f.path.endsWith('.sql')) continue;
        if (f.path.endsWith('JALANKAN-INI.sql')) continue;
        final isi = f.readAsStringSync();
        if (!isi.contains('function resto_billing_state(p_resto_id text)')) {
          continue;
        }
        expect(isi, contains('drop function if exists resto_billing_state(text);'),
            reason: f.path);
      }
    });
  });

  group('VA hilang begitu lunas', () {
    BillingInvoice inv(InvoiceStatus status) => BillingInvoice(
          id: 'INV-1',
          restoId: 'r1',
          periodStart: DateTime(2026, 7, 18),
          periodEnd: DateTime(2026, 8, 17),
          dueDate: DateTime(2026, 8, 18),
          amount: 115000,
          status: status,
          vaNumber: '8890829337690',
          vaBank: 'MANDIRI',
          vaExpiresAt: DateTime(2030, 1, 1),
        );

    test('yang belum lunas tetap menampilkannya', () {
      expect(inv(InvoiceStatus.unpaid).vaHidup, isTrue);
      expect(inv(InvoiceStatus.review).vaHidup, isTrue);
    });

    test('yang sudah lunas tidak', () {
      // Nomor VA di bawah tulisan "Lunas" adalah undangan mentransfer
      // dua kali, dan uang kedua itu tidak punya tagihan untuk dilunasi.
      expect(inv(InvoiceStatus.paid).vaHidup, isFalse);
      expect(inv(InvoiceStatus.waived).vaHidup, isFalse);
    });
  });

  group('invoice PDF', () {
    test('tidak memuat nomor VA', () {
      expect(pdf, isNot(contains('vaNumber')));
    });

    test('harga daftar dan potongannya dipisah', () {
      // Netto tanpa rincian membuat keuangan resto mengira harganya
      // berubah diam-diam.
      expect(pdf, contains("_hitung('Harga langganan'"));
      expect(pdf, contains('if (potongan > 0)'));
    });

    test('menyebut dirinya lunas', () {
      expect(pdf, contains("Text('LUNAS'"));
    });

    test('hanya ditawarkan untuk tagihan yang lunas', () {
      final b = File('lib/screens/billing_screen.dart').readAsStringSync();
      expect(b, contains('t.status == InvoiceStatus.paid'));
      expect(b, contains('Unduh Invoice PDF'));
    });
  });
}
