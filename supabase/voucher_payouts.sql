-- KaataGo — voucher yang dipakai pelanggan dibayarkan sungguhan ke resto.
--
-- Jalankan SETELAH vouchers.sql dan resto_payment_accounts.sql.
-- Aman dijalankan berulang kali.
--
-- Sampai sekarang tahap ketiga voucher hanya berupa jurnal: GL Voucher
-- Redeem didebit, GL Transfer restonya dikredit. Pembukuannya benar,
-- tapi tidak ada satu rupiah pun yang berpindah. Resto menyerahkan
-- makanan seharga seratus ribu, menerima nol dari pelanggan, dan yang
-- didapatnya cuma satu baris di layar.
--
-- Berkas ini yang membuat barisnya diikuti uang.
--
-- ── Kenapa transfer antar-akun, bukan pencairan ke rekening ──────────
--
-- Xendit punya dua cara mengirim uang keluar. Pencairan (disbursement)
-- menembak nomor rekening bank langsung — dan untuk itu kita harus
-- menyimpan nomor rekening tiap resto. Kita sengaja tidak menyimpannya
-- (lihat resto_payment_accounts.sql): data rekening milik orang lain
-- yang kita tampung adalah kerugian yang bukan milik kita tapi kita
-- yang menyebabkannya kalau bocor.
--
-- Transfer antar-akun memindahkan saldo dari akun KaataGo ke sub-akun
-- restonya di dalam xenPlatform. Tujuannya cukup disebut dengan
-- pengenal sub-akun yang memang sudah kita simpan. Dari sana dananya
-- ikut jadwal pencairan resto itu sendiri, ke rekening yang mereka
-- daftarkan sendiri, yang tidak pernah kita lihat.
--
-- ── Kenapa antrean, bukan panggilan langsung dari pemicu ─────────────
--
-- Pemicu berjalan di dalam transaksi yang menyimpan pesanan. Memanggil
-- Xendit dari sana berarti pesanan pelanggan gagal tersimpan setiap
-- kali Xendit lambat atau mati — pelanggan yang sudah antre di kasir
-- menanggung akibat dari gangguan pihak ketiga. Dan kalau panggilannya
-- terlanjur sampai lalu transaksinya dibatalkan, uangnya sudah pindah
-- untuk pesanan yang tidak pernah ada.
--
-- Jadi pemicunya cuma menulis satu baris "harus dibayar". Yang
-- membayarnya berjalan belakangan, boleh gagal, dan boleh diulang.

begin;

create table if not exists voucher_payouts (
  id uuid primary key default gen_random_uuid(),

  -- Satu klaim satu pencairan. Ini batasan basis data, bukan
  -- pemeriksaan di kode: penjadwal yang berjalan dua kali, atau
  -- pemicu yang entah bagaimana menyala dua kali, tidak boleh bisa
  -- membayar voucher yang sama dua kali.
  claim_id text not null unique references voucher_claims (id) on delete cascade,

  resto_id text not null references restaurants (id) on delete cascade,
  order_id uuid,
  amount bigint not null check (amount > 0),

  -- pending → sent, atau pending → failed lalu dicoba lagi.
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed')),

  -- Yang dikembalikan Xendit, supaya baris ini bisa dicocokkan dengan
  -- mutasi di dashboard mereka tanpa menebak-nebak.
  transfer_id text,

  -- Alasan gagalnya, apa adanya dari penyedia. Disimpan supaya yang
  -- memeriksa besok pagi tidak perlu membuka log fungsi edge.
  last_error text,
  attempts integer not null default 0,

  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists voucher_payouts_pending_idx
  on voucher_payouts (created_at) where status <> 'sent';

create index if not exists voucher_payouts_resto_idx
  on voucher_payouts (resto_id, created_at desc);

alter table voucher_payouts enable row level security;

-- Resto boleh melihat yang jadi haknya; Super Admin melihat semuanya.
drop policy if exists "voucher_payouts: read" on voucher_payouts;
create policy "voucher_payouts: read" on voucher_payouts
  for select using (
    is_super_admin() or is_resto_employee(resto_id, array['finance', 'owner', 'admin'])
  );

-- Tidak ada kebijakan tulis untuk siapa pun. Yang menulis ke sini
-- adalah pemicu pemakaian voucher dan fungsi pencairannya, keduanya
-- SECURITY DEFINER. Tangan yang bisa menulis langsung ke tabel ini
-- adalah tangan yang bisa memerintahkan uang sungguhan berpindah.

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Pemicunya sekarang juga mengantre pencairan
-- ─────────────────────────────────────────────────────────────────────

create or replace function log_voucher_use()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim voucher_claims;
  v_gl record;
  v_now timestamptz := now();
  v_ref text := upper(substr(new.id::text, 1, 8));
begin
  if new.voucher_claim_id is null or coalesce(new.voucher_amount, 0) <= 0 then
    return new;
  end if;

  select * into v_claim from voucher_claims where id = new.voucher_claim_id;
  if v_claim.id is null or v_claim.status <> 'claimed' then
    return new;
  end if;

  update voucher_claims
  set status = 'used', order_id = new.id, resto_id = new.resto_id,
      used_at = v_now
  where id = v_claim.id;

  -- Uangnya keluar dari kantong voucher yang sudah ditebus.
  perform _jurnal_kaatago('voucher_redeem', v_claim.id, new.voucher_amount,
    'debit', 'Voucher dipakai di pesanan #' || v_ref);

  -- Dan masuk ke resto: bagi mereka ini uang masuk, bukan pendapatan
  -- yang hilang. Restonya tidak menanggung promo yang tidak dia buat.
  select * into v_gl from _gl_account_for(new.resto_id, 'transfer');
  if v_gl.gl_code is not null and v_gl.gl_code <> '' then
    insert into gl_journal_entries (
      resto_id, entry_date, entry_time, gl_code, gl_name,
      reference_type, reference_id, amount, entry_type, description
    ) values (
      new.resto_id,
      (v_now at time zone 'Asia/Jakarta')::date,
      (v_now at time zone 'Asia/Jakarta')::time,
      v_gl.gl_code, v_gl.gl_name,
      'voucher', v_claim.id, new.voucher_amount, 'credit',
      'Voucher KaataGo ' || coalesce(new.voucher_code, '') ||
        ' — pesanan #' || v_ref
    );
  end if;

  -- Uang sungguhannya menyusul. Baris ini yang membuat jurnal di atas
  -- bukan sekadar janji.
  insert into voucher_payouts (claim_id, resto_id, order_id, amount)
  values (v_claim.id, new.resto_id, new.id, new.voucher_amount)
  on conflict (claim_id) do nothing;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Yang dibaca dan ditulis fungsi pencairannya
-- ─────────────────────────────────────────────────────────────────────

-- Antrean yang siap dibayar, lengkap dengan tujuannya.
--
-- Resto yang belum punya sub-akun aktif tidak ikut terangkut: tidak
-- ada tujuan untuk dikirimi, dan mencobanya cuma menaikkan `attempts`
-- sampai barisnya terlihat seperti gangguan Xendit padahal yang kurang
-- ada di sisi kita.
-- Tipe kembaliannya pernah salah menyebut claim_id sebagai uuid.
-- `create or replace` tidak bisa mengubah tipe kembalian, jadi yang
-- lama harus dibuang dulu — di basis data yang belum pernah
-- menjalankannya, baris ini tidak melakukan apa-apa.
drop function if exists voucher_payouts_due(integer);

create or replace function voucher_payouts_due(p_limit integer default 50)
returns table (
  payout_id uuid,
  claim_id text,
  resto_id text,
  resto_name text,
  account_id text,
  amount bigint
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.claim_id, p.resto_id, r.name, a.account_id, p.amount
  from voucher_payouts p
  join resto_payment_accounts a
    on a.resto_id = p.resto_id and a.active and a.account_id <> ''
  left join restaurants r on r.id = p.resto_id
  where p.status <> 'sent'
  order by p.created_at
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

revoke all on function voucher_payouts_due(integer) from public, anon, authenticated;

-- Menandai hasilnya. Hanya menambah dan menandai — tidak pernah
-- menghapus barisnya, karena baris pencairan yang hilang adalah uang
-- yang berpindah tanpa jejak.
create or replace function mark_voucher_payout(
  p_payout_id uuid,
  p_ok boolean,
  p_transfer_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update voucher_payouts
  set status      = case when p_ok then 'sent' else 'failed' end,
      transfer_id = coalesce(p_transfer_id, transfer_id),
      last_error  = case when p_ok then null else p_error end,
      attempts    = attempts + 1,
      sent_at     = case when p_ok then now() else sent_at end
  where id = p_payout_id
    and status <> 'sent';   -- yang sudah terkirim tidak bisa dibatalkan
end;
$$;

revoke all on function mark_voucher_payout(uuid, boolean, text, text) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- Mengantre yang sudah terlanjur dipakai sebelum berkas ini ada
-- ─────────────────────────────────────────────────────────────────────
--
-- Voucher yang sudah dipakai kemarin tetap utang yang belum dibayar.
-- Tanggal berkas ini dijalankan bukan garis pemisah antara utang dan
-- bukan utang.

insert into voucher_payouts (claim_id, resto_id, order_id, amount)
select c.id, c.resto_id, c.order_id, c.amount
from voucher_claims c
where c.status = 'used' and c.resto_id is not null and c.amount > 0
on conflict (claim_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────
-- Penjadwalnya
-- ─────────────────────────────────────────────────────────────────────
--
-- Antrean yang tidak pernah dijalankan sama saja dengan tidak ada.
-- Tapi alamat fungsi dan kuncinya berbeda antara proyek uji dan
-- produksi, jadi berkas ini tidak menebaknya — selama barisnya belum
-- diisi, penjadwalnya berjalan dan tidak melakukan apa-apa.

create table if not exists voucher_payout_config (
  id integer primary key default 1 check (id = 1),
  function_url text,
  service_key text,
  updated_at timestamptz not null default now()
);

insert into voucher_payout_config (id) values (1) on conflict (id) do nothing;

alter table voucher_payout_config enable row level security;
-- Tidak ada kebijakan apa pun: isinya kunci layanan, dan tidak ada
-- peran di aplikasi yang punya alasan membacanya.

create or replace function run_voucher_payouts()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cfg voucher_payout_config;
begin
  select * into v_cfg from voucher_payout_config where id = 1;
  if v_cfg.function_url is null or v_cfg.service_key is null then
    return;
  end if;

  perform net.http_post(
    url := v_cfg.function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_cfg.service_key
    ),
    body := jsonb_build_object('limit', 50)
  );
end;
$$;

revoke all on function run_voucher_payouts() from public, anon, authenticated;

-- Tiap 15 menit. Resto tidak perlu menunggu semalam untuk menerima
-- uang yang sudah jadi haknya sejak pesanannya selesai.
select cron.unschedule('settle-voucher-payouts')
where exists (select 1 from cron.job where jobname = 'settle-voucher-payouts');

select cron.schedule('settle-voucher-payouts', '*/15 * * * *',
  $cron$select run_voucher_payouts();$cron$);

-- ─────────────────────────────────────────────────────────────────────
-- Setelah menjalankan ini
-- ─────────────────────────────────────────────────────────────────────
--
-- 1. Deploy fungsinya:
--
--      supabase functions deploy settle-voucher-payouts \
--        --project-ref xizpwtycczigjhzxegen
--
-- 2. Isi secret pengenal akun KaataGo sendiri di Xendit — transfer
--    butuh tahu dari akun mana uangnya diambil:
--
--      supabase secrets set XENDIT_ACCOUNT_ID=...
--
--    Nomornya ada di Dashboard Xendit → Settings → Developers, atau:
--
--      curl https://api.xendit.co/balance -u 'xnd_...:' -v
--
-- 3. Isi alamat fungsi dan kunci layanan supaya penjadwalnya hidup:
--
--      update voucher_payout_config set
--        function_url = 'https://xizpwtycczigjhzxegen.supabase.co/functions/v1/settle-voucher-payouts',
--        service_key  = '<service_role key>',
--        updated_at   = now()
--      where id = 1;
--
-- 4. Periksa antreannya kapan saja:
--
--      select p.status, p.attempts, p.amount, r.name, p.last_error
--      from voucher_payouts p left join restaurants r on r.id = p.resto_id
--      order by p.created_at desc;
--
-- Resto yang belum punya sub-akun akan menumpuk sebagai `pending` tanpa
-- pernah dicoba. Itu disengaja — dan cara melihatnya:
--
--   select r.name, count(*), sum(p.amount)
--   from voucher_payouts p
--   left join restaurants r on r.id = p.resto_id
--   left join resto_payment_accounts a on a.resto_id = p.resto_id
--   where p.status <> 'sent' and (a.resto_id is null or not a.active)
--   group by r.name;
