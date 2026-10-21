"""Report rows that render without a leading icon.

The reference app puts `leading = { Icon(...) }` on most settings rows, so a
`SurfaceRow` without `icon:`/`dotColor:` is the visual gap the user sees.
"""
import pathlib
import re

ROOT = pathlib.Path('entry/src/main/ets')
rows_total = 0
missing = []

for path in sorted(ROOT.rglob('*.ets')):
    if 'i18n' in path.parts:
        continue
    text = path.read_text(encoding='utf-8')
    for match in re.finditer(r'SurfaceRow\(\{(.*?)\n(\s*)\}\)', text, re.S):
        body = match.group(1)
        rows_total += 1
        if 'icon:' in body or 'dotColor:' in body:
            continue
        title = re.search(r"title:\s*(?:`([^`]*)`|Tr\.t\('([^']*)'\)|'([^']*)')", body)
        name = next((group for group in title.groups() if group), '?') if title else '?'
        line = text[:match.start()].count('\n') + 1
        missing.append(f'{path.relative_to(ROOT)}:{line}: {name[:48]}')

print(f'{rows_total} rows, {len(missing)} without a leading icon')
print('\n'.join(missing))
