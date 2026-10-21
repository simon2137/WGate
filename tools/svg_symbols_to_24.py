"""Rewrite a Material Symbols path (960x960, y in [-960, 0]) onto the 24x24 grid.

The Symbols sets draw on a 960-unit canvas whose origin sits at the top-left of
the glyph box, i.e. y runs from -960 to 0. ArkUI's SVG subset is happiest with a
plain `viewBox="0 0 24 24"`, so instead of wrapping the glyph in
`<g transform=...>` this script bakes the mapping (x/40, (y+960)/40) into the
path data itself. Handles M L H V C S Q T A Z in both absolute and relative
form; arcs keep their radii split per axis, which is exact for uniform scales.

Usage: python tools/svg_symbols_to_24.py "<path d>"   (prints the 24-grid path)
"""
import re
import sys

ARITY = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7, 'Z': 0}
NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
TOKEN = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)')

SCALE = 1.0 / 40.0   # 960 -> 24
Y_OFFSET = 960.0     # the Symbols canvas starts at y = -960


def fmt(value: float) -> str:
    text = f'{value:.3f}'.rstrip('0').rstrip('.')
    return '0' if text in ('', '-0') else text


def convert(path: str, scale: float = SCALE, y_offset: float = Y_OFFSET) -> str:
    tokens = []
    for command, number in TOKEN.findall(path):
        tokens.append(command if command else float(number))

    out = []
    index = 0
    current = 'M'
    while index < len(tokens):
        token = tokens[index]
        if isinstance(token, str):
            current = token
            index += 1
            out.append(current)
            if current.upper() == 'Z':
                continue
        else:
            # An implicit repeat of the previous command needs its own separator,
            # otherwise "l124-248 44 88" collapses into "-6.21.1".
            out.append(' ')
        relative = current.islower()
        arity = ARITY[current.upper()]
        args = tokens[index:index + arity]
        index += arity

        converted = []
        for position, value in enumerate(args):
            upper = current.upper()
            if upper == 'A':
                # rx ry rotation large-arc sweep x y
                if position in (0, 1):
                    converted.append(fmt(value * scale))
                elif position in (2, 3, 4):
                    converted.append(fmt(value))
                elif position == 5:  # x
                    converted.append(fmt(value * scale if relative else value * scale))
                else:  # y
                    converted.append(fmt(value * scale if relative
                                         else value * scale + y_offset * scale))
            elif upper == 'H':
                converted.append(fmt(value * scale))
            elif upper == 'V':
                converted.append(fmt(value * scale if relative
                                     else value * scale + y_offset * scale))
            else:
                is_y = position % 2 == 1
                if relative:
                    converted.append(fmt(value * scale))
                elif is_y:
                    converted.append(fmt(value * scale + y_offset * scale))
                else:
                    converted.append(fmt(value * scale))
        out.append(' '.join(converted))
    return ''.join(out).replace('Z', 'Z ').strip()


if __name__ == '__main__':
    # Second argument is the y offset in source units: 960 for the Symbols sets
    # (whose y runs from -960 to 0), 0 for Android vector drawables at 960x960.
    offset = float(sys.argv[2]) if len(sys.argv) > 2 else Y_OFFSET
    print(convert(sys.argv[1], y_offset=offset))
