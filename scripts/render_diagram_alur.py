"""Menggambar diagram alur MerchantPOS jadi PNG untuk dokumen Word.

Word tidak bisa merender mermaid, dan menempelkan tangkapan layar
diagram dari browser membuat hasilnya buram saat dicetak. Digambar
langsung di sini supaya tajam pada resolusi cetak.

Tata letaknya sengaja sederhana: tumpukan baris dari atas ke bawah, tiap
baris berisi satu sampai tiga kotak sejajar. Semua alur di dokumen ini
memang berbentuk begitu — memaksakan mesin tata letak graf umum hanya
menambah kode yang tidak dipakai.
"""

from PIL import Image, ImageDraw, ImageFont

SCALE = 3  # digambar 3x lalu diperkecil: tepinya jadi halus

BRAND = (79, 70, 229)
BRAND_DARK = (55, 48, 163)
AMBER = (245, 158, 11)
GREEN = (16, 185, 129)
RED = (239, 68, 68)
INK = (20, 21, 42)
MUTED = (110, 114, 140)
LINE = (206, 209, 228)
PAPER = (255, 255, 255)

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


# Warna per jenis kotak. "start"/"end" menandai ujung alur, "act" langkah
# biasa, "dec" percabangan, "ok"/"no" hasil yang berhasil/ditolak.
STYLES = {
    "start": (BRAND, PAPER, BRAND),
    "end": (BRAND_DARK, PAPER, BRAND_DARK),
    "act": (PAPER, INK, LINE),
    "dec": ((255, 247, 230), INK, AMBER),
    "ok": ((236, 253, 245), (6, 95, 70), GREEN),
    "no": ((254, 242, 242), (153, 27, 27), RED),
}


def render(rows, path, width=760):
    """rows: list of (list_of_(text, style), arrow_label_ke_baris_berikutnya)"""
    W = width * SCALE
    pad = 18 * SCALE
    gap_x = 14 * SCALE
    arrow_h = 30 * SCALE
    box_pad = 11 * SCALE

    f_box = _font(12, bold=True)
    f_small = _font(10)

    probe = Image.new("RGB", (10, 10))
    d = ImageDraw.Draw(probe)

    # Ukur tinggi tiap baris lebih dulu supaya kanvasnya pas — kanvas
    # yang ditebak lalu dipotong selalu menyisakan ruang kosong di bawah.
    layout, total_h = [], pad
    for boxes, arrow in rows:
        n = len(boxes)
        bw = (W - 2 * pad - gap_x * (n - 1)) // n
        line_h = int(f_box.size * 1.35)
        h = 0
        wrapped = []
        for text, _ in boxes:
            lines = _wrap(d, text, f_box, bw - 2 * box_pad)
            wrapped.append(lines)
            h = max(h, len(lines) * line_h + 2 * box_pad)
        layout.append((boxes, wrapped, bw, h, line_h, arrow))
        total_h += h + arrow_h
    total_h -= arrow_h  # baris terakhir tidak diikuti panah
    total_h += pad

    img = Image.new("RGB", (W, total_h), PAPER)
    draw = ImageDraw.Draw(img)

    y = pad
    for idx, (boxes, wrapped, bw, h, line_h, arrow) in enumerate(layout):
        n = len(boxes)
        centers = []
        for i, ((text, style), lines) in enumerate(zip(boxes, wrapped)):
            x = pad + i * (bw + gap_x)
            fill, fg, border = STYLES[style]
            draw.rounded_rectangle(
                [x, y, x + bw, y + h], radius=9 * SCALE, fill=fill, outline=border, width=2 * SCALE
            )
            ty = y + (h - len(lines) * line_h) // 2
            for ln in lines:
                tw = draw.textlength(ln, font=f_box)
                draw.text((x + (bw - tw) / 2, ty), ln, font=f_box, fill=fg)
                ty += line_h
            centers.append(x + bw / 2)

        y += h
        if idx == len(layout) - 1:
            break

        # Satu batang turun dari tengah baris, lalu menyebar ke kotak
        # baris berikutnya. Menarik panah dari tiap kotak ke tiap kotak
        # akan jadi jaring yang justru menyembunyikan alurnya.
        mid = sum(centers) / len(centers)
        y2 = y + arrow_h
        draw.line([mid, y, mid, y2 - 6 * SCALE], fill=MUTED, width=2 * SCALE)
        draw.polygon(
            [
                (mid, y2),
                (mid - 5 * SCALE, y2 - 8 * SCALE),
                (mid + 5 * SCALE, y2 - 8 * SCALE),
            ],
            fill=MUTED,
        )
        if arrow:
            tw = draw.textlength(arrow, font=f_small)
            bx = mid + 8 * SCALE
            draw.rectangle(
                [bx - 3 * SCALE, y + 7 * SCALE, bx + tw + 3 * SCALE, y + 7 * SCALE + f_small.size * 1.2],
                fill=PAPER,
            )
            draw.text((bx, y + 7 * SCALE), arrow, font=f_small, fill=MUTED)
        y = y2

    img = img.resize((W // SCALE, total_h // SCALE), Image.LANCZOS)
    img.save(path)
    print("ditulis:", path, img.size)


if __name__ == "__main__":
    import os

    REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    OUT = os.path.join(REPO, "docs", "gambar")

    render(
        [
            ([("Buka aplikasi sebagai Customer", "start")], None),
            ([("Scan QR meja", "act"), ("Pilih resto dari daftar", "act")], "salah satu"),
            ([("Halaman menu resto", "act")], None),
            ([("Pilih produk, level/varian, catatan", "act")], None),
            ([("Keranjang: Dine In/Take Away, nomor meja, nama", "act")], None),
            ([("Pilih cara bayar: QRIS", "dec")], None),
            ([("Pesanan dibuat — Menunggu Pembayaran", "act")], None),
            ([("Layar QRIS — konfirmasi pembayaran", "act")], None),
            (
                [
                    ("Status: Sudah Dibayar", "ok"),
                    ("Jurnal GL QRIS tercatat", "ok"),
                    ("Dapur menerima pesanan", "ok"),
                ],
                None,
            ),
        ],
        f"{OUT}/alur-01-qris.png",
    )

    render(
        [
            ([("Keranjang — pilih cara bayar: Tunai", "start")], None),
            ([("Pesanan dibuat: payment_method = cash, Menunggu Pembayaran", "act")], None),
            (
                [
                    ("Layar penutup: nomor pesanan + ajakan ke kasir", "act"),
                    ("Dapur langsung menerima pesanannya", "act"),
                ],
                None,
            ),
            ([("Pelanggan datang ke kasir", "act")], None),
            ([("Kasir buka menu Pending Payment", "act")], None),
            ([("Klik Detail — cek isi pesanan", "act")], None),
            ([("Terima Pembayaran — input uang diterima", "dec")], "uang kurang: tombol mati"),
            ([("Simpan: Sudah Dibayar + cash_received", "act")], None),
            (
                [
                    ("Hilang dari Pending Payment", "ok"),
                    ("Muncul di Riwayat Transaksi", "ok"),
                    ("Jurnal GL Tunai tercatat", "ok"),
                ],
                None,
            ),
        ],
        f"{OUT}/alur-02-tunai-kasir.png",
    )

    render(
        [
            ([("Kasir/Admin buka Setor Saldo Cash", "start")], None),
            ([("Isi nominal, bank, no. rekening, foto bukti", "act")], None),
            ([("Popup konfirmasi nominal transfer", "act")], None),
            ([("Tersimpan — status Pending", "act")], None),
            ([("Saldo Cash → GL Suspense", "act")], None),
            ([("Penanda merah muncul di menu Finance", "act")], None),
            ([("Keputusan Finance / Owner", "dec")], None),
            (
                [
                    ("Konfirmasi: Completed, GL Suspense → GL Total Saldo", "ok"),
                    ("Tolak: Ditolak, GL Suspense → Saldo Cash", "no"),
                ],
                None,
            ),
            ([("Notifikasi ke HP pengaju", "end")], None),
        ],
        f"{OUT}/alur-03-setor.png",
    )

    render(
        [
            ([("Kasir/Admin: Ajukan Top Up petty cash", "start")], None),
            ([("Pilih sumber: Manual / Saldo Cash / Saldo Non Cash", "act")], None),
            ([("Tersimpan — status Pending", "act")], None),
            ([("GL sumber → GL Suspense Petty Cash", "act")], None),
            ([("Tanggalnya diberi penanda merah & terbuka sendiri", "act")], None),
            ([("Keputusan Finance / Owner", "dec")], None),
            (
                [
                    ("Setuju: Completed, Suspense Petty → GL Petty Cash", "ok"),
                    ("Tolak: Ditolak, Suspense Petty → GL sumber", "no"),
                ],
                None,
            ),
            ([("Notifikasi ke HP pengaju", "end")], None),
        ],
        f"{OUT}/alur-04-petty.png",
    )

    render(
        [
            ([("Pesanan masuk — status Baru", "start")], None),
            ([("Dapur mencentang item satu per satu", "act")], None),
            (
                [
                    ("Sebagian tercentang: Diproses", "act"),
                    ("Semua tercentang: Selesai", "ok"),
                ],
                None,
            ),
            ([("Notifikasi ke HP pelanggan dan kasir yang menginput", "end")], None),
        ],
        f"{OUT}/alur-05-dapur.png",
    )
