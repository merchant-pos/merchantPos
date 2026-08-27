// KaataGo — pengirim notifikasi push.
//
// Dipanggil trigger `push_outbox` lewat pg_net setiap kali sebuah baris
// masuk ke sana. Tugasnya tiga: menentukan perangkat mana yang pantas
// dikabari, mengirimnya ke FCM, lalu menuliskan hasilnya kembali ke
// baris itu.
//
// Hasilnya sengaja ditulis balik. Notifikasi yang tidak sampai adalah
// jenis kegagalan yang paling sulit dilacak — tidak ada yang mengeluh,
// tidak ada galat di mana pun, cuma ada orang yang menunggu kabar yang
// tidak pernah datang. Selama hasilnya tercatat, "kenapa tidak bunyi?"
// selalu bisa dijawab dengan satu query.
//
// Deploy:
//   supabase functions deploy send-push --project-ref xizpwtycczigjhzxegen --no-verify-jwt
//
// --no-verify-jwt wajib: pemanggilnya database, yang tidak punya sesi
// pengguna. Yang menjaga pintunya adalah PUSH_HOOK_SECRET di bawah.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const FCM_PROJECT = "kaata-pos";

// Kanal Android yang sudah dipakai notifikasi lokal. Disebut tegas di
// tiap pesan: tanpa ini Android memakai kanal bawaan, dan nada dering
// khusus KaataGo tidak pernah berbunyi untuk notifikasi yang datang
// lewat push.
const CHANNELS: Record<string, string> = {
  order_new: "kaata_new_order",
  order_cooking: "kaata_order_status",
  order_ready: "kaata_order_status",
  pending_payment: "kaata_new_order",
  deposit_pending: "kaata_fund_review",
  deposit_reviewed: "kaata_fund_review",
  petty_pending: "kaata_fund_review",
  petty_reviewed: "kaata_fund_review",
  announcement: "kaata_announcement",
};

interface OutboxRow {
  id: string;
  resto_id: string | null;
  event: string;
  payload: {
    audience: "role" | "email" | "order_owner" | "all";

    /// Sasaran pengumuman: karyawan saja, pelanggan saja, atau keduanya.
    /// Hanya dipakai saat audience = "all".
    target?: "employees" | "customers" | "all";
    roles?: string[];
    email?: string;
    session_id?: string;

    /// Penunjuk tujuan yang ikut dikirim ke aplikasi lewat `data`.
    /// Tanpa ini notifikasi hanya bisa membuka aplikasinya, bukan
    /// halaman yang dimaksudnya.
    resto_id?: string;
    ticket_id?: string;

    title: string;
    body: string;
  };
}

/// Peran yang dipakai perangkat pelanggan.
///
/// Aplikasi mendaftarkannya sebagai 'customer'. Versi lama
/// mendaftarkannya tanpa peran sama sekali, dan barisnya masih ada di
/// tabel — jadi keduanya harus dihitung sebagai pelanggan.
///
/// Sempat ditulis sebagai "peran kosong berarti pelanggan", dan itu
/// salah dua arah sekaligus: pengumuman khusus pelanggan tidak sampai
/// ke satu pun pelanggan yang memakai aplikasi versi sekarang,
/// sementara pengumuman khusus karyawan justru ikut sampai ke mereka.
const PERAN_PELANGGAN = "customer";
const FILTER_PELANGGAN = `role.eq.${PERAN_PELANGGAN},role.is.null`;

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ── OAuth untuk FCM HTTP v1 ─────────────────────────────────────────
//
// FCM v1 tidak menerima "server key" seperti API lamanya: tiap panggilan
// butuh access token OAuth yang ditukar dari JWT bertanda tangan kunci
// service account. Tokennya berlaku sejam, jadi disimpan di memori —
// menukarnya untuk tiap notifikasi berarti dua panggilan jaringan untuk
// satu kabar.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt - 60_000) {
    return cachedToken.value;
  }

  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) throw new Error("Secret FCM_SERVICE_ACCOUNT belum diset");
  const sa = JSON.parse(raw);

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const unsigned = `${b64(header)}.${b64(claim)}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${
    btoa(String.fromCharCode(...new Uint8Array(sig)))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`OAuth gagal: ${JSON.stringify(json)}`);

  cachedToken = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cachedToken.value;
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

// ── Siapa yang dikabari ─────────────────────────────────────────────

async function resolveTokens(row: OutboxRow): Promise<string[]> {
  const p = row.payload;
  let q = admin.from("device_tokens").select("token");

  if (p.audience === "role") {
    // Kabar untuk sebuah peran dibatasi restonya. Tanpa itu, pesanan di
    // cabang Dago akan membunyikan HP dapur cabang sebelah — dan itulah
    // cara tercepat membuat orang mematikan notifikasi seluruhnya.
    if (row.resto_id) q = q.eq("resto_id", row.resto_id);
    q = q.in("role", p.roles ?? []);
  } else if (p.audience === "email") {
    if (!p.email) return [];
    q = q.eq("email", p.email);
  } else if (p.audience === "all") {
    // Pengumuman. Resto kosong berarti dari Super Admin — kabar versi
    // baru menyangkut semua orang yang memasang aplikasinya.
    if (!row.resto_id) {
      // Sasarannya tetap dihormati. Sebelumnya cabang ini mengembalikan
      // SELURUH token apa pun sasarannya — jadi pengumuman voucher yang
      // ditujukan ke pelanggan ikut membangunkan kasir dan chef di
      // tengah shift, dan kabar khusus karyawan sampai ke pelanggan.
      const semua = p.target ?? "all";
      if (semua === "customers") q = q.or(FILTER_PELANGGAN);
      if (semua === "employees") q = q.not("role", "in", `(${PERAN_PELANGGAN})`)
        .not("role", "is", null);
      const { data, error } = await q;
      if (error) throw new Error(`Gagal membaca device_tokens: ${error.message}`);
      return (data ?? []).map((r: { token: string }) => r.token);
    }

    // Resto terisi berarti dari admin resto itu, dan sasarannya dua
    // kelompok yang harus dicari dengan cara berbeda.
    //
    // Karyawan gampang: restonya tertulis di barisnya sendiri.
    //
    // Pelanggan tidak. resto_id pada perangkat pelanggan menyebut resto
    // yang sedang dia buka saat itu — dan begitu dia menutup menunya
    // atau membuka resto lain, isinya berubah atau kosong. Menyaring
    // dengan kolom itu saja berarti promo resto A cuma sampai ke
    // pelanggan yang kebetulan sedang membuka menu resto A: orang yang
    // paling tidak perlu diberi tahu, karena dia sudah ada di sana.
    //
    // Yang dipakai justru jejak yang tidak bisa berubah: dia pernah
    // memesan di resto ini. Dibatasi 90 hari supaya pengumuman tidak
    // mengejar orang yang mampir sekali dua tahun lalu.
    const sejak = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
    const { data: pesanan, error: errPesanan } = await admin
      .from("orders")
      .select("customer_label, session_id")
      .eq("resto_id", row.resto_id)
      .gte("created_at", sejak)
      .limit(5000);
    if (errPesanan) {
      throw new Error(`Gagal membaca orders: ${errPesanan.message}`);
    }

    const emails = new Set<string>();
    const sessions = new Set<string>();
    for (const o of pesanan ?? []) {
      if (o.customer_label && o.customer_label !== "Tamu") {
        emails.add(o.customer_label);
      }
      if (o.session_id) sessions.add(o.session_id);
    }

    // Karyawan dikenali dari kolom role-nya. Perangkat pelanggan
    // mendaftar tanpa peran — itulah yang membedakan keduanya, dan
    // itulah satu-satunya penanda yang tersedia di tabel token.
    const target = p.target ?? "all";
    if (target === "employees") {
      return await tokensOf(
        q.eq("resto_id", row.resto_id)
          .not("role", "is", null)
          .not("role", "in", `(${PERAN_PELANGGAN})`),
      );
    }

    const bagian: string[] = [];
    if (target !== "customers") bagian.push(`resto_id.eq.${row.resto_id}`);
    if (emails.size) bagian.push(`email.in.(${[...emails].join(",")})`);
    if (sessions.size) bagian.push(`session_id.in.(${[...sessions].join(",")})`);
    // Pengumuman khusus pelanggan di resto yang belum pernah menerima
    // pesanan tidak punya sasaran sama sekali — dan itu bukan galat.
    if (bagian.length === 0) return [];
    q = q.or(bagian.join(","));

    if (target === "customers") q = q.or(FILTER_PELANGGAN);
  } else {
    // Pemilik pesanan TIDAK disaring restonya.
    //
    // Email dan session id sudah menunjuk satu orang; menambahkan resto
    // hanya menambah satu syarat lagi yang bisa meleset. Dan itu memang
    // meleset: perangkat pelanggan mendaftarkan resto yang sedang dia
    // buka, sedangkan pesanannya menyebut resto tempat dia memesan tadi.
    // Begitu dia menutup halaman menunya atau membuka resto lain,
    // keduanya tidak lagi sama — dan kabar "pesanan kamu siap" berhenti
    // sampai, justru pada saat yang paling dinanti.
    //
    // Pelanggan yang login dikenali dari emailnya, tamu dari session
    // id-nya. Keduanya diperiksa sekaligus karena satu pesanan hanya
    // punya salah satunya.
    const parts: string[] = [];
    if (p.email && p.email !== "Tamu") parts.push(`email.eq.${p.email}`);
    if (p.session_id) parts.push(`session_id.eq.${p.session_id}`);
    if (parts.length === 0) return [];
    q = q.or(parts.join(","));
  }

  return await tokensOf(q);
}

// deno-lint-ignore no-explicit-any
async function tokensOf(query: any): Promise<string[]> {
  const { data, error } = await query;
  if (error) throw new Error(`Gagal membaca device_tokens: ${error.message}`);
  return (data ?? []).map((r: { token: string }) => r.token);
}

// ── Pengiriman ──────────────────────────────────────────────────────

async function send(token: string, row: OutboxRow, bearer: string) {
  const channel = CHANNELS[row.event] ?? "kaata_order_status";
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: row.payload.title, body: row.payload.body },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: channel,
              // Notifikasi untuk kejadian yang sama saling menimpa alih-
              // alih menumpuk jadi lima baris untuk satu pesanan.
              // Kecuali pengumuman: dua pengumuman berbeda adalah dua
              // kabar berbeda, dan yang kedua tidak boleh menghapus yang
              // pertama sebelum sempat dibaca.
              // Tiket support ditandai per tiketnya, bukan per
              // kejadiannya. Dua pengaduan berbeda adalah dua
              // percakapan berbeda — yang kedua tidak boleh menghapus
              // balasan pengaduan pertama sebelum sempat dibaca.
              tag: row.event === "announcement"
                ? row.id
                : row.payload.ticket_id
                  ? `${row.event}:${row.payload.ticket_id}`
                  : row.event,
            },
          },
          // Ikut membawa penunjuk tujuannya, bukan cuma nama
          // kejadiannya.
          //
          // Sebelumnya hanya `event` yang dikirim — dan itu membuat
          // notifikasi yang butuh tujuan tertentu tidak pernah bisa
          // membukanya. Ajakan menilai merchant sudah lama membaca
          // `resto_id` dari sini, dan sudah lama tidak menemukannya.
          //
          // FCM hanya menerima teks di `data`, jadi semuanya
          // ditegaskan jadi string.
          data: {
            event: row.event,
            ...(row.payload.resto_id
              ? { resto_id: String(row.payload.resto_id) }
              : {}),
            ...(row.payload.ticket_id
              ? { ticket_id: String(row.payload.ticket_id) }
              : {}),
          },
        },
      }),
    },
  );

  if (res.ok) return { ok: true as const };

  const body = await res.text();
  // Token yang sudah tidak terdaftar — aplikasinya dicopot, atau datanya
  // dibersihkan. Dibuang di sini, karena kalau dibiarkan setiap kabar
  // berikutnya akan menyeret kegagalan yang sama selamanya.
  if (res.status === 404 || body.includes("UNREGISTERED") || body.includes("INVALID_ARGUMENT")) {
    await admin.from("device_tokens").delete().eq("token", token);
    return { ok: false as const, stale: true, error: body };
  }
  return { ok: false as const, stale: false, error: body };
}

Deno.serve(async (req) => {
  // Fungsinya di-deploy tanpa verifikasi JWT supaya bisa dipanggil
  // trigger database, dan itu berarti siapa pun yang tahu URL-nya bisa
  // memanggilnya juga — termasuk mengirim notifikasi palsu ke perangkat
  // pengguna. Kunci bersama ini yang menutupnya.
  //
  // Kalau secret-nya belum diset, pemeriksaannya dilewati: memaksakannya
  // akan mematikan pengiriman yang sudah berjalan hanya karena satu
  // langkah pemasangan belum dilakukan.
  const expected = Deno.env.get("PUSH_HOOK_SECRET");
  if (expected && req.headers.get("x-kaata-hook-secret") !== expected) {
    return new Response("ditolak", { status: 401 });
  }

  let row: OutboxRow | null = null;
  try {
    const payload = await req.json();
    row = (payload.record ?? payload) as OutboxRow;
    if (!row?.id || !row?.payload) {
      return new Response("bukan baris push_outbox", { status: 400 });
    }

    const tokens = await resolveTokens(row);
    if (tokens.length === 0) {
      // Bukan kegagalan: tidak ada perangkat terdaftar yang cocok. Tetap
      // ditandai selesai supaya tidak terlihat menggantung, tapi
      // sebabnya dicatat.
      await admin.from("push_outbox").update({
        sent_at: new Date().toISOString(),
        error: "tidak ada perangkat terdaftar",
        attempts: 1,
      }).eq("id", row.id);
      return new Response(JSON.stringify({ sent: 0 }), { status: 200 });
    }

    const bearer = await accessToken();
    const results = await Promise.all(tokens.map((t) => send(t, row!, bearer)));
    const sent = results.filter((r) => r.ok).length;
    const failed = results.filter((r) => !r.ok);

    await admin.from("push_outbox").update({
      sent_at: new Date().toISOString(),
      attempts: 1,
      error: failed.length === 0
        ? null
        : `${sent}/${tokens.length} terkirim · ${failed[0].error}`.slice(0, 500),
    }).eq("id", row.id);

    return new Response(JSON.stringify({ sent, failed: failed.length }), { status: 200 });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (row?.id) {
      await admin.from("push_outbox").update({
        error: message.slice(0, 500),
        attempts: 1,
      }).eq("id", row.id);
    }
    // 200, bukan 500: webhook Supabase akan mengulang panggilan yang
    // gagal, dan mengulang kabar yang sama berkali-kali lebih mengganggu
    // daripada satu kabar yang hilang. Sebabnya sudah tercatat di
    // barisnya.
    return new Response(JSON.stringify({ error: message }), { status: 200 });
  }
});
