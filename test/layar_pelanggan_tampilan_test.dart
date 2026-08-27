import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tampilan layar yang menghadap pelanggan.
void main() {
  final layar =
      File('lib/screens/customer_display_screen.dart').readAsStringSync();

  group('nama merchant', () {
    test('dibaca dari barisnya sendiri, bukan setelan', () {
      // Nilai bawaan SettingsProvider "Toko Kamu" — nama yang jelas
      // bukan nama tempat itu, di layar yang justru paling dilihat
      // orang luar.
      expect(layar, contains('_merchantRepo.getOnce(restoId)'));
      // Namanya masih disebut di komentar sebagai catatan; yang tidak
      // boleh kembali pemakaiannya.
      expect(layar, isNot(contains('watch<SettingsProvider>()')));
      expect(layar, isNot(contains("Text(nama)")));
    });

    test('kosong lebih baik daripada nama yang salah', () {
      expect(layar, contains('if (merchant != null) ...['));
    });

    test('gagal membacanya tidak menjatuhkan layarnya', () {
      expect(layar, contains('} catch (_) {'));
    });
  });

  group('logo dan tanda Merchant-POS', () {
    test('logo merchant tampil di layar menganggur', () {
      expect(layar, contains('_LogoMerchant(merchant: merchant'));
    });

    test('yang belum punya logo memakai logo Merchant-POS', () {
      // Ruang kosong di puncak layar yang menghadap pelanggan terbaca
      // seperti gambar yang gagal dimuat.
      expect(layar, contains('if (logo == null || logo.isEmpty)'));
      expect(layar, contains('return MerchantPosLogo(size: ukuran);'));
    });

    test('logo rusak jatuh ke logo Merchant-POS juga', () {
      expect(layar,
          contains('errorBuilder: (_, __, ___) => MerchantPosLogo(size: ukuran)'));
    });

    test('tanda powered by ada di dasar layar, semua keadaan', () {
      // Satu-satunya layar yang dilihat orang yang belum tentu memakai
      // Merchant-POS.
      expect(layar, contains('_PoweredBy()'));
      final blok = layar.substring(layar.indexOf('body: SafeArea('));
      expect(blok.indexOf('_PoweredBy()'),
          greaterThan(blok.indexOf('StreamBuilder<TampilanLayar>')));
    });
  });

  group('foto ulasan', () {
    final info =
        File('lib/screens/merchant_info_screen.dart').readAsStringSync();
    final penampil =
        File('lib/widgets/penampil_foto.dart').readAsStringSync();

    test('bisa diketuk untuk dilihat besar', () {
      // Petak 82 piksel cukup untuk tahu ada fotonya, tidak cukup untuk
      // melihat apa isinya.
      expect(info, contains('lihatFoto(context, ulasan.photos, mulai: i)'));
    });

    test('membuka dari foto yang diketuk, bukan selalu yang pertama', () {
      expect(penampil, contains('PageController(initialPage: widget.mulai)'));
    });

    test('bisa dizoom dan digeser antar foto', () {
      expect(penampil, contains('InteractiveViewer('));
      expect(penampil, contains('PageView.builder('));
    });

    test('memakai layar penuh, bukan dialog', () {
      // Foto yang dizoom di dalam kotak dialog tetap terpotong kotaknya.
      expect(penampil, contains('fullscreenDialog: true'));
    });

    test('satu foto rusak tidak mengosongkan penampilnya', () {
      expect(penampil, contains('Icons.broken_image_outlined'));
    });

    test('daftar kosong tidak membuka apa pun', () {
      expect(penampil, contains('if (foto.isEmpty) return Future.value();'));
    });
  });

  group('QR-nya', () {
    test('memakai kartu Merchant-POS, bukan kotak putih polos', () {
      // Bingkai, logo, dan tulisannya sudah dirancang untuk dipindai
      // dari seberang meja.
      expect(layar, contains('MerchantPosQrCard('));
      expect(layar, isNot(contains('QrImageView(')));
    });

    test('berada di tengah', () {
      // Lebarnya dipatok sendiri oleh kartunya, jadi tanpa Center ia
      // menempel ke kiri pada layar yang lebih lebar.
      final blok = layar.substring(layar.indexOf('if (tampilan.adaQr)'));
      expect(blok.indexOf('Center('), lessThan(blok.indexOf('MerchantPosQrCard(')));
    });

    test('judulnya nama merchant-nya', () {
      expect(layar, contains("title: nama ?? 'Pembayaran'"));
    });

    test('tetap memberi arahan kalau QR-nya tidak ada', () {
      expect(layar, contains("'Silakan bayar di kasir'"));
    });
  });
}
