-- KaataGo — pengumuman resto memilih sasarannya: karyawan, pelanggan,
-- atau keduanya.
--
-- Jalankan SETELAH announcement_categories.sql dan announcement_push.sql.
-- Aman dijalankan berulang kali.
--
-- Sebelumnya satu pengumuman resto pergi ke semua orang yang terkait
-- resto itu. Dua kebutuhan yang sangat berbeda terpaksa memakai jalur
-- yang sama: promo yang justru harus dibaca pelanggan, dan pengumuman
-- internal — jadwal shift, rapat, aturan baru dapur — yang tidak ada
-- urusannya dengan pelanggan dan sering tidak pantas dibaca mereka.
--
-- Tanpa pilihan, yang terjadi bisa ditebak: pengumuman internal berhenti
-- ditulis di sini dan pindah ke grup chat, lalu kotak masuknya kosong
-- dan tidak ada yang membukanya lagi.

begin;

alter table app_announcements
  add column if not exists audience text not null default 'all';

alter table app_announcements drop constraint if exists app_announcements_audience_check;
alter table app_announcements add constraint app_announcements_audience_check
  check (audience in ('employees', 'customers', 'all'));

-- Pengumuman lama tetap 'all' — itu memang perilakunya selama ini, dan
-- mengubahnya surut berarti menyembunyikan kabar yang sudah terlanjur
-- dibaca sebagian orang.

-- ─────────────────────────────────────────────────────────────────────
-- Notifikasinya ikut menyempit
-- ─────────────────────────────────────────────────────────────────────
--
-- Sasaran yang dipilih dititipkan ke antrean push, supaya Edge Function
-- tidak perlu membaca ulang barisnya. Nama audience-nya sendiri
-- ('all') sengaja tidak dipakai ulang untuk ini — itu jenis penerima
-- di antrean push, bukan sasaran pengumuman.
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
      'target', coalesce(new.audience, 'all'),
      'title', new.title,
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
