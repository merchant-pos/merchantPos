"""Menggambar diagram relasi tabel MerchantPOS jadi PNG untuk dokumen Word.

Sengaja dipecah jadi beberapa gambar per wilayah, bukan satu ERD berisi
27 tabel. Satu gambar besar memang memuat semuanya, tapi pada lebar
kertas A4 tulisannya jadi terlalu kecil untuk dibaca — dan diagram yang
tidak terbaca sama saja dengan tidak ada.

Dua jenis garis, dan bedanya bukan hiasan:

  garis penuh   — kunci asing sungguhan; database yang menegakkannya
  garis putus   — cuma kesepakatan; tidak ada yang mencegahnya melanggar

Membedakan keduanya penting justru karena yang putus terlihat sama
persis dengan yang penuh saat membaca kode. Yang putus adalah tempat
data yatim bisa muncul.
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
INK = (20, 21, 42)
MUTED = (110, 114, 140)
LINE = (206, 209, 228)
PAPER = (255, 255, 255)

# Warna per wilayah. Kuncinya dipakai di definisi tiap tabel.
TONE = {
    "inti": (BRAND_SOFT, BRAND, INK),
    "katalog": (GREEN_SOFT, GREEN, INK),
    "pesanan": (AMBER_SOFT, AMBER, INK),
    "uang": (BLUE_SOFT, BLUE, INK),
    "kabar": (PINK_SOFT, PINK, INK),
    "alat": ((245, 246, 250), MUTED, INK),
}

FONT_DIR = "/System/Library/Fonts/Supplemental"


def _font(size, bold=False):
    name = "Arial Bold.ttf" if bold else "Arial.ttf"
    try:
        return ImageFont.truetype(f"{FONT_DIR}/{name}", size * SCALE)
    except OSError:
        return ImageFont.load_default()


class Kotak:
    """Satu tabel di diagram.

    Posisinya ditentukan tangan lewat (col, row) alih-alih mesin tata
    letak. Diagramnya sedikit dan bentuknya sudah diketahui; mesin tata
    letak graf umum akan menaruhnya di tempat yang benar secara
    matematis tapi tidak mengikuti cara orang membacanya.
    """

    def __init__(self, nama, kolom, tone, col, row, span=1):
        self.nama = nama
        self.kolom = kolom
        self.tone = tone
        self.col = col
        self.row = row
        self.span = span
        self.x = self.y = self.w = self.h = 0


def render(kotak, relasi, path, cols=3, width=760, judul=None):
    """kotak: list[Kotak]. relasi: list[(dari, ke, label, kuat)]."""
    W = width * SCALE
    pad = 16 * SCALE
    gap_x = 20 * SCALE
    gap_y = 26 * SCALE
    box_pad = 9 * SCALE

    f_judul = _font(13, bold=True)
    f_nama = _font(11, bold=True)
    f_kol = _font(9)
    f_rel = _font(8)

    kol_w = (W - 2 * pad - gap_x * (cols - 1)) // cols

    # Ukur dulu, gambar belakangan — kanvas yang ditebak lalu dipotong
    # selalu menyisakan ruang kosong di bawah.
    line_nama = int(f_nama.size * 1.5)
    line_kol = int(f_kol.size * 1.45)
    tinggi_baris = {}
    for k in kotak:
        k.w = kol_w * k.span + gap_x * (k.span - 1)
        k.h = line_nama + len(k.kolom) * line_kol + 2 * box_pad
        tinggi_baris[k.row] = max(tinggi_baris.get(k.row, 0), k.h)

    atas = pad + (int(f_judul.size * 2.1) if judul else 0)
    y_baris, y = {}, atas
    for r in sorted(tinggi_baris):
        y_baris[r] = y
        y += tinggi_baris[r] + gap_y
    total_h = y - gap_y + pad

    for k in kotak:
        k.x = pad + k.col * (kol_w + gap_x)
        k.y = y_baris[k.row]

    img = Image.new("RGB", (W, total_h), PAPER)
    draw = ImageDraw.Draw(img)

    if judul:
        draw.text((pad, pad), judul, font=f_judul, fill=INK)

    peta = {k.nama: k for k in kotak}

    # Beberapa relasi bisa melewati lorong yang sama di antara dua baris.
    # Digambar di ketinggian yang persis sama, garis-garisnya bertumpuk
    # jadi satu dan tidak lagi bisa ditelusuri mana menuju mana.
    kelompok = {}
    for dari, ke, _, _ in relasi:
        a, b = peta[dari], peta[ke]
        kelompok.setdefault(tuple(sorted((a.row, b.row))), []).append((dari, ke))
    jalur = {}
    for anggota in kelompok.values():
        n = len(anggota)
        for i, kunci in enumerate(anggota):
            jalur[kunci] = (i - (n - 1) / 2) * 5 * SCALE

    # Garis lebih dulu, supaya kotaknya menimpa garis — bukan sebaliknya.
    #
    # Rutenya bersiku, bukan diagonal. Garis diagonal antara dua kotak
    # yang berjauhan menembus kotak-kotak di antaranya, dan pembacanya
    # tidak punya cara tahu garis itu milik siapa.
    label_nanti = []
    for dari, ke, label, kuat in relasi:
        a, b = peta[dari], peta[ke]
        warna = MUTED if kuat else LINE
        lebar = 2 * SCALE

        titik, label_xy = _rute(a, b, jalur[(dari, ke)])
        for i in range(len(titik) - 1):
            x1, y1 = titik[i]
            x2, y2 = titik[i + 1]
            if kuat:
                draw.line([x1, y1, x2, y2], fill=warna, width=lebar)
            else:
                _garis_putus(draw, x1, y1, x2, y2, warna, lebar)

        if label:
            label_nanti.append((label_xy, label))

    for k in kotak:
        isi, tepi, tulisan = TONE[k.tone]
        draw.rounded_rectangle(
            [k.x, k.y, k.x + k.w, k.y + k.h],
            radius=8 * SCALE, fill=isi, outline=tepi, width=2 * SCALE,
        )
        # Judulnya berpita supaya nama tabel tidak tenggelam di antara
        # daftar kolomnya sendiri.
        draw.rounded_rectangle(
            [k.x, k.y, k.x + k.w, k.y + line_nama + box_pad // 2],
            radius=8 * SCALE, fill=tepi,
        )
        draw.rectangle(
            [k.x, k.y + line_nama, k.x + k.w, k.y + line_nama + box_pad // 2],
            fill=tepi,
        )

        # Nama yang lebih lebar daripada kotaknya dikecilkan sampai muat.
        # Memotongnya berarti menghilangkan justru bagian yang paling
        # menentukan artinya — nama tabel terakhir dalam daftar.
        fn, ukuran = f_nama, 11
        while draw.textlength(k.nama, font=fn) > k.w - 2 * box_pad and ukuran > 7:
            ukuran -= 1
            fn = _font(ukuran, bold=True)
        draw.text((k.x + box_pad, k.y + box_pad // 2 + (f_nama.size - fn.size) // 2),
                  k.nama, font=fn, fill=PAPER)

        ty = k.y + line_nama + box_pad
        for kol in k.kolom:
            draw.text((k.x + box_pad, ty), kol, font=f_kol, fill=tulisan)
            ty += line_kol

    # Label paling akhir. Digambar bersama garisnya, ia tertimpa kotak
    # yang datang sesudahnya — dan yang tertimpa justru label di celah
    # sempit antara dua kotak bersebelahan, yang paling butuh dibaca.
    for (mx, my), label in label_nanti:
        tw = draw.textlength(label, font=f_rel)
        mx = min(max(mx, tw / 2 + pad), W - tw / 2 - pad)
        draw.rectangle(
            [mx - tw / 2 - 3 * SCALE, my - f_rel.size * 0.75,
             mx + tw / 2 + 3 * SCALE, my + f_rel.size * 0.85],
            fill=PAPER,
        )
        draw.text((mx - tw / 2, my - f_rel.size * 0.6), label,
                  font=f_rel, fill=MUTED)

    img = img.resize((W // SCALE, total_h // SCALE), Image.LANCZOS)
    img.save(path)
    print("ditulis:", os.path.basename(path), img.size)


def _rute(a, b, geser=0):
    """Titik-titik siku dari kotak a ke kotak b, plus posisi labelnya.

    Sebaris: lurus mendatar. Beda baris: turun ke lorong di antara
    kedua baris, menyamping di sana, lalu masuk dari atas. Lorong itu
    memang kosong — jaraknya gap_y disediakan justru untuk ini.
    """
    ax, ay = a.x + a.w / 2, a.y + a.h / 2
    bx, by = b.x + b.w / 2, b.y + b.h / 2

    if a.row == b.row:
        if bx > ax:
            p = [(a.x + a.w, ay), (b.x, by)]
        else:
            p = [(a.x, ay), (b.x + b.w, by)]
        return p, ((p[0][0] + p[1][0]) / 2, ay + geser)

    atas, bawah = (a, b) if a.row < b.row else (b, a)
    y_keluar = atas.y + atas.h
    y_masuk = bawah.y
    y_lorong = (y_keluar + y_masuk) / 2 + geser
    x1 = atas.x + atas.w / 2
    x2 = bawah.x + bawah.w / 2

    titik = [(x1, y_keluar), (x1, y_lorong), (x2, y_lorong), (x2, y_masuk)]
    return titik, ((x1 + x2) / 2, y_lorong)


def _garis_putus(draw, x1, y1, x2, y2, warna, lebar):
    panjang = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
    if panjang == 0:
        return
    dx, dy = (x2 - x1) / panjang, (y2 - y1) / panjang
    seg = 7 * SCALE
    t = 0
    while t < panjang:
        t2 = min(t + seg, panjang)
        draw.line([x1 + dx * t, y1 + dy * t, x1 + dx * t2, y1 + dy * t2],
                  fill=warna, width=lebar)
        t += seg * 2


if __name__ == "__main__":
    REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    OUT = os.path.join(REPO, "docs", "gambar")
    os.makedirs(OUT, exist_ok=True)

    # ── 0. Peta seluruh tabel ────────────────────────────────────────
    #
    # Tanpa kolom sama sekali. Yang ditunjukkan di sini cuma satu hal:
    # hampir semuanya menggantung pada restaurants, dan itulah kenapa
    # menghapus satu resto menghapus seluruh isinya.
    render(
        [
            Kotak("restaurants", ["induk seluruh data"], "inti", 1, 0),
            Kotak("employees", ["peran & resto"], "inti", 0, 1),
            Kotak("customers", ["profil pelanggan"], "inti", 1, 1),
            Kotak("sessions", ["sesi meja"], "inti", 2, 1),
            Kotak("products · categories · level_groups",
                  ["katalog menu"], "katalog", 0, 2),
            Kotak("settings · resto_payment_accounts",
                  ["setelan resto"], "katalog", 1, 2),
            Kotak("orders", ["pesanan"], "pesanan", 2, 2),
            Kotak("discounts · promo_banners", ["promo"], "katalog", 0, 3),
            Kotak("payment_charges · mail_requests",
                  ["tagihan & struk"], "pesanan", 1, 3),
            Kotak("gl_accounts · gl_journal_entries",
                  ["buku besar"], "uang", 2, 3),
            Kotak("expenses · expense_gl_accounts · petty_cash_entries",
                  ["pengeluaran & kas kecil"], "uang", 0, 4, span=2),
            Kotak("cash_deposits · gateway_settlements",
                  ["setoran & pencairan"], "uang", 2, 4),
            Kotak("app_announcements · inbox_states",
                  ["pengumuman"], "kabar", 0, 5),
            Kotak("device_tokens · push_config · push_outbox",
                  ["notifikasi"], "alat", 1, 5),
            Kotak("applied_migrations", ["penanda sekali-jalan"], "alat", 2, 5),
        ],
        [
            ("restaurants", "employees", None, True),
            ("restaurants", "sessions", None, True),
            ("restaurants", "products · categories · level_groups", None, True),
            ("restaurants", "settings · resto_payment_accounts", None, True),
            ("restaurants", "orders", None, True),
            ("orders", "payment_charges · mail_requests", None, True),
            ("orders", "gl_accounts · gl_journal_entries", "lewat pemicu", False),
            ("customers", "orders", "customer_label", False),
        ],
        f"{OUT}/erd-00-peta.png",
        judul="Peta seluruh tabel — hampir semuanya menggantung pada restaurants",
    )

    # ── 1. Katalog ───────────────────────────────────────────────────
    render(
        [
            Kotak("restaurants", ["id (PK)", "name, address", "lat, lng",
                                  "dine_in, take_away"], "inti", 1, 0),
            Kotak("categories", ["id (PK)", "resto_id (FK)", "name", "sort_order"],
                  "katalog", 0, 1),
            Kotak("products", ["id (PK)", "resto_id (FK)", "name, price",
                               "category (teks)", "stock (boleh null)",
                               "out_of_stock", "level_options (jsonb)"],
                  "katalog", 1, 1),
            Kotak("level_groups", ["id (PK)", "resto_id (FK)", "name",
                                   "options (jsonb)"], "katalog", 2, 1),
            Kotak("settings", ["resto_id (PK/FK)", "ppn_percent",
                               "service_percent"], "katalog", 0, 2),
            Kotak("employees", ["id (PK)", "resto_id (FK)", "email", "role",
                                "active"], "inti", 1, 2),
            Kotak("resto_payment_accounts",
                  ["resto_id (PK/FK)", "qris_*, bank_*",
                   "gateway_sub_account"], "katalog", 2, 2),
        ],
        [
            ("restaurants", "categories", None, True),
            ("restaurants", "products", None, True),
            ("restaurants", "level_groups", None, True),
            ("restaurants", "settings", None, True),
            ("restaurants", "employees", None, True),
            ("restaurants", "resto_payment_accounts", None, True),
            ("categories", "products", "lewat nama", False),
            ("level_groups", "products", "disalin", False),
        ],
        f"{OUT}/erd-01-katalog.png",
        judul="Katalog & pengaturan resto",
    )

    # ── 2. Pesanan ───────────────────────────────────────────────────
    render(
        [
            Kotak("restaurants", ["id (PK)"], "inti", 1, 0),
            Kotak("sessions", ["id (PK)", "resto_id (FK)", "table_number",
                               "active", "last_order_at"], "inti", 0, 1),
            Kotak("orders",
                  ["id (PK, uuid)", "resto_id (FK)", "session_id (lepas)",
                   "source, payment_status", "kitchen_status, payment_method",
                   "customer_label", "settled_by, settled_at",
                   "discount_id/name/amount", "items (jsonb)", "total"],
                  "pesanan", 1, 1),
            Kotak("customers", ["email (PK)", "name, phone", "photo"],
                  "inti", 2, 1),
            Kotak("payment_charges", ["id (PK)", "order_id (FK)",
                                      "resto_id (FK)", "provider_ref",
                                      "status"], "pesanan", 0, 2),
            Kotak("mail_requests", ["id (PK)", "order_id (FK)", "to_email",
                                    "sent_at"], "pesanan", 2, 2),
        ],
        [
            ("restaurants", "orders", None, True),
            ("restaurants", "sessions", None, True),
            ("sessions", "orders", "session_id", False),
            ("customers", "orders", "customer_label", False),
            ("orders", "payment_charges", None, True),
            ("orders", "mail_requests", None, True),
        ],
        f"{OUT}/erd-02-pesanan.png",
        judul="Pesanan, sesi meja, dan pembayaran",
    )

    # ── 3. Keuangan ──────────────────────────────────────────────────
    #
    # Jurnal ditaruh di tengah, sumbernya mengapit dari atas dan bawah.
    # Menaruhnya di ujung memaksa garis dari sisi terjauh menembus
    # kotak-kotak di antaranya.
    render(
        [
            Kotak("gl_accounts",
                  ["resto_id (FK)", "payment_method", "gl_code, gl_name",
                   "12 jenis akun"], "uang", 0, 0),
            Kotak("orders", ["id (PK)", "total", "discount_amount"],
                  "pesanan", 1, 0, span=2),
            Kotak("expense_gl_accounts",
                  ["resto_id (FK)", "kind", "gl_code"], "uang", 3, 0),
            Kotak("gl_journal_entries",
                  ["id (PK) · resto_id (FK) · gl_code, gl_name · amount",
                   "reference_type · reference_id (lepas)",
                   "entry_type: kredit = uang masuk, debit = uang keluar"],
                  "uang", 0, 1, span=4),
            Kotak("expenses", ["id (PK)", "resto_id (FK)", "amount",
                               "gl_code", "receipt"], "uang", 0, 2),
            Kotak("petty_cash_entries",
                  ["id (PK)", "resto_id (FK)", "amount", "source",
                   "status"], "uang", 1, 2),
            Kotak("cash_deposits",
                  ["id (PK)", "resto_id (FK)", "amount", "proof",
                   "status"], "uang", 2, 2),
            Kotak("gateway_settlements",
                  ["id (PK)", "resto_id (FK)", "gross, mdr_fee", "net"],
                  "uang", 3, 2),
        ],
        [
            ("gl_accounts", "gl_journal_entries", "nomor akun", False),
            ("orders", "gl_journal_entries", "saat lunas", False),
            ("expense_gl_accounts", "gl_journal_entries", "nomor akun", False),
            ("expenses", "gl_journal_entries", "pemicu", False),
            ("petty_cash_entries", "gl_journal_entries", "pemicu", False),
            ("cash_deposits", "gl_journal_entries", "pemicu", False),
            ("gateway_settlements", "gl_journal_entries", "pemicu", False),
        ],
        f"{OUT}/erd-03-keuangan.png",
        cols=4,
        judul="Buku besar — seluruhnya diisi pemicu, tidak ada kunci asing ke jurnal",
    )

    # ── 4. Promo ─────────────────────────────────────────────────────
    render(
        [
            Kotak("restaurants", ["id (PK)"], "inti", 1, 0),
            Kotak("discounts",
                  ["id (PK)", "resto_id (FK)", "basis, kind, value",
                   "product_ids (jsonb)", "product_rules (jsonb)",
                   "min_purchase, compare_mode", "starts_on, ends_on, active"],
                  "katalog", 0, 1),
            Kotak("promo_banners",
                  ["id (PK)", "resto_id (FK)", "image, title, body",
                   "sort_order, active", "starts_on, ends_on"],
                  "katalog", 2, 1),
            Kotak("products", ["id (PK)", "name, price"], "katalog", 0, 2),
            Kotak("orders", ["discount_id (lepas)", "discount_name",
                             "discount_amount"], "pesanan", 2, 2),
        ],
        [
            ("restaurants", "discounts", None, True),
            ("restaurants", "promo_banners", None, True),
            ("discounts", "products", "id di dalam jsonb", False),
            ("discounts", "orders", "disalin, bukan dirujuk", False),
        ],
        f"{OUT}/erd-04-promo.png",
        judul="Diskon & banner promo",
    )

    # ── 5. Kabar ─────────────────────────────────────────────────────
    render(
        [
            Kotak("app_announcements",
                  ["id (PK)", "resto_id (FK, boleh null)", "category, audience",
                   "title, body, image", "download_url"], "kabar", 1, 0),
            Kotak("inbox_states",
                  ["announcement_id (FK)", "email", "read, deleted"],
                  "kabar", 0, 1),
            Kotak("push_outbox",
                  ["id (PK)", "resto_id", "event, payload", "sent_at"],
                  "alat", 2, 1),
            Kotak("device_tokens",
                  ["token (PK)", "resto_id", "email", "role"], "alat", 1, 2),
            Kotak("push_config", ["service account", "project_id"], "alat", 2, 2),
        ],
        [
            ("app_announcements", "inbox_states", None, True),
            ("app_announcements", "push_outbox", "pemicu", False),
            ("push_outbox", "device_tokens", "dipilih saat kirim", False),
            ("push_config", "push_outbox", "kunci pengirim", False),
        ],
        f"{OUT}/erd-05-kabar.png",
        judul="Pengumuman & notifikasi",
    )
