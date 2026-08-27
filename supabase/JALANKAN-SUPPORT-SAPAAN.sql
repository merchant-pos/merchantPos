-- KaataGo — bagian 60: sapaan otomatis KaataGo Support.
-- Jalankan SETELAH bagian 58 dan 59. Aman diulang.

-- KaataGo — sapaan otomatis, dan penanda belum dibaca yang tahan
-- terhadapnya.
--
-- Jalankan SETELAH support_tickets.sql. Aman diulang.
--
-- Yang baru mengadu tidak tahu pengaduannya sampai atau tidak. Layar
-- yang diam sesudah tombol kirim ditekan terbaca sebagai "hilang", dan
-- yang merasa keluhannya hilang akan mengirimkannya lagi — atau berhenti
-- memakai aplikasinya sama sekali.
--
-- Tapi sapaan itu tidak boleh membuat tiketnya terlihat sudah dijawab.
-- Di sisi KaataGo Admin ia harus tetap berdiri sebagai pengaduan yang
-- belum dibaca, karena memang belum ada manusia yang membacanya.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- Dua stempel waktu, bukan satu
-- ─────────────────────────────────────────────────────────────────────
--
-- Penanda belum dibaca semula disimpulkan dari `last_message_from_admin`:
-- ada kabar baru untuk admin kalau pesan terakhir BUKAN dari admin.
-- Cara itu runtuh begitu ada sapaan otomatis — pesan terakhirnya jadi
-- "dari admin", dan pengaduan yang belum dibaca siapa pun langsung
-- terlihat beres.
--
-- Yang benar: catat kapan masing-masing pihak terakhir bicara, lalu
-- bandingkan dengan kapan lawan bicaranya terakhir membaca. Dua
-- pertanyaan yang berbeda tidak bisa dijawab satu kolom.
alter table support_tickets
  add column if not exists last_reporter_at timestamptz,
  add column if not exists last_admin_at timestamptz;

-- Baris lama diisi dari percakapannya sendiri.
update support_tickets t
   set last_reporter_at = (
         select max(m.created_at) from support_messages m
         where m.ticket_id = t.id and m.from_admin = false),
       last_admin_at = (
         select max(m.created_at) from support_messages m
         where m.ticket_id = t.id and m.from_admin = true)
 where t.last_reporter_at is null and t.last_admin_at is null;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Ringkasan tiket
-- ─────────────────────────────────────────────────────────────────────

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
         last_reporter_at = case
           when new.from_admin then last_reporter_at else new.created_at end,
         last_admin_at = case
           when new.from_admin then new.created_at else last_admin_at end,
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

-- ─────────────────────────────────────────────────────────────────────
-- Membuka tiket, berikut sapaannya
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
  v_nama text;
  v_sebutan text;
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

  v_nama := coalesce(nullif(btrim(coalesce(p_name, '')), ''),
                     split_part(v_email, '@', 1));

  -- Percakapan bebas disebut "chat", pengaduan disebut "pengaduan".
  -- Judulnya harus sama persis dengan `kSubjekChatUmum` di aplikasi;
  -- ada tes yang menjaga keduanya tidak berpisah.
  v_sebutan := case
    when btrim(p_subject) = 'Chat dengan KaataGo Admin' then 'chat'
    else 'pengaduan'
  end;

  -- Sapaannya dikirim sebagai pesan biasa dari admin, bukan pesan
  -- sistem: yang membacanya harus merasa disambut orang, bukan dibalas
  -- mesin.
  --
  -- Emailnya 'system:greeting' — dipakai pemicu notifikasi untuk
  -- melewatinya. Orang yang baru saja menekan kirim sedang menatap
  -- layarnya; membunyikan HP-nya detik itu juga bukan kabar, cuma
  -- kebisingan.
  insert into support_messages (
    ticket_id, sender_email, sender_name, from_admin, body)
  values (
    v_row.id, 'system:greeting', null, true,
    'Halo ' || v_nama || ', mohon bersabar KaataGo Admin akan meresponse '
      || v_sebutan || ' secepatnya, terimakasih sudah berkenan menunggu.');

  select * into v_row from support_tickets where id = v_row.id;
  return v_row;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Notifikasi melewati sapaannya
-- ─────────────────────────────────────────────────────────────────────

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
  v_admin record;
begin
  -- Sapaan otomatis tidak dikabarkan. Lihat catatan di
  -- open_support_ticket.
  if new.sender_email = 'system:greeting' then
    return new;
  end if;

  select * into t from support_tickets where id = new.ticket_id;
  if t is null then return new; end if;

  v_cuplikan := left(regexp_replace(new.body, E'[\n\r]+', ' ', 'g'), 90);

  if new.from_admin then
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

    for v_admin in
      select distinct e.email
      from employees e
      where e.role = 'super_admin'
        and coalesce(e.active, true) = true
        and e.email is not null
    loop
      insert into push_outbox (resto_id, event, payload) values (
        null, 'support_message',
        jsonb_build_object(
          'audience', 'email',
          'email', v_admin.email,
          'ticket_id', t.id::text,
          'title', 'Pengaduan dari ' || v_nama,
          'body', v_cuplikan
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   -- Tiket baru harus punya dua pesan: keluhannya, lalu sapaannya —
--   -- dan `last_reporter_at` tetap terisi walau pesan terakhirnya dari
--   -- admin.
--   select subject, last_reporter_at, last_admin_at, admin_read_at,
--          last_message_from_admin
--   from support_tickets order by created_at desc limit 3;
--
--   -- Sapaannya tidak boleh melahirkan baris push:
--   select count(*) from push_outbox
--   where payload ->> 'body' like 'Halo %mohon bersabar%';
