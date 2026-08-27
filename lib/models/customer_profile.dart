class CustomerProfile {
  final String email;
  final String name;
  final String? phone;

  /// Base64-encoded JPEG, stored directly in the `customers` table's
  /// `photo_base64` column — no separate file-storage service needed.
  /// Kept small by compressing/resizing the picked image before encoding
  /// (see CustomerProfileScreen).
  final String? photoBase64;

  CustomerProfile({
    required this.email,
    required this.name,
    this.phone,
    this.photoBase64,
  });

  Map<String, dynamic> toMap() => {
        'email': email,
        'name': name,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        // Selalu dikirim, termasuk saat null: upsert yang menghilangkan
        // kuncinya akan mempertahankan foto lama, sehingga menghapus foto
        // jadi mustahil.
        'photo_base64': photoBase64,
      };

  factory CustomerProfile.fromMap(String email, Map<String, dynamic> map) {
    return CustomerProfile(
      email: email,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String?,
      photoBase64: map['photo_base64'] as String?,
    );
  }
}
