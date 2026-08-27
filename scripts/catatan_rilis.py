#!/usr/bin/env python3
"""Menyusun badan pengumuman rilis dari CATATAN-RILIS.md.

Mencetak JSON siap kirim ke fungsi publish-release. Versi yang belum
punya bagiannya tetap menghasilkan JSON yang sah — hanya tanpa `body`,
sehingga fungsinya memakai kalimat umumnya sendiri. Menahan rilis karena
catatannya belum ditulis akan menukar satu ketidaknyamanan kecil dengan
satu rilis yang gagal terbit.
"""

import json
import sys


def poin_untuk(isi: str, versi: str) -> list[str]:
    """Baris-baris di bawah judul `## <versi>`, sampai judul berikutnya."""
    poin: list[str] = []
    kutip = False
    for baris in isi.splitlines():
        if baris.startswith("## "):
            # Judul berikutnya menutup bagian ini. Tanpa ini, catatan
            # versi lama ikut terbawa ke pengumuman versi baru.
            if kutip:
                break
            kutip = baris[3:].strip() == versi
            continue
        if kutip and baris.strip():
            poin.append(baris.rstrip())
    return poin


def main() -> None:
    path, versi = sys.argv[1], sys.argv[2]
    try:
        isi = open(path).read()
    except OSError:
        print(json.dumps({"version": versi}))
        return

    poin = poin_untuk(isi, versi)
    if not poin:
        print(json.dumps({"version": versi}))
        return

    pesan = "Versi baru MerchantPOS sudah bisa diunduh. Yang berubah:\n\n" + "\n".join(poin)
    print(json.dumps({"version": versi, "body": pesan}))


if __name__ == "__main__":
    main()
