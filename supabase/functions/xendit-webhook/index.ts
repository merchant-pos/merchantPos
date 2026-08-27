// KaataGo — penerima kabar pembayaran dari Xendit.
//
// Inilah satu-satunya hal yang boleh menyatakan sebuah pesanan lunas
// lewat QRIS. Tombol di HP pelanggan tidak, dan tidak akan pernah:
// apa pun yang bisa ditekan orang yang belum membayar bukan bukti
// pembayaran.
//
// Deploy:
//   supabase functions deploy xendit-webhook \
//     --project-ref xizpwtycczigjhzxegen --no-verify-jwt
//
// --no-verify-jwt wajib: pemanggilnya server Xendit, yang tidak punya
// sesi pengguna. Yang menjaga pintunya adalah token callback di bawah.
//
// Secret yang dibutuhkan:
//   XENDIT_CALLBACK_TOKEN   dari Dashboard Xendit → Settings → Callbacks
//
// Daftarkan URL ini di Dashboard Xendit untuk kejadian "QR Code payment":
//   https://xizpwtycczigjhzxegen.supabase.co/functions/v1/xendit-webhook

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  // Token callback diperiksa lebih dulu, sebelum apa pun dibaca dari
  // badan permintaannya. URL fungsi ini terbuka untuk umum — tanpa
  // pemeriksaan ini, siapa pun bisa mengarang kabar "sudah lunas" untuk
  // pesanan mana pun.
  const expected = Deno.env.get("XENDIT_CALLBACK_TOKEN");
  if (!expected) {
    return new Response("XENDIT_CALLBACK_TOKEN belum diset", { status: 500 });
  }
  if (req.headers.get("x-callback-token") !== expected) {
    return new Response("ditolak", { status: 401 });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return new Response("badan permintaan bukan JSON", { status: 400 });
  }

  const data = (payload.data ?? payload) as Record<string, unknown>;
  const referenceId = data.reference_id as string | undefined;
  const status = String(data.status ?? "").toUpperCase();

  if (!referenceId) {
    // Dijawab 200 supaya Xendit berhenti mengulangnya. Kabar yang tidak
    // kita mengerti tidak akan jadi lebih dimengerti pada percobaan
    // kelima.
    return json({ ignored: "tanpa reference_id" });
  }

  // Rinciannya dibaca untuk SETIAP kabar, bukan hanya yang berhasil.
  //
  // Pembayaran yang gagal atau kedaluwarsa justru yang paling sering
  // ditanyakan belakangan — "sudah saya bayar tapi ditolak" tidak bisa
  // dijawab kalau yang tersimpan cuma yang berhasil. Dan yang masih
  // menunggu tetap punya nomor QR serta mitranya sejak sebelum dibayar.
  const detail = (data.payment_detail ?? {}) as Record<string, unknown>;
  const rincian = bersihkan({
    provider_status: data.status,
    failure_reason: data.failure_code ?? data.failure_reason,
    transaction_id: data.id,
    qr_id: data.qr_id,
    product_id: data.product_id,
    partner_code: data.channel_code,
    partner_name: data.partner,
    partner_receipt_id: detail.receipt_id,
    payment_source: detail.source,
    acquirer_id: detail.acquirer_id,
    customer_pan: detail.customer_pan,
    merchant_pan: detail.merchant_pan,
  });
  rincian.provider_status_at = new Date().toISOString();

  // Hanya pembayaran berhasil yang menggerakkan uang. Kejadian lain —
  // kedaluwarsa, dibatalkan — sengaja tidak menyentuh pesanannya:
  // pelanggan yang QR-nya kedaluwarsa masih boleh membayar tunai di
  // kasir, dan pesanannya tidak boleh ikut ditutup.
  if (status !== "SUCCEEDED" && status !== "COMPLETED" && status !== "PAID") {
    // Kolom `status` milik kita sengaja tidak disentuh: ia hanya
    // berubah jadi 'paid' saat uangnya benar-benar diterima, dan
    // pelanggan yang QR-nya kedaluwarsa masih boleh membayar tunai di
    // kasir. Yang dicatat di sini keadaan di sisi penyedia.
    await admin.from("payment_charges")
      .update({ raw: payload, ...rincian })
      .eq("reference_id", referenceId);
    return json({ recorded: `status ${status}` });
  }

  const { data: result, error } = await admin.rpc("settle_gateway_payment", {
    p_reference_id: referenceId,
    p_provider_charge_id: (data.qr_id ?? data.id ?? null) as string | null,
    p_raw: payload,
  });

  if (error) {
    // 500 supaya Xendit mengulang. Ini satu-satunya kegagalan yang
    // memang layak diulang: databasenya sedang tidak bisa dihubungi,
    // sementara uangnya sudah benar-benar diterima.
    return json({ error: error.message }, 500);
  }

  // Rincian kuitansinya disimpan sesudah pembayarannya sah dicatat,
  // bukan sebelum. Kalau langkah ini gagal, uangnya tetap tercatat
  // masuk — yang hilang cuma salinan yang memudahkan pencocokan, dan
  // aslinya tetap utuh di kolom `raw`.
  if (Object.keys(rincian).length > 0) {
    const { error: galatRincian } = await admin
      .from("payment_charges")
      .update(rincian)
      .eq("reference_id", referenceId);
    if (galatRincian) {
      // Dicatat, tidak digagalkan. Mengembalikan 500 di sini membuat
      // Xendit mengulang kabar pembayaran yang sudah berhasil dicatat.
      console.error("gagal menyimpan rincian kuitansi:", galatRincian.message);
    }
  }

  return json({ result });
});

/// Membuang medan yang tidak dikirim Xendit.
///
/// Menulis null menimpa nilai yang mungkin sudah terisi dari kabar
/// sebelumnya — dan kabar yang sama bisa datang dua kali.
function bersihkan(
  isi: Record<string, unknown>,
): Record<string, string> {
  const hasil: Record<string, string> = {};
  for (const [kunci, nilai] of Object.entries(isi)) {
    if (nilai === null || nilai === undefined || nilai === "") continue;
    hasil[kunci] = String(nilai);
  }
  return hasil;
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
