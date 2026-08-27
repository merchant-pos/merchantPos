-- KaataGo — pengumuman ikut membunyikan HP.
--
-- Selama ini pengumuman hanya duduk di Kotak Masuk. Kotak Masuk baru
-- dilihat orang kalau dia membuka aplikasinya, dan orang membuka
-- aplikasinya kalau ada yang memanggil. Pengumuman yang menunggu
-- dibuka adalah pengumuman yang dibaca seminggu kemudian — atau tidak
-- sama sekali.
--
-- Jangkauannya mengikuti resto_id pengumuman itu sendiri, aturan yang
-- sama dengan yang sudah dipakai saat menampilkannya:
--   resto_id kosong  → dari Super Admin, kabar versi baru, untuk semua
--   resto_id terisi  → dari admin resto itu, hanya perangkat restonya
--                      — pelanggan maupun karyawan, apa pun perannya.
--
-- Jalankan di SQL Editor Supabase.

begin;

create or replace function queue_push_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into push_outbox (resto_id, event, payload) values (
    new.resto_id, 'announcement',
    jsonb_build_object(
      'audience', 'all',
      'title', new.title,
      -- Isi pengumuman bisa sepanjang apa pun; baris notifikasi tidak.
      -- Dipotong di sini supaya yang sampai di layar kunci adalah
      -- kalimat pembuka yang utuh, bukan paragraf yang dipenggal
      -- Android di tempat sembarang.
      'body', case
                when length(new.body) > 160
                  then left(new.body, 157) || '...'
                else new.body
              end
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_queue_push_announcement on app_announcements;
create trigger trg_queue_push_announcement
  after insert on app_announcements
  for each row execute function queue_push_announcement();

commit;
