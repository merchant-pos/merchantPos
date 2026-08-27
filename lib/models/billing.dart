/// Penyewa platform — MerchantPOS membukukan dirinya sendiri lewat mesin
/// pembukuan yang sama persis dengan resto.
///
/// Barisnya ada di tabel `restaurants` dan ditandai `is_platform`, jadi
/// seluruh layar keuangan yang sudah ada langsung bekerja untuknya.
/// Konsekuensinya harus dijaga di sisi lain: baris itu tidak boleh
/// muncul di daftar resto mana pun.
/// JANGAN diganti jadi 'merchantpos'.
///
/// Nilainya bukan tulisan yang dibaca orang — ia kunci baris di
/// database yang dipakai bersama KaataGo. Puluhan fungsi dan kebijakan
/// RLS di Postgres mencocokkannya apa adanya (`where resto_id =
/// 'kaatago'`), dan tidak satu pun ikut berubah saat nama aplikasi ini
/// berganti.
///
/// Menggantinya membuat seluruh pembukuan platform — saldo, jurnal,
/// mapping GL — menunjuk resto yang tidak pernah ada. Layarnya tetap
/// terbuka dan angkanya tetap tampil; yang tampil cuma nol semua.
const kPlatformRestoId = 'kaatago';

/// Keadaan tagihan sebuah tagihan langganan.
enum InvoiceStatus {
  /// Belum dibayar.
  unpaid,

  /// Bukti bayar sudah diunggah, menunggu diperiksa MerchantPOS.
  review,

  /// Diterima.
  paid,

  /// Dibebaskan — masa percobaan, atau kompensasi gangguan.
  waived,
}

const _statusDb = {
  InvoiceStatus.unpaid: 'unpaid',
  InvoiceStatus.review: 'review',
  InvoiceStatus.paid: 'paid',
  InvoiceStatus.waived: 'waived',
};

/// Bank yang menyediakan Virtual Account. Daftarnya sama persis dengan
/// batasan di database — kode yang tidak ada di sana ditolak Xendit, dan
/// yang melihat penolakannya adalah resto yang sedang mencoba membayar.
const kBankVA = ['BCA', 'BNI', 'BRI', 'MANDIRI', 'PERMATA', 'BSI', 'CIMB'];

const kInvoiceStatusLabels = {
  InvoiceStatus.unpaid: 'Belum Dibayar',
  InvoiceStatus.review: 'Menunggu Verifikasi',
  InvoiceStatus.paid: 'Lunas',
  InvoiceStatus.waived: 'Dibebaskan',
};

InvoiceStatus _statusOf(Object? v) => _statusDb.entries
    .firstWhere((e) => e.value == v, orElse: () => _statusDb.entries.first)
    .key;

/// Setelan langganan sebuah resto — harga dan tanggal tagihnya.
class RestoBilling {
  final String restoId;

  /// Rupiah per bulan. Nol berarti gratis, dan resto bernilai nol tidak
  /// pernah terkunci.
  final int monthlyPrice;

  /// Tanggal jatuh tempo tiap bulan, 1–28.
  ///
  /// Dibatasi 28 supaya artinya sama di bulan mana pun. "Tanggal 31"
  /// tidak ada di Februari, dan menggesernya diam-diam ke 28 membuat
  /// tagihan datang di hari yang tidak dijanjikan.
  final int billingDay;

  /// Tenggang sesudah jatuh tempo sebelum restonya terkunci.
  final int graceDays;

  final bool active;
  final String? note;

  const RestoBilling({
    required this.restoId,
    this.monthlyPrice = 0,
    this.billingDay = 1,
    this.graceDays = 1,
    this.active = true,
    this.note,
  });

  bool get gratis => monthlyPrice <= 0;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'monthly_price': monthlyPrice,
        'billing_day': billingDay,
        'grace_days': graceDays,
        'active': active,
        'note': note,
      };

  factory RestoBilling.fromMap(Map<String, dynamic> map) => RestoBilling(
        restoId: map['resto_id'] as String,
        monthlyPrice: (map['monthly_price'] as num?)?.toInt() ?? 0,
        billingDay: (map['billing_day'] as num?)?.toInt() ?? 1,
        graceDays: (map['grace_days'] as num?)?.toInt() ?? 1,
        active: map['active'] != false,
        note: map['note'] as String?,
      );

  RestoBilling copyWith({
    int? monthlyPrice,
    int? billingDay,
    int? graceDays,
    bool? active,
    String? note,
  }) =>
      RestoBilling(
        restoId: restoId,
        monthlyPrice: monthlyPrice ?? this.monthlyPrice,
        billingDay: billingDay ?? this.billingDay,
        graceDays: graceDays ?? this.graceDays,
        active: active ?? this.active,
        note: note ?? this.note,
      );
}

/// Satu tagihan bulanan.
class BillingInvoice {
  final String id;
  final String restoId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime dueDate;
  final int amount;
  final InvoiceStatus status;

  final String? proofBase64;
  final String? paidNote;
  final DateTime? submittedAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? rejectReason;

  /// Virtual Account untuk membayar tagihan ini.
  final String? vaBank;
  final String? vaNumber;
  final DateTime? vaExpiresAt;

  /// Harga sebelum diskon. Null pada tagihan lama yang terbit sebelum
  /// diskon langganan ada.
  final int? grossAmount;
  final String? discountId;
  final String? discountName;
  final int discountAmount;

  /// Bagaimana tagihannya akhirnya lunas — `xendit_va`, `manual`, atau
  /// `waived`. Dibedakan karena tingkat kepercayaannya berbeda: yang
  /// pertama terkonfirmasi mesin, yang kedua keputusan orang.
  final String? paidVia;

  /// Nama resto — hanya terisi di layar Super Admin, yang membaca
  /// tagihan lintas resto.
  final String? restoName;

  const BillingInvoice({
    required this.id,
    required this.restoId,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.amount,
    this.status = InvoiceStatus.unpaid,
    this.proofBase64,
    this.paidNote,
    this.submittedAt,
    this.confirmedBy,
    this.confirmedAt,
    this.rejectReason,
    this.grossAmount,
    this.discountId,
    this.discountName,
    this.discountAmount = 0,
    this.vaBank,
    this.vaNumber,
    this.vaExpiresAt,
    this.paidVia,
    this.restoName,
  });

  bool get open =>
      status == InvoiceStatus.unpaid || status == InvoiceStatus.review;

  bool get hasProof => proofBase64 != null && proofBase64!.isNotEmpty;

  /// Punya VA yang masih bisa dipakai.
  ///
  /// Tagihan yang sudah lunas tidak punya, apa pun isi kolomnya.
  /// Nomor VA yang masih terpampang di bawah tulisan "Lunas" adalah
  /// undangan untuk mentransfer dua kali — dan uang kedua itu tidak
  /// punya tagihan untuk dilunasi.
  bool get vaHidup =>
      open &&
      vaNumber != null &&
      vaNumber!.isNotEmpty &&
      (vaExpiresAt == null || vaExpiresAt!.isAfter(DateTime.now()));

  factory BillingInvoice.fromMap(Map<String, dynamic> map) => BillingInvoice(
        id: map['id'] as String,
        restoId: map['resto_id'] as String,
        periodStart: DateTime.parse(map['period_start'].toString()),
        periodEnd: DateTime.parse(map['period_end'].toString()),
        dueDate: DateTime.parse(map['due_date'].toString()),
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        status: _statusOf(map['status']),
        proofBase64: map['proof_base64'] as String?,
        paidNote: map['paid_note'] as String?,
        submittedAt: _waktu(map['submitted_at']),
        confirmedBy: map['confirmed_by'] as String?,
        confirmedAt: _waktu(map['confirmed_at']),
        rejectReason: map['reject_reason'] as String?,
        grossAmount: (map['gross_amount'] as num?)?.toInt(),
        discountId: map['discount_id'] as String?,
        discountName: map['discount_name'] as String?,
        discountAmount: (map['discount_amount'] as num?)?.toInt() ?? 0,
        vaBank: map['va_bank'] as String?,
        vaNumber: map['va_number'] as String?,
        vaExpiresAt: _waktu(map['va_expires_at']),
        paidVia: map['paid_via'] as String?,
        restoName: map['restaurants'] is Map
            ? (map['restaurants'] as Map)['name'] as String?
            : map['resto_name'] as String?,
      );

  static DateTime? _waktu(Object? v) =>
      v == null ? null : DateTime.parse(v.toString()).toLocal();
}

/// Ringkasan keadaan langganan sebuah resto, dihitung di server.
///
/// Dihitung di satu tempat dan dibaca dari sana, bukan disusun ulang di
/// aplikasi: perhitungan yang sama di dua tempat akan berpisah, dan
/// yang terlihat adalah layar yang mengaku aman sementara database
/// menolak menyimpan apa pun.
class BillingState {
  final bool locked;
  final DateTime? dueDate;

  /// Sisa hari menuju jatuh tempo. Negatif berarti sudah lewat.
  final int? daysLeft;

  final int? amount;
  final String? invoiceId;
  final InvoiceStatus? invoiceStatus;
  final int monthlyPrice;
  final int billingDay;
  final bool active;

  /// Kapan tagihan berikutnya jatuh tempo.
  ///
  /// Dihitung server, bukan di sini. Aturan pemotongan tanggal akhir
  /// bulan ada di satu tempat; menyalinnya ke Dart berarti dua
  /// perhitungan yang suatu saat berpisah, dan yang terlihat adalah
  /// layar yang menjanjikan tanggal berbeda dari yang benar-benar
  /// ditagih.
  final DateTime? nextDueDate;

  const BillingState({
    this.locked = false,
    this.dueDate,
    this.daysLeft,
    this.amount,
    this.invoiceId,
    this.invoiceStatus,
    this.monthlyPrice = 0,
    this.billingDay = 1,
    this.active = false,
    this.nextDueDate,
  });

  /// Tidak ada yang perlu dikabarkan: gratis, dimatikan, atau tidak ada
  /// tagihan terbuka.
  static const tenang = BillingState();

  /// Pengingat mulai muncul H-3, dan tetap muncul sesudah lewat jatuh
  /// tempo selama belum lunas.
  ///
  /// Tiga hari dipilih bukan karena angka bulat: itu jarak terpendek
  /// yang masih memuat satu akhir pekan, dan transfer antarbank yang
  /// dikirim Jumat sore baru terlihat Senin.
  bool get perluDiingatkan =>
      active &&
      monthlyPrice > 0 &&
      invoiceId != null &&
      invoiceStatus != InvoiceStatus.paid &&
      invoiceStatus != InvoiceStatus.waived &&
      (daysLeft ?? 99) <= 3;

  bool get lewatTempo => (daysLeft ?? 99) < 0;

  bool get menungguVerifikasi => invoiceStatus == InvoiceStatus.review;

  factory BillingState.fromMap(Map<String, dynamic> map) => BillingState(
        locked: map['locked'] == true,
        dueDate: map['due_date'] == null
            ? null
            : DateTime.parse(map['due_date'].toString()),
        daysLeft: (map['days_left'] as num?)?.toInt(),
        amount: (map['amount'] as num?)?.toInt(),
        invoiceId: map['invoice_id'] as String?,
        invoiceStatus:
            map['invoice_status'] == null ? null : _statusOf(map['invoice_status']),
        monthlyPrice: (map['monthly_price'] as num?)?.toInt() ?? 0,
        billingDay: (map['billing_day'] as num?)?.toInt() ?? 1,
        active: map['active'] == true,
        nextDueDate: map['next_due_date'] == null
            ? null
            : DateTime.parse(map['next_due_date'].toString()),
      );
}


/// Potongan harga langganan untuk resto tertentu.
///
/// Dipilih per resto, bukan berlaku untuk semuanya: yang sering terjadi
/// justru satu-dua resto yang perlu diperlakukan berbeda — masa
/// percobaan, promo pembukaan, kompensasi gangguan.
class BillingDiscount {
  final String id;
  final String name;
  final DiscountKindBilling kind;
  final int value;
  final List<String> restoIds;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool active;
  final String? createdBy;
  final DateTime createdAt;

  const BillingDiscount({
    required this.id,
    required this.name,
    this.kind = DiscountKindBilling.percent,
    required this.value,
    this.restoIds = const [],
    this.startsOn,
    this.endsOn,
    this.active = true,
    this.createdBy,
    required this.createdAt,
  });

  String get valueLabel =>
      kind == DiscountKindBilling.percent ? '$value%' : 'Rp $value';

  /// Potongan untuk sebuah harga langganan.
  ///
  /// Tidak pernah melebihi harganya sendiri — potongan yang lebih besar
  /// daripada tagihannya menghasilkan tagihan negatif, yaitu kami yang
  /// berutang kepada resto yang belum membayar apa pun.
  int amountFor(int price) {
    if (price <= 0) return 0;
    final raw =
        kind == DiscountKindBilling.percent ? price * value ~/ 100 : value;
    return raw.clamp(0, price);
  }

  bool isLive([DateTime? now]) {
    if (!active) return false;
    final hari = now ?? DateTime.now();
    final tgl = DateTime(hari.year, hari.month, hari.day);
    if (startsOn != null && tgl.isBefore(startsOn!)) return false;
    if (endsOn != null && tgl.isAfter(endsOn!)) return false;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind == DiscountKindBilling.percent ? 'percent' : 'amount',
        'value': value,
        'resto_ids': restoIds,
        'starts_on': startsOn?.toIso8601String().split('T').first,
        'ends_on': endsOn?.toIso8601String().split('T').first,
        'active': active,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory BillingDiscount.fromMap(Map<String, dynamic> map) => BillingDiscount(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Diskon',
        kind: map['kind'] == 'amount'
            ? DiscountKindBilling.amount
            : DiscountKindBilling.percent,
        value: (map['value'] as num?)?.toInt() ?? 0,
        restoIds: [
          for (final r in (map['resto_ids'] as List<dynamic>? ?? const []))
            r.toString(),
        ],
        startsOn: map['starts_on'] == null
            ? null
            : DateTime.parse(map['starts_on'].toString()),
        endsOn: map['ends_on'] == null
            ? null
            : DateTime.parse(map['ends_on'].toString()),
        active: map['active'] != false,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'].toString()),
      );

  BillingDiscount copyWith({
    String? name,
    DiscountKindBilling? kind,
    int? value,
    List<String>? restoIds,
    Object? startsOn = _unset,
    Object? endsOn = _unset,
    bool? active,
  }) =>
      BillingDiscount(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        restoIds: restoIds ?? this.restoIds,
        startsOn:
            identical(startsOn, _unset) ? this.startsOn : startsOn as DateTime?,
        endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as DateTime?,
        active: active ?? this.active,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  static const _unset = Object();
}

/// Bentuk potongan langganan. Dinamai terpisah dari DiscountKind milik
/// promo menu — keduanya kebetulan sama bentuknya, tapi hidup di dunia
/// yang berbeda, dan menyatukannya berarti perubahan di salah satunya
/// ikut menyeret yang lain.
enum DiscountKindBilling { percent, amount }
