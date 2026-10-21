"""Overwrite one row's translation in one locale of the i18n catalogue.

`add_catalog_row.py` inserts rows copied verbatim from the reference and
`add_catalog_text.py` inserts rows this build authored; neither can change a row
that already exists. A row whose reference wording reads badly in this UI (for
example "Allow the tunnel to use mobile data" where the surrounding rows are
plain noun labels) is retranslated here instead, so the override is a recorded
decision rather than an edit to the generated payload by hand.

Usage:  python tools/set_catalog_row.py <locale> "<English key>" "<translation>"
"""

import pathlib
import sys

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'
SEP_COL = '\u0002'


def payload_bounds(text: str, locale: str) -> tuple[int, int] | None:
    marker = f"\n    ['{locale}', '"
    start = text.find(marker)
    if start < 0:
        return None
    start += len(marker)
    end = text.find("'],", start)
    if end < 0:
        return None
    return start, end


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__.strip().splitlines()[-1])
        return 2
    locale, key, translation = argv[1], argv[2], argv[3]
    if SEP_ROW in translation or SEP_COL in translation:
        print('translation must not contain the row or column separator')
        return 2

    text = CATALOG.read_text(encoding='utf-8')
    bounds = payload_bounds(text, locale)
    if bounds is None:
        print(f'no payload for {locale}')
        return 1
    start, end = bounds
    rows = text[start:end].split(SEP_ROW)

    for index, chunk in enumerate(rows):
        cut = chunk.find(SEP_COL)
        if cut > 0 and chunk[:cut] == key:
            current = chunk[cut + 1:]
            if current == translation:
                print(f'{locale}: "{key}" already "{translation}"')
                return 0
            rows[index] = key + SEP_COL + translation
            CATALOG.write_text(
                text[:start] + SEP_ROW.join(rows) + text[end:], encoding='utf-8')
            print(f'{locale}: "{key}" {current} -> {translation}')
            return 0

    print(f'{locale}: no row for "{key}"')
    return 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
