"""Draws candidate launcher icons for the name WGate and compares them.

The app has kept one visual language from the beginning: a single white mark,
uniform weight, generous margins, on a #21272A rounded plate.  This script keeps
that language and only changes what the mark says, because the name went from
the W monogram the port started with to "WGate".

    python tools/make_app_icons.py                   # writes build/wgate-icons.png
    python tools/make_app_icons.py --install portal   # install one variant

Shapes are drawn with ImageDraw at three times the final size and downsampled, so
an opening inside a mark stays exactly as wide as it was drawn.  (Blurring a
thin band before thresholding -- what the first wedge did -- ate the band away.)
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_app_icon as base  # noqa: E402  (the path has to be set first)

SIDE = base.SIDE
ROOT = base.ROOT
OUTS = base.OUTS
PREVIEW = ROOT / 'build/wgate-icons.png'
SCALE = 3

CENTRE = SIDE / 2
LEFT = 124
RIGHT = 388
TOP = base.MARK_TOP          # 140, the optical top every earlier mark used
BOTTOM = 388


class Mask:
    """A drawing surface three times too large, halved back on save."""

    def __init__(self) -> None:
        self.image = Image.new('L', (SIDE * SCALE, SIDE * SCALE), 0)
        self.draw = ImageDraw.Draw(self.image)

    def box(self, x0, y0, x1, y1, radius=10, value=255):
        self.draw.rounded_rectangle(
            [x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE],
            radius=radius * SCALE, fill=value)

    def polygon(self, points, value=255):
        self.draw.polygon([(x * SCALE, y * SCALE) for x, y in points], fill=value)

    def circle(self, cx, cy, radius, value=255):
        r = radius * SCALE
        self.draw.ellipse([cx * SCALE - r, cy * SCALE - r,
                           cx * SCALE + r, cy * SCALE + r], fill=value)

    def stroke(self, x0, y0, x1, y1, width, value=255):
        dx, dy = x1 - x0, y1 - y0
        length = (dx * dx + dy * dy) ** 0.5 or 1.0
        nx, ny = -dy / length * width / 2, dx / length * width / 2
        self.polygon([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
                      (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], value)
        self.circle(x0, y0, width / 2, value)
        self.circle(x1, y1, width / 2, value)

    def dome(self, x0, y0, x1, y1, value=255):
        radius = (x1 - x0) / 2
        cx = (x0 + x1) / 2
        points = [(x0, y1)]
        for step in range(61):
            angle = math.pi - math.pi * step / 60
            points.append((cx + radius * math.cos(angle),
                           y0 + radius - radius * math.sin(angle)))
        points.append((x1, y1))
        self.polygon(points, value)

    def done(self) -> Image.Image:
        return self.image.resize((SIDE, SIDE), Image.LANCZOS)


def portal() -> Image.Image:
    """The tunnel mouth itself: a thick arch standing on the baseline."""
    mask = Mask()
    mask.dome(LEFT, TOP, RIGHT, BOTTOM)
    mask.dome(LEFT + 72, TOP + 72, RIGHT - 72, BOTTOM, value=0)
    return mask.done()


def gate() -> Image.Image:
    """A doorway: two posts under a heavy lintel."""
    mask = Mask()
    mask.box(LEFT - 4, TOP + 4, RIGHT + 4, TOP + 62, radius=16)
    mask.box(LEFT + 8, TOP + 48, LEFT + 92, BOTTOM, radius=10)
    mask.box(RIGHT - 92, TOP + 48, RIGHT - 8, BOTTOM, radius=10)
    return mask.done()


def inverted() -> Image.Image:
    """A solid block with the W cut out of it: bold at any size."""
    width = 62
    mask = Mask()
    mask.box(LEFT - 12, TOP - 6, RIGHT + 12, BOTTOM + 6, radius=30)
    mask.stroke(LEFT + 40, TOP + 30, LEFT + 90, BOTTOM - 30, width, value=0)
    mask.stroke(LEFT + 90, BOTTOM - 30, CENTRE, TOP + 156, width, value=0)
    mask.stroke(CENTRE, TOP + 156, RIGHT - 90, BOTTOM - 30, width, value=0)
    mask.stroke(RIGHT - 90, BOTTOM - 30, RIGHT - 40, TOP + 30, width, value=0)
    return mask.done()


def monogram() -> Image.Image:
    """A chunky W with round caps, so the joints stay soft at 24 px."""
    width = 88
    mask = Mask()
    mask.stroke(LEFT + 16, TOP + 6, LEFT + 60, BOTTOM, width)
    mask.stroke(LEFT + 60, BOTTOM, CENTRE, TOP + 132, width)
    mask.stroke(CENTRE, TOP + 132, RIGHT - 60, BOTTOM, width)
    mask.stroke(RIGHT - 60, BOTTOM, RIGHT - 16, TOP + 6, width)
    return mask.done()


def keyhole() -> Image.Image:
    """A solid gate with a keyhole through it."""
    mask = Mask()
    mask.box(LEFT, TOP + 4, RIGHT, BOTTOM, radius=26)
    mask.circle(CENTRE, TOP + 118, 44, value=0)
    mask.polygon([(CENTRE - 26, TOP + 118), (CENTRE + 26, TOP + 118),
                  (CENTRE + 54, BOTTOM + 10), (CENTRE - 54, BOTTOM + 10)], value=0)
    return mask.done()


VARIANTS = [
    ('portal', portal),
    ('gate', gate),
    ('W monogram', monogram),
    ('W in block', inverted),
    ('keyhole', keyhole),
]


def nested() -> Image.Image:
    """Two arches, one inside the other: a tunnel with depth."""
    mask = Mask()
    mask.dome(LEFT, TOP, RIGHT, BOTTOM)
    mask.dome(LEFT + 56, TOP + 56, RIGHT - 56, BOTTOM, value=0)
    mask.dome(LEFT + 84, TOP + 84, RIGHT - 84, BOTTOM)
    mask.dome(LEFT + 112, TOP + 112, RIGHT - 112, BOTTOM, value=0)
    return mask.done()


def light() -> Image.Image:
    """The arch with one dot of light inside it."""
    mask = Mask()
    mask.dome(LEFT, TOP, RIGHT, BOTTOM)
    mask.dome(LEFT + 74, TOP + 74, RIGHT - 74, BOTTOM, value=0)
    mask.circle(CENTRE, BOTTOM - 96, 38)
    return mask.done()


def perspective() -> Image.Image:
    """A tunnel mouth in perspective: narrower at the top, wider at the floor."""
    mask = Mask()
    mask.polygon([(LEFT + 40, TOP + 4), (RIGHT - 40, TOP + 4),
                  (RIGHT, BOTTOM), (LEFT, BOTTOM)])
    mask.polygon([(LEFT + 96, TOP + 34), (RIGHT - 96, TOP + 34),
                  (RIGHT - 32, BOTTOM + 8), (LEFT + 32, BOTTOM + 8)], value=0)
    return mask.done()


def shield() -> Image.Image:
    """A shield, the one shape every VPN app is allowed to use, with a wedge
    notch cut out of its point so it is ours and not a stock shield."""
    mask = Mask()
    points = [(CENTRE - 124, TOP + 6), (CENTRE + 124, TOP + 6),
              (CENTRE + 124, TOP + 138)]
    for step in range(21):
        angle = step / 20
        points.append((CENTRE + 124 * (1 - angle) ** 0.85,
                       TOP + 138 + 112 * angle ** 0.55))
    for step in range(20, -1, -1):
        angle = step / 20
        points.append((CENTRE - 124 * (1 - angle) ** 0.85,
                       TOP + 138 + 112 * angle ** 0.55))
    mask.polygon(points)
    mask.polygon([(CENTRE - 62, BOTTOM - 84), (CENTRE + 62, BOTTOM - 84),
                  (CENTRE, BOTTOM + 6)], value=0)
    return mask.done()


def keystone() -> Image.Image:
    """The arch with a keystone block sitting on its crown."""
    mask = Mask()
    mask.dome(LEFT + 10, TOP + 62, RIGHT - 10, BOTTOM)
    mask.dome(LEFT + 78, TOP + 130, RIGHT - 78, BOTTOM, value=0)
    mask.polygon([(CENTRE - 54, TOP + 2), (CENTRE + 54, TOP + 2),
                  (CENTRE + 34, TOP + 92), (CENTRE - 34, TOP + 92)])
    return mask.done()


EXTRA = [
    ('nested arches', nested),
    ('arch + light', light),
    ('perspective', perspective),
    ('shield', shield),
    ('keystone', keystone),
]


# --- a wider set of concepts -------------------------------------------------
# The first ten were all architecture (arch, doorway, gate frame) or letterforms.
# These go after different kinds of mark: an object, an abstraction, a mechanism,
# a combination, and a piece of geometry.

def key() -> Image.Image:
    """A key: the thing that opens a gate, and the private key a tunnel is."""
    cy = (TOP + BOTTOM) / 2
    mask = Mask()
    mask.circle(CENTRE - 72, cy, 64)
    mask.circle(CENTRE - 72, cy, 26, value=0)
    mask.box(CENTRE - 84, cy - 26, RIGHT - 4, cy + 26, radius=10)
    mask.box(RIGHT - 62, cy + 18, RIGHT - 26, cy + 62, radius=8)
    return mask.done()


def ring() -> Image.Image:
    """A tunnel seen head on: one thick ring, the hole is the depth."""
    cy = (TOP + BOTTOM) / 2
    mask = Mask()
    mask.circle(CENTRE, cy, 126)
    mask.circle(CENTRE, cy, 70, value=0)
    return mask.done()


def battlement() -> Image.Image:
    """A gate tower: two merlons over a solid wall."""
    mask = Mask()
    mask.box(LEFT + 6, TOP + 76, RIGHT - 6, BOTTOM, radius=12)
    mask.box(LEFT + 6, TOP, LEFT + 100, TOP + 86, radius=10)
    mask.box(RIGHT - 100, TOP, RIGHT - 6, TOP + 86, radius=10)
    return mask.done()


def turnstile() -> Image.Image:
    """A turnstile: three arms and a hub, the mechanism that lets one through."""
    cy = (TOP + BOTTOM) / 2
    width = 46
    mask = Mask()
    for x1, y1 in ((CENTRE, TOP + 6), (LEFT + 12, BOTTOM - 40), (RIGHT - 12, BOTTOM - 40)):
        mask.stroke(CENTRE, cy, x1, y1, width)
    mask.circle(CENTRE, cy, width / 2 + 8)
    return mask.done()


def shield_arch() -> Image.Image:
    """A shield with a doorway cut out of it: security and the gate at once."""
    mask = Mask()
    points = [(CENTRE - 122, TOP + 4), (CENTRE + 122, TOP + 4), (CENTRE + 122, TOP + 132)]
    for step in range(21):
        angle = step / 20
        points.append((CENTRE + 122 * (1 - angle) ** 0.85,
                       TOP + 132 + 116 * angle ** 0.55))
    for step in range(20, -1, -1):
        angle = step / 20
        points.append((CENTRE - 122 * (1 - angle) ** 0.85,
                       TOP + 132 + 116 * angle ** 0.55))
    mask.polygon(points)
    mask.dome(CENTRE - 62, TOP + 150, CENTRE + 62, BOTTOM + 10, value=0)
    return mask.done()


def fold() -> Image.Image:
    """A sheet with one corner turned back: the gate opening, as geometry."""
    mask = Mask()
    mask.box(LEFT, TOP, RIGHT, BOTTOM, radius=28)
    mask.polygon([(RIGHT - 104, TOP - 10), (RIGHT + 12, TOP - 10),
                  (RIGHT + 12, TOP + 106)], value=0)
    mask.polygon([(RIGHT - 96, TOP + 10), (RIGHT - 12, TOP + 10),
                  (RIGHT - 12, TOP + 94)])
    return mask.done()


CONCEPTS = [
    ('key', key),
    ('ring', ring),
    ('battlement', battlement),
    ('turnstile', turnstile),
    ('shield + arch', shield_arch),
    ('fold', fold),
]


def padlock() -> Image.Image:
    """A padlock: the oldest gate there is, and the fastest read at 24 px."""
    cy = (TOP + BOTTOM) / 2
    mask = Mask()
    mask.dome(CENTRE - 74, TOP + 6, CENTRE + 74, cy + 10)
    mask.dome(CENTRE - 32, TOP + 48, CENTRE + 32, cy + 10, value=0)
    mask.box(CENTRE - 74, cy - 14, CENTRE + 74, cy + 10, value=0)
    mask.box(LEFT + 22, cy - 4, RIGHT - 22, BOTTOM, radius=24)
    mask.circle(CENTRE, cy + 62, 26, value=0)
    mask.box(CENTRE - 12, cy + 62, CENTRE + 12, cy + 116, radius=6, value=0)
    return mask.done()


def badge() -> Image.Image:
    """A W inside a ring: the badge pattern every app store row uses."""
    cy = (TOP + BOTTOM) / 2
    mask = Mask()
    mask.circle(CENTRE, cy, 128)
    mask.circle(CENTRE, cy, 96, value=0)
    width = 44
    mask.stroke(CENTRE - 52, cy - 44, CENTRE - 24, cy + 48, width)
    mask.stroke(CENTRE - 24, cy + 48, CENTRE, cy - 12, width)
    mask.stroke(CENTRE, cy - 12, CENTRE + 24, cy + 48, width)
    mask.stroke(CENTRE + 24, cy + 48, CENTRE + 52, cy - 44, width)
    return mask.done()


def port() -> Image.Image:
    """Two chevrons facing each other: a port, the gap is the passage."""
    cy = (TOP + BOTTOM) / 2
    width = 58
    mask = Mask()
    mask.stroke(LEFT + 6, TOP + 20, CENTRE - 44, cy, width)
    mask.stroke(CENTRE - 44, cy, LEFT + 6, BOTTOM - 20, width)
    mask.stroke(RIGHT - 6, TOP + 20, CENTRE + 44, cy, width)
    mask.stroke(CENTRE + 44, cy, RIGHT - 6, BOTTOM - 20, width)
    return mask.done()


def letter_g() -> Image.Image:
    """The G of Gate, cut so it is a gate opening and not a stock letter."""
    cy = (TOP + BOTTOM) / 2
    mask = Mask()
    mask.circle(CENTRE, cy, 124)
    mask.circle(CENTRE, cy, 76, value=0)
    mask.box(CENTRE + 4, cy - 30, CENTRE + 150, cy + 118, value=0)
    mask.box(CENTRE - 4, cy + 10, CENTRE + 76, cy + 58, radius=10)
    return mask.done()


WIDER = [
    ('padlock', padlock),
    ('badge', badge),
    ('port', port),
    ('letter G', letter_g),
]


def font(size: int):
    for name in ('segoeui.ttf', 'arial.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def on_plate(mask: Image.Image) -> Image.Image:
    image = base.plate()
    white = Image.new('RGBA', (SIDE, SIDE), (255, 255, 255, 255))
    image.paste(white, (0, 0), mask)
    return image


def contact_sheet(pool=VARIANTS) -> None:
    cells = [('current', base.compose(base.wedge(True)))]
    cells += [(name, on_plate(draw())) for name, draw in pool]
    big, pad, label, mid, small = 150, 20, 26, 48, 24
    width = pad + (big + pad) * len(cells)
    height = 20 + big + label + 20 + mid + 34 + small + 20
    sheet = Image.new('RGBA', (width, height), (247, 247, 248, 255))
    draw = ImageDraw.Draw(sheet)
    x = pad
    for name, image in cells:
        large = image.resize((big, big), Image.LANCZOS)
        sheet.paste(large, (x, 20), large)
        draw.text((x, 20 + big + 4), name, fill=(24, 24, 26, 255), font=font(14))
        medium = image.resize((mid, mid), Image.LANCZOS)
        sheet.paste(medium, (x, 20 + big + label + 16), medium)
        tiny = image.resize((small, small), Image.LANCZOS)
        sheet.paste(tiny, (x, 20 + big + label + 16 + mid + 10), tiny)
        x += big + pad
    sheet.save(PREVIEW)
    print(f'{PREVIEW.relative_to(ROOT)}: {PREVIEW.stat().st_size} B')


def main() -> None:
    wanted = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--install' in sys.argv:
        names = {name: draw for name, draw in VARIANTS + EXTRA + CONCEPTS + WIDER}
        if not wanted or wanted[0] not in names:
            print('pick one of: ' + ', '.join(names))
            return
        image = on_plate(names[wanted[0]]())
        for path in OUTS:
            image.save(path, 'PNG', optimize=True)
            print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B')
        return
    if '--wider' in sys.argv:
        contact_sheet(CONCEPTS + WIDER)
    elif '--concepts' in sys.argv:
        contact_sheet(CONCEPTS)
    elif '--extra' in sys.argv:
        contact_sheet(EXTRA)
    else:
        contact_sheet(VARIANTS)


if __name__ == '__main__':
    main()
