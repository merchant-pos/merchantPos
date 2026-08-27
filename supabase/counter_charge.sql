-- KaataGo — tagihan QRIS di meja kasir.
--
-- Jalankan SETELAH payment_gateway.sql. Aman dijalankan berulang kali.
--
-- Pesanan yang diinput kasir baru dibuat SETELAH pembayarannya diterima,
-- bukan sebelum — itu urutan yang sudah ada sejak awal, dan mengubahnya
-- berarti membongkar alur checkout beserta pengurangan stoknya. Jadi
-- tagihannya boleh berdiri tanpa pesanan: yang menghubungkannya nanti
-- adalah transaksi yang tercatat sesudahnya.

begin;

alter table payment_charges alter column order_id drop not null;

-- Status tagihan, untuk ditanyakan aplikasi kasir sambil menunggu.
--
-- Lewat fungsi, bukan membaca tabelnya langsung: tabel tagihan tetap
-- tertutup rapat dari aplikasi. Yang boleh diketahui cuma satu kata —
-- sudah dibayar atau belum — dan bukan seluruh isinya.
create or replace function gateway_charge_status(p_reference_id text)
returns text
language sql
security definer
set search_path = public
as $$
  select status from payment_charges where reference_id = p_reference_id;
$$;

grant execute on function gateway_charge_status(text) to anon, authenticated;

commit;
