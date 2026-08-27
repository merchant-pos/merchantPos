-- KaataGo — pengenal sub-akun Xendit jadi urusan Super Admin saja.
--
-- Jalankan SETELAH resto_payment_accounts.sql. Aman diulang.
--
-- Sebelumnya Finance resto boleh membaca dan mengubah pengenal ini dari
-- Pengaturan Pembayaran. Itu keliru dari dua sisi.
--
-- Yang pertama: dia tidak punya cara mengetahui nilainya. Sub-akunnya
-- dibuat di akun Xendit milik KaataGo dan pengenalnya ditentukan
-- Xendit — bukan sesuatu yang bisa dicari orang resto di mana pun.
-- Kolom isian yang jawabannya tidak dimiliki siapa pun yang melihatnya
-- hanya mengundang tebakan.
--
-- Yang kedua, dan ini yang berbahaya: salah ketik satu huruf mengirim
-- seluruh pembayaran QRIS resto ini ke sub-akun resto lain. Uangnya
-- tidak hilang — tapi cair ke rekening orang lain, dan yang menemukan
-- selisihnya adalah kedua resto sekaligus, berhari-hari kemudian.
--
-- Batasnya ditegakkan di sini, bukan hanya dengan menyembunyikan
-- kolomnya di aplikasi: kolom yang disembunyikan cuma menghalangi orang
-- yang memakai aplikasinya.
--
-- Edge Function create-qris tetap bisa membacanya — dia memakai service
-- role, yang memang melewati RLS.

begin;

drop policy if exists "resto_payment_accounts: staff read" on resto_payment_accounts;
drop policy if exists "resto_payment_accounts: staff write" on resto_payment_accounts;

drop policy if exists "resto_payment_accounts: super_admin all" on resto_payment_accounts;
create policy "resto_payment_accounts: super_admin all" on resto_payment_accounts
  for all using (is_super_admin()) with check (is_super_admin());

commit;
