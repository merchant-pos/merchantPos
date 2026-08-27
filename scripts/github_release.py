#!/usr/bin/env python3
"""Menerbitkan APK sebagai aset GitHub Release.

Dipanggil oleh scripts/release.sh. Berdiri sendiri supaya bagian yang
berurusan dengan API punya penanganan galat yang layak — token
kedaluwarsa harus terbaca sebagai token kedaluwarsa, bukan sebagai
"gagal".

Rilis lama dihapus lebih dulu: URL "releases/latest/download" hanya
menunjuk satu rilis, jadi menumpuknya cuma menyimpan APK usang yang tak
pernah diunduh siapa pun.

Sebelum dihapus, jumlah unduhannya dipanen ke downloads.json. Angka itu
menempel pada rilis — ikut terhapus bersamanya — sehingga tanpa dipanen
lebih dulu, penghitung di landing page akan kembali nol setiap kali versi
baru terbit.

Permintaannya dikirim lewat `curl`, bukan urllib. Python bawaan Homebrew
di mesin ini tidak dipasangi sertifikat CA, sehingga setiap koneksi HTTPS
gagal di tahap verifikasi; curl memakai penyimpanan sertifikat sistem dan
jalan begitu saja.
"""

import json
import os
import subprocess
import sys

API = "https://api.github.com"


def request(token, method, url, *, body=None, body_file=None, content_type=None):
    """Mengembalikan (kode_http, objek_json_atau_None)."""
    cmd = [
        "curl", "-sS", "-X", method,
        "-o", "/dev/stdout", "-w", "\n%{http_code}",
        "-H", f"Authorization: Bearer {token}",
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: 2022-11-28",
    ]
    if content_type:
        cmd += ["-H", f"Content-Type: {content_type}"]
    if body is not None:
        cmd += ["-d", body]
    if body_file is not None:
        cmd += ["--data-binary", f"@{body_file}"]
    cmd.append(url)

    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"curl gagal ({proc.returncode}): {proc.stderr.strip()}")

    out = proc.stdout.rsplit("\n", 1)
    payload, status = (out[0], out[1]) if len(out) == 2 else ("", out[0])
    try:
        parsed = json.loads(payload) if payload.strip() else None
    except json.JSONDecodeError:
        parsed = None

    code = int(status)
    if code >= 400:
        detail = (parsed or {}).get("message", payload[:300]) if parsed else payload[:300]
        hint = ""
        if code in (401, 403):
            hint = "\n  Token-nya kedaluwarsa atau kurang izin tulis pada repo ini."
        elif code == 404:
            hint = "\n  Repo tidak ditemukan — atau token tidak diberi akses ke repo ini."
        raise SystemExit(f"GitHub menolak {method} {url}\n  HTTP {code}: {detail}{hint}")

    return code, parsed


def carry_forward(path, harvested):
    """Menambahkan unduhan rilis yang akan dihapus ke saldo awal.

    Halaman menjumlahkan saldo ini dengan unduhan rilis yang sedang
    berjalan, sehingga totalnya terus naik alih-alih ikut hilang bersama
    rilis lamanya.
    """
    try:
        with open(path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}

    before = int(data.get("carried", 0))
    data["carried"] = before + harvested
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"  unduhan dipanen: +{harvested} (saldo awal {before} → {data['carried']})")


def main():
    if len(sys.argv) not in (6, 7):
        raise SystemExit(
            "pakai: github_release.py <repo> <tag> <nama> <catatan> <path-apk> "
            "[downloads.json]"
        )
    repo, tag, name, body, apk_path = sys.argv[1:6]
    tally_path = sys.argv[6] if len(sys.argv) == 7 else None

    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise SystemExit("GITHUB_TOKEN kosong.")
    if not os.path.isfile(apk_path):
        raise SystemExit(f"APK tidak ditemukan: {apk_path}")

    _, releases = request(token, "GET", f"{API}/repos/{repo}/releases?per_page=100")

    harvested = sum(
        a.get("download_count", 0)
        for r in releases or []
        for a in r.get("assets", [])
    )
    if tally_path and harvested:
        carry_forward(tally_path, harvested)

    for r in releases or []:
        request(token, "DELETE", f"{API}/repos/{repo}/releases/{r['id']}")
        print(f"  rilis lama dihapus: {r.get('tag_name') or r['id']}")

    # Tag ikut dibuang. Kalau ditinggal, rilis baru bertag sama akan
    # menempel ke commit lama alih-alih yang terkini. Tag yang memang
    # belum ada akan menjawab 404 — dan itu justru keadaan yang dituju,
    # jadi bukan kegagalan.
    cmd = [
        "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
        "-X", "DELETE",
        "-H", f"Authorization: Bearer {token}",
        "-H", "Accept: application/vnd.github+json",
        f"{API}/repos/{repo}/git/refs/tags/{tag}",
    ]
    subprocess.run(cmd, capture_output=True, text=True)

    payload = json.dumps({
        "tag_name": tag,
        "name": name,
        "body": body,
        "draft": False,
        "prerelease": False,
    })
    _, release = request(
        token, "POST", f"{API}/repos/{repo}/releases",
        body=payload, content_type="application/json",
    )
    print(f"  rilis dibuat: {tag}")

    upload_url = release["upload_url"].split("{")[0]

    # Diunggah dua kali dengan nama berbeda, dan itu disengaja.
    #
    # Yang bernomor versi supaya berkas yang mendarat di HP orang bisa
    # dibedakan — folder unduhan berisi lima "MerchantPOS.apk (3)" tidak
    # memberi tahu siapa pun mana yang terbaru.
    #
    # Yang bernama tetap supaya URL "releases/latest/download/MerchantPOS.apk"
    # tetap hidup. URL itu sudah tersebar di mana-mana, dan tautan yang
    # mati karena penggantian nama adalah orang yang gagal memasang
    # aplikasinya tanpa tahu kenapa.
    versi = tag.lstrip("v")
    for nama in (f"MerchantPOS-{versi}.apk", "MerchantPOS.apk"):
        request(
            token, "POST", f"{upload_url}?name={nama}",
            body_file=apk_path,
            content_type="application/vnd.android.package-archive",
        )
    print(f"  https://github.com/{repo}/releases/download/{tag}/MerchantPOS-{versi}.apk")
    print(f"  https://github.com/{repo}/releases/latest/download/MerchantPOS.apk")


if __name__ == "__main__":
    main()
