import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/screens/faq_screen.dart';

void main() {
  final faq = File('lib/screens/faq_screen.dart').readAsStringSync();
  final tentang = File('lib/screens/about_screen.dart').readAsStringSync();
  // Landing page-nya repo terpisah, dan belum tentu ada di sebelah
  // salinan ini. Yang diperiksa di sini kesamaan alamat surel antara
  // aplikasi dan landing page — kalau landing page-nya belum dibuat,
  // tidak ada yang bisa berbeda, jadi tesnya dilewati alih-alih gagal.
  //
  // Dilewati, bukan dihapus: begitu repo-nya ada di sebelah, tesnya
  // hidup lagi sendiri tanpa ada yang perlu ingat menyalakannya.
  final berkasWeb = File('../MerchantPOS Web/index.html');
  final adaLandingPage = berkasWeb.existsSync();
  final web = adaLandingPage ? berkasWeb.readAsStringSync() : '';
  final lewatiLandingPage =
      adaLandingPage ? null : 'landing page MerchantPOS belum dibuat';

  group('alamat surel', () {
    // Alasannya sama dengan nomor WhatsApp: dua alamat terpisah akan
    // berpisah suatu saat, dan yang menemukannya adalah orang yang
    // menulis ke alamat yang sudah tidak dibaca.
    test('sama dengan yang di landing page', () {
      expect(kEmailMerchantPOS, 'merchantpos.app@gmail.com');
      expect(web, contains('mailto:$kEmailMerchantPOS'));
    }, skip: lewatiLandingPage);

    test('membuka mailto berikut subjeknya', () {
      expect(faq, contains("scheme: 'mailto'"));
      expect(faq, contains('subject='));
    });

    test('kegagalannya dikatakan, bukan didiamkan', () {
      final fungsi = faq.substring(faq.indexOf('bukaEmailMerchantPOS'));
      expect(fungsi, contains('Tidak ada aplikasi surel yang terpasang.'));
    });

    test('tampil di layar Tentang MerchantPOS', () {
      expect(tentang, contains('bukaEmailMerchantPOS(context)'));
      expect(tentang, contains('kEmailMerchantPOS'));
    });

    // Yang membaca FAQ lalu tidak menemukan jawabannya justru orang yang
    // paling perlu tahu ke mana harus bertanya.
    test('tampil di FAQ landing page, bukan cuma di footer', () {
      final faqWeb = web.substring(web.indexOf('id="faq"'));
      expect(faqWeb.substring(0, faqWeb.indexOf('<footer>')),
          contains(kEmailMerchantPOS));
    }, skip: lewatiLandingPage);
  });

  group('nomor WhatsApp', () {
    test('sama dengan yang di landing page', () {
      // Dua nomor terpisah akan berpisah suatu saat, dan yang
      // menemukannya adalah orang yang mengirim pesan ke nomor yang
      // sudah tidak dipakai.
      expect(kWhatsAppMerchantPOS, '6281316090867');
      expect(web, contains('wa.me/$kWhatsAppMerchantPOS'));
    }, skip: lewatiLandingPage);

    test('membuka wa.me, langsung ke percakapannya', () {
      expect(faq, contains('https://wa.me/\$kWhatsAppMerchantPOS?text='));
      expect(faq, contains('LaunchMode.externalApplication'));
    });

    test('kegagalannya dikatakan, bukan didiamkan', () {
      expect(faq, contains('Tidak bisa membuka WhatsApp.'));
    });

    test('tombolnya ada di FAQ maupun Tentang', () {
      expect(faq, contains('Chat MerchantPOS Admin'));
      expect(tentang, contains('bukaWhatsAppMerchantPOS(context)'));
    });
  });

  group('isi FAQ', () {
    test('pertanyaannya sama dengan landing page', () {
      for (final t in [
        'Apakah customer perlu install aplikasi juga?',
        'Kenapa customer perlu install MerchantPOS?',
        'Bagaimana kalau internet mati?',
        'Apakah pembayaran QRIS diproses oleh MerchantPOS?',
        'Tarif PPN dan biaya service bisa diatur?',
        'Berapa biaya langganan per bulannya?',
      ]) {
        expect(faq, contains(t), reason: t);
        expect(web, contains(t), reason: 'hilang di web: $t');
      }
    }, skip: lewatiLandingPage);

    test('disalin, bukan diambil dari webnya', () {
      // Halaman yang gagal dimuat karena sinyal buruk berarti jawaban
      // yang paling dibutuhkan saat sedang bermasalah tidak terbaca.
      expect(faq, isNot(contains('http://')));
      expect(faq, contains("const _faq = <(String, String)>["));
    }, skip: lewatiLandingPage);

    test('memakai kata merchant, bukan resto', () {
      final isi = faq.substring(faq.indexOf('const _faq'));
      expect(isi, isNot(contains(' resto ')));
    });
  });

  group('Tentang MerchantPOS', () {
    test('punya tombol FAQ mengambang', () {
      expect(tentang, contains('floatingActionButton: FloatingActionButton.extended'));
      expect(tentang, contains('const FaqScreen()'));
    });

    test('menyisakan ruang supaya baris terakhir tidak tertutup', () {
      expect(tentang, contains('SizedBox(height: 72)'));
    });

    test('fitur barunya ikut disebut', () {
      for (final f in [
        'Voucher MerchantPOS',
        'Nomor pesanan',
        'Merchant terdekat',
        'Layar pelanggan',
        'Cari menu',
        'Topping & level',
        'Fasilitas tempat',
        'Setoran modal',
        'Tagihan langganan',
      ]) {
        expect(tentang, contains(f), reason: f);
      }
    });
  });

  group('nama peran', () {
    test('Super Admin sudah jadi MerchantPOS Admin di teks', () {
      final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
      expect(auth, contains("EmployeeRole.superAdmin: 'MerchantPOS Admin'"));
    });

    test('nilai di basis data tidak ikut berubah', () {
      // 'super_admin' dipakai RLS dan kolom employees; menggantinya
      // berarti tiap kebijakan harus ikut diubah.
      final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
      expect(auth, contains("EmployeeRole.superAdmin: 'super_admin'"));
    });
  });
}
