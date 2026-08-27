-- KaataGo — mengajak pelanggan menilai, sejam sesudah membayar.
--
-- Jalankan SETELAH merchant_reviews.sql. Aman diulang.
--
-- Sejam, bukan seketika. Yang baru saja membayar biasanya sedang makan
-- atau sedang berjalan keluar — ajakan menilai di detik itu ditutup
-- tanpa dibaca. Sejam kemudian, makanannya sudah dicoba dan
-- pendapatnya sudah terbentuk.
--
-- Dan tidak lebih dari tiga jam: ajakan yang datang esok hari menanyakan
-- sesuatu yang sudah kabur, dan jawabannya jadi asal.

begin;

-- Yang sudah pernah diajak, supaya tidak diajak dua kali.
--
-- Barisnya per pesanan, bukan per merchant: orang yang makan di tempat
-- yang sama minggu depan boleh diajak lagi, karena kunjungannya memang
-- berbeda. Yang tidak boleh adalah satu kunjungan diajak berulang kali
-- tiap penjadwal berjalan.
create table if not exists review_prompts (
  order_id uuid primary key references orders (id) on delete cascade,
  sent_at timestamptz not null default now()
);

alter table review_prompts enable row level security;
-- Tidak ada kebijakan untuk siapa pun: yang menulisnya hanya penjadwal
-- di bawah, yang berjalan SECURITY DEFINER.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Penjadwalnya
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_review_prompts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  o record;
begin
  for o in
    select distinct on (ord.customer_label, ord.resto_id)
           ord.id, ord.customer_label, ord.resto_id, r.name as merchant
    from orders ord
    join restaurants r on r.id = ord.resto_id
    where ord.payment_status = 'paid'
      and ord.created_at < now() - interval '1 hour'
      and ord.created_at > now() - interval '3 hours'
      -- Hanya akun terdaftar. Pesanan kasir memakai nama tamu yang
      -- diketik di tempat; tidak ada perangkat yang bisa dituju.
      and exists (select 1 from customers c where c.email = ord.customer_label)
      -- Yang sudah menilai tempat ini tidak diajak lagi.
      and not exists (
        select 1 from merchant_reviews mr
        where mr.resto_id = ord.resto_id
          and mr.customer_email = ord.customer_label
      )
      and not exists (
        select 1 from review_prompts p where p.order_id = ord.id
      )
    order by ord.customer_label, ord.resto_id, ord.created_at desc
  loop
    insert into push_outbox (resto_id, event, payload) values (
      o.resto_id, 'review_prompt',
      jsonb_build_object(
        'audience', 'email',
        'email', o.customer_label,
        'resto_id', o.resto_id,
        'title', 'Gimana pesanan kamu di ' || o.merchant || '?',
        'body', 'Bikin nagih ga nih? Jangan lupa kasih ulasan untuk ' ||
                o.merchant || ' di KaataGo.'
      )
    );

    insert into review_prompts (order_id) values (o.id)
    on conflict (order_id) do nothing;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function queue_review_prompts() from public, anon, authenticated;

-- Tiap 20 menit. Ketepatan menitnya tidak penting di sini — yang
-- penting ajakannya datang saat makanannya masih diingat, dan rentang
-- satu sampai tiga jam sudah menjamin itu.
select cron.unschedule('review-prompts')
where exists (select 1 from cron.job where jobname = 'review-prompts');

select cron.schedule('review-prompts', '*/20 * * * *',
  $cron$select queue_review_prompts();$cron$);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select * from review_prompts order by sent_at desc limit 10;
--
--   select event, payload ->> 'email', payload ->> 'title', created_at
--   from push_outbox where event = 'review_prompt'
--   order by created_at desc limit 10;
