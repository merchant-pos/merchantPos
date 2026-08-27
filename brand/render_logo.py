"""Menggambar logo KaataGo jadi PNG.

Digambar ulang dengan Pillow alih-alih meraster SVG-nya: mesin ini tidak
punya perender SVG, dan bentuknya cukup sederhana — persegi bersudut
tumpul, satu batang, dan tiga poligon — sehingga menggambarnya langsung
justru lebih akurat daripada memasang rantai perkakas baru.

Sumber kebenaran bentuknya tetap brand/kaatago-logo.svg; angka di bawah
disalin dari sana pada kanvas 512x512.
"""

import sys
from PIL import Image, ImageDraw

BRAND = (79, 70, 229)      # #4F46E5
BRAND_DARK = (55, 48, 163) # #3730A3
AMBER = (245, 158, 11)     # #F59E0B
WHITE = (255, 255, 255)

SS = 4  # supersampling: digambar besar lalu dikecilkan, supaya tepinya halus


def draw(size: int, rounded: bool = True) -> Image.Image:
    n = size * SS
    k = n / 512  # skala dari kanvas 512 milik SVG-nya

    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))

    # Gradien diagonal, digambar baris demi baris lalu dipotong oleh
    # topeng bersudut tumpul.
    grad = Image.new('RGB', (n, n))
    gd = ImageDraw.Draw(grad)
    for i in range(n * 2):
        t = i / (n * 2 - 1)
        c = tuple(round(BRAND[j] + (BRAND_DARK[j] - BRAND[j]) * t) for j in range(3))
        gd.line([(i, 0), (0, i)], fill=c)

    mask = Image.new('L', (n, n), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, n - 1, n - 1], radius=int(116 * k), fill=255)
    else:
        md.rectangle([0, 0, n - 1, n - 1], fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)

    def P(*pts):
        return [(x * k, y * k) for x, y in pts]

    # Batang tegak huruf K
    d.rounded_rectangle(
        [132 * k, 140 * k, (132 + 54) * k, (140 + 232) * k],
        radius=14 * k, fill=WHITE)
    # Lengan atas
    d.polygon(P((200, 256), (318, 141), (402, 141), (284, 256)), fill=WHITE)
    # Lengan bawah
    d.polygon(P((200, 256), (284, 256), (402, 371), (318, 371)), fill=AMBER)
    # Kepala panah
    d.polygon(P((362, 300), (436, 256), (436, 344)), fill=AMBER)

    return img.resize((size, size), Image.LANCZOS)


if __name__ == '__main__':
    for target, size in [(a.split('=')[0], int(a.split('=')[1])) for a in sys.argv[1:]]:
        draw(size).save(target)
        print('ditulis:', target, f'{size}x{size}')
