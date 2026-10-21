"""Check every catalogue payload: rows start at a separator and keys translate.

Two kinds of key are checked:

* the ones copied from the reference (`add_catalog_row.py`), hardcoded here;
* the ones this build authored (`add_catalog_text.py`), read from that module so
  the English text and the code cannot drift apart.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from add_catalog_text import AUTHORED  # noqa: E402

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'
SEP_COL = '\u0002'
COPIED_KEYS = ['Active Network', 'Seconds', 'Selected', 'Preferred tunnel']

text = CATALOG.read_text(encoding='utf-8')
bad: list[str] = []


def payload_of(locale: str) -> str | None:
    marker = f"\n    ['{locale}', '"
    at = text.find(marker)
    if at < 0:
        return None
    return text[at + len(marker):text.find("'],", at)]


keys = COPIED_KEYS + list(AUTHORED)
for locale in re.findall(r"\n    \['([a-zA-Z_]+)', '", text):
    payload = payload_of(locale)
    if payload is None:
        continue
    for key in keys:
        needle = key + SEP_COL
        position = payload.find(needle)
        if position > 0 and payload[position - 1] != SEP_ROW:
            bad.append(f'{locale}: {key} glued to the previous row')
    # A key must only appear as the start of a row, never inside a translation.
    for chunk in payload.split(SEP_ROW):
        cut = chunk.find(SEP_COL)
        if cut < 0:
            continue
        english = chunk[:cut]
        for key in keys:
            if key in english and english != key:
                bad.append(f'{locale}: {key} inside "{english[:40]}"')

# Authored rows have to resolve in every locale they claim to translate.
for english, translations in AUTHORED.items():
    for locale, expected in translations.items():
        payload = payload_of(locale)
        if payload is None:
            bad.append(f'{locale}: no payload, cannot carry "{english}"')
            continue
        for chunk in payload.split(SEP_ROW):
            cut = chunk.find(SEP_COL)
            if cut > 0 and chunk[:cut] == english:
                if chunk[cut + 1:] != expected:
                    bad.append(f'{locale}: "{english}" is "{chunk[cut + 1:]}", '
                               f'expected "{expected}"')
                break
        else:
            bad.append(f'{locale}: "{english}" missing')

print('\n'.join(bad) if bad else 'catalogue clean')
sys.exit(1 if bad else 0)
