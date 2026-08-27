#!/usr/bin/env python3
"""Memeriksa urutan berkas SQL: tabel harus dibuat sebelum dipakai.

Yang diperiksa hanya pernyataan di luar badan fungsi. Isi badan fungsi
sengaja dilewati: PL/pgSQL tidak menyentuh tabelnya saat fungsinya
dibuat, hanya saat dipanggil — jadi fungsi yang menulis ke tabel yang
belum ada tetap sah, dan menganggapnya masalah akan memaksa urutan yang
tidak mungkin dipenuhi.

Yang membuat percobaan pertama gagal justru kebalikannya: pernyataan
biasa — insert, alter, create index — yang dijalankan saat itu juga.
"""
import re
import subprocess
import sys

def _kosongkan(s: str, awal: int, akhir: int) -> str:
    """Mengganti sepotong teks dengan spasi sebanyak panjangnya.

    Panjangnya dipertahankan supaya posisi tiap temuan tetap sejajar
    dengan berkas aslinya — tanpa itu, laporannya menunjuk bagian yang
    salah, dan yang membaca laporan akan memperbaiki berkas yang tidak
    bersalah.
    """
    potongan = s[awal:akhir]
    return s[:awal] + re.sub(r'[^\n]', ' ', potongan) + s[akhir:]


def tanpa_badan_fungsi(s: str) -> str:
    """Mengosongkan badan CREATE FUNCTION saja.

    Blok `do $$ ... $$` justru harus tetap: Postgres menjalankannya saat
    itu juga, dan insert di dalamnya menyentuh tabel yang harus sudah
    ada. Mengosongkannya bersama badan fungsi persis yang membuat
    pemeriksaan ini meloloskan backfill_journal.sql.
    """
    pos = 0
    while True:
        m = re.compile(r'create\s+(?:or\s+replace\s+)?function\b',
                       re.I).search(s, pos)
        if not m:
            return s
        buka = re.compile(r'\$([a-z_]*)\$', re.I).search(s, m.start())
        if not buka:
            return s
        tag = buka.group(0)
        tutup = s.find(tag, buka.end())
        if tutup == -1:
            return s
        s = _kosongkan(s, buka.end(), tutup)
        pos = tutup + len(tag)


def tanpa_teks(s: str) -> str:
    """Mengosongkan komentar.

    Komentar baris dulu, baru komentar blok — dan urutan ini bukan
    selera. Ada baris komentar yang menyebut `supabase/*.sql`; kalau
    komentar blok disapu lebih dulu, `/*` di dalamnya berpasangan
    dengan `*/` ribuan baris kemudian dan menelan semua di antaranya.
    Itulah yang sempat membuat pemeriksaan ini melaporkan 19 tabel dari
    44 yang sebenarnya ada, lalu berkata "aman".

    Literal string sengaja dibiarkan: satu kutip yang tidak berpasangan
    membuat penyapunya menelan ribuan baris dengan cara yang sama.
    """
    for pola, bendera in ((r'--[^\n]*', 0), (r'/\*.*?\*/', re.S)):
        while True:
            m = re.search(pola, s, bendera)
            if not m:
                break
            s = _kosongkan(s, m.start(), m.end())
    return s


POLA = [
    (r'\binsert\s+into\s+(?:public\.)?([a-z_][a-z_0-9]*)', 'insert into'),
    (r'\bupdate\s+(?:only\s+)?(?:public\.)?([a-z_][a-z_0-9]*)\s+set\b', 'update'),
    (r'\bdelete\s+from\s+(?:public\.)?([a-z_][a-z_0-9]*)', 'delete from'),
    (r'\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?([a-z_][a-z_0-9]*)', 'alter table'),
    (r'\bcreate\s+(?:unique\s+)?index[^;]*?\bon\s+(?:public\.)?([a-z_][a-z_0-9]*)', 'create index'),
    (r'\bcreate\s+(?:or\s+replace\s+)?trigger[^;]*?\bon\s+(?:public\.)?([a-z_][a-z_0-9]*)', 'create trigger'),
    (r'\bcreate\s+policy[^;]*?\bon\s+(?:public\.)?([a-z_][a-z_0-9]*)', 'create policy'),
    (r'\breferences\s+(?:public\.)?([a-z_][a-z_0-9]*)', 'references'),
]

def main(bundel: str) -> int:
    isi = open(bundel, encoding='utf-8').read()
    baris_bagian = []
    for m in re.finditer(r'^-- (\d+)\. ([a-z_0-9]+\.sql)$', isi, re.M):
        baris_bagian.append((m.start(), m.group(2)))

    def bagian(pos):
        nama = '(kepala berkas)'
        for awal, n in baris_bagian:
            if awal <= pos:
                nama = n
            else:
                break
        return nama

    bersih = tanpa_teks(tanpa_badan_fungsi(isi))
    dibuat = {}
    for m in re.finditer(r'create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_][a-z_0-9]*)',
                         bersih, re.I):
        dibuat.setdefault(m.group(1).lower(), m.start())

    masalah = []
    for pola, jenis in POLA:
        for m in re.finditer(pola, bersih, re.I):
            t = m.group(1).lower()
            if t in dibuat and m.start() < dibuat[t]:
                masalah.append((m.start(), jenis, t))
    masalah.sort()

    print(f'tabel dibuat        : {len(dibuat)}')
    print(f'dipakai sebelum ada : {len(masalah)}')
    for pos, jenis, t in masalah:
        print(f'  {bagian(pos):32s} {jenis} {t}')
    return 1 if masalah else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else 'supabase/JALANKAN-SEMUA.sql'))
