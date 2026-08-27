import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/voucher.dart';

Voucher _batch({
  int total = 1000000,
  int quantity = 10,
  int amount = 100000,
  int claimed = 0,
  int menggantung = 0,
  DateTime? expiresOn,
  bool active = true,
}) =>
    Voucher(
      id: 'VC-1',
      code: 'HEMAT100',
      name: 'Promo Pengguna Baru',
      totalAmount: total,
      quantity: quantity,
      amount: amount,
      expiresOn: expiresOn ?? DateTime.now().add(const Duration(days: 30)),
      active: active,
      createdAt: DateTime(2026, 8, 1),
      claimed: claimed,
      menggantung: menggantung,
    );

VoucherClaim _claim({
  VoucherClaimStatus status = VoucherClaimStatus.claimed,
  DateTime? expiresOn,
  int minPurchase = 0,
  List<String> restoIds = const [],
  int amount = 100000,
}) =>
    VoucherClaim(
      id: 'VCL-1',
      voucherId: 'VC-1',
      customerLabel: 'orang@contoh.com',
      amount: amount,
      status: status,
      createdAt: DateTime(2026, 8, 10),
      code: 'HEMAT100',
      name: 'Promo Pengguna Baru',
      expiresOn: expiresOn ?? DateTime.now().add(const Duration(days: 30)),
      minPurchase: minPurchase,
      restoIds: restoIds,
    );

void main() {
  group('batch voucher', () {
    test('sisa kuota berkurang seiring penebusan', () {
      expect(_batch(claimed: 3).sisa, 7);
      expect(_batch(claimed: 10).sisa, 0);
      expect(_batch(claimed: 10).habis, isTrue);
    });

    test('yang habis tidak bisa ditebus lagi', () {
      // Orang ke-11 harus ditolak, dan itu inti dari kuotanya.
      expect(_batch(claimed: 10).bisaDitebus, isFalse);
      expect(_batch(claimed: 9).bisaDitebus, isTrue);
    });

    test('yang kedaluwarsa tidak bisa ditebus', () {
      final lewat =
          _batch(expiresOn: DateTime.now().subtract(const Duration(days: 1)));
      expect(lewat.kedaluwarsa, isTrue);
      expect(lewat.bisaDitebus, isFalse);
    });

    test('yang ditutup tidak bisa ditebus walau kuotanya ada', () {
      expect(_batch(active: false).bisaDitebus, isFalse);
    });

    test('nilai yang menggantung di tangan pelanggan', () {
      // Sudah keluar dari saldo bebas, belum jadi apa pun — dan yang
      // sudah hangus tidak ikut, karena dananya sudah kembali.
      expect(
          _batch(claimed: 4, menggantung: 4, amount: 100000).nilaiTertebus,
          400000);
    });

    test('kosongnya daftar merchant berarti semua merchant', () {
      expect(_batch().berlakuDiSemuaResto, isTrue);
    });
  });

  group('voucher milik pelanggan', () {
    test('yang baru ditebus siap dipakai', () {
      expect(_claim().siapDipakai, isTrue);
    });

    test('yang sudah dipakai tidak bisa dipakai lagi', () {
      expect(_claim(status: VoucherClaimStatus.used).siapDipakai, isFalse);
    });

    test('yang kedaluwarsa tidak siap dipakai walau statusnya masih claimed',
        () {
      // Penjadwal berjalan sekali sehari; di antara dua jalannya, status
      // di database masih 'claimed' padahal tanggalnya sudah lewat.
      // Layar tidak boleh menawarkan yang sudah hangus.
      final lewat =
          _claim(expiresOn: DateTime.now().subtract(const Duration(days: 1)));
      expect(lewat.siapDipakai, isFalse);
    });

    test('minimum belanja ditegakkan', () {
      final v = _claim(minPurchase: 50000);
      expect(v.bisaDipakaiDi('r1', 30000), isFalse);
      expect(v.bisaDipakaiDi('r1', 50000), isTrue);
    });

    test('merchant yang tidak terdaftar ditolak', () {
      final v = _claim(restoIds: const ['r1']);
      expect(v.bisaDipakaiDi('r2', 100000), isFalse);
      expect(v.bisaDipakaiDi('r1', 100000), isTrue);
    });

    test('setiap penolakan punya kalimatnya', () {
      // Voucher yang tampil tapi tidak bisa dipilih tanpa penjelasan
      // membuat orang mengira aplikasinya rusak.
      expect(_claim(status: VoucherClaimStatus.used).alasanTidakBisa('r1', 1),
          'Sudah dipakai');
      expect(_claim(minPurchase: 50000).alasanTidakBisa('r1', 1),
          'Belanja belum mencapai minimum');
      expect(_claim(restoIds: const ['r1']).alasanTidakBisa('r2', 999999),
          'Tidak berlaku di merchant ini');
      expect(_claim().alasanTidakBisa('r1', 999999), isNull);
    });

    test('tiap status punya labelnya sendiri', () {
      final semua =
          VoucherClaimStatus.values.map((s) => kVoucherClaimLabels[s]).toSet();
      expect(semua.length, VoucherClaimStatus.values.length);
    });

    test('terbaca dari baris database berikut batch-nya', () {
      final v = VoucherClaim.fromMap({
        'id': 'VCL-1',
        'voucher_id': 'VC-1',
        'customer_label': 'a@b.com',
        'amount': 100000,
        'status': 'claimed',
        'created_at': '2026-08-10T10:00:00Z',
        'vouchers': {
          'code': 'HEMAT100',
          'name': 'Promo',
          'expires_on': '2026-12-31',
          'min_purchase': 25000,
          'resto_ids': ['r1'],
        },
      });
      expect(v.code, 'HEMAT100');
      expect(v.minPurchase, 25000);
      expect(v.restoIds, ['r1']);
    });
  });

  group('terbitnya voucher langsung dikabarkan', () {
    final sql = File('supabase/voucher_announcement.sql').readAsStringSync();

    test('pengumumannya ditulis dalam transaksi yang sama', () {
      // Dua langkah terpisah yang harus diingat berurutan berarti
      // suatu saat yang kedua terlewat — dan voucher yang tidak
      // diumumkan adalah uang yang keluar untuk sesuatu yang tidak
      // ada yang tahu.
      expect(sql, contains('function generate_voucher_batch'));
      expect(sql, contains('insert into app_announcements'));
    });

    test('masuk tab Umum, ditujukan ke pelanggan', () {
      expect(sql, contains("'general',"));
      expect(sql, contains("'customers',"));
    });

    test('kodenya ikut supaya bisa disalin dari notifikasi', () {
      expect(sql, contains("'Kode voucher: ' || v_code"));
    });

    test('kuota dan tenggatnya disebut', () {
      expect(sql, contains("p_quantity"));
      expect(sql, contains("to_char(p_expires_on"));
    });

    test('nominalnya diformat, bukan angka telanjang', () {
      // Angka telanjang terbaca salah sekilas, dan sekilas adalah
      // satu-satunya waktu yang dipunya notifikasi.
      expect(sql, contains("to_char(v_amount, 'FM999G999G999G999')"));
    });

    test('minimal belanja hanya disebut kalau ada', () {
      expect(sql, contains('case when p_min_purchase > 0'));
    });

    test('pushnya menumpang pemicu yang sudah ada', () {
      // Berkas ini sengaja tidak tahu apa-apa soal FCM.
      final push = File('supabase/announcement_push.sql').readAsStringSync();
      expect(push, contains('after insert on app_announcements'));
      expect(sql, isNot(contains('push_outbox (resto_id')));
    });

    test('satu akun satu kali tetap ditegakkan basis data', () {
      final vc = File('supabase/vouchers.sql').readAsStringSync();
      expect(vc, contains('unique (voucher_id, customer_label)'));
    });
  });

  group('akun voucher terlihat di pemetaan GL', () {
    final layar =
        File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();

    test('keduanya ikut dihitung dan ditampilkan', () {
      // Akun yang tidak ada di layar ini tidak bisa diperbaiki kalau
      // nomornya salah — dan pemicu jurnal melewatkan baris yang
      // GL-nya kosong tanpa mengeluh.
      expect(layar, contains("const _voucherMethod = 'voucher';"));
      expect(layar, contains("const _voucherRedeemMethod = 'voucher_redeem';"));
      expect(layar, contains('_voucherMethod,\n  _voucherRedeemMethod,'));
      expect(layar, contains("title: 'GL Voucher',"));
    });

    test('hanya muncul di pembukuan MerchantPOS', () {
      // Resto tidak menerbitkan voucher; menghitungnya untuk mereka
      // membuat penanda "belum dipetakan" berbunyi selamanya.
      expect(layar, contains('_platformOnlyMethods'));
      expect(layar, contains('if (!_platformOnlyMethods.contains(m)) m,'));
    });

    test('nomornya disemai saat SQL-nya dijalankan', () {
      final vc = File('supabase/vouchers.sql').readAsStringSync();
      expect(vc, contains("('merchantpos', 'voucher',        '1100073'"));
      expect(vc, contains("('merchantpos', 'voucher_redeem', '1100074'"));
    });
  });

  group('banner, hapus, dan daftar penebus', () {
    final sql = File('supabase/voucher_manage.sql').readAsStringSync();
    final layar = File('lib/screens/voucher_screen.dart').readAsStringSync();

    test('banner ikut ke pengumuman, bukan cuma tersimpan', () {
      expect(sql, contains('banner_base64 text'));
      expect(sql, contains('image_base64, created_by'));
      expect(sql, contains("nullif(p_banner, '')"));
    });

    test('pratinjaunya 16:9, sama dengan hasilnya', () {
      expect(layar, contains('aspectRatio: 16 / 9'));
      expect(layar, contains('fit: BoxFit.cover'));
    });

    test('yang masih berjalan tidak bisa dihapus', () {
      expect(sql, contains('Tutup dulu vouchernya sebelum dihapus'));
      final model = File('lib/models/voucher.dart').readAsStringSync();
      expect(model, contains('bool get bisaDihapus => !active && claimed == 0;'));
    });

    test('yang sudah ada penebusnya tidak bisa dihapus', () {
      // Klaim adalah uang yang menggantung di tangan orang, dan
      // barisnya dirujuk jurnal penebusan serta antrean pencairan.
      expect(sql, contains('pelanggan yang menebus'));
    });

    test('dananya pulang sebelum barisnya dibuang', () {
      // Batch yang dihapus tanpa mengembalikan alokasinya adalah saldo
      // MerchantPOS yang berkurang selamanya untuk voucher yang tak ada.
      final blok = sql.substring(sql.indexOf('function delete_voucher_batch'));
      expect(blok.indexOf("_jurnal_merchantpos('total_balance'"),
          lessThan(blok.indexOf('delete from vouchers')));
      expect(blok, contains('if v.settled_at is null then'));
    });

    test('pengumumannya ikut dicabut', () {
      expect(sql, contains('delete from app_announcements'));
    });

    test('hanya Super Admin yang menghapus', () {
      expect(sql, contains('Hanya Super Admin yang dapat menghapus voucher'));
    });

    test('tombol hapus hanya muncul saat memang boleh', () {
      // Tombol yang selalu menolak lebih membingungkan daripada
      // tombol yang jelas mati.
      expect(layar, contains('if (voucher.bisaDihapus)'));
    });

    test('alasan penolakan server tidak ditelan', () {
      expect(layar, contains('String _pesanGalat(Object e)'));
    });

    test('daftar penebus memisahkan dipakai, menggantung, dan hangus', () {
      expect(layar, contains("'Sudah dipakai'"));
      expect(layar, contains("'Belum dipakai'"));
      expect(layar, contains("'Hangus'"));
      expect(layar, contains('final menggantung = _items.length - dipakai - hangus;'));
    });

    test('kedaluwarsa dinilai dari tanggal, bukan hanya status', () {
      // Penjadwal berjalan sekali sehari; di antara dua jalannya ada
      // voucher yang statusnya masih claimed padahal sudah lewat.
      expect(layar, contains('c.status == VoucherClaimStatus.expired || c.kedaluwarsa'));
    });

    test('emailnya yang ditampilkan', () {
      expect(layar, contains('Text(c.customerLabel,'));
    });
  });

  group('memilih merchant sasaran', () {
    final layar =
        File('lib/screens/voucher_screen.dart').readAsStringSync();

    test('daftarnya bisa dicari', () {
      expect(layar, contains('hintText: \'Cari merchant\''));
      expect(layar, contains('r.name.toLowerCase().contains(q)'));
    });

    test('pilih semua terbatas pada yang sedang tampil', () {
      // "Pilih semua" yang diam-diam mencentang resto yang sedang
      // tersaring keluar adalah voucher yang berlaku di tempat yang
      // tidak pernah dimaksud.
      expect(layar, contains('final tampil = _restoTampil.map((r) => r.id);'));
      expect(layar, contains('_sasaran.removeAll(tampil)'));
    });

    test('yang tersaring keluar tetap terpilih', () {
      expect(layar, contains('if (q.isEmpty) return widget.resto;'));
    });

    test('pencarian tanpa hasil mengatakannya', () {
      expect(layar, contains('Tidak ada merchant bernama itu'));
    });
  });

  group('pencairan sungguhan ke merchant', () {
    final sql = File('supabase/voucher_payouts.sql').readAsStringSync();
    final fn =
        File('supabase/functions/settle-voucher-payouts/index.ts').readAsStringSync();

    test('pemicunya mengantre, bukan memanggil Xendit', () {
      // Panggilan penyedia di dalam transaksi pesanan berarti pesanan
      // pelanggan gagal tersimpan tiap kali penyedianya lambat.
      expect(sql, contains('insert into voucher_payouts'));
      expect(sql, isNot(contains('net.http_post(\n    url := \'https://api.xendit')));
    });

    test('satu klaim satu pencairan, dijaga basis data', () {
      expect(sql, contains('claim_id text not null unique'));
      expect(sql, contains('on conflict (claim_id) do nothing'));
    });

    test('yang sudah terkirim tidak bisa dibatalkan', () {
      expect(sql, contains("and status <> 'sent'"));
    });

    test('barisnya tidak pernah dihapus', () {
      expect(sql, isNot(contains('delete from voucher_payouts')));
    });

    test('tipe claim_id mengikuti voucher_claims, bukan menebak', () {
      // voucher_claims.id bertipe text; kunci asing bertipe uuid
      // ditolak Postgres saat dipasang, bukan saat dipakai.
      final vc = File('supabase/vouchers.sql').readAsStringSync();
      expect(vc, contains('id text primary key'));
      expect(sql, isNot(contains('claim_id uuid')));
    });

    test('hanya merchant bersub-akun aktif yang diangkut', () {
      expect(sql, contains('a.active and a.account_id'));
    });

    test('klaim yang sudah terlanjur dipakai ikut diantre', () {
      // Tanggal pemasangan bukan garis pemisah antara utang dan bukan.
      expect(sql, contains("from voucher_claims c\nwhere c.status = 'used'"));
    });

    test('fungsi pencairannya memakai Transfers, bukan Disbursements', () {
      // Disbursement menuntut nomor rekening resto — yang sengaja
      // tidak kita simpan.
      expect(fn, contains('https://api.xendit.co/transfers'));
      expect(fn, isNot(contains('/disbursements')));
    });

    test('id klaim jadi reference sekaligus kunci idempotensi', () {
      expect(fn, contains('"X-IDEMPOTENCY-KEY": p.claim_id'));
      expect(fn, contains('reference: p.claim_id'));
    });

    test('duplikat dihitung berhasil, bukan gagal', () {
      // Menandainya gagal membuat barisnya dicoba ulang selamanya.
      expect(fn, contains('DUPLICATE_TRANSFER_ERROR'));
      expect(fn, contains('jawab.ok || sudahPernah'));
    });

    test('satu merchant bermasalah tidak menghentikan yang lain', () {
      expect(fn, contains('} catch (e) {'));
      expect(fn, contains('p_ok: false'));
    });

    test('nominalnya dibaca server, tidak pernah dikirim pemanggil', () {
      expect(fn, contains('amount: p.amount'));
      expect(fn, isNot(contains('body.amount')));
    });

    test('menolak jalan tanpa pengenal akun sumber', () {
      // Transfer tanpa sumber yang jelas adalah uang yang diambil dari
      // akun yang tidak kita maksud.
      expect(fn, contains('XENDIT_ACCOUNT_ID belum diisi'));
    });

    test('penjadwalnya diam selama belum dikonfigurasi', () {
      expect(sql, contains('if v_cfg.function_url is null'));
      expect(sql, contains("cron.schedule('settle-voucher-payouts'"));
    });

    test('tabel konfigurasinya tidak terbaca peran mana pun', () {
      expect(sql, contains('alter table voucher_payout_config enable row level security'));
      expect(sql, isNot(contains('"voucher_payout_config: read"')));
    });
  });

  group('voucher khusus pengguna baru', () {
    final sql = File('supabase/voucher_new_customer.sql').readAsStringSync();
    final layar = File('lib/screens/voucher_screen.dart').readAsStringSync();

    test('pengguna baru berarti belum pernah punya pesanan terbayar', () {
      // Pesanan batal tidak dihitung: orang yang memesan lalu
      // membatalkannya belum pernah benar-benar memakai MerchantPOS, dan
      // menutup pintu untuknya justru menutup pintu bagi orang yang
      // paling ingin dibujuk kembali.
      expect(sql, contains('function _pelanggan_baru'));
      expect(sql, contains("payment_status = 'paid'"));
      expect(sql, contains('select not exists ('));
    });

    test('batasnya seluruh MerchantPOS, bukan per merchant', () {
      // Orang yang sudah rutin memesan di resto sebelah bukan pengguna
      // baru hanya karena belum pernah masuk resto ini.
      final fn = sql.substring(sql.indexOf('function _pelanggan_baru'),
          sql.indexOf('function claim_voucher'));
      expect(fn, isNot(contains('resto_id')));
    });

    test('diperiksa saat menebus, bukan cuma disimpan', () {
      expect(sql, contains('if v.new_customers_only and not _pelanggan_baru'));
    });

    test('alasan penolakannya menyebut sebab yang sebenarnya', () {
      expect(sql,
          contains('Voucher ini hanya untuk pengguna baru MerchantPOS'));
    });

    test('diperiksa sebelum kuota', () {
      // Orang yang tidak berhak tidak boleh menghabiskan jatah orang
      // yang berhak, dan tidak boleh diberi tahu "sudah habis" padahal
      // sebabnya bukan itu.
      final blok = sql.substring(sql.indexOf('function claim_voucher'));
      expect(blok.indexOf('new_customers_only'),
          lessThan(blok.indexOf('v_terpakai >= v.quantity')));
    });

    test('syaratnya disebut di pengumumannya', () {
      // Ditolak sesudah bersemangat lebih menjengkelkan daripada tahu
      // sejak awal bahwa ini bukan untuk dirinya.
      expect(sql, contains('Khusus pengguna baru yang belum pernah memesan'));
    });

    test('ada ceklisnya di form terbit, dan tampil di kartunya', () {
      expect(layar, contains("const Text('Khusus pengguna baru',"));
      expect(layar, contains("if (voucher.newCustomersOnly) 'khusus pengguna baru',"));
    });

    test('kolomnya bawaan false, bukan null', () {
      // Voucher lama tidak boleh tiba-tiba jadi terbatas.
      expect(sql, contains('boolean not null default false'));
    });
  });

  group('yang menggantung dan yang sudah kembali', () {
    Voucher batch({int claimed = 0, int menggantung = 0}) => Voucher(
          id: 'VC-1',
          code: 'HEMAT1',
          name: 'Hemat 1',
          totalAmount: 100,
          quantity: 10,
          amount: 10,
          expiresOn: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime(2026, 8, 1),
          claimed: claimed,
          menggantung: menggantung,
        );

    test('yang hangus tidak lagi dihitung menggantung', () {
      // Dananya sudah kembali ke GL Total Saldo; menghitungnya lagi
      // membuat angka di kepala layar lebih besar daripada yang
      // benar-benar tertahan, dan tidak pernah turun.
      expect(batch(claimed: 1, menggantung: 0).nilaiTertebus, 0);
    });

    test('yang masih di tangan orang tetap dihitung', () {
      expect(batch(claimed: 3, menggantung: 2).nilaiTertebus, 20);
    });

    test('kuotanya tetap memakai seluruh penebusan', () {
      // Jatah yang sudah diserahkan tidak kembali jadi jatah hanya
      // karena orangnya lupa memakainya.
      final v = batch(claimed: 10, menggantung: 0);
      expect(v.sisa, 0);
      expect(v.habis, isTrue);
    });

    test('repo memisahkan keduanya dari statusnya', () {
      final repo =
          File('lib/db/voucher_repository.dart').readAsStringSync();
      expect(repo, contains("select('voucher_id, status')"));
      expect(repo, contains("if (r['status'] == 'claimed')"));
    });
  });

  group('dana hangus kembali ke saldo', () {
    final sql = File('supabase/vouchers.sql').readAsStringSync();
    final fn = sql.substring(sql.indexOf('function expire_vouchers'));

    test('yang sudah ditebus tapi tidak dipakai dikembalikan', () {
      expect(fn, contains("cl.status = 'claimed' and vc.expires_on < current_date"));
      expect(fn, contains("_jurnal_merchantpos('voucher_redeem'"));
    });

    test('yang tidak pernah ditebus juga dikembalikan', () {
      expect(fn, contains('v.amount * (v.quantity - count(*))'));
      expect(fn, contains("_jurnal_merchantpos('voucher', v.id, v_sisa"));
    });

    test('keduanya mendarat di GL Total Saldo', () {
      expect("_jurnal_merchantpos('total_balance'".allMatches(fn).length, 2);
    });

    test('tidak dikembalikan dua kali', () {
      expect(fn, contains('settled_at is null'));
      expect(fn, contains('update vouchers set settled_at = now()'));
    });

    test('dijadwalkan tiap hari, bukan menunggu dijalankan orang', () {
      expect(sql, contains("cron.schedule('expire-vouchers', '10 17 * * *'"));
    });
  });

  group('alur uangnya di SQL', () {
    final sql = File('supabase/vouchers.sql').readAsStringSync();

    test('terbit: saldo bebas keluar, kantong voucher terisi', () {
      expect(sql, contains("perform _jurnal_merchantpos('total_balance'"));
      expect(sql, contains("perform _jurnal_merchantpos('voucher', v_id"));
    });

    test('ditebus: pindah dari GL Voucher ke GL Voucher Redeem', () {
      final blok = sql.substring(sql.indexOf('function claim_voucher'));
      expect(blok, contains("_jurnal_merchantpos('voucher', v_id, v.amount,\n    'debit'"));
      expect(blok, contains("_jurnal_merchantpos('voucher_redeem'"));
    });

    test('dipakai: keluar dari Redeem, masuk ke GL merchant', () {
      final blok = sql.substring(sql.indexOf('function log_voucher_use'));
      expect(blok, contains("_jurnal_merchantpos('voucher_redeem'"));
      expect(blok, contains("_gl_account_for(new.resto_id, 'transfer')"));
      expect(blok, contains("'credit'"));
    });

    test('hangus: dananya pulang ke GL Total Saldo', () {
      final blok = sql.substring(sql.indexOf('function expire_vouchers'));
      expect(blok, contains("_jurnal_merchantpos('total_balance'"));
      expect(blok, contains("'credit'"));
    });

    test('sisa yang tak pernah ditebus dihitung sekali saja', () {
      // `settled_at` yang menjaganya, bukan ingatan penjadwal.
      expect(sql, contains('settled_at is null'));
      expect(sql, contains('update vouchers set settled_at = now()'));
    });

    test('nomor akunnya sederet dengan GL Diskon', () {
      expect(sql, contains("'voucher',        '1100073'"));
      expect(sql, contains("'voucher_redeem', '1100074'"));
    });

    test('satu orang satu voucher per batch', () {
      // Tanpa ini, orang pertama yang membaca pengumumannya bisa
      // menebus kesepuluhnya sekaligus.
      expect(sql, contains('unique (voucher_id, customer_label)'));
    });

    test('kuota ditegakkan server, bukan aplikasi', () {
      expect(sql, contains('if v_terpakai >= v.quantity then'));
      expect(sql, contains('Voucher ini sudah habis'));
    });

    test('tiap penolakan penebusan menyebut alasannya', () {
      for (final alasan in [
        'Kode voucher tidak ditemukan',
        'Voucher ini sudah ditutup',
        'Voucher ini sudah kedaluwarsa',
        'Voucher ini sudah kamu tebus',
        'Voucher ini sudah habis',
      ]) {
        expect(sql, contains(alasan), reason: alasan);
      }
    });

    test('nominal per voucher dihitung server saat terbit', () {
      expect(sql, contains('v_amount := p_total / p_quantity'));
    });

    test('yang dicatat keluar hanya yang benar-benar bisa ditebus', () {
      // Sisa pembagian tidak pernah jadi voucher; mencatatnya sebagai
      // uang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
      expect(sql, contains('v_amount * p_quantity'));
    });

    test('hanya Super Admin yang menerbitkan', () {
      expect(sql, contains('Hanya Super Admin yang dapat menerbitkan voucher'));
    });

    test('tidak ada kebijakan tulis untuk siapa pun di tabel penebusan', () {
      // Menebus lewat RPC, memakai lewat pemicu — tangan yang bisa
      // menulis langsung ke sini adalah tangan yang bisa membuat voucher
      // dari udara.
      expect(sql, isNot(contains('"voucher_claims: write"')));
      expect(sql, contains('Tidak ada kebijakan tulis untuk siapa pun'));
    });

    test('pemakaian dicatat pemicu pada pesanan', () {
      expect(sql, contains('after insert on orders'));
      expect(sql, contains('function log_voucher_use'));
    });

    test('kedaluwarsa dijalankan penjadwal harian', () {
      expect(sql, contains("cron.schedule('expire-vouchers'"));
    });
  });
}
