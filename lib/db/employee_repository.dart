import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';

/// CRUD for the `employees` table — used by the Super Admin's "Kelola
/// Karyawan" screen. Regular Admins don't get a UI for this yet (out of
/// scope for now); only Super Admin can add/edit/deactivate employees
/// across any restaurant, enforced both here and by RLS.
class EmployeeRepository {
  final _client = Supabase.instance.client;

  Future<List<Employee>> getAll() async {
    final rows = await _client.from('employees').select().order('email');
    return rows.map((r) => Employee.fromMap(r)).toList();
  }

  Future<List<Employee>> getByResto(String restoId) async {
    final rows = await _client
        .from('employees')
        .select()
        .eq('resto_id', restoId)
        .order('email');
    return rows.map((r) => Employee.fromMap(r)).toList();
  }

  /// Menyimpan karyawan baru, atau memperbarui yang sudah ada.
  ///
  /// Dibedakan lewat id barisnya, bukan emailnya. Kalau memakai email
  /// sebagai acuan, mengubah email akan tersimpan sebagai orang baru dan
  /// meninggalkan baris lamanya — dan itulah alasan kolomnya dulu
  /// terkunci saat mengedit.
  Future<void> upsert(Employee employee) async {
    if (employee.id.isEmpty) {
      await _client.from('employees').insert(employee.toMap());
      return;
    }
    await _client.from('employees').update(employee.toMap()).eq('id', employee.id);
  }

  /// Menghapus satu baris keanggotaan — bukan seluruh akunnya.
  ///
  /// Satu email bisa terdaftar di beberapa resto sekaligus, jadi
  /// menghapus berdasarkan email akan mengeluarkan orang itu dari semua
  /// cabang, termasuk yang tidak sedang diurus.
  Future<void> delete(String id) async {
    await _client.from('employees').delete().eq('id', id);
  }
}
