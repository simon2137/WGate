"""List user-visible English literals that do not go through `Tr.t`."""

import pathlib
import re

ROOT = pathlib.Path('entry/src/main/ets')
PATTERNS = re.compile(
    r"(?:title|description|label|text|placeholder|message|note)\s*:\s*(?:`|')([^`']{3,})")
hits = []
for path in sorted(ROOT.rglob('*.ets')):
    if 'i18n' in path.parts:
        continue
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if 'Tr.t(' in line or 'Tr.tf(' in line:
            continue
        for match in PATTERNS.finditer(line):
            value = match.group(1).strip()
            if not re.search(r'[A-Za-z]{3}', value):
                continue
            if re.fullmatch(r'[\w.%/-]+', value):
                continue
            hits.append(f'{path.as_posix()}:{number}: {value[:90]}')

out = pathlib.Path('build/literal_audit.txt')
out.write_text('\n'.join(hits), encoding='utf-8')
print(len(hits), 'candidate(s)')
