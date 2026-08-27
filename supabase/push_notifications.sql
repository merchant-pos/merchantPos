-- KaataGo — notifikasi yang tetap sampai walau aplikasinya tertutup.
--
-- Jalankan SETELAH customer_cash_payment.sql. Aman dijalankan berulang
-- kali.
--
-- Notifikasi yang sudah ada dibangkitkan aplikasinya sendiri dari aliran
-- realtime, dan itu hanya hidup selama prosesnya hidup. Berkas ini
-- menyiapkan sisi servernya: daftar perangkat yang boleh diketuk, dan
-- pemicu yang memberi tahu Edge Function bahwa ada yang perlu
-- dikabarkan.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Daftar perangkat
-- ─────────────────────────────────────────────────────────────────────

-- Satu baris per perangkat, bukan per orang: satu orang bisa memegang HP
-- dan tablet sekaligus, dan satu HP bisa berpindah tangan antar shift.
-- Tokennya sendiri yang jadi kunci — itu satu-satunya hal yang benar-
-- benar mewakili "tempat notifikasi ini akan mendarat".
create table if not exists device_tokens (
  token text primary key,

  -- Siapa yang sedang memakainya. Semuanya boleh kosong: pelanggan tamu
  -- tidak punya email, dan perangkat yang belum memilih resto belum
  -- terikat ke mana pun.
  email text,
  resto_id text references restaurants (id) on delete cascade,
  role text,

  -- Pengenal pelanggan tamu. Tamu adalah sebagian besar pelanggan resto;
  -- tanpa kolom ini fitur ini hanya bekerja untuk yang paling jarang
  -- membutuhkannya.
  session_id text,

  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_resto_role_idx
  on device_tokens (resto_id, role);
create index if not exists device_tokens_email_idx on device_tokens (email);
create index if not exists device_tokens_session_idx on device_tokens (session_id);

alter table device_tokens enable row level security;

-- Siapa pun boleh mendaftarkan tokennya sendiri, termasuk tamu yang
-- tidak punya sesi login sama sekali — sama seperti kebijakan `orders`,
-- yang memang harus menerima pesanan dari orang tanpa akun.
--
-- Yang dijaga bukan siapa yang boleh menulis, tapi siapa yang boleh
-- membaca: daftar token adalah daftar "ke mana notifikasi bisa
-- dikirim", dan itu tidak boleh bisa dibaca dari aplikasi sama sekali.
-- Edge Function membacanya dengan service role, yang melewati RLS.
drop policy if exists "device_tokens: public upsert" on device_tokens;
create policy "device_tokens: public upsert" on device_tokens
  for insert with check (true);

drop policy if exists "device_tokens: update own" on device_tokens;
create policy "device_tokens: update own" on device_tokens
  for update using (true) with check (true);

drop policy if exists "device_tokens: delete own" on device_tokens;
create policy "device_tokens: delete own" on device_tokens
  for delete using (true);

-- Sengaja tidak ada kebijakan select untuk peran mana pun.

-- ─────────────────────────────────────────────────────────────────────
-- 2. Antrean kabar
-- ─────────────────────────────────────────────────────────────────────

-- Kejadian ditulis ke tabel dulu, baru dikirim.
--
-- Memanggil FCM langsung dari trigger berarti transaksi database
-- menunggu jaringan pihak lain: FCM lambat sedetik, dan kasir menunggu
-- sedetik itu sebelum pesanannya tersimpan. Lebih buruk lagi, FCM
-- gagal berarti seluruh transaksinya batal — pesanan yang sah hilang
-- gara-gara notifikasinya tidak terkirim.
--
-- Dengan antrean, kejadiannya tercatat dulu dan dikirim menyusul. Yang
-- gagal terkirim tetap tercatat di sini berikut galatnya, jadi
-- "notifikasinya tidak sampai" berhenti jadi tebakan.
create table if not exists push_outbox (
  id uuid primary key default gen_random_uuid(),
  resto_id text,
  event text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  error text,
  attempts int not null default 0
);

create index if not exists push_outbox_pending_idx
  on push_outbox (created_at) where sent_at is null;

alter table push_outbox enable row level security;
-- Tidak ada kebijakan apa pun: hanya trigger dan service role yang
-- menyentuhnya.

-- ─────────────────────────────────────────────────────────────────────
-- 3. Pemicu — pesanan
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text := upper(substr(new.id::text, 1, 8));
  v_where text;
begin
  v_where := case
    when new.table_number is not null and new.table_number <> ''
      then 'Meja ' || new.table_number
    when coalesce(new.customer_name, '') <> ''
      then 'Take Away · ' || new.customer_name
    else 'Take Away'
  end;

  -- Pesanan baru → dapur.
  if tg_op = 'INSERT' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'order_new',
      jsonb_build_object(
        'audience', 'role', 'roles', array['chef'],
        'title', 'Pesanan baru masuk',
        'body', v_where || ' · #' || v_ref
      )
    );
    return new;
  end if;

  -- Dapur bergerak → pelanggannya, dan kasir yang menginput.
  if new.kitchen_status is distinct from old.kitchen_status then
    if new.kitchen_status = 'onProgress' then
      insert into push_outbox (resto_id, event, payload) values (
        new.resto_id, 'order_cooking',
        jsonb_build_object(
          'audience', 'order_owner',
          'email', new.customer_label,
          'session_id', new.session_id,
          'title', 'Pesanan kamu lagi dimasak 👨‍🍳',
          'body', 'Dapur sudah mulai. Tunggu sebentar ya — #' || v_ref
        )
      );
    elsif new.kitchen_status = 'done' then
      insert into push_outbox (resto_id, event, payload) values (
        new.resto_id, 'order_ready',
        jsonb_build_object(
          'audience', 'order_owner',
          'email', new.customer_label,
          'session_id', new.session_id,
          'title', 'Pesanan kamu siap! 🎉',
          'body', 'Selamat menikmati — #' || v_ref
        )
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_queue_push_order_insert on orders;
create trigger trg_queue_push_order_insert
  after insert on orders
  for each row execute function queue_push_order();

drop trigger if exists trg_queue_push_order_update on orders;
create trigger trg_queue_push_order_update
  after update on orders
  for each row execute function queue_push_order();

-- Pesanan tunai dari HP pelanggan yang menunggu dibayar — kasir, admin,
-- dan owner perlu tahu ada orang berdiri di depan kasir.
create or replace function queue_push_pending_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source = 'customer'
     and new.payment_status = 'pending'
     and new.payment_method = 'cash' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'pending_payment',
      jsonb_build_object(
        'audience', 'role', 'roles', array['kasir', 'admin', 'owner'],
        'title', 'Pesanan menunggu dibayar',
        'body', 'Pelanggan memilih bayar tunai di kasir — #'
                || upper(substr(new.id::text, 1, 8))
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_pending_payment on orders;
create trigger trg_queue_push_pending_payment
  after insert on orders
  for each row execute function queue_push_pending_payment();

-- ─────────────────────────────────────────────────────────────────────
-- 4. Pemicu — setoran & petty cash
-- ─────────────────────────────────────────────────────────────────────

create or replace function queue_push_deposit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount text := 'Rp ' || to_char(new.amount, 'FM999G999G999');
begin
  -- Pengajuan baru → yang memutuskan.
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'deposit_pending',
      jsonb_build_object(
        'audience', 'role', 'roles', array['finance', 'owner'],
        'title', 'Setoran tunai menunggu konfirmasi',
        'body', v_amount || ' dari ' || coalesce(new.created_by, 'kasir')
      )
    );
    return new;
  end if;

  -- Sudah diputus → yang mengajukan.
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'deposit_reviewed',
      jsonb_build_object(
        'audience', 'email', 'email', new.created_by,
        'title', case new.status
                   when 'approved' then 'Setoran tunai dikonfirmasi ✅'
                   else 'Setoran tunai ditolak' end,
        'body', case new.status
                  when 'approved' then v_amount || ' sudah masuk rekening merchant.'
                  else v_amount || ' dikembalikan ke Saldo Cash'
                       || coalesce(' — ' || nullif(trim(new.review_note), ''), '.')
                end
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_deposit_insert on cash_deposits;
create trigger trg_queue_push_deposit_insert
  after insert on cash_deposits
  for each row execute function queue_push_deposit();

drop trigger if exists trg_queue_push_deposit_update on cash_deposits;
create trigger trg_queue_push_deposit_update
  after update of status on cash_deposits
  for each row execute function queue_push_deposit();

create or replace function queue_push_petty()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount text := 'Rp ' || to_char(new.amount, 'FM999G999G999');
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'petty_pending',
      jsonb_build_object(
        'audience', 'role', 'roles', array['finance', 'owner'],
        'title', 'Top up petty cash menunggu persetujuan',
        'body', v_amount || ' dari ' || coalesce(new.created_by, 'kasir')
      )
    );
    return new;
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into push_outbox (resto_id, event, payload) values (
      new.resto_id, 'petty_reviewed',
      jsonb_build_object(
        'audience', 'email', 'email', new.created_by,
        'title', case new.status
                   when 'approved' then 'Top up petty cash disetujui ✅'
                   else 'Top up petty cash ditolak' end,
        'body', case new.status
                  when 'approved' then v_amount || ' sudah masuk saldo petty cash.'
                  else v_amount || ' tidak jadi ditambahkan'
                       || coalesce(' — ' || nullif(trim(new.review_note), ''), '.')
                end
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_queue_push_petty_insert on petty_cash_entries;
create trigger trg_queue_push_petty_insert
  after insert on petty_cash_entries
  for each row execute function queue_push_petty();

drop trigger if exists trg_queue_push_petty_update on petty_cash_entries;
create trigger trg_queue_push_petty_update
  after update of status on petty_cash_entries
  for each row execute function queue_push_petty();

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Langkah berikutnya, di luar berkas ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Deploy Edge Function-nya:
--        supabase functions deploy send-push --project-ref xizpwtycczigjhzxegen
--
-- 2. Pasang Database Webhook di Dashboard → Database → Webhooks:
--        tabel  : push_outbox
--        event  : Insert
--        tipe   : Supabase Edge Function → send-push
--
--    Webhook dipilih, bukan pg_net di dalam trigger, supaya kegagalan
--    jaringan tidak pernah bisa membatalkan transaksi yang menulis
--    pesanannya.
--
-- 3. Periksa hasilnya kapan pun:
--        select event, created_at, sent_at, error, attempts
--        from push_outbox order by created_at desc limit 20;
--
--    Baris ber-sent_at berarti benar-benar terkirim. Yang ber-error
--    menyebutkan sebabnya. Tidak perlu menebak lagi.
