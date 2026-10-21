"""Compares the two possible status-bar glyphs for the installed mark.

The tray slot is 16-24 px on a PC, so a glyph that reads on a design board can
still be a smudge in the bar.  This renders both candidates at the sizes the
shell actually uses, on both bar colours, with and without the "connected" dot:

    python tools/tray_compare.py            # -> build/icon-studio/tray-compare.png

Candidate A is the doorway (the hole in the mark); B is the slab with the
doorway cut out of its foot -- the icon's own silhouette, shrunk.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from icon_studio import SIDE, Pen

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/icon-studio/tray-compare.png'

WHITE = (0xFF, 0xFF, 0xFF)
DARK = (0x17, 0x19, 0x1B)
GREEN = (47, 191, 113)

SIZES = (16, 20, 24, 32)
PADDING = 0.06
BADGE = 0.26
GAP = 0.06


def arch() -> Image.Image:
    pen = Pen()
    pen.stroke([(256, 296), (256, 430)], 212)
    pen.block(0, 396, SIDE, SIDE, 0, 0)
    return pen.done()


def slab() -> Image.Image:
    pen = Pen()
    pen.block(104, 104, 408, 396, 80)
    pen.stroke([(256, 250), (256, 430)], 156, 0)
    return pen.done()


def square(mask: Image.Image, side: int = 128) -> Image.Image:
    bounds = mask.getbbox()
    mask = mask.crop(bounds)
    inner = int(side * (1 - 2 * PADDING))
    scale = inner / max(mask.size)
    scaled = mask.resize((max(1, round(mask.width * scale)),
                          max(1, round(mask.height * scale))), Image.LANCZOS)
    canvas = Image.new('L', (side, side), 0)
    canvas.paste(scaled, ((side - scaled.width) // 2, (side - scaled.height) // 2))
    return canvas


def glyph(mask: Image.Image, colour, connected: bool) -> Image.Image:
    side = mask.width
    out = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    out.paste(Image.new('RGBA', (side, side), colour + (255,)), (0, 0), mask)
    if not connected:
        return out
    diameter = round(side * BADGE)
    centre = (side - diameter // 2 - round(side * 0.02), side - diameter // 2 - round(side * 0.02))
    radius = diameter // 2 + round(side * GAP)
    draw = ImageDraw.Draw(out)
    draw.ellipse([centre[0] - radius, centre[1] - radius,
                  centre[0] + radius, centre[1] + radius], fill=(0, 0, 0, 0))
    draw.ellipse([centre[0] - diameter // 2, centre[1] - diameter // 2,
                  centre[0] + diameter // 2, centre[1] + diameter // 2], fill=GREEN + (255,))
    return out


def font(size):
    for name in ('msyh.ttc', 'segoeui.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    marks = [('A 门洞（洞本身）', square(arch())), ('B 墙（挖掉门洞）', square(slab()))]
    cell = 210
    width = cell * 2 + 40
    height = 96 + (62 + 46) * len(SIZES)
    board = Image.new('RGB', (width, height), (233, 236, 239))
    draw = ImageDraw.Draw(board)
    draw.text((20, 16), '状态栏字形：两个候选，四种实际尺寸', fill=(30, 34, 40), font=font(16))
    y = 56
    for size in SIZES:
        draw.text((20, y + 8), f'{size} px', fill=(110, 118, 128), font=font(13))
        for column, (_label, mask) in enumerate(marks):
            x = 90 + column * cell
            for row, (bar, colour) in enumerate(((DARK, WHITE), ((233, 236, 239), DARK))):
                yy = y + row * 40
                draw.rectangle([x - 6, yy - 4, x + 150, yy + size + 6], fill=bar)
                for i, connected in enumerate((False, True)):
                    image = glyph(mask, colour, connected).resize((size, size), Image.LANCZOS)
                    board.paste(image, (x + 6 + i * (size + 26), yy), image)
        y += 62 + 46

    for column, (label, _mask) in enumerate(marks):
        draw.text((90 + column * cell, height - 40), label, fill=(40, 46, 54), font=font(14))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    board.save(OUT)
    print(OUT)


if __name__ == '__main__':
    main()
