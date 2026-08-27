import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/db/support_repository.dart';
import 'package:merchant_pos/models/support_ticket.dart';

SupportTicket tiket({
  String status = 'open',
  DateTime? pesanTerakhir,
  bool dariAdmin = false,
  DateTime? dibacaPelapor,
  DateTime? dibacaAdmin,
  String? nama,
  DateTime? pelaporBicara,
  DateTime? adminBicara,
}) =>
    SupportTicket.fromMap({
      'id': 't1',
      'reporter_email': 'budi@toko.com',
      'reporter_name': nama,
      'subject': 'QRIS tidak muncul',
      'status': status,
      'created_at': '2026-08-22T01:00:00Z',
      'last_message_at': pesanTerakhir?.toIso8601String(),
      'last_message_from_admin': dariAdmin,
      'reporter_read_at': dibacaPelapor?.toIso8601String(),
      'admin_read_at': dibacaAdmin?.toIso8601String(),
      // Kalau tidak disebut sendiri, ikut arah pesan terakhirnya —
      // supaya kasus-kasus lama tetap terbaca apa adanya.
      'last_reporter_at': (pelaporBicara ??
              (dariAdmin ? null : pesanTerakhir))
          ?.toIso8601String(),
      'last_admin_at':
          (adminBicara ?? (dariAdmin ? pesanTerakhir : null))
              ?.toIso8601String(),
    });

void main() {
  final jam9 = DateTime.utc(2026, 8, 22, 9);
  final jam10 = DateTime.utc(2026, 8, 22, 10);

  group('status tiket', () {
    test('keempatnya punya kode, tulisan, dan warnanya', () {
      for (final s in SupportStatus.values) {
        expect(kSupportStatusDb[s], isNotNull, reason: '$s tanpa kode');
        expect(kSupportStatusLabel[s], isNotNull, reason: '$s tanpa tulisan');
        expect(kSupportStatusWarna[s], isNotNull, reason: '$s tanpa warna');
      }
    });

    test('kode yang tidak dikenal dibaca sebagai open', () {
      // Baris yang ditulis versi yang lebih baru tidak boleh membuat
      // daftar pengaduan gagal tampil sama sekali.
      expect(supportStatusDari('entah'), SupportStatus.open);
      expect(supportStatusDari(null), SupportStatus.open);
    });

    test('hanya closed yang dianggap selesai', () {
      expect(tiket(status: 'closed').terbuka, isFalse);
      for (final s in ['open', 'on_progress', 'confirm_customer']) {
        expect(tiket(status: s).terbuka, isTrue, reason: s);
      }
    });
  });

  group('penanda belum dibaca', () {
    test('pesan dari pihak sendiri tidak pernah jadi kabar baru', () {
      final t = tiket(pesanTerakhir: jam10, dariAdmin: true);
      expect(t.belumDibaca(sebagaiAdmin: true), isFalse);
    });

    test('pesan admin jadi kabar baru bagi pelapor', () {
      final t = tiket(pesanTerakhir: jam10, dariAdmin: true);
      expect(t.belumDibaca(sebagaiAdmin: false), isTrue);
    });

    test('yang sudah dibuka sesudah pesannya tidak lagi bertanda', () {
      final t = tiket(
          pesanTerakhir: jam9, dariAdmin: true, dibacaPelapor: jam10);
      expect(t.belumDibaca(sebagaiAdmin: false), isFalse);
    });

    test('dibuka sebelum pesannya datang tetap bertanda', () {
      final t = tiket(
          pesanTerakhir: jam10, dariAdmin: true, dibacaPelapor: jam9);
      expect(t.belumDibaca(sebagaiAdmin: false), isTrue);
    });

    test('tiket tanpa pesan sama sekali tidak bertanda', () {
      expect(tiket().belumDibaca(sebagaiAdmin: false), isFalse);
    });

    // Sapaan otomatis adalah pesan dari admin. Kalau penandanya
    // disimpulkan dari "siapa yang bicara terakhir", pengaduan yang baru
    // disapa mesin langsung terlihat beres — padahal belum dibaca siapa
    // pun.
    test('sapaan otomatis tidak menghapus tanda belum dibaca admin', () {
      final t = tiket(
        pesanTerakhir: jam10,
        dariAdmin: true,
        pelaporBicara: jam9,
        adminBicara: jam10,
      );
      expect(t.belumDibaca(sebagaiAdmin: true), isTrue);
    });

    test('tapi pelapor tetap melihatnya sebagai kabar baru', () {
      final t = tiket(
        pesanTerakhir: jam10,
        dariAdmin: true,
        pelaporBicara: jam9,
        adminBicara: jam10,
      );
      expect(t.belumDibaca(sebagaiAdmin: false), isTrue);
    });

    test('admin yang sudah membacanya berhenti bertanda', () {
      final t = tiket(
        pesanTerakhir: jam10,
        dariAdmin: true,
        pelaporBicara: jam9,
        adminBicara: jam10,
        dibacaAdmin: jam10,
      );
      expect(t.belumDibaca(sebagaiAdmin: true), isFalse);
    });

    test('jumlahnya dihitung dari daftar tiketnya sendiri', () {
      final daftar = [
        tiket(pesanTerakhir: jam10, dariAdmin: true),
        tiket(pesanTerakhir: jam10, dariAdmin: false),
        tiket(pesanTerakhir: jam9, dariAdmin: true, dibacaPelapor: jam10),
      ];
      expect(SupportRepository.belumDibaca(daftar, sebagaiAdmin: false), 1);
      expect(SupportRepository.belumDibaca(daftar, sebagaiAdmin: true), 1);
    });
  });

  group('nama pelapor', () {
    test('tanpa nama, bagian depan emailnya yang dipakai', () {
      expect(tiket().namaTampil, 'budi');
      expect(tiket(nama: 'Budi Santoso').namaTampil, 'Budi Santoso');
    });
  });

  group('siapa bicara dengan siapa', () {
    // Yang mengadu berhak tahu sedang bicara dengan siapa — dan yang
    // menjawab jadi ikut bertanggung jawab atas kalimatnya.
    test('balasan admin menyebut nama penjawabnya', () {
      final layar =
          File('lib/screens/support_chat_screen.dart').readAsStringSync();
      expect(layar, contains("'MerchantPOS Admin - \$n'"));
      expect(layar, contains('_labelAdmin(m)'));
    });

    // Keluhan pelanggan dan keluhan merchant menuntut jawaban yang
    // berbeda, dan menyebut nama merchantnya membuat yang menjawab tidak
    // perlu bertanya "ini merchant mana?" sebagai balasan pertama.
    test('pelapor pelanggan dan merchant dibedakan di sisi admin', () {
      expect(tiket().asalTampil(null), 'Customer');
      final m = SupportTicket.fromMap({
        'id': 't2',
        'reporter_email': 'owner@resto.com',
        'subject': 'x',
        'status': 'open',
        'created_at': '2026-08-22T01:00:00Z',
        'reporter_kind': 'merchant',
        'resto_id': 'r1',
      });
      expect(m.asalTampil('MerchantPos Resto'), 'Merchant · MerchantPos Resto');
      // Namanya gagal dimuat bukan alasan menyembunyikan asalnya.
      expect(m.asalTampil(null), 'Merchant');
    });

    test('asalnya tampil di daftar maupun di percakapannya', () {
      final daftar =
          File('lib/screens/support_admin_screen.dart').readAsStringSync();
      expect(daftar, contains('asalTampil('));
      final chat =
          File('lib/screens/support_chat_screen.dart').readAsStringSync();
      expect(chat, contains('t.asalTampil(_namaMerchant)'));
    });
  });

  group('kirim sekali, bukan dua kali', () {
    // `onPressed: _menyimpan ? null : _kirim` baru berlaku setelah
    // layarnya digambar ulang. Dua ketukan cepat sama-sama masuk lebih
    // dulu, dan yang terkirim dua pengaduan — masing-masing membawa
    // salinan fotonya sendiri. Persis yang terjadi.
    test('formulir pengaduan menjaganya sendiri, bukan lewat tombolnya', () {
      final isi =
          File('lib/screens/support_new_ticket_screen.dart').readAsStringSync();
      final fungsi = isi.substring(isi.indexOf('Future<void> _kirim()'));
      expect(fungsi.substring(0, fungsi.indexOf('setState(()')),
          contains('if (_menyimpan) return;'));
    });

    test('kolom balasan juga', () {
      final isi =
          File('lib/screens/support_chat_screen.dart').readAsStringSync();
      final fungsi = isi.substring(isi.indexOf('Future<void> _kirim()'));
      expect(fungsi.substring(0, fungsi.indexOf('setState(()')),
          contains('if (_mengirim) return;'));
    });
  });

  group('urutan daftar', () {
    // Daftar milik sendiri isinya beberapa baris, dan yang membukanya
    // biasanya mencari yang barusan dia kirim. Daftar KaataGo Admin
    // kebalikannya: yang dicari memang yang paling baru menuntut jawaban.
    test('pengaduan sendiri urut menaik, yang terbaru di bawah', () {
      final repo = File('lib/db/support_repository.dart').readAsStringSync();
      final fungsi = repo.substring(repo.indexOf('milikSaya()'));
      expect(fungsi.substring(0, fungsi.indexOf('}')),
          contains("order('created_at', ascending: true)"));
    });

    test('daftar KaataGo Admin tetap yang terbaru di atas', () {
      final repo = File('lib/db/support_repository.dart').readAsStringSync();
      expect(repo, contains('return wb.compareTo(wa);'));
    });
  });

  group('sapaan otomatis', () {
    final sql = File('supabase/support_auto_reply.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('support_auto_reply.sql'));
    });

    test('disapa begitu tiketnya dibuka', () {
      final fn = sql.substring(sql.indexOf('function open_support_ticket'));
      expect(fn, contains('mohon bersabar KaataGo Admin akan meresponse'));
      expect(fn, contains('terimakasih sudah berkenan menunggu'));
    });

    test('menyebut namanya, dan jatuh ke bagian depan email kalau kosong', () {
      expect(sql, contains("split_part(v_email, '@', 1)"));
      expect(sql, contains("'Halo ' || v_nama"));
    });

    test('chat disebut chat, pengaduan disebut pengaduan', () {
      expect(sql, contains("then 'chat'"));
      expect(sql, contains("else 'pengaduan'"));
    });

    // Judulnya harus sama persis dengan yang dipakai aplikasi. Kalau
    // berpisah, chat bebas akan disapa sebagai "pengaduan".
    test('judul chat bebasnya sama dengan yang dikenal aplikasi', () {
      final model =
          File('lib/models/support_ticket.dart').readAsStringSync();
      final kode = RegExp(r"kSubjekChatUmum = '([^']+)'").firstMatch(model);
      expect(kode, isNotNull);
      expect(sql, contains("= '${kode!.group(1)}'"));
    });

    // Orang yang baru menekan kirim sedang menatap layarnya; membunyikan
    // HP-nya detik itu juga bukan kabar, cuma kebisingan.
    test('sapaannya tidak ikut dikabarkan', () {
      final fn = sql.substring(sql.indexOf('function queue_push_support'));
      expect(fn, contains("if new.sender_email = 'system:greeting' then"));
      expect(fn.substring(fn.indexOf("'system:greeting'")),
          contains('return new;'));
    });

    // Dua pertanyaan yang berbeda tidak bisa dijawab satu kolom.
    test('kapan tiap pihak bicara dicatat terpisah', () {
      expect(sql, contains('add column if not exists last_reporter_at'));
      expect(sql, contains('add column if not exists last_admin_at'));
      final trg = sql.substring(sql.indexOf('function touch_support_ticket'));
      expect(trg, contains('last_reporter_at = case'));
      expect(trg, contains('last_admin_at = case'));
    });

    test('baris lama diisi dari percakapannya sendiri', () {
      expect(sql, contains('update support_tickets t'));
      expect(sql, contains('select max(m.created_at) from support_messages m'));
    });
  });

  group('chat bukan pengaduan', () {
    final sql = File('supabase/support_chat_rules.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('support_chat_rules.sql'));
    });

    test('dikenali dari judulnya, sama dengan yang dipakai aplikasi', () {
      final t = SupportTicket.fromMap({
        'id': 'c1',
        'reporter_email': 'budi@toko.com',
        'subject': kSubjekChatUmum,
        'status': 'open',
        'created_at': '2026-08-24T01:00:00Z',
      });
      expect(t.chatBebas, isTrue);
      expect(tiket().chatBebas, isFalse);
      expect(sql, contains("subject <> '$kSubjekChatUmum'"));
    });

    // Menutup obrolan yang memang sudah selesai dengan sendirinya cuma
    // memaksa orangnya membuka percakapan baru untuk bertanya lagi.
    test('tidak pernah ditutup sendiri', () {
      final fn = sql.substring(sql.indexOf('function close_idle_support_tickets'));
      expect(fn, contains("subject <> 'Chat dengan KaataGo Admin'"));
    });

    test('tanpa tahapan di layar percakapannya', () {
      final layar =
          File('lib/screens/support_chat_screen.dart').readAsStringSync();
      expect(layar, contains('widget.sebagaiAdmin && !t.chatBebas'));
      expect(layar, contains('if (t != null && !t.chatBebas) _KepalaStatus'));
      expect(layar, contains('terbuka && !t.chatBebas'));
    });

    test('dipisah jadi tab sendiri di Customer Service', () {
      final layar =
          File('lib/screens/support_admin_screen.dart').readAsStringSync();
      expect(layar, contains("Tab(text: 'Pengaduan"));
      expect(layar, contains("Tab(text: 'Chat"));
      expect(layar, contains('_daftar(chat: chat)'));
    });

    test('tidak masuk daftar Pengaduan Saya', () {
      final fab = File('lib/widgets/support_fab.dart').readAsStringSync();
      expect(fab, contains('for (final x in t) if (!x.chatBebas) x'));
      expect(fab, contains('for (final t in _tiket) if (!t.chatBebas) t'));
    });
  });

  group('tiket kembar', () {
    final sql = File('supabase/support_chat_rules.sql').readAsStringSync();

    // Penjaga yang hanya ada di aplikasi bukan penjaga: HP yang belum
    // diperbarui, permintaan yang diulang jaringan, atau proses yang
    // mati lalu dicoba lagi semuanya lolos begitu saja.
    test('dijaga basis data, bukan cuma tombolnya', () {
      final fn = sql.substring(sql.indexOf('function open_support_ticket'));
      expect(fn, contains("now() - interval '10 seconds'"));
      expect(fn, contains('return v_row;'));
    });

    // Menghapus percakapan yang sudah dijawab jauh lebih merugikan
    // daripada menyisakan satu baris kembar.
    test('pembersihannya tidak menyentuh yang sudah dibalas manusia', () {
      final bersih = sql.substring(sql.indexOf('with kembar as'));
      expect(bersih, contains("m.sender_email <> 'system:greeting'"));
      expect(bersih, contains('m.from_admin = true'));
      expect(bersih, contains('urutan > 1'));
    });
  });

  group('pesan kembar', () {
    final sql = File('supabase/support_pesan_kembar.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('support_pesan_kembar.sql'));
    });

    // Bukan lagi bergantung pada urutan pemeriksaan di aplikasi maupun
    // di fungsi. Basis data yang menolak barisnya, dan penolakan itu
    // berlaku untuk semua jalan masuk sekaligus.
    test('ditolak indeks unik, bukan cuma diperiksa fungsi', () {
      expect(sql, contains('create unique index if not exists '
          'support_messages_tanpa_kembar'));
      expect(sql, contains('md5(body)'));
    });

    // Postgres menolak mengindeks date_trunc atas timestamptz apa
    // adanya, karena hasilnya bergantung zona waktu sesi.
    test('ekspresi waktunya immutable', () {
      expect(sql, contains("timezone('UTC', created_at)"));
    });

    test('sapaan paling banyak satu per percakapan', () {
      expect(sql, contains('support_messages_satu_sapaan'));
      expect(sql, contains("where sender_email = 'system:greeting'"));
    });

    // Orang yang mengirim "iya" dua kali berjarak beberapa detik memang
    // mengirimnya dua kali. Menghapus yang kedua berarti menghapus
    // ucapan yang benar-benar diucapkan.
    test('batas kembarnya satu detik, bukan lebih', () {
      expect(sql, contains("date_trunc('second'"));
      expect(sql, isNot(contains("date_trunc('minute'")));
    });
  });

  group('notifikasi saat aplikasi terbuka', () {
    final push = File('lib/services/push_service.dart').readAsStringSync();

    // Android tidak pernah menampilkan sendiri notifikasi yang tiba saat
    // aplikasinya di depan. Pesanan tidak apa-apa — aliran realtimenya
    // sudah membunyikan. Percakapan support tidak punya itu: alirannya
    // hanya hidup selama layar percakapan ITU terbuka.
    test('pesan support ikut ditampilkan sendiri', () {
      final daftar = push.substring(push.indexOf('_foregroundEvents = {'));
      expect(daftar.substring(0, daftar.indexOf('};')),
          contains("'support_message'"));
    });

    // Membunyikannya lagi cuma mengagetkan orang yang sedang membacanya.
    test('kecuali untuk percakapan yang sedang dibuka', () {
      expect(push, contains('tiketSupportTerbuka'));
      expect(push,
          contains("message.data['ticket_id'] == tiketSupportTerbuka"));
    });

    test('penandanya dilepas saat layarnya ditutup', () {
      final layar =
          File('lib/screens/support_chat_screen.dart').readAsStringSync();
      expect(layar,
          contains('PushService.tiketSupportTerbuka = widget.ticketId;'));
      final buang = layar.substring(layar.indexOf('void dispose()'));
      expect(buang.substring(0, buang.indexOf('super.dispose')),
          contains('tiketSupportTerbuka = null'));
    });
  });

  group('baris kembar di aliran', () {
    final repo = File('lib/db/support_repository.dart').readAsStringSync();

    // Aliran Supabase berlangganan lebih dulu, baru mengambil isi
    // awalnya. Baris yang lahir tepat di antara keduanya datang dua
    // kali — sekali sebagai kejadian realtime, sekali lagi di dalam isi
    // awal. Itu persis keadaan saat pengaduan baru dibuat, dan itulah
    // sebabnya dobelnya hilang sendiri begitu layarnya dibuka ulang.
    test('pesan disaring berdasarkan idnya', () {
      expect(repo, contains('static List<SupportMessage> _tanpaKembar('));
      expect(repo, contains('unik[m.id] = m;'));
      expect(repo, contains('.map(_tanpaKembar)'));
    });

    test('daftar tiket disaring dengan alasan yang sama', () {
      final fn = repo.substring(repo.indexOf('Stream<List<SupportTicket>> semua()'));
      expect(fn.substring(0, fn.indexOf('Stream<List<SupportMessage>>')),
          contains('unik[t.id] = t;'));
    });

    // Disaring di repositori, bukan di layar: dua layar memakai aliran
    // yang sama, dan yang kedua akan tertinggal saat yang pertama
    // diperbaiki.
    test('disaring di satu tempat, bukan di tiap layar', () {
      final chat =
          File('lib/screens/support_chat_screen.dart').readAsStringSync();
      expect(chat, isNot(contains('unik[')));
    });
  });

  group('penanda per jenis', () {
    final fab = File('lib/widgets/support_fab.dart').readAsStringSync();

    // Satu angka di tombol mengambang cuma memberi tahu "ada sesuatu" —
    // yang membukanya masih harus menebak yang mana.
    test('chat dan pengaduan punya penandanya masing-masing', () {
      expect(fab, contains('belumDibacaChat'));
      expect(fab, contains('belumDibacaPengaduan'));
      expect('_Penanda(jumlah:'.allMatches(fab).length, greaterThanOrEqualTo(2));
    });

    test('penanda kosong tidak digambar', () {
      final w = fab.substring(fab.indexOf('class _Penanda'));
      expect(w, contains('if (jumlah <= 0) return const SizedBox.shrink();'));
    });
  });

  group('judul notifikasi', () {
    final sql = File('supabase/support_push_wording.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('support_push_wording.sql'));
    });

    // Yang membacanya di layar kunci tidak punya cara tahu itu
    // sebenarnya pertanyaan biasa — dan yang mengirimnya merasa dituduh
    // mengadu padahal cuma bertanya.
    test('chat tidak pernah disebut pengaduan', () {
      expect(sql, contains("when v_chat then 'Chat dari ' || v_nama"));
      expect(sql, contains("when v_chat then 'Balasan KaataGo Admin'"));
    });

    test('pengaduan tetap disebut pengaduan', () {
      expect(sql, contains("else 'Pengaduan dari ' || v_nama"));
    });

    test('sapaannya tetap tidak dikabarkan', () {
      expect(sql, contains("if new.sender_email = 'system:greeting' then"));
    });
  });

  group('SQL-nya', () {
    final sql = File('supabase/support_tickets.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('support_tickets.sql'));
    });

    test('empat status, sama dengan yang dikenal aplikasi', () {
      for (final s in SupportStatus.values) {
        expect(sql, contains("'${kSupportStatusDb[s]}'"), reason: '$s');
      }
    });

    // Keluhan sering berisi hal yang tidak ingin dibaca seruangan —
    // termasuk keluhan tentang orang di ruangan itu.
    test('pelapor melihat tiketnya sendiri, bukan tiket rekannya', () {
      expect(sql, contains("is_super_admin() or reporter_email = auth.jwt() ->> 'email'"));
      expect(sql, isNot(contains('is_resto_employee')));
    });

    // Tiket tertutup yang masih bisa ditulisi adalah tiket yang tidak
    // pernah benar-benar selesai.
    test('tiket tertutup tidak bisa dibalas', () {
      final policy = sql.substring(sql.indexOf('"support_messages: write"'));
      expect(policy.substring(0, policy.indexOf(');')),
          contains("t.status <> 'closed'"));
    });

    test('status hanya bisa diubah lewat fungsinya', () {
      expect(sql, isNot(contains('for update')));
      expect(sql, contains('create or replace function set_support_status'));
    });

    // Yang paling tahu keluhannya sudah selesai adalah orang yang
    // mengeluh — tapi hanya sampai di situ haknya.
    test('pelapor hanya boleh menutup, tidak mengubah status lain', () {
      expect(sql, contains("if not v_admin and p_status <> 'closed' then"));
    });

    group('penutupan otomatis', () {
      final fn =
          sql.substring(sql.indexOf('function close_idle_support_tickets'));

      test('hanya yang sedang menunggu jawaban pelapor', () {
        expect(fn, contains("status = 'confirm_customer'"));
      });

      // Tiket yang pesan terakhirnya dari pelapor berarti bolanya ada di
      // KaataGo. Menutupnya karena "tidak ada jawaban" akan menghukum
      // orang yang justru sudah menjawab.
      test('hanya kalau pesan terakhirnya dari admin', () {
        expect(fn, contains('last_message_from_admin = true'));
      });

      test('menunggu 24 jam, dan ditandai ditutup sendiri', () {
        expect(fn, contains("interval '24 hours'"));
        expect(fn, contains('auto_closed = true'));
      });

      test('dijadwalkan berjalan sendiri', () {
        expect(sql, contains("cron.schedule('close-idle-support'"));
      });
    });

    // Tanpa ini, tiket yang baru saja dijawab pelapor tetap berstatus
    // menunggu — lalu ditutup penjadwal tepat setelah orangnya membalas.
    test('balasan pelapor membangunkan tiket yang sedang menunggu', () {
      final trg = sql.substring(sql.indexOf('function touch_support_ticket'));
      expect(trg, contains("when status = 'confirm_customer' and new.from_admin = false"));
      expect(trg, contains("then 'on_progress'"));
    });

    test('percakapannya disiarkan realtime, dengan penangkap galat', () {
      expect(sql, contains('add table support_messages'));
      expect(sql, contains('exception when duplicate_object then null;'));
    });
  });

  group('notifikasi', () {
    final sql = File('supabase/support_push.sql').readAsStringSync();
    final fungsi =
        File('supabase/functions/send-push/index.ts').readAsStringSync();
    final router =
        File('lib/services/notification_router.dart').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      expect(File('scripts/gabung_sql.sh').readAsStringSync(),
          contains('support_push.sql'));
    });

    test('balasan admin dikabarkan ke pelapornya saja', () {
      final cabang = sql.substring(sql.indexOf('if new.from_admin then'),
          sql.indexOf('  else'));
      expect(cabang, contains("'audience', 'email'"));
      expect(cabang, contains('t.reporter_email'));
    });

    // Baris token hanya punya peran kalau perangkatnya mendaftar setelah
    // orangnya masuk sebagai KaataGo Admin. Menyasar lewat peran gagal
    // dengan "tidak ada perangkat terdaftar" — persis yang terjadi.
    // Emailnya jauh lebih tahan: ia ditulis di setiap pendaftaran token.
    test('pengaduan baru disasar lewat email admin, bukan perannya', () {
      final cabang = sql.substring(sql.indexOf('  else'));
      expect(cabang, contains("where e.role = 'super_admin'"));
      expect(cabang, contains("'audience', 'email'"));
      expect(cabang, isNot(contains("'audience', 'role'")));
    });

    // KaataGo Admin tidak terikat merchant mana pun; menyertakan
    // resto_id akan membuat kabarnya tersaring habis.
    test('kabarnya tidak dibatasi merchant', () {
      final cabang = sql.substring(sql.indexOf('  else'));
      expect(cabang,
          contains('insert into push_outbox (resto_id, event, payload) values (\n        null,'));
    });

    test('yang sudah tidak aktif tidak ikut dikabari', () {
      expect(sql, contains('coalesce(e.active, true) = true'));
    });

    // Perubahan status ditulis sebagai pesan sistem, jadi ia ikut lewat
    // pemicu yang sama. Pemicu terpisah di tabel tiket berarti dua
    // tempat yang harus sepakat soal siapa yang dikabari.
    test('satu pemicu untuk pesan maupun perubahan status', () {
      expect(sql, contains('after insert on support_messages'));
      expect(sql, isNot(contains('on support_tickets')));
    });

    // Sebelumnya hanya `event` yang dikirim — dan itu membuat notifikasi
    // yang butuh tujuan tertentu tidak pernah bisa membukanya.
    test('muatannya membawa penunjuk tujuan, bukan cuma nama kejadian', () {
      expect(fungsi, contains('resto_id: String(row.payload.resto_id)'));
      expect(fungsi, contains('ticket_id: String(row.payload.ticket_id)'));
    });

    // Dua pengaduan berbeda adalah dua percakapan berbeda; yang kedua
    // tidak boleh menghapus balasan yang pertama sebelum sempat dibaca.
    test('notifikasi tiap tiket tidak saling menimpa', () {
      expect(fungsi, contains(r'`${row.event}:${row.payload.ticket_id}`'));
    });

    test('diketuk membuka percakapannya, bukan sekadar aplikasinya', () {
      expect(router, contains("if (event == 'support_message')"));
      expect(router, contains("data?['ticket_id']"));
      // Sisi mana yang membuka menentukan apa yang boleh ditekan.
      expect(router, contains('sebagaiAdmin: auth.isSuperAdmin'));
    });
  });

  group('pintunya', () {
    test('tombol mengambang ada di beranda pelanggan dan pegawai', () {
      for (final f in [
        'customer_home_screen',
        'kasir_home_screen',
        'admin_home_screen',
        'owner_home_screen',
        'finance_home_screen',
      ]) {
        final isi = File('lib/screens/$f.dart').readAsStringSync();
        expect(isi, contains('SupportFab()'), reason: f);
      }
    });

    test('KaataGo Admin punya menu Customer Service', () {
      final isi =
          File('lib/screens/super_admin_home_screen.dart').readAsStringSync();
      expect(isi, contains("title: 'Customer Service'"));
      expect(isi, contains('SupportAdminScreen()'));
      // Penanda merahnya ikut naik ke beranda — tanpa itu, satu-satunya
      // cara tahu ada yang menunggu adalah membuka layarnya.
      expect(isi, contains('milikSemuaBelumDibaca()'));
    });

    // Yang berlabel selebar setengah layar, dan di beranda yang penuh ia
    // duduk tepat di atas tombol menu terakhir.
    test('tombolnya bulat kecil, bukan berlabel', () {
      final isi = File('lib/widgets/support_fab.dart').readAsStringSync();
      expect(isi, isNot(contains('FloatingActionButton.extended')));
      expect(isi, contains('mini: true'));
      expect(isi, contains("tooltip: 'MerchantPOS Support'"));
    });

    // Tanpa ruang di bawah, tombolnya menutupi menu terakhir — dan yang
    // tertutup justru menu yang paling jarang digulir sampai ke sana.
    test('daftar menunya menyisakan ruang untuk tombolnya', () {
      final layout = File('lib/widgets/responsive.dart').readAsStringSync();
      expect(layout, contains('EdgeInsets.fromLTRB(20, 20, 20, kFabSafeBottom)'));
      final owner =
          File('lib/screens/owner_home_screen.dart').readAsStringSync();
      expect(owner, contains('kFabSafeBottom'));
    });

    // Chat yang melahirkan tiket baru tiap dibuka akan mengubur
    // pengaduan sungguhan di bawah puluhan percakapan berisi satu
    // sapaan.
    test('chat bebas memakai percakapan yang masih terbuka', () {
      final isi = File('lib/widgets/support_fab.dart').readAsStringSync();
      expect(isi, contains("if (pilihan == 'chat')"));
      expect(isi, contains('chatUmumTerbuka()'));
      final model =
          File('lib/models/support_ticket.dart').readAsStringSync();
      expect(model,
          contains("const kSubjekChatUmum = 'Chat dengan KaataGo Admin';"));
      final repo = File('lib/db/support_repository.dart').readAsStringSync();
      expect(repo, contains("neq('status', 'closed')"));
    });

    // Percakapan bebas bukan pengaduan atas satu hal tertentu, jadi
    // memintanya diberi judul cuma menahan orang di depan kolom kosong.
    test('chat bebas tidak meminta judul', () {
      final isi =
          File('lib/screens/support_new_ticket_screen.dart').readAsStringSync();
      expect(isi, contains('if (widget.subjekTetap == null)'));
      expect(isi, contains('subject: widget.subjekTetap ?? _judul.text'));
    });

    // Pengaduan tanpa akun tidak punya tempat untuk dibalas, dan
    // pengadu yang tidak pernah menerima jawabannya akan mengira
    // KaataGo mendiamkannya.
    test('tidak ditawarkan kepada yang belum masuk', () {
      final isi = File('lib/widgets/support_fab.dart').readAsStringSync();
      expect(isi, contains('if (!context.watch<AuthProvider>().isLoggedIn)'));
    });
  });
}
