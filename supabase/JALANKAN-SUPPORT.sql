-- KaataGo — bagian 58 dan 59: KaataGo Support berikut notifikasinya.
-- Jalankan kapan saja setelah schema.sql. Aman diulang.


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 58 — tiket, percakapan, dan penutupan otomatis
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — pengaduan, tiket, dan percakapannya.
--
-- Jalankan kapan saja setelah schema.sql. Aman diulang.
--
-- Selama ini satu-satunya jalan mengadu adalah WhatsApp ke nomor
-- KaataGo Admin. Itu bekerja saat merchantnya lima. Pada merchant
-- kelima puluh, tidak ada yang tahu keluhan mana yang sudah dijawab,
-- mana yang tenggelam di bawah percakapan lain, dan mana yang sebenarnya
-- masalah yang sama muncul untuk ketiga kalinya.
--
-- Tiket menjawab tiga hal yang tidak bisa dijawab gulungan obrolan:
-- keluhan ini sudah selesai atau belum, siapa yang sedang menunggu siapa,
-- dan sudah berapa lama.

begin;

create table if not exists support_tickets (
  id uuid primary key default gen_random_uuid(),

  -- Yang mengadu. Emailnya kunci — bukan perangkatnya: yang mengadu dari
  -- HP lama harus menemukan tiketnya di HP baru.
  reporter_email text not null,
  reporter_name text,

  -- 'customer' atau 'merchant'. Bukan sekadar catatan: keduanya datang
  -- dengan masalah yang berbeda, dan admin yang tahu ini sebelum membuka
  -- percakapannya menjawab lebih cepat.
  reporter_kind text not null default 'customer'
    check (reporter_kind in ('customer', 'merchant')),

  -- Diisi kalau yang mengadu pegawai merchant.
  resto_id text references restaurants (id) on delete set null,

  subject text not null,

  -- open           — masuk, belum disentuh admin
  -- on_progress    — admin sedang menanganinya
  -- confirm_customer — admin sudah menjawab, giliran pengadu menanggapi
  -- closed         — selesai
  status text not null default 'open'
    check (status in ('open', 'on_progress', 'confirm_customer', 'closed')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Pesan terakhir, untuk mengurutkan daftar tanpa membaca seluruh
  -- percakapan tiap tiket.
  last_message_at timestamptz,
  last_message_body text,
  last_message_from_admin boolean not null default false,

  -- Kapan tiap pihak terakhir membuka percakapannya. Penanda belum
  -- dibaca dihitung dari sini, bukan dari bendera per pesan: satu
  -- stempel waktu tidak bisa berbeda pendapat dengan dirinya sendiri.
  reporter_read_at timestamptz,
  admin_read_at timestamptz,

  closed_at timestamptz,
  closed_by text,

  -- Ditutup sendiri karena pengadunya tidak menanggapi. Dibedakan dari
  -- yang ditutup orang: tiket yang mati karena didiamkan bukan tiket
  -- yang selesai, dan yang membaca laporannya nanti berhak tahu bedanya.
  auto_closed boolean not null default false
);

create index if not exists support_tickets_reporter_idx
  on support_tickets (reporter_email, created_at desc);
create index if not exists support_tickets_status_idx
  on support_tickets (status, last_message_at desc);

create table if not exists support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references support_tickets (id) on delete cascade,

  sender_email text not null,
  sender_name text,

  -- Siapa yang bicara. Disimpan, bukan disimpulkan dari emailnya saat
  -- dibaca: orang bisa berhenti jadi admin, dan percakapan lama tidak
  -- boleh berubah artinya karenanya.
  from_admin boolean not null default false,

  body text not null,

  -- Tangkapan layar keluhan, base64. Satu saja — pengaduan yang butuh
  -- lima gambar sebenarnya butuh percakapan, dan itu sudah tersedia di
  -- sini.
  photo_base64 text,

  -- Ditulis sistem, bukan orang: "Tiket ditutup otomatis", "Status
  -- diubah jadi Sedang Diproses". Ditandai supaya bisa ditampilkan
  -- berbeda dan tidak terbaca seolah admin yang mengetiknya.
  is_system boolean not null default false,

  created_at timestamptz not null default now()
);

create index if not exists support_messages_ticket_idx
  on support_messages (ticket_id, created_at);

alter table support_tickets enable row level security;
alter table support_messages enable row level security;

-- Pengadu melihat tiketnya sendiri; KaataGo Admin melihat semuanya.
--
-- Pegawai merchant lain TIDAK melihat pengaduan rekannya. Keluhan
-- sering berisi hal yang tidak ingin dibaca seruangan — termasuk
-- keluhan tentang orang di ruangan itu.
drop policy if exists "support_tickets: read" on support_tickets;
create policy "support_tickets: read" on support_tickets
  for select using (
    is_super_admin() or reporter_email = auth.jwt() ->> 'email'
  );

drop policy if exists "support_tickets: reporter insert" on support_tickets;
create policy "support_tickets: reporter insert" on support_tickets
  for insert with check (reporter_email = auth.jwt() ->> 'email');

-- Sengaja tidak ada policy update. Status dan penanda baca diubah lewat
-- fungsi di bawah — kalau barisnya bisa disunting langsung, pengadu bisa
-- menutup tiket atas nama admin, atau sebaliknya.

drop policy if exists "support_messages: read" on support_messages;
create policy "support_messages: read" on support_messages
  for select using (
    exists (
      select 1 from support_tickets t
      where t.id = support_messages.ticket_id
        and (is_super_admin() or t.reporter_email = auth.jwt() ->> 'email')
    )
  );

-- Menulis hanya ke tiket sendiri, dan hanya selama tiketnya belum
-- ditutup. Tiket tertutup yang masih bisa ditulisi adalah tiket yang
-- tidak pernah benar-benar selesai.
drop policy if exists "support_messages: write" on support_messages;
create policy "support_messages: write" on support_messages
  for insert with check (
    sender_email = auth.jwt() ->> 'email'
    and is_system = false
    and exists (
      select 1 from support_tickets t
      where t.id = support_messages.ticket_id
        and t.status <> 'closed'
        and (is_super_admin() or t.reporter_email = auth.jwt() ->> 'email')
    )
  );

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Realtime
-- ─────────────────────────────────────────────────────────────────────
--
-- Dibungkus penangkap galat: `add table` gagal kalau tabelnya sudah
-- terdaftar, dan galatnya menghentikan sisa bagiannya.
do $$ begin
  alter publication supabase_realtime add table support_messages;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table support_tickets;
exception when duplicate_object then null;
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- Ringkasan tiket ikut pesan terakhirnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Ditulis pemicu supaya tidak pernah ada jalan mengirim pesan tanpa
-- daftar tiketnya ikut bergerak. Daftar yang urutannya bergantung pada
-- aplikasi yang ingat memperbaruinya adalah daftar yang cepat atau
-- lambat menampilkan tiket mati di paling atas.
create or replace function touch_support_ticket()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update support_tickets
     set last_message_at = new.created_at,
         last_message_body = left(new.body, 160),
         last_message_from_admin = new.from_admin,
         updated_at = new.created_at,
         -- Pesan dari pengadu membangunkan tiket yang sedang menunggu
         -- jawabannya. Tanpa ini, tiket yang baru saja dijawab pengadu
         -- tetap berstatus "menunggu pengadu" — lalu ditutup sendiri
         -- oleh penjadwal, tepat setelah orangnya membalas.
         status = case
           when status = 'confirm_customer' and new.from_admin = false
             then 'on_progress'
           else status
         end
   where id = new.ticket_id;
  return new;
end;
$$;

drop trigger if exists trg_touch_support_ticket on support_messages;
create trigger trg_touch_support_ticket
  after insert on support_messages
  for each row execute function touch_support_ticket();

-- ─────────────────────────────────────────────────────────────────────
-- Membuat tiket
-- ─────────────────────────────────────────────────────────────────────

create or replace function open_support_ticket(
  p_subject text,
  p_body text,
  p_kind text default 'customer',
  p_resto_id text default null,
  p_name text default null,
  p_photo text default null)
returns support_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_row support_tickets;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu untuk membuat pengaduan.';
  end if;
  if btrim(coalesce(p_subject, '')) = '' then
    raise exception 'Judul pengaduannya belum diisi.';
  end if;
  if btrim(coalesce(p_body, '')) = '' then
    raise exception 'Ceritakan dulu keluhannya.';
  end if;

  insert into support_tickets (
    reporter_email, reporter_name, reporter_kind, resto_id, subject,
    reporter_read_at)
  values (
    v_email, p_name,
    case when p_kind = 'merchant' then 'merchant' else 'customer' end,
    p_resto_id, btrim(p_subject), now())
  returning * into v_row;

  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body, photo_base64)
  values (v_row.id, v_email, p_name, false, btrim(p_body), p_photo);

  select * into v_row from support_tickets where id = v_row.id;
  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Mengubah status
-- ─────────────────────────────────────────────────────────────────────
--
-- Admin boleh ke status mana pun. Pengadu hanya boleh menutup — dan itu
-- memang haknya: yang paling tahu keluhannya sudah selesai adalah orang
-- yang mengeluh.
create or replace function set_support_status(p_id uuid, p_status text)
returns support_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
  v_admin boolean := is_super_admin();
  v_row support_tickets;
  v_label text;
begin
  if v_email is null then
    raise exception 'Harus masuk dulu.';
  end if;

  select * into v_row from support_tickets where id = p_id;
  if v_row is null then
    raise exception 'Tiketnya tidak ditemukan.';
  end if;

  if not v_admin and v_row.reporter_email <> v_email then
    raise exception 'Tiket ini bukan milikmu.';
  end if;

  if not v_admin and p_status <> 'closed' then
    raise exception 'Hanya KaataGo Admin yang bisa mengubah status ini.';
  end if;

  if p_status not in ('open', 'on_progress', 'confirm_customer', 'closed') then
    raise exception 'Status tidak dikenal.';
  end if;

  if v_row.status = p_status then
    return v_row;
  end if;

  v_label := case p_status
    when 'open' then 'Dibuka'
    when 'on_progress' then 'Sedang Diproses'
    when 'confirm_customer' then 'Menunggu Konfirmasi Pelapor'
    else 'Selesai'
  end;

  update support_tickets
     set status = p_status,
         updated_at = now(),
         closed_at = case when p_status = 'closed' then now() else null end,
         closed_by = case when p_status = 'closed' then v_email else null end,
         auto_closed = false
   where id = p_id
  returning * into v_row;

  -- Perubahan status ikut jadi pesan di percakapannya.
  --
  -- Status yang cuma berubah di kepala tabel tidak pernah terbaca orang
  -- yang sedang membuka percakapannya — dan justru itu satu-satunya
  -- layar yang dia buka.
  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body, is_system)
  values (p_id, v_email, null, v_admin, 'Status diubah jadi ' || v_label, true);

  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Penanda sudah dibaca
-- ─────────────────────────────────────────────────────────────────────

create or replace function mark_support_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then return; end if;

  if is_super_admin() then
    update support_tickets set admin_read_at = now() where id = p_id;
  else
    update support_tickets set reporter_read_at = now()
     where id = p_id and reporter_email = v_email;
  end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menutup sendiri tiket yang didiamkan
-- ─────────────────────────────────────────────────────────────────────
--
-- Hanya tiket yang sedang menunggu jawaban pengadunya, dan hanya kalau
-- pesan terakhirnya memang dari admin. Tiket yang pesan terakhirnya dari
-- pengadu berarti bolanya ada di KaataGo — menutupnya karena "tidak ada
-- jawaban" akan menghukum orang yang justru sudah menjawab.
create or replace function close_idle_support_tickets()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jumlah integer := 0;
  t record;
begin
  for t in
    select id from support_tickets
    where status = 'confirm_customer'
      and last_message_from_admin = true
      and coalesce(last_message_at, updated_at) < now() - interval '24 hours'
  loop
    update support_tickets
       set status = 'closed',
           closed_at = now(),
           closed_by = null,
           auto_closed = true,
           updated_at = now()
     where id = t.id;

    insert into support_messages (
      ticket_id, sender_email, sender_name, from_admin, body, is_system)
    values (t.id, 'system', null, true,
            'Tiket ditutup otomatis karena tidak ada tanggapan selama '
            '24 jam. Buat pengaduan baru kalau masalahnya belum selesai.',
            true);

    v_jumlah := v_jumlah + 1;
  end loop;

  return v_jumlah;
end;
$$;

select cron.unschedule('close-idle-support')
where exists (select 1 from cron.job where jobname = 'close-idle-support');

-- Tiap jam. Ketepatan menitnya tidak penting — yang dijanjikan "24 jam",
-- bukan "24 jam nol menit".
select cron.schedule('close-idle-support', '0 * * * *',
  $cron$select close_idle_support_tickets();$cron$);

grant execute on function open_support_ticket(text, text, text, text, text, text)
  to authenticated;
grant execute on function set_support_status(uuid, text) to authenticated;
grant execute on function mark_support_read(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select subject, reporter_email, status, last_message_at, auto_closed
--   from support_tickets order by last_message_at desc nulls last;
--
--   select t.subject, m.from_admin, m.is_system, m.body, m.created_at
--   from support_messages m join support_tickets t on t.id = m.ticket_id
--   order by m.created_at desc limit 20;
--
--   select close_idle_support_tickets();


-- ═══════════════════════════════════════════════════════════════════
-- BAGIAN 59 — notifikasi push
-- ═══════════════════════════════════════════════════════════════════

-- KaataGo — notifikasi untuk KaataGo Support.
--
-- Jalankan SETELAH support_tickets.sql dan push_notifications.sql.
-- Aman diulang.
--
-- Penanda di dalam aplikasi hanya terlihat oleh orang yang sedang
-- membuka aplikasinya. Yang mengadu lalu menutup HP-nya — dan itulah
-- yang dilakukan hampir semua orang setelah mengadu — tidak akan pernah
-- tahu keluhannya sudah dijawab sampai ia kebetulan membuka KaataGo
-- lagi. Balasan yang tidak sampai sama saja dengan tidak dibalas.

-- Satu pemicu untuk kedua arah.
--
-- Perubahan status pun ikut lewat sini, karena `set_support_status`
-- menuliskannya sebagai pesan sistem. Menambah pemicu terpisah di tabel
-- tiket berarti dua tempat yang harus sepakat soal siapa yang dikabari
-- — dan yang kedua akan tertinggal.
create or replace function queue_push_support()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  t support_tickets;
  v_nama text;
  v_cuplikan text;
begin
  select * into t from support_tickets where id = new.ticket_id;
  if t is null then return new; end if;

  -- Isi pesannya dipotong, bukan dikirim utuh. Notifikasi Android
  -- memotongnya sendiri di tengah kata, dan pengaduan yang panjang jadi
  -- terbaca setengah kalimat tanpa ujung.
  v_cuplikan := left(regexp_replace(new.body, E'[\n\r]+', ' ', 'g'), 90);

  if new.from_admin then
    -- Ke pelapor. Tepat satu orang, jadi audiensnya email.
    insert into push_outbox (resto_id, event, payload) values (
      t.resto_id, 'support_message',
      jsonb_build_object(
        'audience', 'email',
        'email', t.reporter_email,
        'ticket_id', t.id::text,
        'title', 'KaataGo Support — ' || t.subject,
        'body', v_cuplikan
      )
    );
  else
    v_nama := coalesce(nullif(btrim(coalesce(t.reporter_name, '')), ''),
                       split_part(t.reporter_email, '@', 1));

    -- Ke KaataGo Admin. `resto_id` sengaja null: KaataGo Admin tidak
    -- terikat merchant mana pun, dan menyaring peran berdasarkan resto
    -- akan membuat kabarnya tidak sampai ke siapa pun.
    insert into push_outbox (resto_id, event, payload) values (
      null, 'support_message',
      jsonb_build_object(
        'audience', 'role',
        'roles', jsonb_build_array('super_admin'),
        'ticket_id', t.id::text,
        'title', 'Pengaduan dari ' || v_nama,
        'body', v_cuplikan
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_queue_push_support on support_messages;
create trigger trg_queue_push_support
  after insert on support_messages
  for each row execute function queue_push_support();

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select event, payload ->> 'title', payload ->> 'audience',
--          payload ->> 'ticket_id', sent_at, error
--   from push_outbox where event = 'support_message'
--   order by created_at desc limit 10;
--
--   -- Yang gagal terkirim menyisakan `error`; yang belum terkirim
--   -- menyisakan sent_at kosong.
