"""Delete catalogue rows by exact English key, across every locale.

Used to retract a key that was inserted with the wrong wording, so the catalogue
goes back to what the code asks for. Idempotent: keys that are already gone are
simply skipped.
"""

import argparse
import pathlib
import re

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('keys', nargs='+')
    parser.add_argument('--dry-run', action='store_true')
    arguments = parser.parse_args()
    keys = set(arguments.keys)

    text = CATALOG.read_text(encoding='utf-8')
    removed = 0
    for locale in re.findall(r"\n    \['([a-zA-Z_]+)', '", text):
        marker = f"\n    ['{locale}', '"
        at = text.find(marker) + len(marker)
        end = text.find("'],", at)
        rows = text[at:end].split(SEP_ROW)
        kept = [row for row in rows if row.split('\u0002', 1)[0] not in keys]
        gone = len(rows) - len(kept)
        if gone:
            removed += gone
            text = text[:at] + SEP_ROW.join(kept) + text[end:]

    print(f'{removed} row(s) {"would be " if arguments.dry_run else ""}removed')
    if not arguments.dry_run and removed:
        CATALOG.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
