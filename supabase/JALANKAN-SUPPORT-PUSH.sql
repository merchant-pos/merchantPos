-- KaataGo — perbaikan bagian 59: pengaduan baru disasar lewat email
-- KaataGo Admin, bukan perannya.
--
-- Jalankan lagi walau bagian 59 sudah pernah dijalankan. Aman diulang.

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
  v_admin record;
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

    -- Ke KaataGo Admin, satu baris per orang, disasar lewat emailnya.
    --
    -- Sempat memakai audiens 'role' dengan peran super_admin, dan itu
    -- gagal dengan "tidak ada perangkat terdaftar": baris token hanya
    -- punya peran kalau perangkatnya mendaftar setelah orangnya masuk
    -- sebagai KaataGo Admin. Satu perangkat yang pernah dipakai masuk
    -- sebagai peran lain, atau yang barisnya ditulis versi lama, tidak
    -- akan pernah terjaring.
    --
    -- Emailnya jauh lebih tahan: ia ditulis di setiap pendaftaran token,
    -- apa pun peran yang sedang dipegang saat itu.
    --
    -- Konsekuensinya satu baris outbox per admin, bukan satu untuk
    -- semuanya. Jumlah KaataGo Admin dihitung jari, dan kabar yang
    -- sampai lebih berharga daripada satu baris yang rapi.
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
