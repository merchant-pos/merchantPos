import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Siapa yang perangkatnya terdaftar, dan siapa yang menerima apa.
///
/// Pengumuman yang masuk kotak masuk tapi tidak pernah muncul sebagai
/// notifikasi hampir selalu berarti perangkatnya tidak pernah terdaftar
/// — bukan penargetannya yang salah.
void main() {
  final binder =
      File('lib/widgets/order_notification_binder.dart').readAsStringSync();
  final push =
      File('supabase/functions/send-push/index.ts').readAsStringSync();

  group('pendaftaran perangkat', () {
    test('karyawan didaftarkan walau belum punya merchant', () {
      // Super Admin tidak terikat resto mana pun. Syarat restoId != null
      // membuatnya tidak pernah mendaftar sama sekali.
      expect(binder, contains('if (auth.isEmployee) {'));
      expect(binder, isNot(contains('if (auth.isEmployee && auth.restoId != null)')));
    });

    test('pelanggan yang sudah masuk didaftarkan walau belum buka merchant', () {
      // Voucher menyasar emailnya, bukan restonya.
      expect(binder, contains('if (auth.isLoggedIn) {'));
      expect(binder, contains('session.hasActiveResto ? session.restoId : null'));
    });

    test('tamu tetap butuh merchant aktif', () {
      // Tanpa resto, tidak ada satu pun penanda untuk memanggilnya.
      final blok = binder.substring(binder.indexOf('// Tamu hanya dikenal'));
      expect(blok, contains('if (session.hasActiveResto && session.restoId != null)'));
    });

    test('perannya ikut dikirim supaya bisa dibedakan', () {
      expect(binder, contains("role: 'customer',"));
      expect(binder, contains('role: auth.role?.dbValue,'));
    });
  });

  group('penargetan di server', () {
    test('pelanggan dikenali dari peran customer, bukan peran kosong', () {
      // Aplikasi menyimpannya sebagai 'customer'. Menganggap "peran
      // kosong berarti pelanggan" salah dua arah sekaligus.
      expect(push, contains("const PERAN_PELANGGAN = \"customer\";"));
      expect(push, contains('role.eq.\${PERAN_PELANGGAN},role.is.null'));
      expect(push, isNot(contains('q.is("role", null)')));
    });

    test('karyawan tidak lagi berarti "punya peran apa pun"', () {
      // Peran 'customer' juga bukan kosong — jadi pengumuman khusus
      // karyawan dulu ikut sampai ke pelanggan.
      final blok = push.substring(push.indexOf('if (target === "employees")'));
      expect(blok.substring(0, 400), contains('not("role", "in"'));
    });

    test('pengumuman tanpa merchant tetap menghormati sasarannya', () {
      // Cabang ini dulu mengembalikan seluruh token apa pun sasarannya.
      final blok = push.substring(push.indexOf('if (!row.resto_id)'));
      expect(blok.substring(0, 700), contains('semua === "customers"'));
      expect(blok.substring(0, 700), contains('semua === "employees"'));
    });

    test('pengumuman untuk semua orang tetap kena semuanya', () {
      final blok = push.substring(push.indexOf('if (!row.resto_id)'));
      expect(blok.substring(0, 700), contains('p.target ?? "all"'));
    });
  });
}
