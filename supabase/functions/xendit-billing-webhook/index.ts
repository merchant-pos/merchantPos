// KaataGo — penerima kabar pembayaran tagihan langganan dari Xendit.
//
// Inilah satu-satunya hal yang boleh menyatakan sebuah tagihan
// langganan lunas lewat Virtual Account. Tombol di aplikasi resto tidak,
// dan tidak akan pernah: apa pun yang bisa ditekan pihak yang belum
// membayar bukan bukti pembayaran.
//
// Deploy:
//   supabase functions deploy xendit-billing-webhook \
//     --project-ref xizpwtycczigjhzxegen --no-verify-jwt
//
// --no-verify-jwt wajib: pemanggilnya server Xendit, yang tidak punya
// sesi pengguna. Yang menjaga pintunya adalah token callback di bawah.
//
// Secret yang dibutuhkan:
//   XENDIT_CALLBACK_TOKEN   dari Dashboard Xendit → Settings → Callbacks
//
// Daftarkan URL ini di Dashboard Xendit untuk kejadian
// "Virtual Account paid" / "FVA Paid":
//   https://xizpwtycczigjhzxegen.supabase.co/functions/v1/xendit-billing-webhook
//
// ── Kenapa terpisah dari xendit-webhook ──────────────────────────────
//
// Keduanya menerima kabar dari Xendit, tapi yang dilunasinya berbeda
// jenis: yang satu pesanan pelanggan, yang satu tagihan kami sendiri.
// Menyatukannya berarti satu fungsi yang harus menebak lebih dulu kabar
// ini soal apa — dan tebakan yang salah di sini melunasi hal yang salah.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  // Token diperiksa lebih dulu, sebelum apa pun dibaca dari badan
  // permintaannya. URL fungsi ini terbuka untuk umum — tanpa
  // pemeriksaan ini, siapa pun bisa mengarang kabar "sudah lunas" untuk
  // tagihan mana pun, dan membuka kunci resto yang belum membayar.
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

  // Xendit menyebut tagihannya lewat external_id — yang kita isi dengan
  // nomor tagihan saat VA-nya dibuat.
  const invoiceId = (data.external_id ?? data.externalId) as string | undefined;
  const amount = Number(data.amount ?? data.transaction_amount ?? 0);
  const paymentId = String(
    data.payment_id ?? data.id ?? data.callback_virtual_account_id ?? "",
  );
  const vaNumber = data.account_number as string | undefined;

  // Dijawab 200 supaya Xendit berhenti mengulangnya. Kabar yang tidak
  // kita mengerti tidak akan jadi lebih dimengerti pada percobaan
  // kelima — dan pengulangannya hanya menumpuk di antrean mereka.
  if (!invoiceId && !vaNumber) {
    return new Response("tidak ada external_id maupun account_number", {
      status: 200,
    });
  }

  let id = invoiceId;

  // Cadangan: sebagian bentuk callback tidak membawa external_id.
  // Nomor VA-nya unik dan tersimpan di baris tagihannya, jadi masih ada
  // jalan menemukannya.
  if (!id && vaNumber) {
    const { data: row } = await admin
      .from("billing_invoices")
      .select("id")
      .eq("va_number", vaNumber)
      .order("due_date", { ascending: false })
      .limit(1)
      .maybeSingle();
    id = row?.id;
  }

  if (!id) {
    return new Response("tagihan tidak dikenali", { status: 200 });
  }

  const { data: hasil, error } = await admin.rpc("settle_billing_va", {
    p_invoice_id: id,
    p_amount: amount,
    p_payment_id: paymentId,
  });

  if (error) {
    // 500 supaya Xendit mengulanginya. Ini satu-satunya kegagalan yang
    // memang layak diulang: gangguan sesaat di sisi kami, sementara
    // uangnya sudah benar-benar masuk.
    return new Response(error.message, { status: 500 });
  }

  // Jawabannya ditulis apa adanya, bukan disatukan jadi "gagal".
  // Inilah catatan yang dibaca orang saat ada uang masuk yang tidak
  // jelas mendarat di mana, dan pesan yang menyamarkan sebabnya
  // memberangkatkan penelusuran ke arah yang salah.
  const pesan: Record<string, string> = {
    paid: "ok — tagihan lunas",
    already_paid: "ok — tagihan ini sudah lunas sebelumnya",
    not_found: `tagihan ${id} tidak ada — uangnya masuk, tagihannya tidak dikenali`,
    underpaid: `kurang bayar untuk ${id} — diterima ${amount}, tidak dilunasi`,
  };

  // Semuanya 200: tidak satu pun dari keadaan ini jadi lebih baik kalau
  // Xendit mengulanginya.
  return new Response(pesan[String(hasil)] ?? `hasil tidak dikenali: ${hasil}`, {
    status: 200,
  });
});
