import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/cashier_shift.dart';

void main() {
  group('model shift', () {
    CashierShift buat(Map<String, dynamic> tambahan) => CashierShift.fromMap({
          'id': 's1',
          'resto_id': 'r1',
          'employee_email': 'andi@toko.com',
          'opened_at': '2026-08-22T01:00:00Z',
          'opening_cash': 200000,
          ...tambahan,
        });

    test('shift tanpa closed_at masih terbuka', () {
      expect(buat({}).terbuka, isTrue);
      expect(buat({'closed_at': '2026-08-22T09:00:00Z'}).terbuka, isFalse);
    });

    test('selisih nol berarti pas', () {
      expect(buat({'difference': 0}).pas, isTrue);
      expect(buat({'difference': -5000}).pas, isFalse);
      expect(buat({'difference': 5000}).pas, isFalse);
    });

    test('selisih minus berarti uangnya kurang', () {
      expect(buat({'difference': -5000}).kurang, isTrue);
      expect(buat({'difference': 5000}).kurang, isFalse);
    });

    // Pegawai yang berhenti dan barisnya dihapus tidak boleh membuat
    // shift lamanya kehilangan penanggung jawab.
    test('tanpa nama, emailnya yang dipakai', () {
      expect(buat({}).namaTampil, 'andi');
      expect(buat({'employee_name': 'Andi Kasir'}).namaTampil, 'Andi Kasir');
      expect(buat({'employee_name': '  '}).namaTampil, 'andi');
    });

    test('shift yang masih buka belum punya angka apa pun', () {
      final s = buat({});
      expect(s.countedCash, isNull);
      expect(s.expectedCash, isNull);
      expect(s.difference, isNull);
    });
  });

  group('SQL-nya', () {
    final sql = File('supabase/cashier_shift.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      final skrip = File('scripts/gabung_sql.sh').readAsStringSync();
      expect(skrip, contains('cashier_shift.sql'));
    });

    // Dua shift terbuka bersamaan akan menghitung penjualan tunai yang
    // sama dua kali, lalu keduanya sama-sama terlihat kelebihan uang.
    test('satu laci hanya boleh punya satu shift terbuka', () {
      expect(sql, contains('create unique index if not exists '
          'cashier_shifts_satu_terbuka'));
      expect(sql, contains('where closed_at is null'));
    });

    // Angka yang menilai seseorang tidak boleh berasal dari perangkat
    // orang itu.
    test('tidak ada jalan menyunting barisnya langsung', () {
      expect(sql, isNot(contains('for insert')));
      expect(sql, isNot(contains('for update')));
      expect(sql, isNot(contains('for all')));
      expect(sql, contains('for select using'));
    });

    test('menutup shift dihitung server, bukan dikirim aplikasi', () {
      expect(sql, contains('create or replace function close_shift'));
      expect(sql, contains('v_expected := shift_expected_cash('));
      expect(sql, contains('difference = p_counted_cash - v_expected'));
    });

    test('shift yang sudah ditutup tidak bisa ditutup dua kali', () {
      expect(sql, contains('Shift ini sudah ditutup.'));
    });

    test('menutup shift orang lain hanya untuk atasan', () {
      expect(sql, contains("array['owner', 'finance', 'admin']"));
    });

    group('perhitungan uang yang seharusnya ada', () {
      final fn = sql.substring(sql.indexOf('function shift_expected_cash'),
          sql.indexOf('function close_shift'));

      test('dimulai dari modal awal laci', () {
        expect(fn, contains('s.opening_cash'));
      });

      test('hanya penjualan tunai yang lunas', () {
        expect(fn, contains("o.payment_status = 'paid'"));
        expect(fn, contains("o.payment_method = 'cash'"));
      });

      test('dibatasi rentang waktu shiftnya', () {
        expect(fn, contains('o.created_at >= s.opened_at'));
        expect(fn, contains('o.created_at < p_until'));
      });

      // Uang setoran yang ditolak dikembalikan ke laci, jadi ia kembali
      // jadi tanggung jawab shift ini. Aturannya sama persis dengan
      // cashOnHand di lib/utils/cash_balance.dart — dua tempat yang
      // menghitung "tunai di laci" tidak boleh berbeda aturan.
      test('setoran dan petty cash yang ditolak tidak dikurangkan', () {
        expect(fn, contains("d.status <> 'rejected'"));
        expect(fn, contains("p.status <> 'rejected'"));
      });

      test('hanya petty cash yang menarik dari laci', () {
        expect(fn, contains("p.source = 'cash_withdrawal'"));
      });
    });
  });

  group('layarnya', () {
    final layar =
        File('lib/screens/cashier_shift_screen.dart').readAsStringSync();

    // Kasir yang tahu lebih dulu "seharusnya sekian" akan menghitung
    // sampai ketemu angka itu, bukan menghitung apa adanya.
    test('angka yang seharusnya tidak bocor sebelum uangnya dihitung', () {
      final tutup = layar.substring(layar.indexOf('Future<void> _tutup()'));
      final tanya = tutup.indexOf('_tanyaRupiah(');
      final minta = tutup.indexOf('_repo.perkiraan(');
      expect(tanya, greaterThan(0));
      expect(minta, greaterThan(tanya),
          reason: 'perkiraannya diminta sebelum nominalnya ditulis');
    });

    // Salah ketik satu angka nol tercatat selamanya sebagai selisih
    // jutaan rupiah atas nama orang yang tidak melakukan apa-apa. Menutup
    // shift tidak bisa dibatalkan, jadi kesempatan memperbaikinya harus
    // ada sebelum disimpan.
    test('nominalnya masih bisa diperbaiki sebelum tersimpan', () {
      final tutup = layar.substring(
          layar.indexOf('Future<void> _tutup()'),
          layar.indexOf('await _repo.tutup('));
      expect(tutup, contains('_konfirmasiSelisih('));
      expect(tutup, contains('nilaiAwal: awal'));
      expect(layar, contains("cancelLabel: 'Perbaiki Nominal'"));
    });

    test('hasilnya baru ditampilkan setelah tersimpan', () {
      final i = layar.indexOf('await _repo.tutup(');
      expect(layar.indexOf('_tampilkanHasil('), greaterThan(i));
    });

    // Perkiraan yang ditunjukkan sebelum menutup hanya penunjuk. Yang
    // tersimpan tetap dihitung ulang server di dalam close_shift, jadi
    // angka basi atau dipalsukan di perjalanan tidak bisa mengubah
    // selisih yang tercatat.
    test('aplikasi tidak pernah menghitung sendiri', () {
      final repo =
          File('lib/db/cashier_shift_repository.dart').readAsStringSync();
      final fungsi = repo.substring(repo.indexOf('Future<int> perkiraan('));
      expect(fungsi, contains("_client.rpc('shift_expected_cash'"));
      // Tidak ada aritmetika sama sekali — cuma meneruskan jawaban server.
      final badan = fungsi.substring(0, fungsi.indexOf('/// Menutup shift'));
      expect(badan.contains(' - '), isFalse);
      expect(badan.contains(' + '), isFalse);
    });
  });

  group('selisih kasir', () {
    final sql = File('supabase/cash_variance.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('cash_variance.sql'));
    });

    test('punya akun GL sendiri, di rentang titipan', () {
      expect(sql, contains("'cash_variance', '2100003', 'GL Selisih Kasir'"));
      // Resto baru harus ikut dapat, bukan cuma yang sudah ada.
      expect(sql, contains('create or replace function _default_gl_accounts'));
    });

    // credit = uang masuk, debit = uang keluar. Kurang berarti uangnya
    // memang tidak ada di laci.
    test('kurang dijurnal debit, lebih dijurnal credit', () {
      expect(sql,
          contains("case when v_selisih < 0 then 'debit' else 'credit' end"));
    });

    // Tidak ada yang bisa ditagih dari uang yang justru berlebih.
    test('hanya yang kurang jadi tagihan', () {
      final pemicu = sql.substring(sql.indexOf('function journal_cash_variance'));
      final tagih = pemicu.substring(pemicu.indexOf('if v_selisih < 0 then'));
      expect(tagih, contains('insert into cash_variances'));
    });

    test('satu shift paling banyak satu tagihan', () {
      expect(sql, contains('shift_id uuid not null unique'));
      expect(sql, contains('on conflict (shift_id) do nothing'));
    });

    // Kalau kasir boleh menutup tagihan atas namanya sendiri, angka yang
    // menilai seseorang bisa dihapus oleh orang itu juga.
    test('kasir boleh melihat, tidak boleh melunasi', () {
      expect(sql, contains("array['owner', 'finance', 'admin', 'kasir']"));
      final fungsi = sql.substring(sql.indexOf('function settle_cash_variance'));
      expect(fungsi, contains("array['owner', 'finance', 'admin']"));
      expect(fungsi, isNot(contains("'kasir'")));
    });

    test('tidak ada jalan menyunting tagihannya langsung', () {
      final bagian = sql.substring(sql.indexOf('on cash_variances'));
      expect(bagian, isNot(contains('for insert')));
      expect(bagian, isNot(contains('for update')));
      expect(bagian, isNot(contains('for all')));
    });

    test('yang sudah lunas tidak bisa dilunasi dua kali', () {
      expect(sql, contains('Selisih ini sudah dilunasi.'));
    });

    // Menahan penutupan shift karena pemetaan GL berarti kasir tidak
    // bisa pulang gara-gara urusan pembukuan.
    test('GL yang belum dipetakan tidak menahan penutupan shift', () {
      final pemicu = sql.substring(sql.indexOf('function journal_cash_variance'));
      expect(pemicu, contains('if v_gl.gl_code is null'));
      expect(pemicu.substring(pemicu.indexOf('if v_gl.gl_code is null')),
          contains('return new;'));
    });
  });

  group('riwayat sesudah dilunasi', () {
    final layar =
        File('lib/screens/cashier_shift_screen.dart').readAsStringSync();

    // Tanda merah yang menetap selamanya membuat shift yang sudah
    // dibereskan terus terlihat seperti masalah yang belum selesai.
    test('shift yang selisihnya dibayar ditandai beres', () {
      expect(layar, contains('final beres = selisih == 0 || lunas;'));
      expect(layar, contains("beres\n                      ? 'Pas'"));
    });

    // Riwayat yang menyembunyikan bahwa pernah ada selisih adalah
    // riwayat yang tidak bisa dipakai menelusuri apa pun.
    test('rinciannya tetap tercatat, bukan cuma lencananya', () {
      expect(layar, contains('if (lunas && selisih != 0)'));
      expect(layar, contains('_RincianPelunasan('));
    });

    // Empat pertanyaan yang tidak bisa dijawab lencana: berapa yang
    // dihitung waktu itu, berapa kurangnya, siapa yang menanggungnya,
    // dan siapa yang mencatat pelunasannya.
    test('rinciannya menyebut nominal, selisih, dan siapa yang membayar', () {
      final kartu = layar.substring(layar.indexOf('class _RincianPelunasan'));
      expect(kartu, contains("label: 'Modal awal laci'"));
      expect(kartu, contains("label: 'Diinput kasir'"));
      expect(kartu, contains("label: 'Seharusnya'"));
      expect(kartu, contains("label: 'Selisih kurang'"));
      expect(kartu, contains('Dibayar tunai oleh '));
      expect(kartu, contains('Dicatat oleh '));
    });

    // Shift tanpa tagihan sama sekali — yang uangnya memang pas, atau
    // yang justru lebih — tidak boleh terbaca sebagai "sudah dilunasi".
    // Tidak ada yang perlu dilunasi di sana.
    test('shift tanpa tagihan tidak disebut lunas', () {
      final fungsi = layar.substring(layar.indexOf('CashVariance? _tagihanShift('));
      expect(fungsi.substring(0, fungsi.indexOf('}\n\n')),
          contains('return null;'));
      expect(layar, contains('final lunas = tagihan?.lunas ?? false;'));
    });
  });

  group('pemeriksaan modal awal', () {
    final sql = File('supabase/shift_opening_check.sql').readAsStringSync();
    final layar =
        File('lib/screens/cashier_shift_screen.dart').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('shift_opening_check.sql'));
    });

    // Kalau shift kemarin kurang Rp 10.000, yang betul-betul tertinggal
    // di laci memang jumlah yang kurang itu — dan kekurangannya sudah
    // punya tagihannya sendiri. Memakai angka "seharusnya" berarti
    // menagihkan kekurangan yang sama dua kali, kepada dua orang.
    test('titik awalnya uang yang dihitung, bukan yang seharusnya', () {
      expect(sql, contains('t.counted_cash'));
      expect(sql, isNot(contains('t.expected_cash')));
    });

    test('yang terjadi sesudah penutupan ikut dihitung', () {
      expect(sql, contains("o.payment_method = 'cash'"));
      expect(sql, contains('from cash_deposits d'));
      expect(sql, contains("p.source = 'cash_withdrawal'"));
    });

    // Daftar kosong akan terbaca aplikasi sebagai "gagal", padahal
    // artinya "belum ada pembandingnya".
    test('merchant tanpa shift tertutup tetap dapat satu baris', () {
      expect(sql, contains('right join (select 1) satu on true'));
      expect(sql, contains('returns table (ada boolean, jumlah bigint)'));
    });

    test('dihitung sesudah nominalnya ditulis, bukan sebelum', () {
      final buka = layar.substring(layar.indexOf('Future<void> _buka()'));
      final tanya = buka.indexOf('_tanyaRupiah(');
      final minta = buka.indexOf('_repo.perkiraanModalAwal(');
      expect(minta, greaterThan(tanya));
    });

    // Gagal mengambil pembandingnya bukan alasan menahan kasir membuka
    // shift di depan antrean.
    test('tanpa pembanding, modal awalnya diterima apa adanya', () {
      final buka = layar.substring(layar.indexOf('Future<void> _buka()'));
      expect(buka, contains('if (perkiraan == null || perkiraan == jawab.jumlah) break;'));
    });

    test('nominalnya masih bisa diperbaiki sebelum shift dibuka', () {
      final buka = layar.substring(
          layar.indexOf('Future<void> _buka()'),
          layar.indexOf('await _repo.buka('));
      expect(buka, contains('_konfirmasiSelisih('));
      expect(buka, contains("tombolLanjut: 'Ya, Buka Shift'"));
    });
  });

  group('mapping GL-nya', () {
    test('GL Selisih Kasir bisa dipetakan Finance', () {
      final layar =
          File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();
      expect(layar, contains("const _cashVarianceMethod = 'cash_variance';"));
      // Ikut daftar utamanya — kalau tidak, kolomnya tampil tapi tidak
      // pernah ikut tersimpan.
      expect(layar, contains('  _cashVarianceMethod,\n];'));
      expect(layar, contains("title: 'GL Selisih Kasir'"));
    });
  });

  group('pintunya', () {
    // Kasir yang memegang laci, tapi atasannya yang menutup shift saat
    // kasirnya sudah pulang — keempatnya butuh pintu ini.
    test('ada di beranda kasir, admin, owner, dan finance', () {
      for (final f in [
        'kasir_home_screen',
        'admin_home_screen',
        'owner_home_screen',
        'finance_home_screen',
      ]) {
        final isi = File('lib/screens/$f.dart').readAsStringSync();
        expect(isi, contains('Shift Kasir'), reason: '$f tanpa pintu shift');
        expect(isi, contains('CashierShiftScreen()'), reason: '$f tanpa tujuan');
      }
    });
  });
}
