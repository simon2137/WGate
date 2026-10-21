"""List catalogue keys that a rewrite lost or gained for one locale."""
import pathlib
import sys

SEP_ROW = '\u0001'
SEP_COL = '\u0002'


def rows(path: pathlib.Path, locale: str) -> list[str]:
    for line in path.read_text(encoding='utf-8').splitlines():
        stripped = line.strip()
        if not (stripped.startswith("['") and "', '" in stripped):
            continue
        if stripped[2:stripped.index("'", 2)] != locale:
            continue
        head = stripped.index("', '") + 4
        payload = stripped[head:stripped.rindex("']")]
        return [r for r in payload.split(SEP_ROW) if r]
    return []


before = pathlib.Path(sys.argv[1])
after = pathlib.Path(sys.argv[2])
locale = sys.argv[3]
old = {r.split(SEP_COL)[0]: r for r in rows(before, locale)}
new = {r.split(SEP_COL)[0]: r for r in rows(after, locale)}
print(f'{locale}: before {len(old)} keys, after {len(new)} keys')
for key in sorted(set(old) - set(new)):
    print(f'  lost: {key!r}')
for key in sorted(set(new) - set(old)):
    print(f'  gained: {key!r} -> {new[key].split(SEP_COL)[1][:40]!r}')
