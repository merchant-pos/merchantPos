-- KaataGo — pelanggan boleh memilih bayar tunai di kasir.
--
-- Jalankan SETELAH orders_gl_code.sql. Aman dijalankan berulang kali.
--
-- Sampai sekarang pesanan mandiri dari HP pelanggan selalu QRIS, dan itu
-- dianggap benar di banyak tempat sekaligus. Yang berubah di sini cuma
-- satu: kalau pesanannya sudah menyebut cara bayarnya sendiri, sebutan
-- itu yang dipakai — bukan diganti QRIS karena kebetulan datang dari
-- pelanggan.

begin;

-- Uang yang diserahkan pelanggan di meja kasir.
--
-- Kembaliannya tidak ikut disimpan: itu selalu bisa dihitung ulang dari
-- uang yang diterima dikurangi totalnya, dan menyimpan dua angka yang
-- saling terikat berarti membuka peluang keduanya tidak lagi cocok.
alter table orders add column if not exists cash_received bigint;

-- Sebelumnya: pesanan mana pun dari pelanggan langsung dipetakan ke
-- 'qris' tanpa melihat apa pun. Akibatnya pesanan tunai akan tercatat
-- masuk ke GL QRIS — uangnya benar jumlahnya, tapi salah kantong, dan
-- Finance baru sadar saat mencocokkan mutasi QRIS yang tidak pernah ada.
--
-- Baris pelanggan lama tidak pernah mengisi payment_method, jadi
-- pemetaan lamanya tetap berlaku persis untuk mereka.
create or replace function _normalize_payment_method(p_source text, p_payment_method text)
returns text
language sql
immutable
as $$
  select case
    when p_payment_method in ('cash', 'qris', 'transfer') then p_payment_method
    when p_payment_method = 'QRIS' then 'qris'
    when p_payment_method = 'Transfer' then 'transfer'
    when p_payment_method = 'Tunai' then 'cash'
    when p_source = 'customer' then 'qris'
    else 'cash'
  end;
$$;

-- Setoran dan top up ikut disiarkan realtime.
--
-- Tanpa ini, kasir baru tahu pengajuannya disetujui kalau kebetulan
-- membuka layarnya lagi — padahal justru itu yang bikin orang tidak
-- membukanya: tidak ada yang memberi tahu ada yang perlu dilihat.
do $$
begin
  alter publication supabase_realtime add table cash_deposits;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table petty_cash_entries;
exception when duplicate_object then null;
end $$;

-- Pesanan tunai pelanggan diselesaikan kasir lewat UPDATE biasa —
-- kebijakan "orders: employees update" sudah mengizinkannya, dan RPC
-- mark_order_paid memang khusus untuk tamu yang tidak punya sesi login.
-- Tidak ada yang perlu ditambahkan di sini.

commit;
