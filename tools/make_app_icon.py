"""Draws the app icon: the original dark plate, and one light shape on it.

The name is WGate but the mark is no longer the letter: a W at 24 px turns to
mud (its feet and its second stroke are 30 px apart, less than the stroke is
wide), and every letterform tried in tools/icon_studio.py either lost its shape
or read as a different letter.  What the app actually is -- a gate you go
through -- draws better: a wall with an arch cut through it, and a bar of light
lying on the sill.  The geometry lives in tools/icon_studio.py, which is also
where every alternative is drawn; this module keeps the plate helpers the older
candidate script imports and writes the two copies the launcher and the tray
read.

    python tools/make_app_icon.py            # writes the app icon (the doorway)
    python tools/icon_studio.py decide       # the shortlist, side by side
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
# The launcher reads the app-level icon (AppScope), the tray derivation reads the
# module-level copy, so both are written from the same drawing.
OUTS = [
    ROOT / 'AppScope/resources/base/media/app_icon.png',
    ROOT / 'entry/src/main/resources/base/media/app_icon.png',
]
PREVIEW = ROOT / 'build/icon_variants.png'
OLD = ROOT / 'build/app_icon_old.png'

SIDE = 512
PLATE = (0x21, 0x27, 0x2A, 255)      # untouched from the previous icon
PLATE_RADIUS = 112
WORK = 4                             # supersampling factor
MARK = 't-door'                      # the mark tools/icon_studio.py installs

# Mark box, in final pixels: the old wedge, kept for tools/make_app_icons.py.
MARK_W = 264
MARK_H = 248
MARK_TOP = 140
ROUND = 26                           # radius of the plate-corner treatment
NOTCH_W = 104                        # half-width of the V cut in the top edge
NOTCH_D = 46                         # how far that V reaches down


def rounded_polygon(points: list, radius: int, size: int) -> Image.Image:
    """A filled polygon with rounded corners, on a `size` square L-mode mask.

    Drawn four times too large, blurred and then cut at mid-grey: blurring
    pulls every corner back by about `radius` and the threshold restores a
    hard edge, which rounds the corners without any per-vertex geometry.
    """
    scale = WORK
    mask = Image.new('L', (size * scale, size * scale), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(x * scale, y * scale) for x, y in points], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius * scale * 0.62))
    mask = mask.point(lambda value: 255 if value >= 128 else 0)
    return mask.resize((size, size), Image.LANCZOS)


def wedge(notch: bool, notch_w: int = NOTCH_W, notch_d: int = NOTCH_D) -> Image.Image:
    """The mark as an L-mode mask, `SIDE` square."""
    centre = SIDE / 2
    left = centre - MARK_W / 2
    right = centre + MARK_W / 2
    top = MARK_TOP
    bottom = MARK_TOP + MARK_H
    if notch:
        points = [
            (left, top),
            (centre - notch_w, top),
            (centre, top + notch_d),
            (centre + notch_w, top),
            (right, top),
            (centre, bottom),
        ]
    else:
        points = [(left, top), (right, top), (centre, bottom)]
    return rounded_polygon(points, ROUND, SIDE)


def plate() -> Image.Image:
    image = Image.new('RGBA', (SIDE, SIDE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle([0, 0, SIDE - 1, SIDE - 1], PLATE_RADIUS, fill=PLATE)
    return image


def compose(mask: Image.Image) -> Image.Image:
    image = plate()
    white = Image.new('RGBA', (SIDE, SIDE), (255, 255, 255, 255))
    image.paste(white, (0, 0), mask)
    return image


def contact_sheet() -> None:
    """Old mark, plain wedge, notched wedge -- at app size and at tray size."""
    variants = []
    if OLD.exists():
        variants.append(('before', Image.open(OLD).convert('RGBA')))
    variants.append(('wedge', compose(wedge(False))))
    variants.append(('wedge + V', compose(wedge(True))))
    variants.append(('V deeper', compose(wedge(True, 84, 78))))
    cell = SIDE + 24
    sheet = Image.new('RGBA', (cell * len(variants), 24 + SIDE + 24 + 72), (245, 245, 245, 255))
    draw = ImageDraw.Draw(sheet)
    for index, (name, image) in enumerate(variants):
        x = index * cell + 12
        sheet.paste(image, (x, 24), image)
        draw.text((x, 30 + SIDE), name, fill=(20, 20, 20, 255))
        small = image.resize((32, 32), Image.LANCZOS)
        sheet.paste(small, (x, 70 + SIDE), small)
        tiny = image.resize((24, 24), Image.LANCZOS)
        sheet.paste(tiny, (x + 40, 74 + SIDE), tiny)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW)
    print(f'{PREVIEW.relative_to(ROOT)}: {PREVIEW.stat().st_size} B')


def main() -> None:
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import icon_studio
    icon_studio.install(MARK)
    if '--preview' in sys.argv:
        icon_studio.sheet()


if __name__ == '__main__':
    main()
