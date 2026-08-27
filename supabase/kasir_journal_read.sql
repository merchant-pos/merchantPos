-- KaataGo — kasir boleh melihat jurnal dari catatan yang dia buat.
--
-- Aman dijalankan berulang kali.
--
-- Layar Saldo & Pengeluaran memang sudah dibuka untuk kasir: dia
-- mencatat pengeluaran dari petty cash dan mengajukan top up, dan
-- keduanya terlihat di sana. Yang tertinggal cuma satu — mengetuk salah
-- satu catatan untuk melihat jurnalnya.
--
-- Karena hak bacanya berhenti di admin dan finance, jawabannya selalu
-- kosong, dan layarnya menyimpulkan yang paling masuk akal dari data
-- kosong: "akun GL-nya belum dipetakan". Kasir lalu mencari kesalahan
-- pemetaan yang tidak pernah ada, sementara di layar Finance jurnal yang
-- sama muncul lengkap.
--
-- Tidak ada yang baru yang terbuka: barisnya menjelaskan catatan yang
-- sudah boleh dia lihat isinya. Menulis tetap tertutup untuk semua peran
-- — seluruh baris jurnal ditulis oleh pemicu, tidak pernah oleh
-- aplikasi.

begin;

drop policy if exists "gl_journal_entries: finance/admin read" on gl_journal_entries;
drop policy if exists "gl_journal_entries: staff read" on gl_journal_entries;
create policy "gl_journal_entries: staff read" on gl_journal_entries
  for select using (
    is_resto_employee(resto_id, array['admin', 'finance', 'kasir'])
  );

commit;
