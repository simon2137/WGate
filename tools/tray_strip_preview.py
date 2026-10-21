"""Show the tray glyphs the way the system bar will: on a dark bar and on a
light one, at 24 vp and at 2x."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / 'entry/src/main/resources/base/media'
OUT = ROOT / 'build/icon-studio/tray-preview.png'

NAMES = ['tray_idle_light.png', 'tray_up_light.png',
         'tray_idle_dark.png', 'tray_up_dark.png']


def font(size):
    try:
        return ImageFont.truetype('msyh.ttc', size)
    except OSError:
        return ImageFont.load_default()


width, height = 660, 250
canvas = Image.new('RGB', (width, height), (233, 236, 239))
draw = ImageDraw.Draw(canvas)

# a dark status bar on top, a light one below
draw.rectangle([0, 0, width, 118], fill=(28, 27, 31))
draw.text((16, 10), '深色状态栏', fill=(180, 188, 200), font=font(14))
draw.text((16, 132), '浅色状态栏', fill=(90, 96, 104), font=font(14))

for i, name in enumerate(NAMES):
    image = Image.open(MEDIA / name).convert('RGBA')
    dark_bar = i < 2
    y = 34 if dark_bar else 156
    x = 180 + (i % 2) * 210
    for j, size in enumerate((24, 48)):
        small = image.resize((size, size), Image.LANCZOS)
        px = x + j * 90
        canvas.paste(small, (px, y + (48 - size) // 2), small)
    draw.text((x - 8, y + 56), name.replace('tray_', '').replace('.png', ''),
              fill=(150, 158, 172) if dark_bar else (90, 96, 104), font=font(12))

OUT.parent.mkdir(parents=True, exist_ok=True)
canvas.save(OUT)
print(OUT)
