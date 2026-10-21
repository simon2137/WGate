"""Compare per-locale row counts of two catalogue snapshots."""
import pathlib
import sys

SEP_ROW = '\u0001'


def counts(path: pathlib.Path) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        stripped = line.strip()
        if not (stripped.startswith("['") and "', '" in stripped):
            continue
        locale = stripped[2:stripped.index("'", 2)]
        head = stripped.index("', '") + 4
        payload = stripped[head:stripped.rindex("']")]
        out[locale] = len(payload.split(SEP_ROW))
    return out


before = counts(pathlib.Path(sys.argv[1]))
after = counts(pathlib.Path(sys.argv[2]))
for locale in sorted(set(before) | set(after)):
    delta = after.get(locale, 0) - before.get(locale, 0)
    flag = '' if delta >= 0 else '  <-- LOST ROWS'
    print(f'{locale:8} {before.get(locale, 0):4} -> {after.get(locale, 0):4}  ({delta:+d}){flag}')
