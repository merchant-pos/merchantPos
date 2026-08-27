import 'package:flutter/material.dart';

/// Judul percakapan bebas dengan Merchant-POS Admin.
///
/// Bukan pengaduan — sekadar bertanya. Dibedakan lewat judulnya, bukan
/// lewat kolom baru: satu kolom lagi berarti satu migrasi lagi, dan yang
/// dibedakannya cuma kalimat di kepala percakapan.
///
/// Ditaruh di berkas model supaya lapisan mana pun bisa membacanya
/// tanpa memanggil repositori.
/// Judul tiket yang menandai percakapan bebas, bukan pengaduan.
///
/// Dicocokkan apa adanya oleh pemicu di Postgres untuk memisahkan chat
/// dari pengaduan — chat tidak punya status dan tidak ikut ditutup
/// sendiri setelah 24 jam. Mengubah teks ini berarti mengubah
/// pemicunya juga, berbarengan; kalau tidak, chat berikutnya tercatat
/// sebagai pengaduan tanpa satu pun galat yang menyebutkannya.
const kSubjekChatUmum = 'Chat dengan Merchant-POS Admin';

/// Tahap sebuah pengaduan.
///
/// [confirmCustomer] bukan sekadar "menunggu" — ia satu-satunya status
/// yang bisa menutup tiketnya sendiri kalau didiamkan 24 jam. Karena itu
/// ia dinyatakan sebagai status tersendiri, bukan disimpulkan dari siapa
/// yang mengirim pesan terakhir.
enum SupportStatus { open, onProgress, confirmCustomer, closed }

const kSupportStatusDb = {
  SupportStatus.open: 'open',
  SupportStatus.onProgress: 'on_progress',
  SupportStatus.confirmCustomer: 'confirm_customer',
  SupportStatus.closed: 'closed',
};

const kSupportStatusLabel = {
  SupportStatus.open: 'Open',
  SupportStatus.onProgress: 'On Progress',
  SupportStatus.confirmCustomer: 'Confirm Customer',
  SupportStatus.closed: 'Close',
};

const kSupportStatusWarna = {
  SupportStatus.open: Color(0xFFDC2626),
  SupportStatus.onProgress: Color(0xFFF59E0B),
  SupportStatus.confirmCustomer: Color(0xFF6366F1),
  SupportStatus.closed: Color(0xFF10B981),
};

SupportStatus supportStatusDari(String? kode) {
  for (final e in kSupportStatusDb.entries) {
    if (e.value == kode) return e.key;
  }
  return SupportStatus.open;
}

class SupportTicket {
  final String id;
  final String reporterEmail;
  final String? reporterName;
  final bool dariMerchant;
  final String? restoId;
  final String subject;
  final SupportStatus status;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final String? lastMessageBody;
  final bool lastMessageFromAdmin;
  final DateTime? reporterReadAt;
  final DateTime? adminReadAt;

  /// Kapan masing-masing pihak terakhir bicara.
  ///
  /// Dua kolom, bukan satu penanda "siapa yang terakhir". Sapaan
  /// otomatis membuat pesan terakhir jadi "dari admin" pada tiket yang
  /// belum dibaca siapa pun — dan penanda tunggal langsung menyatakan
  /// tiket itu beres.
  final DateTime? lastReporterAt;
  final DateTime? lastAdminAt;

  /// Ditutup penjadwal karena didiamkan, bukan oleh orang. Tiket yang
  /// mati karena tidak ditanggapi bukan tiket yang selesai.
  final bool autoClosed;

  SupportTicket({
    required this.id,
    required this.reporterEmail,
    this.reporterName,
    this.dariMerchant = false,
    this.restoId,
    required this.subject,
    required this.status,
    required this.createdAt,
    this.lastMessageAt,
    this.lastMessageBody,
    this.lastMessageFromAdmin = false,
    this.reporterReadAt,
    this.adminReadAt,
    this.lastReporterAt,
    this.lastAdminAt,
    this.autoClosed = false,
  });

  bool get terbuka => status != SupportStatus.closed;

  /// Percakapan bebas, bukan pengaduan.
  ///
  /// Tidak punya tahapan dan tidak pernah "selesai" — ia obrolan biasa.
  /// Memberinya status Open dan Confirm Customer membuat orang yang
  /// cuma bertanya merasa sedang mengurus perkara.
  bool get chatBebas => subject == kSubjekChatUmum;

  /// Dari siapa pengaduan ini, dari sudut pandang Merchant-POS Admin.
  ///
  /// Yang menjawab perlu tahu ini sebelum membaca kalimat pertamanya:
  /// keluhan pelanggan dan keluhan merchant menuntut jawaban yang
  /// berbeda, dan menyebut nama merchantnya membuat yang menjawab tidak
  /// perlu bertanya "ini merchant mana?" sebagai balasan pertama.
  String asalTampil(String? namaMerchant) {
    if (!dariMerchant) return 'Customer';
    final n = (namaMerchant ?? '').trim();
    return n.isEmpty ? 'Merchant' : 'Merchant · $n';
  }

  String get namaTampil {
    final n = reporterName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return reporterEmail.split('@').first;
  }

  /// Ada pesan baru untuk pihak ini.
  ///
  /// Dihitung dari satu stempel waktu, bukan dari bendera per pesan:
  /// satu stempel waktu tidak bisa berbeda pendapat dengan dirinya
  /// sendiri, dan pesan yang terlewat tandanya tidak akan pernah
  /// ketahuan.
  bool belumDibaca({required bool sebagaiAdmin}) {
    // Yang dibandingkan kapan LAWAN BICARA terakhir bicara — bukan
    // siapa yang paling terakhir bicara di tiket ini. Sapaan otomatis
    // adalah pesan dari admin, dan pengaduan yang baru disapa mesin
    // tetap pengaduan yang belum dibaca manusia.
    final lawan = sebagaiAdmin ? lastReporterAt : lastAdminAt;
    if (lawan == null) return false;
    final dibaca = sebagaiAdmin ? adminReadAt : reporterReadAt;
    return dibaca == null || lawan.isAfter(dibaca);
  }

  factory SupportTicket.fromMap(Map<String, dynamic> map) => SupportTicket(
        id: map['id'].toString(),
        reporterEmail: map['reporter_email']?.toString() ?? '',
        reporterName: map['reporter_name']?.toString(),
        dariMerchant: map['reporter_kind'] == 'merchant',
        restoId: map['resto_id']?.toString(),
        subject: map['subject']?.toString() ?? '(tanpa judul)',
        status: supportStatusDari(map['status']?.toString()),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        lastMessageAt:
            DateTime.tryParse(map['last_message_at']?.toString() ?? ''),
        lastMessageBody: map['last_message_body']?.toString(),
        lastMessageFromAdmin: map['last_message_from_admin'] == true,
        reporterReadAt:
            DateTime.tryParse(map['reporter_read_at']?.toString() ?? ''),
        adminReadAt: DateTime.tryParse(map['admin_read_at']?.toString() ?? ''),
        lastReporterAt:
            DateTime.tryParse(map['last_reporter_at']?.toString() ?? ''),
        lastAdminAt:
            DateTime.tryParse(map['last_admin_at']?.toString() ?? ''),
        autoClosed: map['auto_closed'] == true,
      );
}

class SupportMessage {
  final String id;
  final String ticketId;
  final String senderEmail;
  final String? senderName;
  final bool fromAdmin;
  final String body;
  final String? photoBase64;
  final bool isSystem;
  final DateTime createdAt;

  SupportMessage({
    required this.id,
    required this.ticketId,
    required this.senderEmail,
    this.senderName,
    required this.fromAdmin,
    required this.body,
    this.photoBase64,
    this.isSystem = false,
    required this.createdAt,
  });

  factory SupportMessage.fromMap(Map<String, dynamic> map) => SupportMessage(
        id: map['id'].toString(),
        ticketId: map['ticket_id'].toString(),
        senderEmail: map['sender_email']?.toString() ?? '',
        senderName: map['sender_name']?.toString(),
        fromAdmin: map['from_admin'] == true,
        body: map['body']?.toString() ?? '',
        photoBase64: map['photo_base64']?.toString(),
        isSystem: map['is_system'] == true,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
