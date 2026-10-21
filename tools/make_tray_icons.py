"""Draws the desktop tray icons from the app's own icon.

The tray is a 24 vp slot in the system bar, so the icon cannot be the app icon
itself (a dark rounded square would be a blob at that size).  What it keeps is
the mark: the mark is cut out of resources/base/media/app_icon.png, given the
two colours the status bar asks for (a white glyph for a dark bar, a dark glyph
for a light one) and a green dot for "a tunnel is up".  Re-run this after
changing the app icon:

    python tools/make_tray_icons.py

When the installed mark is a slab with a hole (tools/icon_studio.py writes
build/icon-studio/tray-mark.png for those), the glyph is the hole instead --
the doorway reads at 24 vp where the slab would not.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'entry/src/main/resources/base/media/app_icon.png'
MARK = ROOT / 'build/icon-studio/tray-mark.png'
OUT = SOURCE.parent

SIDE = 128          # px; the bar scales it down to 24 vp
PADDING = 0.06      # share of the side left empty around the mark
BADGE = 0.26        # share of the side used by the "connected" dot
GAP = 0.06          # transparent ring that separates the dot from the mark


def mark() -> Image.Image:
    """The white glyph of the app icon, as an alpha-only mask."""
    if MARK.exists():
        return Image.open(MARK).convert('RGBA').getchannel('A')
    icon = Image.open(SOURCE).convert('RGBA')
    # The app icon is a white mark on a dark rounded square, so the mark is
    # whatever is bright: a luminance threshold keeps the glyph and drops the
    # plate, including its anti-aliased edge.
    luminance = icon.convert('L')
    alpha = luminance.point(lambda value: 255 if value > 150 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise SystemExit(f'no mark found in {SOURCE}')
    return alpha.crop(bounds)


def square(mask: Image.Image) -> Image.Image:
    """Centres the cropped mark on a transparent square canvas."""
    width, height = mask.size
    inner = int(SIDE * (1 - 2 * PADDING))
    scale = inner / max(width, height)
    scaled = mask.resize((max(1, round(width * scale)), max(1, round(height * scale))),
                         Image.LANCZOS)
    canvas = Image.new('L', (SIDE, SIDE), 0)
    canvas.paste(scaled, ((SIDE - scaled.width) // 2, (SIDE - scaled.height) // 2))
    return canvas


def glyph(mask: Image.Image, colour: tuple) -> Image.Image:
    out = Image.new('RGBA', (SIDE, SIDE), (0, 0, 0, 0))
    out.paste(Image.new('RGBA', (SIDE, SIDE), colour + (255,)), (0, 0), mask)
    return out


def badge(image: Image.Image) -> Image.Image:
    """Adds the "a tunnel is up" dot at the bottom right."""
    diameter = round(SIDE * BADGE)
    radius = radius_of_gap(diameter)
    centre = (SIDE - diameter // 2 - round(SIDE * 0.02), SIDE - diameter // 2 - round(SIDE * 0.02))
    draw = ImageDraw.Draw(image)
    # The gap is painted onto the *alpha* channel with a transparent fill, so
    # the dot does not merge with the mark's descender.
    gap_box = [centre[0] - radius, centre[1] - radius, centre[0] + radius, centre[1] + radius]
    draw.ellipse(gap_box, fill=(0, 0, 0, 0))
    dot_box = [centre[0] - diameter // 2, centre[1] - diameter // 2,
               centre[0] + diameter // 2, centre[1] + diameter // 2]
    draw.ellipse(dot_box, fill=(47, 191, 113, 255))
    return image


def radius_of_gap(diameter: int) -> int:
    return diameter // 2 + round(SIDE * GAP)


def main() -> None:
    mask = square(mark())
    targets = {
        'tray_idle_light.png': ((0xFF, 0xFF, 0xFF), False),
        'tray_idle_dark.png': ((0x17, 0x19, 0x1B), False),
        'tray_up_light.png': ((0xFF, 0xFF, 0xFF), True),
        'tray_up_dark.png': ((0x17, 0x19, 0x1B), True),
    }
    for name, (colour, connected) in targets.items():
        image = glyph(mask, colour)
        if connected:
            image = badge(image)
        path = OUT / name
        image.save(path, 'PNG', optimize=True)
        print(f'{path.name}: {path.stat().st_size} B')


if __name__ == '__main__':
    main()
