"""Before/after strip for the launcher icon, plus the size ladder."""
import pathlib

from PIL import Image

BUILD = pathlib.Path('build/icon_candidates')
LEFT, TOP = 32, 28


def paste(sheet, path, size, x, y):
    art = Image.open(path).convert('RGBA').resize((size, size), Image.LANCZOS)
    sheet.paste(art, (x, y), art)


def main():
    width = LEFT * 2 + 128 + 60 + 48 + 32 + 24
    sheet = Image.new('RGB', (width + 300, 210), (244, 246, 247))
    paste(sheet, BUILD / 'previous-128.png', 128, LEFT, TOP)
    paste(sheet, BUILD / 'final-128.png', 128, LEFT + 128 + 60, TOP)
    ladder = LEFT + 128 + 60 + 128 + 40
    x = ladder
    for size in (64, 48, 32):
        paste(sheet, BUILD / f'final-{size}.png', size, x, TOP + 128 - size)
        x += size + 18
    sheet.save(BUILD / 'before_after.png')
    print('wrote', BUILD / 'before_after.png')


if __name__ == '__main__':
    main()
