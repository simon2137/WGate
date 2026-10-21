"""Compose a strip of the given glyphs (default: the settings/detail-page set)."""
import sys
import pathlib

from PIL import Image

DEFAULT = ['ic_dns', 'ic_globe', 'ic_autorenew', 'ic_monitor_heart',
           'ic_view_quilt', 'ic_security', 'ic_view_headline', 'ic_backup_restore']
BUILD = pathlib.Path('build')
CELL, PAD = 132, 10


def strip(names, out_name):
    art = Image.new('RGB', (PAD + len(names) * (CELL + PAD), CELL + 2 * PAD), 'white')
    for index, name in enumerate(names):
        glyph = Image.open(BUILD / f'{name}.png').convert('L').resize((CELL, CELL), Image.LANCZOS)
        art.paste(Image.merge('RGB', (glyph, glyph, glyph)), (PAD + index * (CELL + PAD), PAD))
    target = BUILD / out_name
    art.save(target)
    print('wrote', target)


if __name__ == '__main__':
    names = sys.argv[1:] or DEFAULT
    strip(names, 'icons_settings.png' if names is DEFAULT else 'icons_detail.png')
