"""Report which strings the interface asks for but each offered locale lacks.

The catalogue carries rows for every locale the reference ships, but only the
offered ones are reachable. A key that is missing from an offered locale falls
back to English at runtime, which is exactly what a Chinese interface should not
do, so this prints the gap per locale.

`Tr.t('a ' + 'b')` reaches the catalogue as one joined key, so the argument is
read as a whole and its literals are joined before comparing.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path('entry/src/main/ets')
CATALOG = ROOT / 'i18n/Catalog.ets'
SEP_ROW = '\u0001'
SEP_COL = '\u0002'
OFFERED = ['en', 'zh_CN', 'zh_TW']


def payload(locale: str) -> dict[str, str]:
    text = CATALOG.read_text(encoding='utf-8')
    marker = f"\n    ['{locale}', '"
    at = text.find(marker)
    if at < 0:
        return {}
    body = text[at + len(marker):text.find("'],", at)]
    rows: dict[str, str] = {}
    for chunk in body.split(SEP_ROW):
        cut = chunk.find(SEP_COL)
        if cut > 0:
            rows[chunk[:cut]] = chunk[cut + 1:]
    return rows


def argument_at(source: str, open_paren: int) -> str:
    """Text between `(` and its matching `)`, ignoring parens inside literals."""
    depth = 0
    quote = ''
    index = open_paren
    while index < len(source):
        character = source[index]
        if quote:
            if character == '\\':
                index += 2
                continue
            if character == quote:
                quote = ''
        elif character in '"\'`':
            quote = character
        elif character == '(':
            depth += 1
        elif character == ')':
            depth -= 1
            if depth == 0:
                return source[open_paren + 1:index]
        index += 1
    return ''


def literal_of(argument: str) -> str:
    """Concatenate the string literals in an argument, in order."""
    pieces: list[str] = []
    for match in re.finditer(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'', argument):
        piece = match.group(1) if match.group(1) is not None else match.group(2)
        pieces.append(piece.replace("\\'", "'").replace('\\"', '"'))
    return ''.join(pieces)


def used_keys() -> set[str]:
    keys: set[str] = set()
    for path in ROOT.rglob('*.ets'):
        source = path.read_text(encoding='utf-8')
        for match in re.finditer(r'Tr\.t[f]?\(', source):
            key = literal_of(argument_at(source, match.end() - 1))
            if key:
                keys.add(key)
    return keys


used = used_keys()
print(f'{len(used)} string(s) requested by the source')
worst = 0
for locale in OFFERED:
    if locale == 'en':
        continue
    rows = payload(locale)
    missing = sorted(k for k in used if k not in rows)
    worst = max(worst, len(missing))
    print(f'{locale}: {len(rows)} row(s), {len(missing)} request(s) would fall back to English')
    for key in missing[:40]:
        print(f'  - {key}')
    if len(missing) > 40:
        print(f'  … {len(missing) - 40} more')

sys.exit(1 if worst else 0)
