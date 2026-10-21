"""Render the settings-row glyphs to a PNG so their silhouettes can be checked.

The page is written next to the SVGs (and into build/) so that a headless
browser resolves `<img src>` as a sibling file. Inline `<svg>` is not painted by
Edge's headless screenshot path on this machine, hence the <img> approach.
"""
import pathlib
import shutil

NAMES = ['ic_dns', 'ic_globe', 'ic_autorenew', 'ic_monitor_heart',
         'ic_view_quilt', 'ic_security', 'ic_view_headline', 'ic_backup_restore']

BASE = pathlib.Path('entry/src/main/resources/base/media')
BUILD = pathlib.Path('build')

CSS = """body{margin:0;background:#fff;font-family:sans-serif;color:#333}
.row{display:flex;align-items:flex-end;gap:10px;padding:14px 16px}
.cell{display:flex;flex-direction:column;align-items:center;gap:6px}
.sm img{width:24px;height:24px}.big img{width:88px;height:88px}
img{display:block}.cap{font-size:11px}"""


def page() -> str:
    small = ''.join(
        f'<div class="cell"><img class="s24" src="{n}.svg" width="24" height="24">'
        f'<span class="cap">{n[3:]}</span></div>' for n in NAMES)
    big = ''.join(
        f'<div class="cell"><img class="s88" src="{n}.svg" width="88" height="88"></div>'
        for n in NAMES)
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS}</style>'
            f'<div class="row">{small}</div><div class="row">{big}</div>'
            f'<style>.s24{{width:24px;height:24px}}.s88{{width:88px;height:88px}}</style>')


def main() -> None:
    html = page()
    for folder in (BASE, BUILD):
        (folder / 'icon_preview.html').write_text(html, encoding='utf-8')
    # Keep a copy of the glyphs next to the build page so both copies render.
    for n in NAMES:
        shutil.copyfile(BASE / f'{n}.svg', BUILD / f'{n}.svg')
    print('wrote', BUILD / 'icon_preview.html')


if __name__ == '__main__':
    main()
