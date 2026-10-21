"""Draws the picture at the top of the README.

It is the app's own icon on the app's own plate colour, with the name beside it,
so the repository opens on the same mark the launcher shows.  Re-run it after
changing the icon:

    python tools/make_readme_hero.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / 'AppScope/resources/base/media/app_icon.png'
OUT = ROOT / 'docs/img/hero.png'

WIDTH, HEIGHT = 1200, 340
BACK = (0x1C, 0x1B, 0x1F)      # Theme.DARK background
PLATE = (0x21, 0x27, 0x2A)     # the icon's plate
AQUA = (0x76, 0xBE, 0xBD)      # Theme.DARK primary
INK = (0xF2, 0xF2, 0xF4)
MUTED = (0x8D, 0x9D, 0x9F)


def font(name, size):
    return ImageFont.truetype(str(Path('C:/Windows/Fonts') / name), size)


def main():
    board = Image.new('RGB', (WIDTH, HEIGHT), BACK)
    draw = ImageDraw.Draw(board)

    # a soft diagonal wash, so the plate does not look like a flat rectangle
    for y in range(HEIGHT):
        shade = 0.86 + 0.28 * (1 - abs(y / HEIGHT - 0.45))
        draw.line([(0, y), (WIDTH, y)],
                  fill=tuple(min(255, round(c * shade)) for c in PLATE))

    icon = Image.open(ICON).convert('RGBA').resize((148, 148), Image.LANCZOS)
    board.paste(icon, (72, (HEIGHT - 148) // 2), icon)

    left = 72 + 148 + 56
    draw.text((left, 92), 'WGate', font=font('msyhbd.ttc', 78), fill=INK)
    draw.text((left + 2, 194), 'HarmonyOS 上的 WireGuard / AmneziaWG 客户端',
              font=font('msyh.ttc', 27), fill=MUTED)
    draw.line([(left + 3, 242), (left + 3 + 120, 242)], fill=AQUA, width=4)
    draw.text((left + 2, 258), '开源 · 无账号 · 无遥测', font=font('msyh.ttc', 21), fill=(0xA9, 0xB4, 0xB8))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    board.save(OUT, 'PNG', optimize=True)
    print(f'{OUT}  {OUT.stat().st_size} B  ({WIDTH}x{HEIGHT})')


if __name__ == '__main__':
    main()
