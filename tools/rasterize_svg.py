"""Rasterise our single-colour 24dp SVGs so the glyphs can be eyeballed locally.

There is no SVG rasteriser on this machine (no ImageMagick, Inkscape, rsvg or
Chrome, and Edge's headless screenshot drops both inline `<svg>` and `<img
src=*.svg>`), so this module does the small subset our icons use: `path` with
M/L/H/V/C/S/Q/T/A/Z, absolute or relative, nonzero or even-odd fill.

Usage:
    python tools/rasterize_svg.py                 # writes build/icon_sheet.png
    python tools/rasterize_svg.py ic_dns.svg      # writes build/ic_dns.png
"""
import math
import pathlib
import re
import sys

from PIL import Image

TOKEN = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)')
ARITY = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7, 'Z': 0}
SEGMENTS = 24          # samples per curve segment
SUPERSAMPLE = 4
MEDIA = pathlib.Path('entry/src/main/resources/base/media')
BUILD = pathlib.Path('build')

SHEET_NAMES = ['ic_dns', 'ic_globe', 'ic_autorenew', 'ic_monitor_heart',
               'ic_view_quilt', 'ic_security', 'ic_view_headline', 'ic_backup_restore']


def _tokens(path):
    out = []
    for command, number in TOKEN.findall(path):
        out.append(command if command else float(number))
    return out


def _arc(points, x1, y1, rx, ry, rotation, large, sweep, x2, y2):
    """Append an elliptical arc using the SVG endpoint parameterisation."""
    if rx == 0 or ry == 0:
        points.append((x2, y2))
        return
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rotation)
    cos_phi, sin_phi = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2.0, (y1 - y2) / 2.0
    x1p = cos_phi * dx + sin_phi * dy
    y1p = -sin_phi * dx + cos_phi * dy
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    factor = 0.0 if den == 0 else math.sqrt(max(0.0, num / den))
    if large == sweep:
        factor = -factor
    cxp = factor * rx * y1p / ry
    cyp = -factor * ry * x1p / rx
    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2.0
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2.0

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        norm = math.hypot(ux, uy) * math.hypot(vx, vy)
        value = max(-1.0, min(1.0, dot / norm if norm else 1.0))
        result = math.acos(value)
        return -result if ux * vy - uy * vx < 0 else result

    start = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                  (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if sweep == 0 and delta > 0:
        delta -= 2 * math.pi
    elif sweep != 0 and delta < 0:
        delta += 2 * math.pi

    for step in range(1, SEGMENTS + 1):
        theta = start + delta * step / SEGMENTS
        px = cx + rx * math.cos(theta) * cos_phi - ry * math.sin(theta) * sin_phi
        py = cy + rx * math.cos(theta) * sin_phi + ry * math.sin(theta) * cos_phi
        points.append((px, py))


def subpaths(path):
    """Flatten a path's `d` into polylines."""
    tokens = _tokens(path)
    polys, current = [], []
    x = y = 0.0
    cubic_ctrl = None   # last cubic control point, for the S reflection
    quad_ctrl = None    # last quadratic control point, for the T reflection
    start = (0.0, 0.0)
    index = 0
    command = 'M'
    while index < len(tokens):
        token = tokens[index]
        if isinstance(token, str):
            command = token
            index += 1
            if command.upper() == 'Z':
                if current:
                    current.append(start)
                    polys.append(current)
                    current = []
                x, y = start
                continue
        upper = command.upper()
        relative = command.islower()
        args = tokens[index:index + ARITY[upper]]
        index += ARITY[upper]

        if upper == 'M':
            nx = args[0] + (x if relative else 0)
            ny = args[1] + (y if relative else 0)
            if current:
                polys.append(current)
            current = [(nx, ny)]
            x, y = nx, ny
            start = (nx, ny)
            command = 'l' if relative else 'L'   # implicit repeats are lineto
        elif upper == 'L':
            nx = args[0] + (x if relative else 0)
            ny = args[1] + (y if relative else 0)
            current.append((nx, ny))
            x, y = nx, ny
            cubic_ctrl = quad_ctrl = None
        elif upper == 'H':
            x = args[0] + (x if relative else 0)
            current.append((x, y))
        elif upper == 'V':
            y = args[0] + (y if relative else 0)
            current.append((x, y))
        elif upper in ('C', 'S', 'Q', 'T'):
            if upper == 'C':
                c1x, c1y = args[0] + (x if relative else 0), args[1] + (y if relative else 0)
                c2x, c2y = args[2] + (x if relative else 0), args[3] + (y if relative else 0)
                nx, ny = args[4] + (x if relative else 0), args[5] + (y if relative else 0)
                cubic_ctrl = (c2x, c2y)
            elif upper == 'S':
                # The first control point mirrors the previous curve's last one.
                if cubic_ctrl is None:
                    c1x, c1y = x, y
                else:
                    c1x, c1y = 2 * x - cubic_ctrl[0], 2 * y - cubic_ctrl[1]
                c2x, c2y = args[0] + (x if relative else 0), args[1] + (y if relative else 0)
                nx, ny = args[2] + (x if relative else 0), args[3] + (y if relative else 0)
                cubic_ctrl = (c2x, c2y)
            elif upper == 'Q':
                c1x, c1y = args[0] + (x if relative else 0), args[1] + (y if relative else 0)
                c2x = c1x
                c2y = c1y
                nx, ny = args[2] + (x if relative else 0), args[3] + (y if relative else 0)
                quad_ctrl = (c1x, c1y)
            else:  # T: mirror the previous quadratic control point
                if quad_ctrl is None:
                    c1x, c1y = x, y
                else:
                    c1x, c1y = 2 * x - quad_ctrl[0], 2 * y - quad_ctrl[1]
                c2x = c1x
                c2y = c1y
                nx, ny = args[0] + (x if relative else 0), args[1] + (y if relative else 0)
                quad_ctrl = (c1x, c1y)
            for step in range(1, SEGMENTS + 1):
                t = step / SEGMENTS
                mt = 1 - t
                if upper == 'Q':
                    px = mt * mt * x + 2 * mt * t * c1x + t * t * nx
                    py = mt * mt * y + 2 * mt * t * c1y + t * t * ny
                else:
                    px = (mt ** 3) * x + 3 * mt * mt * t * c1x + 3 * mt * t * t * c2x + (t ** 3) * nx
                    py = (mt ** 3) * y + 3 * mt * mt * t * c1y + 3 * mt * t * t * c2y + (t ** 3) * ny
                current.append((px, py))
            x, y = nx, ny
        elif upper == 'A':
            nx = args[5] + (x if relative else 0)
            ny = args[6] + (y if relative else 0)
            _arc(current, x, y, args[0], args[1], args[2], args[3], args[4], nx, ny)
            x, y = nx, ny
    if current:
        polys.append(current)
    return polys


def render(paths, size=96, evenodd=False):
    """Fill the polylines into a grayscale image of `size` x `size`."""
    scale = size * SUPERSAMPLE / 24.0
    height = size * SUPERSAMPLE
    coverage = [[0] * height for _ in range(height)]
    edges = []
    for poly in paths:
        for (x1, y1), (x2, y2) in zip(poly, poly[1:]):
            edges.append((x1 * scale, y1 * scale, x2 * scale, y2 * scale,
                          1 if y2 > y1 else -1 if y2 < y1 else 0))
        if poly and poly[0] != poly[-1]:
            (x1, y1), (x2, y2) = poly[-1], poly[0]
            edges.append((x1 * scale, y1 * scale, x2 * scale, y2 * scale,
                          1 if y2 > y1 else -1 if y2 < y1 else 0))

    for row in range(height):
        scan = row + 0.5
        crossings = []
        for x1, y1, x2, y2, direction in edges:
            if (y1 <= scan < y2) or (y2 <= scan < y1):
                t = (scan - y1) / (y2 - y1)
                crossings.append((x1 + t * (x2 - x1), direction))
        if not crossings:
            continue
        crossings.sort()
        winding = 0
        for index in range(len(crossings) - 1):
            winding += crossings[index][1]
            inside = (winding % 2 != 0) if evenodd else (winding != 0)
            if inside:
                start_x = max(0, int(math.ceil(crossings[index][0] - 0.5)))
                end_x = min(height, int(math.ceil(crossings[index + 1][0] - 0.5)))
                for column in range(start_x, end_x):
                    coverage[row][column] = 255

    image = Image.new('L', (height, height), 0)
    image.putdata([value for row in coverage for value in row])
    return image.resize((size, size), Image.BOX)


def glyph(name):
    """Union of every `<path>` in the file; each keeps its own fill rule.

    The hand-written icons mix an even-odd `ring()` with a plain `solid()` dot,
    so a single winding buffer would get the holes wrong.
    """
    text = (MEDIA / f'{name}.svg').read_text(encoding='utf-8')
    merged = None
    for attributes, body in re.findall(r'<path([^>]*?)(?:/>|>(.*?)</path>)', text, re.S):
        source = body or ''
        d = re.search(r'\sd="([^"]+)"', attributes)
        if d is None and source:
            d = re.search(r'\sd="([^"]+)"', source)
        if d is None:
            continue
        evenodd = 'evenodd' in attributes
        art = render(subpaths(d.group(1)), evenodd=evenodd)
        merged = art if merged is None else Image.frombytes(
            'L', art.size, bytes(max(a, b) for a, b in zip(merged.tobytes(), art.tobytes())))
    if merged is None:
        raise SystemExit(f'{name}.svg holds no path')
    return merged


def main(argv):
    if len(argv) > 1:
        for name in argv[1:]:
            stem = name[:-4] if name.endswith('.svg') else name
            # Save black-on-white: the coverage buffer has 255 inside the glyph.
            glyph(stem).point(lambda v: 255 - v).save(BUILD / f'{stem}.png')
            print('wrote', BUILD / f'{stem}.png')
        return

    cell, pad, scale = 120, 12, 4   # scale: 96 -> 384 for the sheet
    width = pad + len(SHEET_NAMES) * (cell + pad)
    sheet = Image.new('L', (width, cell + 2 * pad), 255)
    for index, name in enumerate(SHEET_NAMES):
        art = glyph(name).resize((cell, cell), Image.LANCZOS)
        sheet.paste(art.point(lambda v: 255 - v), (pad + index * (cell + pad), pad))
    sheet.save(BUILD / 'icon_sheet.png')
    print('wrote', BUILD / 'icon_sheet.png')


if __name__ == '__main__':
    main(sys.argv)
