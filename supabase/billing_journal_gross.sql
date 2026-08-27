-- KaataGo — pendapatan langganan dicatat sebesar harga penuh.
--
-- Jalankan SETELAH billing_discount_apply.sql. Aman diulang.
--
-- ── Kesalahannya ─────────────────────────────────────────────────────
--
-- Pemicu jurnal mengkredit `amount`, yaitu nominal yang SUDAH dipotong
-- diskon, lalu mendebit diskonnya sekali lagi. Untuk tagihan 230.000
-- dengan diskon 50%, jurnalnya jadi:
--
--     kredit  Pendapatan Langganan   115.000
--     debit   Diskon Langganan       115.000
--     ────────────────────────────────────── +
--     bersih                               0
--
-- Padahal uang yang benar-benar masuk 115.000. Diskonnya terhitung dua
-- kali: sekali dengan mengecilkan pendapatannya, sekali lagi sebagai
-- debit tersendiri.
--
-- Yang benar: pendapatan dicatat sebesar harga daftarnya, dan diskon
-- menguranginya.
--
--     kredit  Pendapatan Langganan   230.000
--     debit   Diskon Langganan       115.000
--     ────────────────────────────────────── +
--     bersih                          115.000
--
-- Bukan sekadar supaya angka bersihnya benar. Dengan cara ini, "berapa
-- harga daftar yang kita jual" dan "berapa yang kita berikan sebagai
-- potongan" jadi dua angka yang bisa dibaca terpisah — dan pertanyaan
-- "berapa besar diskon kita tahun ini" punya jawabannya sendiri, bukan
-- angka yang harus dikira-kira dari selisih.

begin;

create or replace function log_billing_journal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gl record;
  v_now timestamptz := now();
  v_resto text;
  v_gross bigint;
begin
  if new.status <> 'paid' then
    return new;
  end if;

  if exists (
    select 1 from gl_journal_entries
    where reference_type = 'billing' and reference_id = new.id
  ) then
    return new;
  end if;

  select name into v_resto from restaurants where id = new.resto_id;

  -- Harga daftarnya. Tagihan lama yang terbit sebelum kolom diskon ada
  -- tidak punya gross_amount — untuk mereka, nominalnya sendiri memang
  -- harga penuhnya.
  v_gross := coalesce(new.gross_amount, new.amount);

  select * into v_gl from _gl_account_for('kaatago', 'subscription');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      'kaatago',
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'billing', new.id, v_gross, 'credit',
      'Langganan ' || coalesce(v_resto, new.resto_id) || ' — ' || new.id
    );
  end if;

  if coalesce(new.discount_amount, 0) > 0 then
    select * into v_gl from _gl_account_for('kaatago', 'subscription_discount');
    if v_gl.gl_code is not null and v_gl.gl_code <> '' then
      insert into gl_journal_entries (
        resto_id, entry_date, entry_time, gl_code, gl_name,
        reference_type, reference_id, amount, entry_type, description
      ) values (
        'kaatago',
        (v_now at time zone 'Asia/Jakarta')::date,
        (v_now at time zone 'Asia/Jakarta')::time,
        v_gl.gl_code, v_gl.gl_name,
        'billing_discount', new.id, new.discount_amount, 'debit',
        coalesce(nullif(new.discount_name, ''), 'Diskon langganan')
          || ' — ' || coalesce(v_resto, new.resto_id)
      );
    end if;
  end if;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Memperbaiki jurnal yang sudah terlanjur salah
-- ─────────────────────────────────────────────────────────────────────
--
-- Barisnya TIDAK diubah dan TIDAK dihapus. Jurnal hanya bertambah —
-- aturan yang sama dengan pembalikan pengeluaran, dan alasannya sama:
-- pembukuan yang barisnya bisa disunting belakangan tidak bisa dipakai
-- membuktikan apa pun.
--
-- Yang ditambahkan adalah selisihnya, sebagai baris koreksi tersendiri
-- yang menyebut dirinya koreksi. Orang yang membacanya enam bulan lagi
-- akan melihat kesalahannya sekaligus perbaikannya, bukan pembukuan yang
-- terlihat selalu benar.

insert into gl_journal_entries (
  resto_id, entry_date, entry_time, gl_code, gl_name,
  reference_type, reference_id, amount, entry_type, description
)
select
  'kaatago',
  (now() at time zone 'Asia/Jakarta')::date,
  (now() at time zone 'Asia/Jakarta')::time,
  j.gl_code, j.gl_name,
  'billing', i.id,
  i.gross_amount - i.amount, 'credit',
  'Koreksi pencatatan diskon — ' || i.id
    || ' (pendapatan semula dicatat sesudah potongan)'
from billing_invoices i
join gl_journal_entries j
  on j.reference_type = 'billing'
 and j.reference_id = i.id
 and j.entry_type = 'credit'
where i.gross_amount is not null
  and i.gross_amount > i.amount
  and j.amount = i.amount
  and not exists (
    select 1 from gl_journal_entries k
    where k.reference_type = 'billing'
      and k.reference_id = i.id
      and k.description like 'Koreksi pencatatan diskon%'
  );

commit;
