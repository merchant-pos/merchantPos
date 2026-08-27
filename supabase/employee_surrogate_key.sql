-- KaataGo — email karyawan jadi bisa diubah.
--
-- Jalankan SETELAH owner_multi_resto.sql. Aman dijalankan berulang kali.
--
-- Selama ini baris karyawan dikenali dari emailnya sendiri, jadi
-- mengubah email berarti mengubah identitas barisnya — yang bukan
-- "mengubah", melainkan membuat orang baru dan meninggalkan yang lama.
-- Karena itu kolomnya dikunci di layar admin.
--
-- Sekarang barisnya punya id sendiri yang tidak berarti apa-apa selain
-- "baris ini". Email kembali menjadi data biasa: boleh salah ketik saat
-- didaftarkan, boleh diperbaiki nanti, tanpa kehilangan riwayat apa pun
-- yang menempel pada baris itu.

begin;

-- Kolom baru terisi otomatis untuk baris yang sudah ada, karena
-- defaultnya dihitung per baris saat kolomnya ditambahkan.
alter table employees add column if not exists id uuid not null default gen_random_uuid();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'employees'::regclass and contype = 'p'
  ) then
    alter table employees add constraint employees_pkey primary key (id);
  end if;
end $$;

-- Pasangan (email, resto_id) tetap unik: satu orang tetap tidak boleh
-- terdaftar dua kali di resto yang sama. Yang berubah hanya soal apa
-- yang menjadi identitas barisnya.
do $$
begin
  begin
    create unique index if not exists employees_email_resto_uidx
      on employees (email, resto_id) nulls not distinct;
  exception when syntax_error or feature_not_supported then
    create unique index if not exists employees_email_resto_uidx
      on employees (email, resto_id);
  end;
end $$;

commit;
