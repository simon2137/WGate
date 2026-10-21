"""Colour rasteriser for the app-icon candidates.

`rasterize_svg.py` only knows single-colour 24dp glyphs, so it cannot show a
gradient background. This module renders the small subset an icon needs:
`rect` (with rx), `circle`, `path`, solid or gradient fills, fill-opacity,
in document order with alpha compositing.

Usage:
    python tools/rasterize_icon.py build/icon_candidates/a.svg 192
"""
import math
import pathlib
import re
import sys

import numpy
from PIL import Image, ImageDraw

from rasterize_svg import subpaths

SUPERSAMPLE = 4


def attr(text, name, default=None):
    hit = re.search(rf'\s{name}="([^"]*)"', text)
    return hit.group(1) if hit else default


def colour(value):
    value = value.strip()
    if value.startswith('#'):
        value = value[1:]
        if len(value) == 3:
            value = ''.join(ch * 2 for ch in value)
        return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    named = {'white': (255, 255, 255), 'black': (0, 0, 0), 'none': None}
    return named.get(value.lower())


def gradients(text):
    """Collect linear/radial gradients as (kind, geometry, stops)."""
    found = {}
    for kind in ('linearGradient', 'radialGradient'):
        for block in re.findall(rf'<{kind}\b([^>]*)>(.*?)</{kind}>', text, re.S):
            head, body = block
            ident = attr(head, 'id')
            stops = [(float(attr(stop, 'offset', '0').rstrip('%')) / 100.0,
                      colour(attr(stop, 'stop-color', '#000000')))
                     for stop in re.findall(r'<stop\b([^>]*)/?>', body)]
            geometry = {
                'x1': float(attr(head, 'x1', '0') or 0),
                'y1': float(attr(head, 'y1', '0') or 0),
                'x2': float(attr(head, 'x2', '1') or 1),
                'y2': float(attr(head, 'y2', '0') or 0),
                'cx': float(attr(head, 'cx', '0.5') or 0.5),
                'cy': float(attr(head, 'cy', '0.5') or 0.5),
                'r': float(attr(head, 'r', '0.5') or 0.5),
            }
            found[ident] = (kind, geometry, sorted(stops))
    return found


def sample(stops, t):
    t = max(0.0, min(1.0, t))
    for index in range(len(stops) - 1):
        (t0, c0), (t1, c1) = stops[index], stops[index + 1]
        if t0 <= t <= t1:
            span = t1 - t0
            k = 0.0 if span == 0 else (t - t0) / span
            return tuple(round(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
    return stops[-1][1] if t > stops[-1][0] else stops[0][1]


def paint(stops, kind, geometry, box, size, viewport):
    """Build the shape-sized RGB tile holding its gradient."""
    left, top, right, bottom = box
    width = max(1, round((right - left) * size / viewport))
    height = max(1, round((bottom - top) * size / viewport))
    art = Image.new('RGB', (width, height))
    pixels = []
    for row in range(height):
        for column in range(width):
            u = (left + (column + 0.5) * viewport / size - left) / max(1e-6, right - left)
            v = (top + (row + 0.5) * viewport / size - top) / max(1e-6, bottom - top)
            if kind == 'linearGradient':
                dx = geometry['x2'] - geometry['x1']
                dy = geometry['y2'] - geometry['y1']
                denominator = dx * dx + dy * dy
                t = 0.0 if denominator == 0 else ((u - geometry['x1']) * dx +
                                                 (v - geometry['y1']) * dy) / denominator
            else:
                t = math.hypot(u - geometry['cx'], v - geometry['cy']) / max(1e-6, geometry['r'])
            pixels.append(sample(stops, t))
    art.putdata(pixels)
    return art


def polygon_mask(polys, size, viewport, evenodd):
    """Scanline fill of the flattened polylines, supersampled then box-filtered.

    With `evenodd` the subpaths are XOR-ed together, which is what `fill-rule=
    "evenodd"` means across a multi-subpath path: nested contours punch holes
    instead of stacking. Without it each subpath is simply OR-ed in, which suits
    glyphs built from disjoint parts.
    """
    large = size * SUPERSAMPLE
    scale = large / viewport
    if evenodd:
        accumulator = numpy.zeros((large, large), dtype=bool)
        for poly in polys:
            points = [(x * scale, y * scale) for x, y in poly]
            if len(points) < 3:
                continue
            tile = Image.new('L', (large, large), 0)
            ImageDraw.Draw(tile).polygon(points, fill=255)
            accumulator ^= numpy.asarray(tile) > 127
        coverage = Image.fromarray((accumulator * 255).astype('uint8'))
        return coverage.resize((size, size), Image.BOX)

    coverage = Image.new('L', (large, large), 0)
    draw = ImageDraw.Draw(coverage)
    for poly in polys:
        points = [(x * scale, y * scale) for x, y in poly]
        if len(points) < 3:
            continue
        # PIL fills a self-intersecting polygon with the even-odd rule, which is
        # what `ring()` relies on; nonzero glyphs are made of disjoint parts.
        draw.polygon(points, fill=255)
    return coverage.resize((size, size), Image.BOX)


def stroke_mask(polys, size, viewport, width):
    """Mask for a stroked polyline, rounded caps and joins, supersampled."""
    large = size * SUPERSAMPLE
    scale = large / viewport
    mask = Image.new('L', (large, large), 0)
    draw = ImageDraw.Draw(mask)
    radius = width * scale / 2.0
    for poly in polys:
        points = [(x * scale, y * scale) for x, y in poly]
        if len(points) > 1:
            draw.line(points, fill=255, width=max(1, round(width * scale)), joint='curve')
        for x, y in (points[:1] + points[-1:]):
            draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)
    return mask.resize((size, size), Image.BOX)


def render(svg_path, size=192):
    text = pathlib.Path(svg_path).read_text(encoding='utf-8')
    viewport = float(attr(re.search(r'<svg\b[^>]*>', text).group(0), 'viewBox',
                          '0 0 192 192').split()[2])
    defs = gradients(text)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    for tag, head, _ in re.findall(r'<(rect|circle|path)\b([^>]*?)(?:/>|>(.*?)</\1>)', text, re.S):
        fill = attr(head, 'fill', '#000000')
        opacity = float(attr(head, 'fill-opacity', '1') or 1)
        box = None

        if tag == 'rect':
            x, y = float(attr(head, 'x', '0') or 0), float(attr(head, 'y', '0') or 0)
            w, h = float(attr(head, 'width', '0') or 0), float(attr(head, 'height', '0') or 0)
            rx = float(attr(head, 'rx', '0') or 0)
            mask = Image.new('L', (size * SUPERSAMPLE, size * SUPERSAMPLE), 0)
            draw = ImageDraw.Draw(mask)
            box = (x, y, x + w, y + h)
            factor = size * SUPERSAMPLE / viewport
            draw.rounded_rectangle(
                [x * factor, y * factor, (x + w) * factor, (y + h) * factor],
                radius=rx * factor, fill=255)
            mask = mask.resize((size, size), Image.BOX)
            left, top = round(x * size / viewport), round(y * size / viewport)
        elif tag == 'circle':
            cx, cy = float(attr(head, 'cx', '0') or 0), float(attr(head, 'cy', '0') or 0)
            r = float(attr(head, 'r', '0') or 0)
            factor = size * SUPERSAMPLE / viewport
            mask = Image.new('L', (size * SUPERSAMPLE, size * SUPERSAMPLE), 0)
            ImageDraw.Draw(mask).ellipse([(cx - r) * factor, (cy - r) * factor,
                                          (cx + r) * factor, (cy + r) * factor], fill=255)
            mask = mask.resize((size, size), Image.BOX)
            box = (cx - r, cy - r, cx + r, cy + r)
            left, top = round((cx - r) * size / viewport), round((cy - r) * size / viewport)
        else:
            d = attr(head, 'd')
            if d is None:
                continue
            polys = subpaths(d)
            stroke = attr(head, 'stroke', 'none')
            xs = [x for poly in polys for x, _ in poly]
            ys = [y for poly in polys for _, y in poly]
            if stroke not in ('none', None):
                # Stroked outline (the previous launcher icon was drawn this way):
                # the stroke becomes the shape, its own bbox the gradient box.
                width = float(attr(head, 'stroke-width', '1') or 1)
                box = (min(xs) - width / 2, min(ys) - width / 2,
                       max(xs) + width / 2, max(ys) + width / 2)
                mask = stroke_mask(polys, size, viewport, width)
                fill = stroke
                opacity = float(attr(head, 'stroke-opacity',
                                     attr(head, 'opacity', '1')) or 1)
            else:
                box = (min(xs), min(ys), max(xs), max(ys))
                mask = polygon_mask(polys, size, viewport, 'evenodd' in head)
            left, top = round(box[0] * size / viewport), round(box[1] * size / viewport)

        if fill.startswith('url('):
            kind, geometry, stops = defs[fill[5:-1]]
            tile = paint(stops, kind, geometry, box, size, viewport)
        else:
            rgb = colour(fill)
            if rgb is None:
                continue
            tile = Image.new('RGB', mask.size, rgb)

        if opacity < 1:
            mask = mask.point(lambda value: round(value * opacity))
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        if fill.startswith('url('):
            layer.paste(tile, (left, top))
        else:
            layer.paste(tile, (0, 0))
        layer.putalpha(mask)
        canvas = Image.alpha_composite(canvas, layer)

    return canvas


if __name__ == '__main__':
    source = sys.argv[1]
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 192
    out = pathlib.Path(source).with_suffix('').with_name(pathlib.Path(source).stem + f'-{size}.png')
    art = render(source, size)
    flat = Image.new('RGB', art.size, (255, 255, 255))
    flat.paste(art, (0, 0), art)
    flat.save(out)
    print('wrote', out, f'{size}x{size}')
