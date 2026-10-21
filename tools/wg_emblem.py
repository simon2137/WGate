"""Place the WireGuard emblem (the dragon-in-a-ring mark) on our icon canvas.

The official mark lives in `build/wireguard.svg` twice: the big ring-and-dragon
outline plus a small eye. Both carry `transform="translate(-1.5394)"`, which is
half a unit and can be folded into the numbers. The mark's own bounding box is
about 2.3..301.3 by 0..292, so scaling by `side / 299` centres it in a square of
`side` units.

ArkUI's SVG subset is happiest with no `<g transform>`, so this script bakes the
scale and offset into the path data and writes a composed candidate icon.

Usage: python tools/wg_emblem.py <out-stem> [--side 92] [--cy 100]
"""
import argparse
import pathlib
import re

import svg_path_transform

SOURCE = pathlib.Path('build/wireguard.svg')
OUT_DIR = pathlib.Path('build/icon_candidates')

# Bounding box of the emblem in its own units, measured from the source file.
MARK = (2.32, 0.0, 301.28, 291.92)

BACKGROUND = """  <linearGradient id="bg" x1="0.1" y1="0" x2="0.7" y2="1">
      <stop offset="0%" stop-color="#0F2A33"/>
      <stop offset="100%" stop-color="#04100F"/>
    </linearGradient>
    <linearGradient id="arch" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0%" stop-color="#8DF0D4"/>
      <stop offset="100%" stop-color="#2FBEEB"/>
    </linearGradient>
    <linearGradient id="dragon" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0%" stop-color="#A6F7DA"/>
      <stop offset="100%" stop-color="#33C4F2"/>
    </linearGradient>"""


def emblem_paths():
    """The two `class="a"` paths that make up the mark (ring+dragon, then eye)."""
    text = SOURCE.read_text(encoding='utf-8')
    paths = re.findall(r'<path class="a"[^>]*\sd="([^"]+)"', text)
    # The wordmark letters are also class "a"; the mark is the last two.
    return paths[-2:]


def place(path: str, side: float, cx: float, cy: float) -> str:
    x0, y0, x1, y1 = MARK
    scale = side / (x1 - x0)
    tx = cx - (x0 + x1) / 2 * scale
    ty = cy - (y0 + y1) / 2 * scale
    # The source wraps the mark in translate(-1.5394); fold it in.
    return svg_path_transform.transform(path, scale, tx - 1.5394 * scale, ty)


def build(side: float, cx: float, cy: float, arch: str, dragon: str,
          outer: float, inner: float) -> str:
    ring, eye = emblem_paths()
    arch_fill = 'url(#arch)' if arch == 'gradient' else arch
    dragon_fill = 'url(#dragon)' if dragon == 'gradient' else dragon
    # Legs run from `foot` up to `shoulder`, where the semicircular head starts,
    # so the crown of the tunnel sits at shoulder - outer.
    middle, shoulder, foot = 96.0, 96.0, 154.0
    inner_left, inner_right = middle - inner, middle + inner
    outer_left, outer_right = middle - outer, middle + outer
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 192 192" width="192" height="192">
  <defs>
    {BACKGROUND}
  </defs>
  <rect x="0" y="0" width="192" height="192" rx="40" fill="url(#bg)"/>
  <path d="M{inner_left} {foot} L{inner_left} {shoulder} A{inner} {inner} 0 0 1 {inner_right} {shoulder} L{inner_right} {foot} Z"
        fill="#03100F"/>
  <path d="M{outer_left} {foot} L{outer_left} {shoulder} A{outer} {outer} 0 0 1 {outer_right} {shoulder} L{outer_right} {foot} L{inner_right} {foot} L{inner_right} {shoulder} A{inner} {inner} 0 0 0 {inner_left} {shoulder} L{inner_left} {foot} Z"
        fill="{arch_fill}"/>
  <path d="{place(ring, side, cx, cy)}" fill="{dragon_fill}" fill-rule="evenodd"/>
  <path d="{place(eye, side, cx, cy)}" fill="#03100F"/>
</svg>
"""


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stem')
    parser.add_argument('--side', type=float, default=92.0)
    parser.add_argument('--cx', type=float, default=96.0)
    parser.add_argument('--cy', type=float, default=100.0)
    parser.add_argument('--arch', default='gradient', help='"gradient" or a hex colour')
    parser.add_argument('--dragon', default='gradient', help='"gradient" or a hex colour')
    parser.add_argument('--outer', type=float, default=56.0)
    parser.add_argument('--inner', type=float, default=32.0)
    arguments = parser.parse_args()

    target = OUT_DIR / f'{arguments.stem}.svg'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        build(arguments.side, arguments.cx, arguments.cy, arguments.arch,
              arguments.dragon, arguments.outer, arguments.inner),
        encoding='utf-8')
    print('wrote', target)
