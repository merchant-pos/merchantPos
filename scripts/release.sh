#!/usr/bin/env bash
#
# MerchantPOS — rilis sekali jalan.
#
#   1. build APK release
#   2. salin ke folder "MerchantPOS Realase/" dengan nama bernomor versi
#   3. unggah sebagai aset GitHub Release di repo landing page
#   4. hapus rilis lama supaya cuma yang terbaru yang tersisa
#   5. tulis ulang nomor versi & ukuran di landing page, lalu push
#
# Aset rilis sengaja TIDAK di-commit ke Git. Git menyimpan setiap versi
# file selamanya, jadi APK 78 MB yang "dihapus" di commit berikutnya
# tetap tinggal di riwayat — sepuluh rilis berarti repo 780 MB yang harus
# diunduh siapa pun yang clone. GitHub Release menyimpan asetnya di luar
# riwayat, dan URL "releases/latest/download/MerchantPOS.apk" selalu menunjuk
# ke yang terbaru sehingga link di landing page tidak pernah perlu ganti.
#
# Butuh sebuah GitHub Personal Access Token berizin `repo`, dibaca dari
# (urut prioritas):
#   - variabel lingkungan GITHUB_TOKEN
#   - berkas ~/.config/merchantpos/release-token
#
# Pakai:
#   scripts/release.sh              rilis versi yang tertulis di pubspec
#   scripts/release.sh --dry-run    jalankan semuanya kecuali unggah & push
#   scripts/release.sh --ulang      timpa rilis yang versinya sudah terbit

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$(cd "$APP_DIR/.." && pwd)/MerchantPOS Web"
RELEASE_DIR="$APP_DIR/MerchantPOS Realase"
REPO="bujejuki-spec/MerchantPOS-LandingPage"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log()  { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── Prasyarat ────────────────────────────────────────────────────────
[[ -d "$WEB_DIR" ]] || fail "Repo landing page tidak ditemukan di: $WEB_DIR"
command -v python3 >/dev/null || fail "python3 tidak tersedia."

TOKEN="${GITHUB_TOKEN:-}"
if [[ -z "$TOKEN" && -f "$HOME/.config/merchantpos/release-token" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$HOME/.config/merchantpos/release-token")"
fi
if [[ -z "$TOKEN" && "$DRY_RUN" == false ]]; then
  fail "Token GitHub belum ada.

Buat sekali di https://github.com/settings/tokens (klasik, centang scope 'repo'),
lalu simpan:

  mkdir -p ~/.config/merchantpos
  printf '%s' 'TOKEN_KAMU' > ~/.config/merchantpos/release-token
  chmod 600 ~/.config/merchantpos/release-token"
fi

VERSION="$(grep '^version:' "$APP_DIR/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)"
BUILD="$(grep '^version:' "$APP_DIR/pubspec.yaml" | awk '{print $2}' | cut -d+ -f2)"
[[ -n "$VERSION" ]] || fail "Tidak bisa membaca version dari pubspec.yaml"
TAG="v$VERSION"

log "Merilis MerchantPOS $VERSION (build $BUILD)"
$DRY_RUN && echo "  (dry run — tidak ada yang diunggah atau di-push)"

# ── 0. Versi ini sudah pernah terbit? ────────────────────────────────
#
# Menjalankan ulang rilis untuk versi yang sama bukan sekadar mubazir.
# Rilisnya dihapus lalu dibuat ulang — dan yang ikut hilang bersamanya
# angka unduhan yang belum sempat dipanen. Pengumumannya juga terkirim
# dua kali ke seluruh kotak masuk, dan yang menerimanya tidak punya cara
# tahu itu kabar yang sama.
#
# Kalau memang disengaja — build gagal separuh jalan, misalnya — lewati
# dengan --ulang.
if ! $DRY_RUN && [[ "${1:-}" != "--ulang" ]]; then
  SUDAH="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases/tags/$TAG" || echo 000)"
  if [[ "$SUDAH" == "200" ]]; then
    fail "Rilis $TAG sudah ada di GitHub.

Naikkan versinya di pubspec.yaml, atau — kalau memang mau menimpa yang
sudah ada — jalankan:

  scripts/release.sh --ulang"
  fi
fi

# ── 1. Build ─────────────────────────────────────────────────────────
log "Build APK release"
export PATH="$HOME/development/flutter/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/jdk-17.0.13+11/Contents/Home}"
( cd "$APP_DIR" && flutter build apk --release )

BUILT="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$BUILT" ]] || fail "APK hasil build tidak ditemukan."

mkdir -p "$RELEASE_DIR"
LOCAL_COPY="$RELEASE_DIR/MerchantPOS-Release-$VERSION.apk"
cp "$BUILT" "$LOCAL_COPY"

SIZE_MB="$(( $(stat -f%z "$BUILT") / 1048576 ))"
log "APK siap — ${SIZE_MB} MB → $LOCAL_COPY"

# ── 2. Rilis GitHub ──────────────────────────────────────────────────
if $DRY_RUN; then
  log "Lewati unggah rilis (dry run)"
else
  log "Menerbitkan rilis $TAG"
  GITHUB_TOKEN="$TOKEN" python3 "$APP_DIR/scripts/github_release.py" \
    "$REPO" "$TAG" "MerchantPOS $VERSION" \
    "Build $BUILD · ${SIZE_MB} MB · Android 6.0 ke atas" \
    "$BUILT" "$WEB_DIR/downloads.json"
fi

# ── 3. Landing page ──────────────────────────────────────────────────
log "Menyesuaikan nomor versi di landing page"
python3 - "$WEB_DIR/index.html" "$VERSION" "$SIZE_MB" "$REPO" "$TAG" <<'PY'
import re, sys
path, version, size, repo, tag = sys.argv[1:6]
html = open(path).read()

# Penanda yang hilang berarti halamannya akan diam-diam terus menampilkan
# versi lama — lebih baik gagal keras daripada merilis halaman yang
# berbohong soal versinya. Diperiksa keberadaannya, bukan perubahannya:
# merilis ulang versi yang sama sah-sah saja dan tidak boleh dianggap
# galat.
for marker in ('<code id="app-version">', '<span id="app-size">', 'var APK_URL'):
    if marker not in html:
        sys.exit(f'Penanda {marker} tidak ditemukan di index.html')

html = re.sub(r'(<code id="app-version">)[^<]*(</code>)', rf'\g<1>{version}\g<2>', html)
html = re.sub(r'(<span id="app-size">)[^<]*(</span>)', rf'\g<1>± {size} MB\g<2>', html)

# Tautannya menunjuk berkas bernomor versi, supaya yang mendarat di HP
# orang bisa dibedakan. Aset bernama tetap tetap diunggah juga, jadi
# tautan lama yang sudah tersebar tidak ikut mati.
apk = f'https://github.com/{repo}/releases/download/{tag}/MerchantPOS-{version}.apk'
html = re.sub(r'(var APK_URL = ")[^"]*(")', rf'\g<1>{apk}\g<2>', html)

open(path, 'w').write(html)
print(f'  versi → {version}, ukuran → ± {size} MB')
print(f'  tautan unduh → MerchantPOS-{version}.apk')
PY

if $DRY_RUN; then
  log "Lewati commit & push landing page (dry run)"
else
  if git -C "$WEB_DIR" diff --quiet; then
    log "Landing page sudah sesuai — tidak ada yang perlu di-commit"
  else
    log "Commit & push landing page"
    git -C "$WEB_DIR" add -A
    git -C "$WEB_DIR" commit -q -m "Rilis MerchantPOS $VERSION

Nomor versi dan ukuran unduhan mengikuti build $BUILD. APK-nya ada di
GitHub Release $TAG; link unduh di halaman ini menunjuk ke
releases/latest/download sehingga tidak perlu ikut berubah."
    git -C "$WEB_DIR" push -q origin main
  fi
fi

# ── 4. Pengumuman di kotak masuk ─────────────────────────────────────
#
# Diumumkan dari sini, bukan diketik ulang lewat akun Super Admin.
# Dua langkah terpisah yang harus diingat berurutan berarti suatu saat
# yang kedua terlewat — dan pembaruan yang tidak diumumkan sama saja
# dengan pembaruan yang tidak pernah dirilis.
#
# Kuncinya bukan service role key. Yang dititipkan ke laptop ini hanya
# kunci bersama yang kemampuannya persis satu: menerbitkan pengumuman
# versi. Kalau laptopnya bocor, yang bisa dilakukan orang paling jauh
# mengumumkan versi palsu.
ANNOUNCE_FN="https://xizpwtycczigjhzxegen.supabase.co/functions/v1/publish-release"
ANNOUNCE_SECRET_FILE="$HOME/.config/merchantpos/release-hook-secret"

log "Mengumumkan ke kotak masuk"
if $DRY_RUN; then
  printf '  (dry-run) dilewati\n'
elif [[ ! -f "$ANNOUNCE_SECRET_FILE" ]]; then
  # Bukan kegagalan rilis. APK-nya sudah terbit dan bisa diunduh; yang
  # belum cuma kabarnya, dan itu masih bisa dikirim manual.
  printf '  dilewati — %s belum ada\n' "$ANNOUNCE_SECRET_FILE"
else
  # Catatan rilisnya diambil dari docs/CATATAN-RILIS.md, bagian yang
  # judulnya sama dengan versi ini. Versi tanpa bagiannya tetap terbit —
  # pengumumannya memakai kalimat umum, dan itu lebih baik daripada
  # menahan rilis karena catatannya belum sempat ditulis.
  ANNOUNCE_BODY=$(python3 "$APP_DIR/scripts/catatan_rilis.py" \
    "$APP_DIR/docs/CATATAN-RILIS.md" "$VERSION")

  ANNOUNCE_RESULT=$(curl -s -X POST "$ANNOUNCE_FN" \
    -H "Content-Type: application/json" \
    -H "x-kaata-release-secret: $(cat "$ANNOUNCE_SECRET_FILE")" \
    -d "$ANNOUNCE_BODY" || true)
  printf '  %s\n' "${ANNOUNCE_RESULT:-tidak ada jawaban}"
fi

log "Selesai — MerchantPOS $VERSION"
