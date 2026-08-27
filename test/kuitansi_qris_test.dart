import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rincian kuitansi QRIS disimpan sebagai kolomnya sendiri.
///
/// Semuanya sudah ada di kolom `raw` sejak awal, tapi terkubur di dalam
/// JSON ia tidak bisa dicari, diurutkan, atau dicocokkan baris-per-baris
/// dengan mutasi di dashboard penyedia — dan itu persis yang dibutuhkan
/// saat ada satu pembayaran yang angkanya tidak cocok.
void main() {
  final sql = File('supabase/qris_receipt_fields.sql').readAsStringSync();
  final fn =
      File('supabase/functions/xendit-webhook/index.ts').readAsStringSync();

  const medan = {
    'transaction_id': 'ID Transaksi',
    'qr_id': 'ID QR',
    'product_id': 'ID Product',
    'partner_code': 'Mitra',
    'partner_name': 'Partner',
    'partner_receipt_id': 'ID Kuitansi Mitra',
    'payment_source': 'Sumber',
    'acquirer_id': 'ID Pengakuisisi',
    'customer_pan': 'Customer PAN',
  };

  group('kolomnya', () {
    test('seluruh medan yang diminta punya kolomnya', () {
      for (final e in medan.entries) {
        expect(sql, contains('add column if not exists ${e.key} text'),
            reason: e.value);
      }
    });

    test('ID Referensi memang sudah ada sejak awal', () {
      final asal = File('supabase/payment_gateway.sql').readAsStringSync();
      expect(asal, contains('reference_id text not null unique'));
    });

    test('yang sering dicocokkan punya indeksnya', () {
      expect(sql, contains('payment_charges_transaction_idx'));
      expect(sql, contains('payment_charges_partner_receipt_idx'));
    });
  });

  group('pengisiannya', () {
    test('webhook mengisi seluruh medan itu', () {
      for (final kunci in medan.keys) {
        expect(fn, contains('$kunci:'), reason: kunci);
      }
    });

    test('dibaca untuk setiap kabar, bukan hanya yang sukses', () {
      // Yang gagal justru paling sering ditanyakan belakangan —
      // "sudah saya bayar tapi ditolak" tidak bisa dijawab kalau yang
      // tersimpan cuma yang berhasil.
      expect(fn.indexOf('const rincian = bersihkan('),
          lessThan(fn.indexOf('status !== "SUCCEEDED"')));
    });

    test('yang belum sukses ikut disimpan berikut rinciannya', () {
      final blok = fn.substring(fn.indexOf('status !== "SUCCEEDED"'));
      expect(blok, contains('.update({ raw: payload, ...rincian })'));
    });

    test('status milik kita tidak ikut berubah sebelum uangnya diterima', () {
      // Pelanggan yang QR-nya kedaluwarsa masih boleh membayar tunai di
      // kasir, dan pesanannya tidak boleh ikut ditutup.
      final blok = fn.substring(
          fn.indexOf('status !== "SUCCEEDED"'),
          fn.indexOf('settle_gateway_payment'));
      expect(blok, isNot(contains("status: 'paid'")));
      expect(blok, isNot(contains('status:')));
    });

    test('status penyedia punya kolomnya sendiri', () {
      // Menimpanya ke kolom `status` berarti kehilangan bedanya antara
      // "belum dibayar" dan "sudah gagal".
      expect(sql, contains('add column if not exists provider_status text'));
      expect(sql,
          contains('add column if not exists provider_status_at timestamptz'));
      expect(fn, contains('provider_status: data.status,'));
      expect(fn, contains("rincian.provider_status_at ="));
    });

    test('sebab kegagalannya ikut tersimpan', () {
      expect(sql, contains('add column if not exists failure_reason text'));
      expect(fn, contains('failure_reason: data.failure_code'));
    });

    test('penulisannya menyusul sesudah pembayarannya sah dicatat', () {
      // Yang dihitung boleh lebih dulu; yang tidak boleh adalah
      // menulisnya sebelum uangnya sah tercatat masuk.
      expect(fn.indexOf('settle_gateway_payment'),
          lessThan(fn.indexOf('if (Object.keys(rincian).length > 0)')));
    });

    test('kegagalannya tidak membuat Xendit mengulang', () {
      // Mengembalikan 500 di sini membuat kabar pembayaran yang sudah
      // berhasil dicatat dikirim ulang.
      final blok =
          fn.substring(fn.indexOf('if (Object.keys(rincian).length > 0)'));
      expect(blok, contains('console.error'));
      // Yang dicari: tidak ada `return json(..., 500)` sesudah titik
      // ini. Kata "500" sendiri muncul di komentarnya, jadi yang
      // diperiksa bentuk pengembaliannya.
      expect(blok, isNot(contains('}, 500)')));
    });

    test('medan yang tidak dikirim tidak menimpa yang sudah terisi', () {
      // Kabar yang sama bisa datang dua kali.
      expect(fn, contains('if (nilai === null || nilai === undefined'));
      expect(fn, contains('if (Object.keys(rincian).length > 0)'));
    });

    test('payload dibaca dari data maupun akarnya', () {
      expect(fn, contains('payload.data ?? payload'));
      expect(sql, contains("coalesce(raw -> 'data', raw)"));
    });
  });

  group('yang lama ikut terisi', () {
    test('pembayaran sebelum berkas ini dijalankan ikut dibaca dari raw', () {
      // Tanggal pemasangan bukan garis pemisah antara yang bisa
      // dicocokkan dan yang tidak.
      expect(sql, contains('update payment_charges c'));
      expect(sql, contains('where raw is not null'));
    });

    test('yang sudah terisi tidak ditimpa', () {
      expect(sql, contains('coalesce(c.transaction_id,'));
    });

    test('raw tetap disimpan sebagai sumber kebenarannya', () {
      expect(sql, isNot(contains('drop column')));
      expect(sql, contains('select raw from payment_charges'));
    });
  });
}
