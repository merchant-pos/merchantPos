// KaataGo — membuat Virtual Account untuk tagihan langganan resto.
//
// Dipanggil aplikasi resto sambil menyebut nomor tagihannya saja.
// Nominalnya **tidak** ikut dikirim: fungsi ini membacanya sendiri dari
// tabel tagihan. Nominal yang datang dari aplikasi bisa diubah siapa pun
// yang ingin melunasi tagihan sejuta rupiah dengan seribu.
//
// Deploy:
//   supabase functions deploy create-billing-va --project-ref xizpwtycczigjhzxegen
//
// Secret yang dibutuhkan:
//   XENDIT_SECRET_KEY   kunci rahasia Xendit milik KaataGo
//
// ── Bedanya dari create-qris, dan kenapa itu penting ─────────────────
//
// create-qris memasang header `for-user-id` berisi sub-akun restonya,
// supaya dananya cair ke rekening resto itu. Fungsi ini **sengaja tidak
// memasangnya**: tagihan langganan adalah satu-satunya aliran uang yang
// tujuannya memang rekening KaataGo.
//
// Salah memasang header itu di sini berarti resto membayar tagihan
// langganan ke rekeningnya sendiri, dan tidak ada satu pun galat yang
// muncul saat itu terjadi — tagihannya tetap lunas, uangnya tidak pernah
// sampai.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const BANK_TERSEDIA = [
  "BCA",
  "BNI",
  "BRI",
  "MANDIRI",
  "PERMATA",
  "BSI",
  "CIMB",
];

interface InvoiceRow {
  id: string;
  resto_id: string;
  amount: number;
  status: string;
  due_date: string;
  va_bank: string | null;
  va_number: string | null;
  va_id: string | null;
  va_expires_at: string | null;
}

Deno.serve(async (req) => {
  try {
    const { invoice_id, bank, simulate } = await req.json();

    if (!invoice_id) return json({ error: "sebutkan invoice_id" }, 400);

    if (simulate === true) return await simulasiBayar(String(invoice_id));

    const bankCode = String(bank ?? "BCA").toUpperCase();
    if (!BANK_TERSEDIA.includes(bankCode)) {
      return json({ error: `bank ${bankCode} tidak tersedia` }, 400);
    }

    const { data: inv, error } = await admin
      .from("billing_invoices")
      .select(
        "id, resto_id, amount, status, due_date, va_bank, va_number, va_id, va_expires_at",
      )
      .eq("id", invoice_id)
      .maybeSingle<InvoiceRow>();

    if (error) return json({ error: error.message }, 500);
    if (!inv) return json({ error: "tagihan tidak ditemukan" }, 404);
    if (inv.status === "paid" || inv.status === "waived") {
      return json({ error: "tagihan ini sudah lunas" }, 409);
    }

    // VA yang masih hidup dan banknya sama dipakai ulang.
    //
    // Resto yang menutup layarnya lalu kembali akan memanggil fungsi ini
    // lagi. Kalau tiap panggilan membuat VA baru, satu tagihan punya
    // beberapa nomor sekaligus — dan yang sudah dicatat di aplikasi bank
    // resto adalah nomor lama, yang diam-diam berhenti berlaku.
    if (
      inv.va_number &&
      inv.va_bank === bankCode &&
      inv.va_expires_at &&
      new Date(inv.va_expires_at) > new Date()
    ) {
      return json({
        bank: inv.va_bank,
        account_number: inv.va_number,
        amount: inv.amount,
        expires_at: inv.va_expires_at,
        reused: true,
        test_mode: (Deno.env.get("XENDIT_SECRET_KEY") ?? "")
          .startsWith("xnd_development_"),
      });
    }

    const secret = Deno.env.get("XENDIT_SECRET_KEY");
    if (!secret) return json({ error: "XENDIT_SECRET_KEY belum diset" }, 500);

    // Mode uji ditentukan server, bukan aplikasi.
    //
    // Aplikasi tidak punya cara mengetahuinya sendiri, dan menitipkannya
    // ke penanda saat build berarti mengandalkan seseorang ingat
    // mematikannya sebelum rilis — yang selalu gagal tepat pada rilis
    // yang paling sibuk. Dengan cara ini, mengganti kunci ke produksi
    // sudah cukup untuk melenyapkan seluruh perkakas ujinya.
    const testMode = secret.startsWith("xnd_development_");

    // Berlaku sampai seminggu sesudah jatuh tempo. VA yang mati tepat di
    // tanggal jatuh tempo menutup pintu justru pada hari orang paling
    // mungkin membayarnya.
    const kedaluwarsa = new Date(inv.due_date);
    kedaluwarsa.setDate(kedaluwarsa.getDate() + 7);
    kedaluwarsa.setHours(23, 59, 59, 0);

    const { data: resto } = await admin
      .from("restaurants")
      .select("name")
      .eq("id", inv.resto_id)
      .maybeSingle();

    const namaVA = `KAATAGO ${String(resto?.name ?? "RESTO").toUpperCase()}`
      .slice(0, 50);

    // is_closed + expected_amount: hanya nominal persis yang diterima.
    // Tanpa itu, transfer kurang seribu rupiah tetap masuk dan tagihannya
    // tidak lunas — uangnya ada di rekening kita, restonya tetap
    // terkunci, dan tidak ada yang tahu kenapa.
    //
    // is_single_use: nomornya mati begitu terbayar, jadi transfer bulan
    // depan tidak mendarat di tagihan bulan ini.
    const res = await fetch("https://api.xendit.co/callback_virtual_accounts", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(`${secret}:`)}`,
        // Sengaja TIDAK ada for-user-id di sini. Lihat catatan di atas.
      },
      body: JSON.stringify({
        external_id: inv.id,
        bank_code: bankCode,
        name: namaVA,
        expected_amount: inv.amount,
        is_closed: true,
        is_single_use: true,
        expiration_date: kedaluwarsa.toISOString(),
        // `description` sengaja tidak dikirim.
        //
        // Sebagian bank menolaknya mentah-mentah — Mandiri menjawab
        // DESCRIPTION_NOT_SUPPORTED_ERROR — dan yang mana saja berbeda
        // per bank dan bisa berubah kapan pun di sisi Xendit.
        // Mengirimkannya hanya untuk bank tertentu berarti daftar
        // pengecualian yang harus diikuti selamanya, demi kolom yang
        // tidak pernah dibaca siapa pun: nomor tagihan sudah ada di
        // external_id, dan nama restonya sudah ada di `name`.
      }),
    });

    const body = await res.json();
    if (!res.ok) {
      return json({
        error: body?.message ?? "Xendit menolak permintaan",
        detail: body,
      }, 502);
    }

    await admin
      .from("billing_invoices")
      .update({
        va_bank: bankCode,
        va_number: body.account_number,
        va_id: body.id,
        va_expires_at: kedaluwarsa.toISOString(),
      })
      .eq("id", inv.id);

    return json({
      bank: bankCode,
      account_number: body.account_number,
      amount: inv.amount,
      expires_at: kedaluwarsa.toISOString(),
      reused: false,
      test_mode: testMode,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

/// Menyuruh Xendit berlaku seolah uangnya sudah ditransfer.
///
/// Hanya hidup dengan kunci development — Xendit sendiri yang menolak
/// endpoint ini pada kunci produksi. Jadi tidak ada penanda yang bisa
/// tertinggal menyala di rilis: mengganti kuncinya sudah cukup.
///
/// Nominalnya dibaca dari tagihannya, bukan dari yang mengirim. VA-nya
/// tertutup di nominal itu, dan simulasi dengan angka lain hanya akan
/// menghasilkan penolakan yang membingungkan penguji.
async function simulasiBayar(invoiceId: string) {
  const secret = Deno.env.get("XENDIT_SECRET_KEY");
  if (!secret) return json({ error: "XENDIT_SECRET_KEY belum diset" }, 500);
  if (!secret.startsWith("xnd_development_")) {
    return json({ error: "Simulasi hanya tersedia di mode uji" }, 403);
  }

  const { data: inv } = await admin
    .from("billing_invoices")
    .select("id, amount, va_number, status")
    .eq("id", invoiceId)
    .maybeSingle<{ id: string; amount: number; va_number: string | null; status: string }>();

  if (!inv) return json({ error: "tagihan tidak ditemukan" }, 404);
  if (!inv.va_number) return json({ error: "belum ada Virtual Account" }, 409);
  if (inv.status === "paid" || inv.status === "waived") {
    return json({ error: "tagihan ini sudah lunas" }, 409);
  }

  const res = await fetch(
    `https://api.xendit.co/callback_virtual_accounts/external_id=${
      encodeURIComponent(inv.id)
    }/simulate_payment`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(`${secret}:`)}`,
      },
      body: JSON.stringify({ amount: inv.amount }),
    },
  );

  const body = await res.json();
  if (!res.ok) {
    return json({ error: body?.message ?? "Xendit menolak simulasi" }, 502);
  }
  return json({ simulated: true });
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
