"""Print one catalogue row as ASCII escapes (console code page safe)."""

import pathlib
import sys

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'
SEP_COL = '\u0002'


def main(argv):
    locale, key = argv[1], argv[2]
    text = CATALOG.read_text(encoding='utf-8')
    marker = f"\n    ['{locale}', '"
    start = text.find(marker) + len(marker)
    payload = text[start:text.find("'],", start)]
    for chunk in payload.split(SEP_ROW):
        cut = chunk.find(SEP_COL)
        if cut > 0 and chunk[:cut] == key:
            print(f'{locale} {key!r} -> {chunk[cut + 1:].encode("unicode_escape").decode()}')
            return 0
    print(f'{locale}: no row for {key!r}')
    return 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
