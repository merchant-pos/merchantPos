-- KaataGo — banner voucher, dan menghapus batch yang tidak jadi.
--
-- Jalankan SETELAH voucher_announcement.sql. Aman dijalankan berulang.

begin;

-- Gambar 16:9 sebagai base64, sependekatan dengan banner promo resto
-- dan gambar pengumuman. Menyimpannya di kolom, bukan object storage,
-- membuat satu voucher tetap satu baris — pengumuman yang gambarnya
-- hilang karena berkasnya terhapus terpisah adalah jenis kerusakan yang
-- tidak perlu diciptakan.
alter table vouchers add column if not exists banner_base64 text;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Terbit — sekarang membawa bannernya ke kotak masuk
-- ─────────────────────────────────────────────────────────────────────

create or replace function generate_voucher_batch(
  p_code text,
  p_name text,
  p_total bigint,
  p_quantity integer,
  p_expires_on date,
  p_min_purchase bigint default 0,
  p_resto_ids jsonb default '[]'::jsonb,
  p_banner text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_amount bigint;
  v_code text := upper(trim(p_code));
  v_nilai text;
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menerbitkan voucher';
  end if;

  if p_quantity <= 0 or p_total <= 0 then
    raise exception 'Nominal dan jumlah voucher harus lebih dari nol';
  end if;

  v_amount := p_total / p_quantity;
  if v_amount <= 0 then
    raise exception 'Nominal per voucher jadi nol — kurangi jumlahnya';
  end if;

  if p_expires_on <= current_date then
    raise exception 'Tanggal kedaluwarsa minimal besok';
  end if;

  v_id := 'VC-' || upper(substr(md5(v_code || now()::text), 1, 10));

  insert into vouchers (
    id, code, name, total_amount, quantity, amount, expires_on,
    min_purchase, resto_ids, banner_base64, created_by
  ) values (
    v_id, v_code, p_name,
    -- Yang dicatat keluar adalah yang benar-benar bisa ditebus. Sisa
    -- pembagian tidak pernah jadi voucher, jadi mencatatnya sebagai uang
    -- yang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
    v_amount * p_quantity,
    p_quantity, v_amount, p_expires_on,
    p_min_purchase, coalesce(p_resto_ids, '[]'::jsonb),
    nullif(p_banner, ''),
    auth.jwt() ->> 'email'
  );

  perform _jurnal_kaatago('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_kaatago('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  v_nilai := 'Rp ' || to_char(v_amount, 'FM999G999G999G999');

  insert into app_announcements (
    title, body, category, audience, image_base64, created_by
  ) values (
    'Voucher ' || v_nilai || ' dari KaataGo',
    'Buruan tebus, kuotanya cuma ' || p_quantity || ' dan siapa cepat dia dapat! ' ||
    'Kode voucher: ' || v_code || E'\n\n' ||
    'Tiap voucher bernilai ' || v_nilai ||
    case when p_min_purchase > 0
      then ', minimal belanja Rp ' || to_char(p_min_purchase, 'FM999G999G999G999')
      else '' end ||
    '. Berlaku sampai ' || to_char(p_expires_on, 'DD Mon YYYY') || '. ' ||
    'Tebus di menu Voucher Saya — satu akun cuma bisa sekali, jadi jangan sampai keduluan.',
    'general',
    'customers',
    nullif(p_banner, ''),
    auth.jwt() ->> 'email'
  );

  return v_id;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- Menghapus batch yang tidak jadi
-- ─────────────────────────────────────────────────────────────────────
--
-- Dua syarat, dan keduanya soal uang.
--
-- Harus ditutup dulu. Batch yang masih berjalan sedang diumumkan ke
-- orang banyak; menghapusnya berarti kode yang sudah tersebar tiba-tiba
-- tidak ada, dan yang menemukannya adalah pelanggan yang mengetik kode
-- dari notifikasi lalu diberi tahu kodenya tidak ditemukan.
--
-- Harus belum ada yang menebus. Klaim adalah uang yang sudah menggantung
-- di tangan orang; barisnya juga yang dirujuk jurnal penebusan dan
-- antrean pencairan. Menghapus batch-nya membuat catatan itu kehilangan
-- namanya, dan yang tersisa adalah angka di buku besar tanpa keterangan
-- dari mana asalnya.
--
-- Dananya dikembalikan lebih dulu, bukan lenyap bersama barisnya. Batch
-- yang dihapus tanpa mengembalikan alokasinya adalah saldo KaataGo yang
-- berkurang selamanya untuk voucher yang tidak pernah ada.

create or replace function delete_voucher_batch(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v vouchers;
  v_klaim integer;
begin
  if not is_super_admin() then
    raise exception 'Hanya Super Admin yang dapat menghapus voucher';
  end if;

  select * into v from vouchers where id = p_id;
  if v.id is null then
    raise exception 'Voucher tidak ditemukan';
  end if;

  if v.active then
    raise exception 'Tutup dulu vouchernya sebelum dihapus';
  end if;

  select count(*) into v_klaim from voucher_claims where voucher_id = v.id;
  if v_klaim > 0 then
    raise exception 'Sudah ada % pelanggan yang menebus — batch ini tidak bisa dihapus', v_klaim;
  end if;

  -- Alokasinya pulang ke saldo bebas, kecuali sudah pernah pulang lewat
  -- penjadwal kedaluwarsa.
  if v.settled_at is null then
    perform _jurnal_kaatago('voucher', v.id, v.total_amount,
      'debit', 'Batal voucher ' || v.code);
    perform _jurnal_kaatago('total_balance', v.id, v.total_amount,
      'credit', 'Dana voucher ' || v.code || ' kembali — batch dihapus');
  end if;

  -- Pengumumannya ikut dicabut. Kabar yang menyuruh menebus kode yang
  -- sudah tidak ada adalah kabar yang lebih buruk daripada tidak ada
  -- kabar sama sekali.
  delete from app_announcements
  where audience = 'customers'
    and category = 'general'
    and body like '%Kode voucher: ' || v.code || '%';

  delete from vouchers where id = v.id;
end;
$$;

revoke all on function delete_voucher_batch(text) from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select code, active, settled_at,
--          (select count(*) from voucher_claims c where c.voucher_id = v.id) as penebus
--   from vouchers v order by created_at desc;
