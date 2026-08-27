-- KaataGo — voucher yang terbit langsung mengabari pelanggan.
--
-- Jalankan SETELAH vouchers.sql, announcement_audience.sql, dan
-- announcement_categories.sql. Aman dijalankan berulang kali.
--
-- Voucher yang diterbitkan tapi tidak diumumkan adalah uang yang sudah
-- keluar dari saldo KaataGo untuk sesuatu yang tidak ada yang tahu.
-- Kuotanya habis oleh siapa pun yang kebetulan membuka layar Voucher
-- Saya, dan sisanya hangus tanpa pernah dilihat orang.
--
-- Pengumumannya ditulis di sini, di dalam transaksi yang sama dengan
-- penerbitannya. Dua langkah terpisah yang harus diingat berurutan
-- berarti suatu saat yang kedua terlewat.
--
-- Push-nya menyusul sendiri: `trg_queue_push_announcement` sudah
-- menyala pada setiap baris baru di app_announcements, jadi berkas ini
-- tidak perlu tahu apa-apa soal FCM.

begin;

create or replace function generate_voucher_batch(
  p_code text,
  p_name text,
  p_total bigint,
  p_quantity integer,
  p_expires_on date,
  p_min_purchase bigint default 0,
  p_resto_ids jsonb default '[]'::jsonb
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
    min_purchase, resto_ids, created_by
  ) values (
    v_id, v_code, p_name,
    -- Yang dicatat keluar adalah yang benar-benar bisa ditebus. Sisa
    -- pembagian tidak pernah jadi voucher, jadi mencatatnya sebagai uang
    -- yang keluar berarti saldo berkurang untuk sesuatu yang tidak ada.
    v_amount * p_quantity,
    p_quantity, v_amount, p_expires_on,
    p_min_purchase, coalesce(p_resto_ids, '[]'::jsonb),
    auth.jwt() ->> 'email'
  );

  -- Uang berpindah dari saldo bebas ke kantong voucher.
  perform _jurnal_kaatago('total_balance', v_id, v_amount * p_quantity,
    'debit', 'Terbit voucher ' || v_code || ' — ' || p_quantity || ' × ' || v_amount);
  perform _jurnal_kaatago('voucher', v_id, v_amount * p_quantity,
    'credit', 'Alokasi voucher ' || v_code);

  -- Rp 100.000, bukan 100000. Angka telanjang di notifikasi terbaca
  -- salah sekilas, dan sekilas adalah satu-satunya waktu yang dipunya
  -- notifikasi.
  v_nilai := 'Rp ' || to_char(v_amount, 'FM999G999G999G999');

  -- Kabarnya masuk Kotak Masuk tab Umum, dan pemicu push mengantarnya
  -- ke layar kunci. Kodenya ikut di badan pesan supaya bisa disalin
  -- tanpa membuka aplikasi.
  insert into app_announcements (title, body, category, audience, created_by)
  values (
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
    auth.jwt() ->> 'email'
  );

  return v_id;
end;
$$;

commit;

-- ─────────────────────────────────────────────────────────────────────
-- Memeriksanya
-- ─────────────────────────────────────────────────────────────────────
--
--   select title, category, audience, created_at
--   from app_announcements where audience = 'customers'
--   order by created_at desc limit 5;
--
-- Kalau barisnya ada tapi push-nya tidak sampai, yang bermasalah bukan
-- berkas ini — periksa antrean push-nya:
--
--   select event, created_at, sent_at, error
--   from push_outbox order by created_at desc limit 10;
