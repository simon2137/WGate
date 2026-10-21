"""Repair rows that `add_catalog_row.py` appended without a leading separator.

The payload's last row was not terminated with the row separator, so the first
inserted row merged into the previous translation ("…一样。Active Network<col>
活跃网络"). This script puts a separator in front of every row that lacks one,
which makes it a standalone row again.
"""
import pathlib
import re

CATALOG = pathlib.Path('entry/src/main/ets/i18n/Catalog.ets')
SEP_ROW = '\u0001'
SEP_COL = '\u0002'
KEYS = ['Active Network', 'Seconds']

text = CATALOG.read_text(encoding='utf-8')
fixed = 0
for locale in re.findall(r"\n    \['([a-zA-Z_]+)', '", text):
    marker = f"\n    ['{locale}', '"
    at = text.find(marker) + len(marker)
    end = text.find("'],", at)
    payload = text[at:end]
    rebuilt = []
    for index, row in enumerate(payload.split(SEP_ROW)):
        rebuilt.append(row)
    # Walk the payload and give every key row a separator in front of it.
    for key in KEYS:
        needle = key + SEP_COL
        while True:
            hit = payload.find(needle)
            if hit < 0:
                break
            if hit > 0 and payload[hit - 1] != SEP_ROW:
                payload = payload[:hit] + SEP_ROW + payload[hit:]
                fixed += 1
                continue
            break
    if payload != text[at:end]:
        text = text[:at] + payload + text[end:]

CATALOG.write_text(text, encoding='utf-8')
print(f'{fixed} row(s) separated')
