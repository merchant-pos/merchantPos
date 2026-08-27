// KaataGo — menerbitkan pengumuman versi baru dari skrip rilis.
//
// Sebelumnya pengumuman versi harus dikirim manual lewat akun Super
// Admin, setelah APK-nya terbit. Dua langkah terpisah yang harus
// diingat berurutan berarti suatu saat yang kedua terlewat — dan
// pembaruan yang tidak diumumkan sama saja dengan pembaruan yang tidak
// pernah dirilis.
//
// Fungsi ini yang memegang hak menulisnya, bukan skrip di laptop.
// Skripnya cukup memegang satu kunci bersama yang kemampuannya persis
// satu: menerbitkan pengumuman versi. Kalau laptopnya bocor, yang bisa
// dilakukan orang paling jauh mengumumkan versi palsu — bukan membaca
// seluruh isi database, yang akan terjadi kalau service role key
// dititipkan ke sana.
//
// Deploy:
//   supabase functions deploy publish-release \
//     --project-ref xizpwtycczigjhzxegen --no-verify-jwt
//
// Secret:
//   RELEASE_HOOK_SECRET

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const DOWNLOAD_URL =
  "https://github.com/bujejuki-spec/KaataGo-LandingPage/releases/latest/download/KaataGo.apk";

Deno.serve(async (req) => {
  const expected = Deno.env.get("RELEASE_HOOK_SECRET");
  if (!expected) {
    return json({ error: "RELEASE_HOOK_SECRET belum diset" }, 500);
  }
  if (req.headers.get("x-kaata-release-secret") !== expected) {
    return new Response("ditolak", { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "badan permintaan bukan JSON" }, 400);
  }

  const version = String(body.version ?? "").trim();
  if (!version) return json({ error: "version wajib diisi" }, 400);

  // Rilis yang sudah diumumkan tidak diumumkan lagi.
  //
  // Skrip rilis boleh dijalankan ulang — build gagal di tengah, jaringan
  // putus saat mengunggah — dan tiap pengulangan tidak boleh menambah
  // satu baris lagi ke kotak masuk semua orang.
  const { data: existing } = await admin
    .from("app_announcements")
    .select("id")
    .eq("category", "update")
    .eq("version", version)
    .maybeSingle();

  if (existing) return json({ skipped: "versi ini sudah diumumkan" });

  // Isinya sengaja sama dengan template yang disodorkan ke Super Admin,
  // dan sengaja tidak merinci apa saja yang berubah. Daftar perubahan
  // yang ditulis mesin akan berisi hal yang tidak dimengerti
  // pembacanya — dan pengumuman yang tidak dimengerti akan berhenti
  // dibaca pada rilis berikutnya. Yang perlu diketahui pemakainya cuma
  // satu: ada yang baru, dan ini cara mengambilnya.
  const title = String(body.title ?? `KaataGo ${version} sudah tersedia`);
  const message = String(
    body.body ??
      "Versi baru KaataGo sudah bisa diunduh. Perbarui aplikasimu untuk " +
        "mendapat perbaikan dan fitur terbaru.",
  );

  const { error } = await admin.from("app_announcements").insert({
    title,
    body: message,
    category: "update",
    version,
    download_url: String(body.download_url ?? DOWNLOAD_URL),
    created_by: "sistem",
  });

  if (error) return json({ error: error.message }, 500);
  return json({ published: version });
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
