import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/support_ticket.dart';

class SupportRepository {
  final _client = Supabase.instance.client;

  String? get _email => _client.auth.currentUser?.email;

  /// Tiket milik orang yang sedang masuk, yang paling lama di atas.
  ///
  /// Urutannya menaik, seperti percakapan: pengaduan terbaru ada di
  /// bawah. Daftar milik sendiri isinya beberapa baris saja, dan yang
  /// membukanya biasanya mencari yang barusan dia kirim — bukan
  /// menelusuri arsip. Daftar MerchantPOS Admin urutannya kebalikannya,
  /// karena di sana yang dicari memang yang paling baru menuntut
  /// jawaban.
  Future<List<SupportTicket>> milikSaya() async {
    final email = _email;
    if (email == null) return const [];
    final rows = await _client
        .from('support_tickets')
        .select()
        .eq('reporter_email', email)
        .order('created_at', ascending: true)
        .limit(50);
    return rows.map((r) => SupportTicket.fromMap(r)).toList();
  }

  /// Percakapan bebas yang masih terbuka, kalau ada.
  Future<SupportTicket?> chatUmumTerbuka() async {
    final email = _email;
    if (email == null) return null;
    final rows = await _client
        .from('support_tickets')
        .select()
        .eq('reporter_email', email)
        .eq('subject', kSubjekChatUmum)
        .neq('status', 'closed')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : SupportTicket.fromMap(rows.first);
  }

  /// Seluruh tiket — hanya terbaca MerchantPOS Admin, ditegakkan RLS.
  ///
  /// Yang terbuka lebih dulu, lalu yang pesannya paling baru. Daftar yang
  /// diurutkan waktu saja akan menenggelamkan tiket yang belum dijawab di
  /// bawah tiket yang sudah selesai tapi ramai.
  Stream<List<SupportTicket>> semua() {
    return _client
        .from('support_tickets')
        .stream(primaryKey: ['id'])
        .order('last_message_at', ascending: false)
        .map((rows) {
          // Alasannya sama dengan _tanpaKembar: baris yang lahir tepat
          // saat langganannya dibuka bisa datang dua kali.
          final unik = <String, SupportTicket>{};
          for (final r in rows) {
            final t = SupportTicket.fromMap(r);
            unik[t.id] = t;
          }
          final list = unik.values.toList();
          list.sort((a, b) {
            if (a.terbuka != b.terbuka) return a.terbuka ? -1 : 1;
            final wa = a.lastMessageAt ?? a.createdAt;
            final wb = b.lastMessageAt ?? b.createdAt;
            return wb.compareTo(wa);
          });
          return list;
        });
  }

  Stream<List<SupportMessage>> pesan(String ticketId) {
    return _client
        .from('support_messages')
        .stream(primaryKey: ['id'])
        .eq('ticket_id', ticketId)
        // `ascending` WAJIB disebut.
        //
        // Pada aliran realtime, `order()` bawaannya MENURUN — kebalikan
        // dari `select().order()` yang bawaannya menaik. Menulis
        // `.order('created_at')` saja membuat pesan terbaru berada di
        // paling atas, dan percakapannya terbaca terbalik.
        .order('created_at', ascending: true)
        .map(_tanpaKembar);
  }

  /// Membuang baris berulang, lalu mengurutkannya sendiri.
  ///
  /// Aliran Supabase berlangganan lebih dulu, baru mengambil isi
  /// awalnya. Baris yang lahir tepat di antara keduanya datang dua
  /// kali — sekali sebagai kejadian realtime, sekali lagi di dalam isi
  /// awal — dan daftarnya menampilkan keduanya.
  ///
  /// Itu persis keadaan saat pengaduan baru dibuat: pesannya tersimpan
  /// sepersekian detik sebelum layar percakapannya berlangganan. Yang
  /// terlihat: pesan pertama dan sapaannya muncul dobel, lalu normal
  /// sendiri begitu layarnya dibuka ulang — karena pada pembukaan kedua
  /// tidak ada lagi baris yang lahir di sela itu.
  ///
  /// Disaring di sini, bukan di layar: dua layar memakai aliran yang
  /// sama, dan yang kedua akan tertinggal saat yang pertama diperbaiki.
  static List<SupportMessage> _tanpaKembar(List<Map<String, dynamic>> rows) {
    final unik = <String, SupportMessage>{};
    for (final r in rows) {
      final m = SupportMessage.fromMap(r);
      unik[m.id] = m;
    }
    return unik.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Satu tiket, sekali ambil — dipakai layar percakapan untuk mengetahui
  /// statusnya tanpa menunggu aliran daftarnya.
  Future<SupportTicket?> satu(String id) async {
    final rows =
        await _client.from('support_tickets').select().eq('id', id).limit(1);
    return rows.isEmpty ? null : SupportTicket.fromMap(rows.first);
  }

  Stream<SupportTicket?> pantau(String id) {
    return _client
        .from('support_tickets')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) =>
            rows.isEmpty ? null : SupportTicket.fromMap(rows.first));
  }

  Future<SupportTicket> buat({
    required String subject,
    required String body,
    required bool dariMerchant,
    String? restoId,
    String? nama,
    String? photoBase64,
  }) async {
    final row = await _client.rpc('open_support_ticket', params: {
      'p_subject': subject,
      'p_body': body,
      'p_kind': dariMerchant ? 'merchant' : 'customer',
      'p_resto_id': restoId,
      'p_name': nama,
      'p_photo': photoBase64,
    });
    return SupportTicket.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Mengirim pesan. Ditolak basis data kalau tiketnya sudah ditutup —
  /// tiket tertutup yang masih bisa ditulisi adalah tiket yang tidak
  /// pernah benar-benar selesai.
  Future<void> kirim({
    required String ticketId,
    required String body,
    required bool sebagaiAdmin,
    String? nama,
    String? photoBase64,
  }) async {
    final email = _email;
    if (email == null) return;
    await _client.from('support_messages').insert({
      'ticket_id': ticketId,
      'sender_email': email,
      'sender_name': nama,
      'from_admin': sebagaiAdmin,
      'body': body.trim(),
      'photo_base64': photoBase64,
    });
  }

  Future<SupportTicket> ubahStatus(String id, SupportStatus status) async {
    final row = await _client.rpc('set_support_status', params: {
      'p_id': id,
      'p_status': kSupportStatusDb[status],
    });
    return SupportTicket.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<void> tandaiDibaca(String id) async {
    await _client.rpc('mark_support_read', params: {'p_id': id});
  }

  /// Berapa tiket yang menunggu dibaca MerchantPOS Admin.
  ///
  /// Sekali ambil, untuk penanda merah di beranda. Aliran realtime cuma
  /// untuk layar yang sedang dibuka — penanda di beranda tidak perlu
  /// bergerak dalam hitungan detik, dan langganan yang hidup di beranda
  /// akan tetap hidup di seluruh layar di bawahnya.
  Future<int> milikSemuaBelumDibaca() async {
    final rows = await _client
        .from('support_tickets')
        .select('last_message_at, last_message_from_admin, admin_read_at, '
            'last_reporter_at, last_admin_at, '
            'status, reporter_email, subject, id, created_at')
        .neq('status', 'closed');
    final tiket = rows.map((r) => SupportTicket.fromMap(r)).toList();
    return belumDibaca(tiket, sebagaiAdmin: true);
  }

  /// Berapa tiket yang punya pesan belum dibaca untuk pihak ini.
  ///
  /// Dipakai penanda di tombol mengambang. Dihitung dari daftar tiketnya
  /// sendiri, bukan dari permintaan terpisah — jumlah yang datang dari
  /// dua sumber berbeda akan berbeda cepat atau lambat.
  static int belumDibaca(List<SupportTicket> tiket,
          {required bool sebagaiAdmin}) =>
      tiket.where((t) => t.belumDibaca(sebagaiAdmin: sebagaiAdmin)).length;
}
