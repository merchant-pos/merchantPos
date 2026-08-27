-- KaataGo — GL Diskon terisi bawaannya di tiap resto.
--
-- Jalankan SETELAH billing_journal_gross.sql. Aman diulang.
--
-- Akun diskon lahir bersama fitur promo menu, dan disemai untuk seluruh
-- resto yang ada saat itu. Tapi barisnya bisa hilang di tiga jalan:
-- resto yang dibuat sebelum berkas promonya dijalankan, resto yang
-- barisnya terhapus saat merapikan pemetaan, dan resto yang barisnya ada
-- tapi nomornya dikosongkan.
--
-- Ketiganya berakhir sama: pemicu jurnal diam-diam melewatkan diskonnya.
-- Transaksinya tetap terjadi, potongannya tetap diberikan, tapi tidak
-- ada satu baris pun di GL Diskon — dan pertanyaan "berapa yang kita
-- berikan sebagai potongan bulan ini" tidak punya jawaban di mana pun.
--
-- Nomornya tetap bisa diubah Finance lewat Mapping GL Account. Yang
-- dijamin di sini cuma satu: tidak ada resto yang berjalan tanpa akun
-- diskon sama sekali.

begin;

-- Resto biasa: 2200002, sederet dengan akun pengurang pendapatan lain.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
select r.id, 'discount', '2200002', 'GL Diskon Penjualan'
from restaurants r
where r.is_platform = false
on conflict (resto_id, payment_method) do nothing;

-- Baris yang ada tapi nomornya kosong ikut diisi. `on conflict do
-- nothing` di atas tidak menyentuhnya — dan baris kosong persis sama
-- akibatnya dengan baris yang tidak ada.
update gl_accounts
set gl_code = '2200002',
    gl_name = coalesce(nullif(gl_name, ''), 'GL Diskon Penjualan')
where payment_method = 'discount'
  and coalesce(gl_code, '') = ''
  and resto_id in (select id from restaurants where is_platform = false);

-- KaataGo memakai golongan 11xxxxx untuk pembukuannya sendiri.
insert into gl_accounts (resto_id, payment_method, gl_code, gl_name)
values
  ('kaatago', 'discount',              '1100072', 'GL Diskon Lain KaataGo'),
  ('kaatago', 'subscription_discount', '1100002', 'GL Diskon Langganan')
on conflict (resto_id, payment_method) do nothing;

update gl_accounts
set gl_code = '1100002',
    gl_name = coalesce(nullif(gl_name, ''), 'GL Diskon Langganan')
where resto_id = 'kaatago'
  and payment_method = 'subscription_discount'
  and coalesce(gl_code, '') = '';

-- Resto baru sesudah ini sudah terurus oleh seed_gl_accounts_for_new_resto,
-- yang membaca _default_gl_accounts() — dan 'discount' sudah ada di sana.

commit;
