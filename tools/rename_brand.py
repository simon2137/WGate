"""Renames the product in the generated string catalogue.

`Catalog.ets` is generated from the reference project's `strings.xml`, and a
number of its rows mention that project by name ("Thank you for using WG
Tunnel!").  This build is called WGate, so the brand is replaced in both the
English key and every translation -- the key *is* the English sentence, so the
two have to move together or the lookup stops matching.

The list runs oldest first: the catalogue may still hold any of the earlier
names depending on when it was last regenerated, and each step is skipped when
the old name is not there.

Idempotent: run it after regenerating the catalogue, and again on a catalogue
that has already been renamed and it does nothing.

    python tools/rename_brand.py
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'entry/src/main/ets/i18n/Catalog.ets'

RENAMES = [
    ('WG Tunnel', 'Wedge'),
    ('Wedge', 'WGate'),
]


def main() -> None:
    text = CATALOG.read_text(encoding='utf-8')
    for old, new in RENAMES:
        count = text.count(old)
        if count == 0:
            print(f'catalogue has no {old!r}')
            continue
        text = text.replace(old, new)
        print(f'replaced {count} occurrence(s) of {old!r} with {new!r}')
    CATALOG.write_text(text, encoding='utf-8')
    print(f'wrote {CATALOG.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
