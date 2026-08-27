import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';

class AnnouncementRepository {
  final _client = Supabase.instance.client;

  /// Inbox seseorang: seluruh pengumuman yang belum dia hapus.
  ///
  /// Penghapusan dicatat per orang, bukan dengan membuang pengumumannya —
  /// satu orang membersihkan inbox-nya tidak boleh menghilangkan
  /// pengumuman itu dari orang lain.
  ///
  /// [restoId] menyaring pengumuman milik resto lain. Disaring di sini,
  /// bukan di query, karena penyaringannya berupa "milik semua resto ATAU
  /// milik resto saya" — dan baris untuk semua resto adalah yang
  /// resto_id-nya kosong, yang paling mudah terlewat kalau ditulis
  /// sebagai kondisi SQL.
  Future<List<Announcement>> inboxFor(String email, {String? restoId}) async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .order('created_at', ascending: false);

    final states = await _client
        .from('inbox_states')
        .select()
        .eq('email', email);

    final deleted = <String>{};
    final read = <String>{};
    for (final s in states) {
      final id = s['announcement_id'] as String;
      if (s['deleted_at'] != null) deleted.add(id);
      if (s['read_at'] != null) read.add(id);
    }

    return rows
        .where((r) => !deleted.contains(r['id'] as String))
        .map((r) => Announcement.fromMap(r, read: read.contains(r['id'] as String)))
        .where((a) => a.visibleToEmployee(restoId))
        .toList();
  }

  /// Kotak masuk pelanggan.
  ///
  /// Bedanya dengan [inboxFor] ada dua, dan keduanya lahir dari satu
  /// kenyataan: pelanggan tidak punya "resto sendiri".
  ///
  /// Pertama, jangkauannya. Yang dipakai bukan satu resto, tapi seluruh
  /// resto yang pernah dia pesan — promo dari warung langganannya harus
  /// tetap sampai walau dia sedang membuka menu resto lain. Menyaring
  /// dengan resto yang sedang terbuka berarti promo cuma sampai ke
  /// orang yang sudah berada di sana, yaitu orang yang paling tidak
  /// membutuhkannya.
  ///
  /// Kedua, nama pengirimnya ikut dibawa. "Diskon 20% hari ini" tanpa
  /// nama resto adalah kabar yang tidak bisa dipakai.
  Future<List<Announcement>> customerInbox({
    String? email,
    required Set<String> restoIds,
  }) async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .order('created_at', ascending: false)
        .limit(100);

    // Tamu tidak punya email, jadi tidak punya penanda sudah dibaca.
    // Bukan alasan untuk menyembunyikan pengumumannya — sebagian besar
    // pelanggan resto memang tidak login.
    final deleted = <String>{};
    final read = <String>{};
    if (email != null) {
      final states =
          await _client.from('inbox_states').select().eq('email', email);
      for (final s in states) {
        final id = s['announcement_id'] as String;
        if (s['deleted_at'] != null) deleted.add(id);
        if (s['read_at'] != null) read.add(id);
      }
    }

    final items = rows
        .where((r) => !deleted.contains(r['id'] as String))
        .map((r) =>
            Announcement.fromMap(r, read: read.contains(r['id'] as String)))
        .where((a) => a.visibleToCustomer(restoIds))
        .toList();

    // Nama restonya diambil sekali untuk seluruh daftar, bukan per
    // baris: sepuluh pengumuman dari resto yang sama tidak boleh jadi
    // sepuluh panggilan jaringan.
    final ids = {
      for (final a in items)
        if (a.restoId != null) a.restoId!,
    };
    if (ids.isEmpty) return items;

    try {
      final restos = await _client
          .from('restaurants')
          .select('id, name')
          .inFilter('id', ids.toList());
      final names = {
        for (final r in restos) r['id'] as String: r['name'] as String,
      };
      return [
        for (final a in items)
          a.restoId == null ? a : a.copyWith(restoName: names[a.restoId]),
      ];
    } catch (_) {
      // Nama restonya gagal diambil — pengumumannya tetap ditampilkan.
      return items;
    }
  }

  /// Pengumuman terbaru, tanpa perlu login — dipakai layar tamu untuk
  /// memberi tahu bahwa ada versi yang lebih baru.
  Future<Announcement?> latest() async {
    final rows = await _client
        .from('app_announcements')
        .select()
        .eq('category', 'update')
        .isFilter('resto_id', null)
        .not('version', 'is', null)
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Announcement.fromMap(rows.first);
  }
  Future<void> markRead(String email, String announcementId) async {
    await _client.from('inbox_states').upsert({
      'email': email,
      'announcement_id': announcementId,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'email,announcement_id');
  }

  /// Menandai banyak pesan sekaligus sudah dibaca.
  ///
  /// Ditulis dalam satu perintah, bukan satu per satu: menandai dua
  /// puluh pesan berarti dua puluh perjalanan bolak-balik ke server, dan
  /// yang menekan "tandai semua" justru sedang membereskan tumpukan yang
  /// banyak.
  Future<void> markManyRead(String email, List<String> announcementIds) async {
    if (announcementIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('inbox_states').upsert([
      for (final id in announcementIds)
        {'email': email, 'announcement_id': id, 'read_at': now},
    ], onConflict: 'email,announcement_id');
  }

  Future<void> deleteForUser(String email, List<String> announcementIds) async {
    if (announcementIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('inbox_states').upsert([
      for (final id in announcementIds)
        {'email': email, 'announcement_id': id, 'read_at': now, 'deleted_at': now},
    ], onConflict: 'email,announcement_id');
  }

  /// Menerbitkan pengumuman.
  ///
  /// Pemberitahuan versi hanya boleh dari Super Admin; pengumuman umum
  /// boleh juga dari Admin resto untuk restonya sendiri. Keduanya
  /// ditegakkan RLS, bukan di sini — layar cuma menyembunyikan
  /// tombolnya.
  Future<void> publish({
    required String title,
    required String body,
    required AnnouncementCategory category,
    String? version,
    String? downloadUrl,
    String? restoId,
    String? imageBase64,
    AnnouncementAudience audience = AnnouncementAudience.all,
    required String createdBy,
  }) async {
    await _client.from('app_announcements').insert({
      'title': title,
      'body': body,
      'category': category.dbValue,
      if (version != null) 'version': version,
      if (downloadUrl != null) 'download_url': downloadUrl,
      if (restoId != null) 'resto_id': restoId,
      if (imageBase64 != null) 'image_base64': imageBase64,
      'audience': audience.dbValue,
      'created_by': createdBy,
    });
  }
}
