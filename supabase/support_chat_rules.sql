-- KaataGo — chat bebas bukan pengaduan, dan tiket kembar tidak lahir
-- dua kali.
--
-- Jalankan SETELAH support_auto_reply.sql. Aman diulang.

-- ─────────────────────────────────────────────────────────────────────
-- Tiket kembar
-- ─────────────────────────────────────────────────────────────────────
--
-- Dua ketukan cepat pada tombol Kirim melahirkan dua tiket berisi
-- kalimat yang sama persis. Aplikasi sudah menjaganya sejak 2.16.0, tapi
-- penjaga yang hanya ada di aplikasi bukan penjaga: HP yang belum
-- diperbarui, permintaan yang diulang jaringan, atau proses yang mati
-- lalu dicoba lagi semuanya lolos begitu saja.
--
-- Penjaganya di sini: pengaduan dengan judul dan isi yang sama, dari
-- orang yang sama, dalam sepuluh detik terakhir, dianggap satu — dan
-- yang kedua mengembalikan tiket yang pertama alih-alih membuat yang
-- baru.
--
-- Sepuluh detik, bukan satu jam. Yang benar-benar mengirim dua keluhan
-- serupa berjarak semenit sedang menambahkan sesuatu, bukan salah
-- pencet.
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

  -- Kembar yang baru saja lahir.
  select t.* into v_row
  from support_tickets t
  join support_messages m on m.ticket_id = t.id
  where t.reporter_email = v_email
    and t.subject = btrim(p_subject)
    and t.created_at > now() - interval '10 seconds'
    and m.from_admin = false
    and m.body = btrim(p_body)
  order by t.created_at desc
  limit 1;

  if v_row.id is not null then
    return v_row;
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

  v_sebutan := case
    when btrim(p_subject) = 'Chat dengan KaataGo Admin' then 'chat'
    else 'pengaduan'
  end;

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
-- Chat tidak pernah ditutup sendiri
-- ─────────────────────────────────────────────────────────────────────
--
-- Percakapan bebas tidak punya tahapan dan tidak menuntut keputusan
-- siapa pun. Menutupnya karena "tidak ada tanggapan selama 24 jam"
-- adalah menutup obrolan yang memang sudah selesai dengan sendirinya —
-- lalu memaksa orangnya membuka percakapan baru hanya untuk bertanya
-- lagi besok.
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
      and subject <> 'Chat dengan KaataGo Admin'
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

-- ─────────────────────────────────────────────────────────────────────
-- Membersihkan tiket kembar yang terlanjur lahir
-- ─────────────────────────────────────────────────────────────────────
--
-- Yang dibuang hanya yang benar-benar kembar: judul, pelapor, dan isi
-- pesan pertamanya sama, lahir dalam menit yang sama, dan BELUM pernah
-- dibalas manusia. Yang sudah ada percakapannya tidak disentuh —
-- menghapus percakapan yang sudah dijawab jauh lebih merugikan daripada
-- menyisakan satu baris kembar.
with kembar as (
  select t.id,
         row_number() over (
           partition by t.reporter_email, t.subject,
                        date_trunc('minute', t.created_at)
           order by t.created_at
         ) as urutan
  from support_tickets t
  where not exists (
    select 1 from support_messages m
    where m.ticket_id = t.id
      and m.from_admin = true
      and m.sender_email <> 'system:greeting'
  )
)
delete from support_tickets
where id in (select id from kembar where urutan > 1);

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select subject, count(*) from support_tickets
--   group by subject order by 2 desc;
--
--   -- Satu tiket harus berisi dua pesan saja saat baru dibuat:
--   select t.subject, count(m.id)
--   from support_tickets t join support_messages m on m.ticket_id = t.id
--   group by t.id, t.subject order by t.created_at desc limit 5;
