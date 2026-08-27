/// Keadaan sebuah voucher yang sudah ditebus pelanggan.
enum VoucherClaimStatus {
  /// Sudah ditebus, belum dipakai.
  claimed,

  /// Sudah dipakai membayar.
  used,

  /// Kedaluwarsa tanpa dipakai; dananya sudah kembali ke saldo MerchantPOS.
  expired,
}

const _claimDb = {
  VoucherClaimStatus.claimed: 'claimed',
  VoucherClaimStatus.used: 'used',
  VoucherClaimStatus.expired: 'expired',
};

const kVoucherClaimLabels = {
  VoucherClaimStatus.claimed: 'Siap Dipakai',
  VoucherClaimStatus.used: 'Sudah Dipakai',
  VoucherClaimStatus.expired: 'Hangus',
};

/// Sekumpulan voucher yang diterbitkan sekaligus.
///
/// Super Admin mengalokasikan sejumlah uang lalu memecahnya jadi
/// beberapa voucher bernilai sama — Rp 1.000.000 jadi 10 voucher
/// @Rp 100.000. Kodenya satu untuk seluruh batch, dan sengaja begitu:
/// kodenya diumumkan ke banyak orang sekaligus, dan kode yang berbeda
/// per orang tidak bisa diumumkan.
class Voucher {
  final String id;
  final String code;
  final String name;

  /// Yang dialokasikan, dan dipecah jadi berapa.
  final int totalAmount;
  final int quantity;

  /// Nilai tiap voucher.
  final int amount;

  final DateTime expiresOn;
  final int minPurchase;

  /// Resto tempat voucher ini bisa dipakai. Kosong berarti semua resto.
  final List<String> restoIds;

  final bool active;

  /// Sisa yang tidak pernah ditebus sudah dikembalikan ke saldo.
  final DateTime? settledAt;

  final String? createdBy;
  final DateTime createdAt;

  /// Gambar 16:9 yang ikut tampil di kotak masuk pelanggan.
  final String? bannerBase64;

  /// Hanya untuk yang belum pernah memesan lewat MerchantPOS.
  ///
  /// Voucher promosi paling mahal adalah yang ditebus orang yang memang
  /// sudah pasti memesan. Batasan ini membuat anggarannya jatuh ke
  /// orang yang belum pernah mencoba sama sekali.
  final bool newCustomersOnly;

  /// Sudah ditebus berapa — hanya terisi di layar MerchantPOS Admin.
  ///
  /// Menghitung seluruh penebusan, termasuk yang sudah dipakai maupun
  /// hangus. Inilah yang menentukan kuotanya: jatah yang sudah
  /// diserahkan tidak kembali jadi jatah hanya karena orangnya lupa
  /// memakainya.
  final int claimed;

  /// Yang masih benar-benar menggantung — sudah ditebus, belum dipakai,
  /// belum hangus.
  ///
  /// Dipisah dari [claimed] karena keduanya menjawab pertanyaan yang
  /// berbeda. Dulu keduanya satu angka, dan akibatnya voucher yang sudah
  /// hangus — dananya sudah kembali ke GL Total Saldo — tetap tercatat
  /// sebagai uang yang menggantung. Angka di kepala layar jadi lebih
  /// besar daripada yang benar-benar tertahan, dan tidak pernah turun.
  final int menggantung;

  const Voucher({
    required this.id,
    required this.code,
    required this.name,
    required this.totalAmount,
    required this.quantity,
    required this.amount,
    required this.expiresOn,
    this.minPurchase = 0,
    this.restoIds = const [],
    this.active = true,
    this.settledAt,
    this.createdBy,
    required this.createdAt,
    this.bannerBase64,
    this.newCustomersOnly = false,
    this.claimed = 0,
    this.menggantung = 0,
  });

  bool get punyaBanner => bannerBase64 != null && bannerBase64!.isNotEmpty;

  /// Batch yang sudah ditutup dan belum ada penebusnya boleh dihapus.
  ///
  /// Kodenya yang sudah tersebar tidak boleh tiba-tiba hilang, dan
  /// klaim yang sudah menggantung di tangan orang tidak boleh
  /// kehilangan induknya — server menegakkan keduanya, ini cuma yang
  /// menentukan tombolnya menyala atau tidak.
  bool get bisaDihapus => !active && claimed == 0;

  bool get berlakuDiSemuaResto => restoIds.isEmpty;

  int get sisa => (quantity - claimed).clamp(0, quantity);

  bool get habis => claimed >= quantity;

  bool get kedaluwarsa {
    final kini = DateTime.now();
    return DateTime(kini.year, kini.month, kini.day).isAfter(expiresOn);
  }

  bool get bisaDitebus => active && !habis && !kedaluwarsa;

  /// Nilai yang masih menggantung di tangan pelanggan — sudah keluar dari
  /// saldo bebas, belum jadi apa pun.
  int get nilaiTertebus => menggantung * amount;
}

/// Voucher milik seorang pelanggan.
class VoucherClaim {
  final String id;
  final String voucherId;
  final String customerLabel;
  final int amount;
  final VoucherClaimStatus status;
  final String? restoId;
  final DateTime? usedAt;
  final DateTime createdAt;

  /// Ikut dibaca dari batch-nya supaya layar pelanggan bisa menampilkan
  /// nama, kode, dan masa berlakunya tanpa panggilan kedua.
  final String? code;
  final String? name;
  final DateTime? expiresOn;
  final int minPurchase;
  final List<String> restoIds;

  const VoucherClaim({
    required this.id,
    required this.voucherId,
    required this.customerLabel,
    required this.amount,
    this.status = VoucherClaimStatus.claimed,
    this.restoId,
    this.usedAt,
    required this.createdAt,
    this.code,
    this.name,
    this.expiresOn,
    this.minPurchase = 0,
    this.restoIds = const [],
  });

  bool get kedaluwarsa {
    if (expiresOn == null) return false;
    final kini = DateTime.now();
    return DateTime(kini.year, kini.month, kini.day).isAfter(expiresOn!);
  }

  /// Bisa dipakai membayar sekarang.
  bool get siapDipakai =>
      status == VoucherClaimStatus.claimed && !kedaluwarsa;

  /// Berlaku di resto ini, dan tagihannya memenuhi minimum belanjanya.
  bool bisaDipakaiDi(String restoId, int total) =>
      siapDipakai &&
      (restoIds.isEmpty || restoIds.contains(restoId)) &&
      total >= minPurchase;

  /// Alasan sebuah voucher tidak bisa dipakai pada tagihan ini.
  ///
  /// Selalu ada kalimatnya. Voucher yang tampil tapi tidak bisa dipilih
  /// tanpa penjelasan membuat orang mengira aplikasinya rusak.
  String? alasanTidakBisa(String restoId, int total) {
    if (status == VoucherClaimStatus.used) return 'Sudah dipakai';
    if (status == VoucherClaimStatus.expired || kedaluwarsa) return 'Hangus';
    if (restoIds.isNotEmpty && !restoIds.contains(restoId)) {
      return 'Tidak berlaku di merchant ini';
    }
    if (total < minPurchase) return 'Belanja belum mencapai minimum';
    return null;
  }

  factory VoucherClaim.fromMap(Map<String, dynamic> map) {
    final batch = map['vouchers'] is Map
        ? Map<String, dynamic>.from(map['vouchers'] as Map)
        : const <String, dynamic>{};
    return VoucherClaim(
      id: map['id'] as String,
      voucherId: map['voucher_id'] as String,
      customerLabel: map['customer_label'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      status: _claimDb.entries
          .firstWhere((e) => e.value == map['status'],
              orElse: () => _claimDb.entries.first)
          .key,
      restoId: map['resto_id'] as String?,
      usedAt: map['used_at'] == null
          ? null
          : DateTime.parse(map['used_at'].toString()).toLocal(),
      createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
      code: batch['code'] as String?,
      name: batch['name'] as String?,
      expiresOn: batch['expires_on'] == null
          ? null
          : DateTime.parse(batch['expires_on'].toString()),
      minPurchase: (batch['min_purchase'] as num?)?.toInt() ?? 0,
      restoIds: [
        for (final r in (batch['resto_ids'] as List<dynamic>? ?? const []))
          r.toString(),
      ],
    );
  }
}

/// Jawaban server saat sebuah kode ditebus.
///
/// Selalu membawa alasan saat ditolak. "Voucher tidak berlaku" tanpa
/// sebab membuat orang mencoba lagi dengan kode yang sama, lalu
/// menyalahkan aplikasinya.
class ClaimResult {
  final String? claimId;
  final int amount;
  final String? reason;

  const ClaimResult({this.claimId, this.amount = 0, this.reason});

  bool get berhasil => reason == null && claimId != null;

  factory ClaimResult.fromMap(Map<String, dynamic> map) => ClaimResult(
        claimId: map['claim_id'] as String?,
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        reason: map['reason'] as String?,
      );
}

Voucher voucherFromMap(
  Map<String, dynamic> map, {
  int claimed = 0,
  int menggantung = 0,
}) =>
    Voucher(
      id: map['id'] as String,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? 'Voucher',
      totalAmount: (map['total_amount'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      expiresOn: DateTime.parse(map['expires_on'].toString()),
      minPurchase: (map['min_purchase'] as num?)?.toInt() ?? 0,
      restoIds: [
        for (final r in (map['resto_ids'] as List<dynamic>? ?? const []))
          r.toString(),
      ],
      active: map['active'] != false,
      settledAt: map['settled_at'] == null
          ? null
          : DateTime.parse(map['settled_at'].toString()).toLocal(),
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
      bannerBase64: map['banner_base64'] as String?,
      newCustomersOnly: map['new_customers_only'] == true,
      claimed: claimed,
      menggantung: menggantung,
    );
