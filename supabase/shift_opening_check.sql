-- KaataGo — perkiraan modal awal saat shift dibuka.
--
-- Jalankan SETELAH cashier_shift.sql. Aman diulang.
--
-- Menutup shift sudah punya pembanding: uang yang dihitung tangan
-- dibandingkan dengan yang seharusnya ada. Membuka shift belum punya
-- apa-apa — modal awal diketik apa adanya, dan tidak ada yang
-- memeriksanya.
--
-- Akibatnya selisih bisa lahir sebelum jualan dimulai. Kasir yang salah
-- ketik modal awal — atau menerima laci yang isinya sudah tidak sesuai
-- sejak semalam — baru mengetahuinya delapan jam kemudian, saat shiftnya
-- ditutup dan selisihnya sudah jadi tanggung jawabnya sendiri.

-- Berapa yang seharusnya ada di laci sekarang, sebelum shift dibuka.
--
-- Titik awalnya uang yang DIHITUNG pada penutupan terakhir, bukan yang
-- seharusnya ada saat itu. Kalau shift kemarin kurang Rp 10.000, yang
-- betul-betul tertinggal di laci memang jumlah yang kurang itu — dan
-- kekurangannya sudah punya tagihannya sendiri di `cash_variances`.
-- Memakai angka "seharusnya" berarti menagihkan kekurangan yang sama dua
-- kali, kepada dua orang yang berbeda.
--
-- Lalu ditambah-kurangi apa pun yang terjadi sesudah penutupan itu:
-- penjualan tunai di sela-sela shift, setoran, dan penarikan petty cash.
-- Biasanya kosong — tapi "biasanya" bukan alasan untuk tidak
-- menghitungnya.
create or replace function expected_opening_cash(p_resto_id text)
returns table (ada boolean, jumlah bigint)
language sql
stable
security definer
set search_path = public
as $$
  with terakhir as (
    select s.counted_cash, s.closed_at
    from cashier_shifts s
    where s.resto_id = p_resto_id
      and s.closed_at is not null
      and s.counted_cash is not null
    order by s.closed_at desc
    limit 1
  )
  select
    exists (select 1 from terakhir),
    coalesce((
      select t.counted_cash
           + coalesce((
               select sum(o.total)
               from orders o
               where o.resto_id = p_resto_id
                 and o.payment_status = 'paid'
                 and o.payment_method = 'cash'
                 and o.created_at >= t.closed_at
             ), 0)
           - coalesce((
               select sum(d.amount)
               from cash_deposits d
               where d.resto_id = p_resto_id
                 and d.status <> 'rejected'
                 and d.created_at >= t.closed_at
             ), 0)
           - coalesce((
               select sum(p.amount)
               from petty_cash_entries p
               where p.resto_id = p_resto_id
                 and p.source = 'cash_withdrawal'
                 and p.status <> 'rejected'
                 and p.created_at >= t.closed_at
             ), 0)
      from terakhir t
    ), 0)::bigint
  from terakhir
  -- Merchant yang belum pernah menutup shift sekali pun tetap dapat satu
  -- baris, dengan `ada` = false. Daftar kosong akan terbaca aplikasi
  -- sebagai "gagal", padahal artinya "belum ada pembandingnya".
  right join (select 1) satu on true;
$$;

grant execute on function expected_opening_cash(text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from expected_opening_cash('<resto_id>');
--
--   -- Pada merchant yang belum pernah menutup shift, hasilnya
--   -- (false, 0) — bukan daftar kosong.
