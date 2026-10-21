"""Fill the Traditional Chinese rows from the Simplified ones.

The catalogue ships rows for every locale the reference has, but only three are
offered. Simplified Chinese covers nearly every string the interface asks for,
Traditional covers about half, so the rest of a Traditional interface would show
English. This converts the missing rows with OpenCC's `s2twp` profile (character
mapping plus Taiwan vocabulary) and appends them to the `zh_TW` payload.

Idempotent: a second run reports `0 row(s) added`.
"""

import argparse
import pathlib
import re

import opencc

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'
SEP_COL = '\u0002'
SOURCE = 'zh_CN'
TARGET = 'zh_TW'


def payload_span(text: str, locale: str) -> tuple[int, int]:
    marker = f"\n    ['{locale}', '"
    at = text.find(marker)
    if at < 0:
        raise SystemExit(f'{locale} is not in {CATALOG}')
    start = at + len(marker)
    return start, text.find("'],", start)


def rows_of(payload: str) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for chunk in payload.split(SEP_ROW):
        cut = chunk.find(SEP_COL)
        if cut > 0:
            rows.append((chunk[:cut], chunk[cut + 1:]))
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    arguments = parser.parse_args()

    text = CATALOG.read_text(encoding='utf-8')
    source = rows_of(text[slice(*payload_span(text, SOURCE))])
    start, end = payload_span(text, TARGET)
    payload = text[start:end]
    translated = dict(rows_of(payload))

    converter = opencc.OpenCC('s2twp')
    missing = [(key, value) for key, value in source if key not in translated]
    if not missing:
        print(f'0 row(s) added, {TARGET} already covers {SOURCE}')
        return

    prefix = '' if payload.endswith(SEP_ROW) else SEP_ROW
    added = SEP_ROW.join(
        f'{key}{SEP_COL}{converter.convert(value)}' for key, value in missing)
    print(f'{len(missing)} row(s) would be added to {TARGET}')
    if arguments.dry_run:
        for key, value in missing[:10]:
            print(f'  {key} -> {converter.convert(value)}')
        return

    CATALOG.write_text(text[:start] + payload + prefix + added + text[end:],
                       encoding='utf-8')
    print(f'{len(missing)} row(s) added to {TARGET}')


if __name__ == '__main__':
    main()
