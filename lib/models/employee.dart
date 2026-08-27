/// Mirrors a row in Postgres `employees` — an account allowed to sign in
/// as staff (rather than falling through to the customer flow), scoped
/// to one restaurant (except `super_admin`, which isn't scoped at all).
class Employee {
  /// Identitas baris, bukan identitas orangnya.
  ///
  /// Dulu emailnya sendiri yang menjadi kunci, sehingga memperbaiki
  /// alamat yang salah ketik berarti membuat baris baru dan
  /// meninggalkan yang lama. Dengan id tersendiri, email kembali
  /// menjadi data biasa yang boleh diperbaiki.
  ///
  /// Kosong berarti barisnya belum pernah disimpan.
  final String id;

  final String email;
  final String name;
  final String? nip; // Nomor Induk Pegawai — internal employee ID number
  final String role; // 'super_admin' | 'admin' | 'kasir' | 'chef' | 'finance'
  final String? restoId;
  final bool active;

  Employee({
    this.id = '',
    required this.email,
    required this.name,
    this.nip,
    required this.role,
    required this.restoId,
    this.active = true,
  });

  Map<String, dynamic> toMap() => {
        'email': email,
        'name': name,
        'nip': nip,
        'role': role,
        'resto_id': restoId,
        'active': active,
      };

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'] as String? ?? '',
      email: map['email'] as String,
      name: map['name'] as String? ?? '',
      nip: map['nip'] as String?,
      role: map['role'] as String,
      restoId: map['resto_id'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }
}
