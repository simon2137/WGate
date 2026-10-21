"""Builds build/tray-preview.png: the four tray icons at 24 px and at 128 px."""
from pathlib import Path

from PIL import Image

MEDIA = Path('entry/src/main/resources/base/media')
NAMES = [('tray_idle_light.png', (32, 34, 36, 255)),
         ('tray_up_light.png', (32, 34, 36, 255)),
         ('tray_idle_dark.png', (245, 246, 247, 255)),
         ('tray_up_dark.png', (245, 246, 247, 255))]
CELL = 160
sheet = Image.new('RGBA', (CELL * 4, CELL), (128, 128, 128, 255))
for index, (name, background) in enumerate(NAMES):
    tile = Image.new('RGBA', (CELL, CELL), background)
    big = Image.open(MEDIA / name).convert('RGBA').resize((128, 128), Image.LANCZOS)
    tile.paste(big, ((CELL - 128) // 2, (CELL - 128) // 2), big)
    small = Image.open(MEDIA / name).convert('RGBA').resize((24, 24), Image.LANCZOS)
    tile.paste(small, (2, 2), small)
    sheet.paste(tile, (index * CELL, 0))
sheet.save('build/tray-preview.png')
print('build/tray-preview.png', sheet.size)
