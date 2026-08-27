// KaataGo — membuat tagihan QRIS di Xendit.
//
// Dipanggil aplikasi pelanggan sambil menyebut nomor pesanannya saja.
// Nominalnya **tidak** ikut dikirim: fungsi ini membacanya sendiri dari
// pesanan di database. Nominal yang datang dari HP bisa diubah siapa pun
// yang mau membayar seratus ribu dengan seribu rupiah.
//
// Deploy:
//   supabase functions deploy create-qris --project-ref xizpwtycczigjhzxegen
//
// Secret yang dibutuhkan:
//   XENDIT_SECRET_KEY   kunci rahasia Xendit (xnd_development_… saat uji)
//
// Kunci itu tidak boleh pernah ada di dalam APK. Siapa pun yang
// memegangnya bisa membuat tagihan, menarik dana, dan membaca seluruh
// riwayat transaksi merchant.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Berlaku 30 menit. Cukup panjang untuk orang yang masih memilih menu
// atau kehabisan pulsa data sebentar, cukup pendek supaya QR yang
// terlanjur difoto tidak bisa dibayar berjam-jam kemudian.
const EXPIRY_MINUTES = 30;

interface OrderRow {
  id: string;
  resto_id: string | null;
  total: number;
  payment_status: string;
  payment_method: string | null;
}

Deno.serve(async (req) => {
  try {
    const body0 = await req.json();
    const { order_id, simulate, resto_id, amount } = body0;

    if (simulate === true) {
      return await simulatePayment(order_id, body0.reference_id);
    }

    // Dua cara memanggil: menyebut pesanannya, atau — untuk pembayaran
    // di meja kasir — menyebut restonya berikut nominalnya.
    //
    // Pesanan yang diinput kasir baru dibuat setelah pembayarannya
    // diterima, jadi saat QR-nya harus terbit belum ada pesanan yang
    // bisa disebut. Nominalnya di sini datang dari aplikasi, dan itu
    // memang lebih longgar daripada jalur pelanggan — tapi yang
    // memasukkannya adalah kasir resto itu sendiri, yang salah ketiknya
    // merugikan restonya sendiri, bukan pelanggannya.
    if (!order_id) {
      if (!resto_id || !amount) {
        return json({ error: "sebutkan order_id, atau resto_id dan amount" }, 400);
      }
      return await createCharge({
        restoId: String(resto_id),
        amount: Number(amount),
        orderId: null,
      });
    }

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id, resto_id, total, payment_status, payment_method")
      .eq("id", order_id)
      .maybeSingle<OrderRow>();

    if (orderError) return json({ error: orderError.message }, 500);
    if (!order) return json({ error: "pesanan tidak ditemukan" }, 404);
    if (order.payment_status === "paid") {
      return json({ error: "pesanan ini sudah dibayar" }, 409);
    }

    return await createCharge({
      restoId: order.resto_id ?? "",
      amount: order.total,
      orderId: order.id,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

/// Menerbitkan (atau memakai ulang) satu tagihan QRIS.
async function createCharge(
  { restoId, amount, orderId }: {
    restoId: string;
    amount: number;
    orderId: string | null;
  },
) {
  try {
    // Tagihan yang masih hidup dipakai ulang, bukan dibuatkan yang baru.
    //
    // Pelanggan yang menutup layarnya lalu kembali akan memanggil fungsi
    // ini lagi. Kalau tiap panggilan membuat QR baru, satu pesanan bisa
    // punya lima QR aktif sekaligus — dan kalau dua di antaranya
    // terbayar, yang kedua adalah uang pelanggan yang harus
    // dikembalikan.
    const { data: existing } = orderId == null
      ? { data: null }
      : await admin
      .from("payment_charges")
      .select("reference_id, qr_string, amount, expires_at")
      .eq("order_id", orderId)
      .eq("status", "pending")
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

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

    // Sub-akun resto ini, kalau ada.
    //
    // Inilah yang menentukan dananya cair ke rekening siapa. Tanpa ini,
    // pembayaran dibuat atas nama akun platform — dan uang milik resto
    // orang lain mendarat di rekening KaataGo, yang justru ingin
    // dihindari.
    const { data: account } = await admin
      .from("resto_payment_accounts")
      .select("account_id, active")
      .eq("resto_id", restoId)
      .maybeSingle();

    const subAccount =
      account?.active === false ? null : account?.account_id ?? null;

    // Resto tanpa sub-akun sengaja TIDAK dibuatkan tagihan — kecuali di
    // mode uji.
    //
    // Di produksi, menjatuhkannya ke akun platform akan "berhasil":
    // QR-nya terbit, pelanggannya membayar, dan uangnya mendarat di
    // rekening yang salah tanpa satu pun tanda bahwa ada yang keliru.
    // Kegagalan yang terlihat jauh lebih murah daripada keberhasilan
    // yang salah alamat.
    //
    // Di mode uji tidak ada uang sungguhan yang bisa salah alamat, dan
    // sub-akun belum tentu tersedia — pengaktifannya di penyedia butuh
    // persetujuan yang memakan hari. Menahan pengujian selama masa
    // tunggu itu berarti seluruh alur pembayaran baru bisa dicoba
    // pertama kali justru saat uangnya sudah sungguhan.
    if (!subAccount && !testMode) {
      return json({
        error: "resto ini belum punya akun pembayaran",
        needs_setup: true,
      }, 409);
    }

    if (existing?.qr_string) {
      return json({
        reference_id: existing.reference_id,
        qr_string: existing.qr_string,
        amount: existing.amount,
        expires_at: existing.expires_at,
        reused: true,
        test_mode: testMode,
      });
    }

    // Pengenal kita sendiri, bukan nomor pesanannya mentah-mentah: satu
    // pesanan bisa butuh QR kedua setelah yang pertama kedaluwarsa, dan
    // keduanya harus bisa dibedakan saat webhooknya datang.
    const referenceId = `kaatago-${orderId ?? "counter"}-${Date.now()}`;
    const expiresAt = new Date(Date.now() + EXPIRY_MINUTES * 60_000);

    const res = await fetch("https://api.xendit.co/qr_codes", {
      method: "POST",
      headers: {
        // Xendit memakai Basic auth dengan kunci rahasia sebagai
        // username dan kata sandi kosong.
        Authorization: `Basic ${btoa(secret + ":")}`,
        "Content-Type": "application/json",
        "api-version": "2022-07-31",
        // Dibuat atas nama sub-akun restonya. Kuncinya tetap milik
        // platform — yang berpindah cuma atas nama siapa tagihannya
        // terbit, dan ke rekening siapa dananya nanti cair.
        //
        // Tanpa sub-akun (hanya mungkin di mode uji), tagihannya terbit
        // atas nama akun platform.
        ...(subAccount ? { "for-user-id": subAccount } : {}),
      },
      body: JSON.stringify({
        reference_id: referenceId,
        type: "DYNAMIC",
        currency: "IDR",
        amount: amount,
        expires_at: expiresAt.toISOString(),
      }),
    });

    const body = await res.json();
    if (!res.ok) {
      // Dicatat sebagai gagal, bukan dibiarkan menghilang: pelanggan
      // yang QR-nya tidak muncul akan bertanya, dan jawabannya harus ada
      // di suatu tempat.
      await admin.from("payment_charges").insert({
        order_id: orderId,
        resto_id: restoId,
        reference_id: referenceId,
        amount: amount,
        status: "failed",
        raw: body,
      });
      return json({ error: `Xendit menolak: ${JSON.stringify(body)}` }, 502);
    }

    await admin.from("payment_charges").insert({
      order_id: orderId,
      resto_id: restoId,
      reference_id: referenceId,
      provider_charge_id: body.id ?? null,
      qr_string: body.qr_string ?? null,
      amount: amount,
      status: "pending",
      expires_at: expiresAt.toISOString(),
      raw: body,
    });

    return json({
      reference_id: referenceId,
      qr_string: body.qr_string,
      amount: amount,
      expires_at: expiresAt.toISOString(),
      reused: false,
      test_mode: testMode,
      // Supaya layar ujinya bisa menyebutkan bahwa dananya belum
      // terarah ke resto yang benar.
      platform_account: subAccount == null,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
}

/// Memalsukan pembayaran, hanya untuk pengujian.
///
/// Dashboard Xendit tidak selalu menyediakan tombol simulasi, dan
/// jalan satu-satunya lewat API — yang berarti menyalin secret key ke
/// terminal, lalu menebak QR mana yang dimaksud di antara sekian
/// banyak. Kuncinya sudah ada di sini, dan nomor pesanannya sudah
/// diketahui, jadi keduanya tidak perlu diulang di tempat lain.
///
/// Ditolak mentah-mentah kalau kunci yang terpasang bukan kunci Test.
/// Fungsi yang bisa menyatakan sebuah tagihan terbayar tanpa uang
/// benar-benar berpindah tidak boleh ada di lingkungan produksi, dan
/// penjagaan yang mengandalkan "nanti diingat untuk dihapus" akan
/// gagal pada rilis yang paling sibuk.
async function simulatePayment(orderId?: string, referenceId?: string) {
  const secret = Deno.env.get("XENDIT_SECRET_KEY") ?? "";
  if (!secret.startsWith("xnd_development_")) {
    return json({ error: "simulasi hanya untuk kunci Test" }, 403);
  }

  const query = admin
    .from("payment_charges")
    .select("provider_charge_id, reference_id, amount, status, resto_id")
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(1);

  const { data: charge } = referenceId != null
    ? await query.eq("reference_id", referenceId).maybeSingle()
    : await query.eq("order_id", orderId ?? "").maybeSingle();

  if (!charge?.provider_charge_id) {
    return json({ error: "tidak ada tagihan menunggu untuk pesanan ini" }, 404);
  }

  // Simulasinya pun harus atas nama sub-akun yang menerbitkan
  // tagihannya. Dipanggil atas nama platform, Xendit tidak akan
  // menemukan QR-nya sama sekali.
  const { data: account } = await admin
    .from("resto_payment_accounts")
    .select("account_id")
    .eq("resto_id", charge.resto_id ?? "")
    .maybeSingle();

  const res = await fetch(
    `https://api.xendit.co/qr_codes/${charge.provider_charge_id}/payments/simulate`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(secret + ":")}`,
        "Content-Type": "application/json",
        "api-version": "2022-07-31",
        ...(account?.account_id ? { "for-user-id": account.account_id } : {}),
      },
      body: JSON.stringify({ amount: charge.amount }),
    },
  );

  const body = await res.text();
  return json({
    simulated: res.ok,
    status: res.status,
    reference_id: charge.reference_id,
    response: body.slice(0, 400),
  }, res.ok ? 200 : 502);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
