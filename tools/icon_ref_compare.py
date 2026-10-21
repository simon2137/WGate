"""The original project's icon beside the new one, on the same plate and at the
same three sizes -- the comparison that decides whether a redesign kept the
family.

    python tools/icon_ref_compare.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/icon-studio/before-after.png'
SIDE = 384
RADIUS = int(112 * SIDE / 512)
LADDER = (72, 48, 24)


def squircle(image):
    mask = Image.new('L', (SIDE, SIDE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIDE - 1, SIDE - 1], RADIUS, fill=255)
    out = Image.new('RGBA', (SIDE, SIDE), (0, 0, 0, 0))
    out.paste(image.resize((SIDE, SIDE), Image.LANCZOS), (0, 0), mask)
    return out


def font(size):
    try:
        return ImageFont.truetype('msyh.ttc', size)
    except OSError:
        return ImageFont.load_default()


def column(board, art, x, label):
    draw = ImageDraw.Draw(board)
    draw.text((x, 20), label, fill=(24, 24, 27), font=font(20))
    board.paste(art, (x, 56), art)
    draw.text((x, SIDE + 74), ' / '.join(str(s) for s in LADDER) + ' px',
              fill=(110, 116, 124), font=font(14))
    cursor = x
    for size in LADDER:
        small = art.resize((size, size), Image.LANCZOS)
        board.paste(small, (cursor, SIDE + 96), small)
        cursor += size + 16


before = squircle(Image.open(ROOT / '_ref_android/app/src/main/ic_launcher-playstore.png')
                  .convert('RGBA'))
after = squircle(Image.open(ROOT / 'AppScope/resources/base/media/app_icon.png').convert('RGBA'))

pad = 48
board = Image.new('RGB', (pad * 3 + SIDE * 2, SIDE + 200), (245, 246, 247))
column(board, before, pad, '原项目（WG Tunnel）')
column(board, after, pad * 2 + SIDE, 'WGate')
OUT.parent.mkdir(parents=True, exist_ok=True)
board.save(OUT)
print(OUT)
