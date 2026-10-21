"""Print the template rows as ASCII escapes, so the console cannot mangle them."""
import pathlib

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'
SEP_COL = '\u0002'
KEYS = ('peer: %1$s', 'handshake: %1$s', 'via %1$s')

for line in CATALOG.read_text(encoding='utf-8').splitlines():
    stripped = line.strip()
    if not stripped.startswith("['"):
        continue
    locale = stripped[2:stripped.index("'", 2)]
    if locale not in ('zh_CN', 'zh_TW'):
        continue
    head = stripped.index("', '") + 4
    for row in stripped[head:stripped.rindex("']")].split(SEP_ROW):
        key = row.split(SEP_COL)[0]
        if key in KEYS and SEP_COL in row:
            print(f'{locale:6} | {key:16} -> {ascii(row.split(SEP_COL)[1])}')
