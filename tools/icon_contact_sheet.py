"""Contact sheet: each candidate at icon-preview sizes, on a light surface."""
import pathlib
import sys

from PIL import Image

SIZES = (128, 64, 48, 32)
CELL = max(SIZES) + 16
BUILD = pathlib.Path('build/icon_candidates')


def main(names):
    columns = len(SIZES) * len(names)
    sheet = Image.new('RGB', (columns * CELL + 16, CELL + 40), (238, 241, 242))
    x = 16
    for name in names:
        for size in SIZES:
            art = Image.open(BUILD / f'{name}-{size}.png').convert('RGBA')
            sheet.paste(art, (x, 16), art)
            x += CELL
    out = BUILD / 'sheet.png'
    sheet.save(out)
    print('wrote', out)


if __name__ == '__main__':
    main(sys.argv[1:] or ['a', 'a2', 'b', 'c'])
