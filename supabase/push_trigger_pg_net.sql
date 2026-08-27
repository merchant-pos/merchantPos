-- KaataGo — panggil Edge Function langsung dari database, tanpa webhook.
--
-- Jalankan SETELAH fix_device_tokens_rls.sql. Aman dijalankan berulang
-- kali.
--
-- Rencana semula memakai Database Webhook, tapi tipe "Supabase Edge
-- Function" tidak tersedia di Dashboard proyek ini. pg_net melakukan hal
-- yang sama dari sisi database, dan sebetulnya lebih sedikit bagian yang
-- bisa rusak: satu tempat yang mengatur, bukan dua.
--
-- pg_net mengirim permintaannya secara asinkron — dititipkan ke antrean,
-- bukan ditunggu. Itu penting: transaksi yang menulis pesanan tidak
-- boleh menunggu jaringan pihak lain, dan kegagalan mengirim notifikasi
-- tidak boleh membatalkan pesanan yang sah.

begin;

create extension if not exists pg_net with schema extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Alamat dan kunci pemanggilnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Disimpan di tabel, bukan ditanam di badan fungsi: kunci yang tertanam
-- di definisi fungsi ikut terbaca siapa pun yang boleh melihat skema.
-- Tabel ini tidak punya kebijakan RLS satu pun, jadi tidak bisa disentuh
-- dari aplikasi — yang membacanya cuma trigger di bawah, yang berjalan
-- sebagai pemiliknya.
create table if not exists push_config (
  id int primary key default 1,
  function_url text not null,
  secret text not null,
  constraint push_config_single_row check (id = 1)
);

alter table push_config enable row level security;
revoke all on table push_config from anon, authenticated;

insert into push_config (id, function_url, secret) values (
  1,
  'https://xizpwtycczigjhzxegen.supabase.co/functions/v1/send-push',
  'fBFcxm-9uT-rQ3ha8I29_i4Y4xm_vq3a-oE1gOFEHhM'
)
on conflict (id) do update set
  function_url = excluded.function_url,
  secret = excluded.secret;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Pemicunya
-- ─────────────────────────────────────────────────────────────────────

create or replace function notify_push_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_config push_config;
begin
  select * into v_config from push_config where id = 1;
  if v_config.function_url is null then
    return new;
  end if;

  -- Barisnya dikirim utuh dalam bentuk yang sama dengan yang dikirim
  -- Database Webhook, supaya Edge Function-nya tidak perlu tahu dari
  -- mana panggilannya datang.
  perform net.http_post(
    url := v_config.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-kaata-hook-secret', v_config.secret
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object(
        'id', new.id,
        'resto_id', new.resto_id,
        'event', new.event,
        'payload', new.payload
      )
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_push_outbox on push_outbox;
create trigger trg_notify_push_outbox
  after insert on push_outbox
  for each row execute function notify_push_outbox();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memastikan
-- ─────────────────────────────────────────────────────────────────────
-- Buat satu pesanan, lalu:
--
--   select event, created_at, sent_at, error from push_outbox
--   order by created_at desc limit 5;
--
-- sent_at terisi berarti benar-benar terkirim. Kalau masih kosong,
-- lihat antrean pg_net-nya — di situ tercatat jawaban HTTP-nya:
--
--   select id, created, status_code, content from net._http_response
--   order by created desc limit 5;
