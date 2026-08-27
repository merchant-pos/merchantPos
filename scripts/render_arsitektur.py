"""Menggambar arsitektur MerchantPOS jadi PNG untuk dokumen Word.

Dua gambar, dan keduanya menjelaskan sistem yang sama dari dua tempat
berdiri yang berbeda:

  Pov pengguna  — siapa memakai apa, dan apa yang berpindah di antara
                  mereka. Tidak ada satu pun nama teknologi di sini.
  Pov teknikal  — lapisannya, dan apa yang berbicara ke apa.

Dipisah karena pembacanya berbeda. Orang resto yang membaca diagram
berisi "pg_net" dan "RLS" tidak menemukan dirinya di sana, dan pengembang
yang membaca diagram berisi "Kasir menerima uang" tidak menemukan tempat
menambal kodenya. Menggabungkan keduanya menghasilkan satu gambar yang
gagal untuk kedua pembacanya sekaligus.
"""

import os

from PIL import Image, ImageDraw, ImageFont

SCALE = 3

BRAND = (79, 70, 229)
BRAND_SOFT = (238, 237, 252)
AMBER = (245, 158, 11)
AMBER_SOFT = (255, 247, 230)
GREEN = (16, 185, 129)
GREEN_SOFT = (236, 253, 245)
BLUE = (14, 165, 233)
BLUE_SOFT = (236, 250, 255)
PINK = (219, 39, 119)
PINK_SOFT = (253, 242, 248)
SLATE = (100, 116, 139)
SLATE_SOFT = (241, 245, 249)
INK = (20, 21, 42)
MUTED = (110, 114, 140)
LINE = (206, 209, 228)
PAPER = (255, 255, 255)
BAND = (250, 250, 253)

TONE = {
    "ungu": (BRAND_SOFT, BRAND),
    "kuning": (AMBER_SOFT, AMBER),
    "hijau": (GREEN_SOFT, GREEN),
    "biru": (BLUE_SOFT, BLUE),
    "pink": (PINK_SOFT, PINK),
    "abu": (SLATE_SOFT, SLATE),
}

FONT_DIR = "/System/Library/Fonts/Supplemental"


def _font(size, bold=False):
    name = "Arial Bold.ttf" if bold else "Arial.ttf"
    try:
        return ImageFont.truetype(f"{FONT_DIR}/{name}", size * SCALE)
    except OSError:
        return ImageFont.load_default()


def _wrap(draw, text, font, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=font) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


class Blok:
    """Satu kotak. `isi` boleh kosong — sebagian kotak cukup namanya."""

    def __init__(self, nama, isi, tone, col, span=1):
        self.nama = nama
        self.isi = isi
        self.tone = tone
        self.col = col
        self.span = span
        self.x = self.y = self.w = self.h = 0


class Lajur:
    """Satu pita mendatar berisi beberapa blok, dengan judul di kirinya."""

    def __init__(self, judul, ket, blok):
        self.judul = judul
        self.ket = ket
        self.blok = blok


def render(lajur, panah, path, cols=4, width=780, judul=None, lebar_judul=96):
    W = width * SCALE
    pad = 16 * SCALE
    gap_x = 12 * SCALE
    gap_y = 30 * SCALE
    box_pad = 8 * SCALE
    LJ = lebar_judul * SCALE

    f_judul = _font(13, bold=True)
    f_lajur = _font(10, bold=True)
    f_ket = _font(8)
    f_nama = _font(10, bold=True)
    f_isi = _font(8)
    f_panah = _font(8)

    area = W - 2 * pad - LJ
    kol_w = (area - gap_x * (cols - 1)) // cols

    probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))

    line_nama = int(f_nama.size * 1.45)
    line_isi = int(f_isi.size * 1.4)

    atas = pad + (int(f_judul.size * 2.2) if judul else 0)
    y = atas
    for lj in lajur:
        tinggi = 0
        for b in lj.blok:
            b.w = kol_w * b.span + gap_x * (b.span - 1)
            b.isi_wrap = []
            for baris in b.isi:
                b.isi_wrap += _wrap(probe, baris, f_isi, b.w - 2 * box_pad)
            b.h = line_nama + len(b.isi_wrap) * line_isi + 2 * box_pad
            tinggi = max(tinggi, b.h)
        for b in lj.blok:
            b.x = pad + LJ + b.col * (kol_w + gap_x)
            b.y = y
            b.h = tinggi
        lj.y, lj.h = y, tinggi
        y += tinggi + gap_y
    total_h = y - gap_y + pad

    img = Image.new("RGB", (W, total_h), PAPER)
    draw = ImageDraw.Draw(img)

    if judul:
        draw.text((pad, pad), judul, font=f_judul, fill=INK)

    # Pita latar tiap lajur lebih dulu — supaya kotak dan garis di
    # atasnya, bukan sebaliknya.
    for lj in lajur:
        draw.rounded_rectangle(
            [pad, lj.y - box_pad, W - pad, lj.y + lj.h + box_pad],
            radius=10 * SCALE, fill=BAND,
        )
        ty = lj.y + (lj.h - int(f_lajur.size * 1.4) - int(f_ket.size * 1.3)) // 2
        draw.text((pad + box_pad, ty), lj.judul, font=f_lajur, fill=INK)
        ty += int(f_lajur.size * 1.5)
        for baris in _wrap(draw, lj.ket, f_ket, LJ - 2 * box_pad):
            draw.text((pad + box_pad, ty), baris, font=f_ket, fill=MUTED)
            ty += int(f_ket.size * 1.3)

    peta = {b.nama: b for lj in lajur for b in lj.blok}

    label_nanti = []
    for item in panah:
        dari, ke, label = item[0], item[1], item[2]
        lewat = item[3] * W if len(item) > 3 else None
        a, b = peta[dari], peta[ke]
        titik = _panah(draw, a, b, lewat)
        if label:
            label_nanti.append((titik, label))

    for lj in lajur:
        for b in lj.blok:
            isi, tepi = TONE[b.tone]
            draw.rounded_rectangle(
                [b.x, b.y, b.x + b.w, b.y + b.h],
                radius=8 * SCALE, fill=isi, outline=tepi, width=2 * SCALE,
            )
            fn, uk = f_nama, 10
            while draw.textlength(b.nama, font=fn) > b.w - 2 * box_pad and uk > 6:
                uk -= 1
                fn = _font(uk, bold=True)
            draw.text((b.x + box_pad, b.y + box_pad), b.nama, font=fn, fill=tepi)
            ty = b.y + box_pad + line_nama
            for baris in b.isi_wrap:
                draw.text((b.x + box_pad, ty), baris, font=f_isi, fill=INK)
                ty += line_isi

    # Label paling akhir. Digambar bersama panahnya, ia tertimpa kotak
    # yang datang sesudahnya — dan yang tertimpa justru label di celah
    # sempit antara dua kotak bersebelahan.
    for (mx, my), label in label_nanti:
        tw = draw.textlength(label, font=f_panah)
        mx = min(max(mx, tw / 2 + pad), W - tw / 2 - pad)
        draw.rectangle(
            [mx - tw / 2 - 3 * SCALE, my - f_panah.size * 0.8,
             mx + tw / 2 + 3 * SCALE, my + f_panah.size * 0.8],
            fill=PAPER,
        )
        draw.text((mx - tw / 2, my - f_panah.size * 0.6), label,
                  font=f_panah, fill=MUTED)

    img = img.resize((W // SCALE, total_h // SCALE), Image.LANCZOS)
    img.save(path)
    print("ditulis:", os.path.basename(path), img.size)


def _panah(draw, a, b, lewat=None):
    """Panah bersiku dari blok a ke blok b. Mengembalikan titik labelnya.

    `lewat` adalah koordinat x lorong tegak yang harus dilewati. Dipakai
    saat panahnya melompati satu lajur: tanpa itu, batang tegaknya jatuh
    tepat di tengah kotak lajur yang dilompati, dan garis yang menembus
    kotak terbaca seolah menyentuh kotak itu.
    """
    def garis(x1, y1, x2, y2):
        draw.line([x1, y1, x2, y2], fill=MUTED, width=2 * SCALE)

    if abs(b.y - a.y) < 4:  # sebaris
        if b.x > a.x:
            x1, x2 = a.x + a.w, b.x
        else:
            x1, x2 = a.x, b.x + b.w
        yy = a.y + a.h / 2
        garis(x1, yy, x2, yy)
        _kepala(draw, x2, yy, 1 if x2 > x1 else -1, 0)
        return ((x1 + x2) / 2, yy)

    turun = b.y > a.y
    x1 = a.x + a.w / 2
    x2 = b.x + b.w / 2
    y1 = a.y + a.h if turun else a.y
    y2 = b.y if turun else b.y + b.h

    if lewat is None:
        ym = (y1 + y2) / 2
        garis(x1, y1, x1, ym)
        garis(x1, ym, x2, ym)
        garis(x2, ym, x2, y2)
        _kepala(draw, x2, y2, 0, 1 if turun else -1)
        return ((x1 + x2) / 2, ym)

    # Keluar dari a, menyamping ke lorong, turun melewati lajur di
    # antaranya, lalu menyamping lagi masuk ke b.
    ya = y1 + 12 * SCALE * (1 if turun else -1)
    yb = y2 - 12 * SCALE * (1 if turun else -1)
    garis(x1, y1, x1, ya)
    garis(x1, ya, lewat, ya)
    garis(lewat, ya, lewat, yb)
    garis(lewat, yb, x2, yb)
    garis(x2, yb, x2, y2)
    _kepala(draw, x2, y2, 0, 1 if turun else -1)
    # Labelnya di ruas mendatar atas — ruas itu jatuh di sela antar-lajur
    # yang memang kosong. Di tengah batang tegaknya, ia mendarat tepat di
    # atas kotak lajur yang sedang dilewati dan menutupi tulisannya.
    return ((x1 + lewat) / 2, ya)


def _kepala(draw, x, y, dx, dy):
    s = 5 * SCALE
    if dy:
        p = [(x, y), (x - s, y - s * dy), (x + s, y - s * dy)]
    else:
        p = [(x, y), (x - s * dx, y - s), (x - s * dx, y + s)]
    draw.polygon(p, fill=MUTED)


if __name__ == "__main__":
    REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    OUT = os.path.join(REPO, "docs", "gambar")
    os.makedirs(OUT, exist_ok=True)

    # ── Pov pengguna ─────────────────────────────────────────────────
    #
    # Tidak ada satu pun nama teknologi. Yang digambarkan adalah apa
    # yang berpindah tangan: pesanan, uang, dan catatannya.
    #
    # Urutan kotak di lajur RESTO mengikuti urutan kejadian dari kiri ke
    # kanan — Pending Payment, lalu Kasir, lalu Dapur. Uang tunai
    # berpindah tangan di Kasir, dan itu titik yang tidak boleh dilompati:
    # dari sanalah pesanannya lanjut ke dapur dan catatannya masuk
    # pembukuan.
    render(
        [
            Lajur("PELANGGAN", "HP sendiri, tanpa perlu akun", [
                Blok("Pesan dari meja", ["Scan QR meja atau pilih resto",
                                         "Pilih menu, level, catatan"],
                     "ungu", 0, span=2),
                Blok("Bayar", ["QRIS langsung dari HP,",
                               "atau tunai di kasir"], "ungu", 2, span=2),
            ]),
            Lajur("RESTO", "Yang melayani pesanan", [
                Blok("Pending Payment", ["Pesanan dari HP yang",
                                         "memilih bayar tunai"], "kuning", 0),
                Blok("Kasir", ["Menerima uang tunai",
                               "Input pesanan di konter",
                               "Cetak struk"], "kuning", 1),
                Blok("Dapur", ["Masuk antrean hanya",
                               "sesudah lunas"], "kuning", 2),
                Blok("Admin", ["Menu, harga, stok",
                               "Banner, QR meja, promo"], "hijau", 3),
            ]),
            Lajur("KEUANGAN", "Yang menjaga uangnya", [
                Blok("Setor & kas kecil", ["Kasir mengajukan,",
                                           "Finance menyetujui"], "biru", 0,
                     span=2),
                Blok("Pembukuan", ["Jurnal GL tercatat sendiri",
                                   "saat pesanan lunas"], "biru", 2, span=2),
            ]),
            Lajur("PEMILIK", "Yang melihat semuanya", [
                Blok("Owner", ["Seluruh layar di atas, untuk tiap resto",
                               "yang dimilikinya"], "ungu", 0, span=2),
                Blok("Super Admin", ["Daftar resto, karyawan lintas resto,",
                                     "pengumuman versi aplikasi"],
                     "abu", 2, span=2),
            ]),
        ],
        [
            ("Pesan dari meja", "Bayar", None),
            ("Bayar", "Pending Payment", "kalau tunai"),
            ("Bayar", "Dapur", "kalau QRIS — lunas seketika"),
            ("Pending Payment", "Kasir", None),
            ("Kasir", "Dapur", None),
            ("Kasir", "Setor & kas kecil", "uang tunai di laci"),
            ("Kasir", "Pembukuan", "jurnal saat lunas"),
            ("Setor & kas kecil", "Pembukuan", None),
        ],
        f"{OUT}/arsitektur-01-pengguna.png",
        judul="Arsitektur dari sisi pengguna — siapa memakai apa, dan apa yang berpindah",
        lebar_judul=104,
    )

    # ── Pov teknikal ─────────────────────────────────────────────────
    render(
        [
            Lajur("APLIKASI", "Flutter, satu APK Android", [
                Blok("Layar", ["51 layar", "Tidak pernah memanggil",
                               "Supabase langsung"], "ungu", 0),
                Blok("Provider", ["9 penyimpan keadaan",
                                  "Keranjang, sesi, tema"], "ungu", 1),
                Blok("Repository", ["23 berkas", "Satu-satunya yang",
                                    "menyentuh data"], "ungu", 2),
                Blok("Model & Utils", ["Perhitungan murni",
                                       "Pajak, diskon, status",
                                       "— bisa diuji tanpa layar"], "ungu", 3),
            ]),
            Lajur("PERANGKAT", "Yang tetap ada saat luring", [
                Blok("sqflite v12", ["Katalog & transaksi lokal"], "abu", 0,
                     span=2),
                Blok("SharedPreferences", ["Tema, sesi, daftar pesanan tamu"],
                     "abu", 2, span=2),
            ]),
            Lajur("SUPABASE", "Pengganti server aplikasi", [
                Blok("Postgres + RLS", ["27 tabel",
                                        "is_resto_employee()",
                                        "is_super_admin()"], "hijau", 0),
                Blok("Pemicu & RPC", ["Jurnal GL otomatis",
                                      "cancel_my_order,",
                                      "claim_guest_orders"], "hijau", 1),
                Blok("Edge Functions", ["5 fungsi Deno",
                                        "create-qris, send-push,",
                                        "xendit-webhook, …"], "hijau", 2),
                Blok("pg_cron · pg_net", ["Pesanan hangus 30 menit",
                                          "Sesi meja tutup sendiri",
                                          "Antrean push"], "hijau", 3),
            ]),
            Lajur("LUAR", "Pihak ketiga", [
                Blok("Xendit", ["QRIS: membuat tagihan,",
                                "mengabarkan lunas"], "kuning", 0),
                Blok("FCM v1", ["Dikirimi send-push;",
                                "aplikasi mendaftarkan",
                                "tokennya sendiri"], "kuning", 1),
                Blok("Resend", ["Struk lewat email"], "kuning", 2),
                Blok("GitHub Release", ["APK & pengumuman versi"], "kuning", 3),
            ]),
        ],
        [
            ("Layar", "Provider", None),
            ("Provider", "Repository", None),
            ("Repository", "sqflite v12", "luring"),
            ("Repository", "Postgres + RLS", "HTTPS", 0.567),
            ("Pemicu & RPC", "Edge Functions", "pg_net"),
            ("pg_cron · pg_net", "Edge Functions", None),
            ("Edge Functions", "Xendit", None),
            ("Edge Functions", "FCM v1", None),
            ("Edge Functions", "Resend", None),
        ],
        f"{OUT}/arsitektur-02-teknikal.png",
        judul="Arsitektur teknis — tidak ada lapisan server sendiri di antaranya",
        lebar_judul=104,
    )
