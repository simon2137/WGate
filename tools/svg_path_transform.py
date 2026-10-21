"""Bake a uniform affine transform (scale + translate) into SVG path data.

`<g transform>` is untested in ArkUI's SVG subset, so scaled-down artwork has to
be rewritten number by number. Handles M L H V C S Q T A Z in absolute and
relative form: relative coordinates scale but do not translate, flags and the
arc rotation angle are left alone, arc radii scale with the axes.

Usage:
  python tools/svg_path_transform.py --scale 0.31 --tx -12 --ty 4 "<path d>"
"""
import argparse
import re

ARITY = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7, 'Z': 0}
TOKEN = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)')


def fmt(value: float) -> str:
    text = f'{value:.3f}'.rstrip('0').rstrip('.')
    return '0' if text in ('', '-0') else text


def transform(path: str, scale: float = 1.0, tx: float = 0.0, ty: float = 0.0) -> str:
    tokens = []
    for command, number in TOKEN.findall(path):
        tokens.append(command if command else float(number))

    out = []
    index = 0
    current = 'M'
    started = False
    while index < len(tokens):
        token = tokens[index]
        if isinstance(token, str):
            current = token
            index += 1
            # Per the SVG spec a leading `m` is an absolute moveto.
            if not started and current == 'm':
                current = 'M'
            out.append(current)
            if current.upper() == 'Z':
                continue
        else:
            out.append(' ')
        started = True

        relative = current.islower()
        upper = current.upper()
        arity = ARITY[upper]
        args = tokens[index:index + arity]
        index += arity

        converted = []
        for position, value in enumerate(args):
            if upper == 'A':
                if position in (0, 1, 2, 3, 4):
                    # radii scale (rotation and the two flags do not)
                    converted.append(fmt(value * scale) if position in (0, 1) else fmt(value))
                elif position == 5:
                    converted.append(fmt(value * scale if relative else value * scale + tx))
                else:
                    converted.append(fmt(value * scale if relative else value * scale + ty))
            elif upper == 'H':
                converted.append(fmt(value * scale if relative else value * scale + tx))
            elif upper == 'V':
                converted.append(fmt(value * scale if relative else value * scale + ty))
            else:
                is_y = position % 2 == 1
                if relative:
                    converted.append(fmt(value * scale))
                elif is_y:
                    converted.append(fmt(value * scale + ty))
                else:
                    converted.append(fmt(value * scale + tx))
        out.append(' '.join(converted))
    return ''.join(out).replace('Z', 'Z ').strip()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('path')
    parser.add_argument('--scale', type=float, default=1.0)
    parser.add_argument('--tx', type=float, default=0.0)
    parser.add_argument('--ty', type=float, default=0.0)
    arguments = parser.parse_args()
    print(transform(arguments.path, arguments.scale, arguments.tx, arguments.ty))
