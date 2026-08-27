// KaataGo — membayarkan voucher yang sudah dipakai ke resto yang melayaninya.
//
// Voucher adalah promo KaataGo. Pelanggan membayar kurang, resto tetap
// menyerahkan makanannya penuh, dan selisihnya kami yang tanggung.
// Sampai fungsi ini berjalan, "kami tanggung" itu baru berupa jurnal.
//
// Deploy:
//   supabase functions deploy settle-voucher-payouts --project-ref xizpwtycczigjhzxegen
//
// Secret yang dibutuhkan:
//   XENDIT_SECRET_KEY   kunci rahasia Xendit milik KaataGo
//   XENDIT_ACCOUNT_ID   pengenal akun KaataGo sendiri — sumber dananya
//
// ── Kenapa transfer, bukan disbursement ──────────────────────────────
//
// Disbursement menembak nomor rekening bank, dan kita sengaja tidak
// menyimpan nomor rekening resto mana pun. Transfer memindahkan saldo
// ke sub-akun restonya di xenPlatform; dari sana dananya ikut jadwal
// pencairan mereka sendiri, ke rekening yang tidak pernah kita lihat.
//
// ── Kenapa `reference` diisi id klaimnya ─────────────────────────────
//
// Xendit menolak transfer dengan `reference` yang sudah pernah dipakai.
// Dengan id klaim di sana, penjadwal yang berjalan dua kali, atau
// jaringan yang putus setelah permintaannya sampai tapi sebelum
// jawabannya pulang, tidak bisa mengirim uang yang sama dua kali.
// Penjagaan itu ada di sisi Xendit — bukan pada ingatan fungsi ini.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

interface Due {
  payout_id: string;
  claim_id: string;
  resto_id: string;
  resto_name: string | null;
  account_id: string;
  amount: number;
}

Deno.serve(async (req) => {
  try {
    const kunci = Deno.env.get("XENDIT_SECRET_KEY");
    const sumber = Deno.env.get("XENDIT_ACCOUNT_ID");
    if (!kunci) return json({ error: "XENDIT_SECRET_KEY belum diisi" }, 500);
    if (!sumber) return json({ error: "XENDIT_ACCOUNT_ID belum diisi" }, 500);

    let batas = 50;
    try {
      const body = await req.json();
      if (body?.limit) batas = Number(body.limit);
    } catch (_) {
      // Dipanggil penjadwal tanpa badan permintaan. Bukan galat.
    }

    const { data, error } = await admin.rpc("voucher_payouts_due", {
      p_limit: batas,
    });
    if (error) return json({ error: error.message }, 500);

    const antre = (data ?? []) as Due[];
    const hasil = { terkirim: 0, gagal: 0, total: 0 };

    for (const p of antre) {
      try {
        const jawab = await fetch("https://api.xendit.co/transfers", {
          method: "POST",
          headers: {
            "Authorization": `Basic ${btoa(kunci + ":")}`,
            "Content-Type": "application/json",
            "X-IDEMPOTENCY-KEY": p.claim_id,
          },
          body: JSON.stringify({
            reference: p.claim_id,
            amount: p.amount,
            source_user_id: sumber,
            destination_user_id: p.account_id,
          }),
        });

        const isi = await jawab.json().catch(() => ({}));

        // Permintaan kedua untuk `reference` yang sama ditolak sebagai
        // duplikat. Itu bukan kegagalan — itu bukti uangnya sudah
        // terkirim. Menandainya gagal akan membuat baris ini dicoba
        // terus setiap penjadwal berjalan, selamanya.
        const sudahPernah = jawab.status === 409 ||
          isi?.error_code === "DUPLICATE_TRANSFER_ERROR" ||
          isi?.error_code === "DUPLICATE_ERROR";

        if (jawab.ok || sudahPernah) {
          await admin.rpc("mark_voucher_payout", {
            p_payout_id: p.payout_id,
            p_ok: true,
            p_transfer_id: isi?.id ?? isi?.transfer_id ?? null,
          });
          hasil.terkirim++;
        } else {
          await admin.rpc("mark_voucher_payout", {
            p_payout_id: p.payout_id,
            p_ok: false,
            p_error: pesanGalat(isi, jawab.status),
          });
          hasil.gagal++;
        }
      } catch (e) {
        // Satu resto yang bermasalah tidak boleh menghentikan
        // pembayaran ke resto lain di antrean yang sama.
        await admin.rpc("mark_voucher_payout", {
          p_payout_id: p.payout_id,
          p_ok: false,
          p_error: String(e),
        });
        hasil.gagal++;
      }
      hasil.total++;
    }

    return json(hasil);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

// Xendit menyembunyikan sebab sebenarnya beberapa lapis ke dalam.
// Pesan "request failed" yang tersimpan di antrean tidak menolong
// siapa pun yang memeriksanya besok pagi.
function pesanGalat(isi: Record<string, unknown>, status: number): string {
  const kode = isi?.error_code ?? "";
  const pesan = isi?.message ?? isi?.error ?? "";
  const gabung = [kode, pesan].filter(Boolean).join(" — ");
  return gabung || `HTTP ${status}`;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
