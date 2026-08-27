-- KaataGo — pendaftaran token push lewat fungsi, bukan tulis langsung.
--
-- Jalankan SETELAH push_notifications.sql. Aman dijalankan berulang kali.
--
-- Gejalanya: aplikasi mendapat token FCM, tapi menyimpannya ditolak
-- dengan 42501 "new row violates row-level security policy for table
-- device_tokens" — padahal kebijakan INSERT-nya berbunyi `with check
-- (true)`, yang secara logika tidak mungkin gagal.
--
-- Sebabnya bukan kebijakan INSERT-nya. Pendaftarannya berupa upsert,
-- dan `insert ... on conflict do update` mengharuskan Postgres MEMBACA
-- baris yang bentrok lebih dulu — jadi butuh kebijakan SELECT. Tabel ini
-- sengaja dibuat tanpa kebijakan SELECT, karena daftar token tidak perlu
-- terbaca aplikasi. Niatnya benar, akibatnya upsert-nya mustahil lolos.
--
-- Menambahkan kebijakan SELECT akan membuka seluruh daftar token —
-- berikut email karyawan dan resto tempatnya bekerja — kepada siapa pun
-- yang punya anon key, dan kunci itu memang tertanam di dalam APK.
--
-- Jalan keluarnya membalik arah: tabelnya ditutup rapat dari aplikasi,
-- dan pendaftarannya lewat satu fungsi SECURITY DEFINER yang tugasnya
-- cuma itu. Aplikasi tidak lagi bisa membaca, mengubah, atau menghapus
-- baris mana pun — dia hanya bisa menitipkan tokennya sendiri.

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Tutup akses langsung
-- ─────────────────────────────────────────────────────────────────────
alter table device_tokens enable row level security;

drop policy if exists "device_tokens: public upsert" on device_tokens;
drop policy if exists "device_tokens: update own" on device_tokens;
drop policy if exists "device_tokens: delete own" on device_tokens;
drop policy if exists "device_tokens: insert" on device_tokens;
drop policy if exists "device_tokens: update" on device_tokens;
drop policy if exists "device_tokens: delete" on device_tokens;

revoke all on table device_tokens from anon, authenticated;

-- Tanpa kebijakan apa pun dan tanpa hak akses, tabel ini tidak bisa
-- disentuh dari aplikasi sama sekali. Yang menyentuhnya cuma fungsi di
-- bawah dan Edge Function (service role).

-- ─────────────────────────────────────────────────────────────────────
-- 2. Satu-satunya pintu masuk
-- ─────────────────────────────────────────────────────────────────────

create or replace function register_device_token(
  p_token text,
  p_email text default null,
  p_resto_id text default null,
  p_role text default null,
  p_session_id text default null,
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return;
  end if;

  insert into device_tokens (
    token, email, resto_id, role, session_id, platform, updated_at
  ) values (
    p_token, p_email, p_resto_id, p_role, p_session_id, p_platform, now()
  )
  on conflict (token) do update set
    -- Seluruh kolom ditimpa, bukan digabung. Satu HP bisa berpindah
    -- tangan antar shift, dan pemilik lama yang tertinggal di barisnya
    -- berarti kasir yang sudah logout tetap menerima kabar setoran
    -- penggantinya.
    email = excluded.email,
    resto_id = excluded.resto_id,
    role = excluded.role,
    session_id = excluded.session_id,
    platform = excluded.platform,
    updated_at = now();
end;
$$;

create or replace function unregister_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from device_tokens where token = p_token;
end;
$$;

-- Tamu memakai anon, karyawan yang login memakai authenticated —
-- keduanya harus bisa mendaftarkan perangkatnya.
grant execute on function register_device_token(text, text, text, text, text, text)
  to anon, authenticated;
grant execute on function unregister_device_token(text) to anon, authenticated;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memastikan
-- ─────────────────────────────────────────────────────────────────────
-- Setelah berkas ini jalan, aplikasi versi 1.37.0 ke atas akan memakai
-- fungsi di atas. Buka Tes Notifikasi di HP; barisnya harus berbunyi
-- "Push aktif". Lalu:
--
--   select email, role, resto_id, platform, updated_at
--   from device_tokens order by updated_at desc;
