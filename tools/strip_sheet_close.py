"""Drop the "Close" affordance from every sheet header.

The reference app dismisses a bottom sheet by swiping it down or tapping the
scrim, never with a control in the header, so the sheets here carry a title only.
The pattern is always the same: one statement (`Text(Tr.t('Close'))` or
`Button(Tr.t('Close'))`) followed by its chained attributes, which sit one level
deeper. Everything deeper than the statement's indentation belongs to it and goes
with it.

The close *icon* is deliberately not matched: at TunnelsView the same glyph is
the "leave selection mode" button in the list header, which has to stay.

Usage: python tools/strip_sheet_close.py [--dry-run]
"""
import argparse
import pathlib
import re
import sys

FILES = [
    'entry/src/main/ets/pages/Home.ets',
    'entry/src/main/ets/pages/Index.ets',
    'entry/src/main/ets/pages/Monitoring.ets',
    'entry/src/main/ets/pages/TunnelConfig.ets',
    'entry/src/main/ets/pages/TunnelRecovery.ets',
    'entry/src/main/ets/view/TunnelsView.ets',
]

HEADS = (
    re.compile(r"^\s*Text\(Tr\.t\('Close'\)\)\s*$"),
    re.compile(r"^\s*Button\(Tr\.t\('Close'\)\)\s*$"),
)


def indent(line: str) -> int:
    return len(line) - len(line.lstrip(' '))


def strip(text: str) -> tuple[str, int]:
    lines = text.split('\n')
    kept = []
    removed = 0
    index = 0
    while index < len(lines):
        line = lines[index]
        if any(head.match(line) for head in HEADS):
            base = indent(line)
            index += 1
            # Chained attributes and their bodies are deeper than the statement.
            while index < len(lines) and (lines[index].strip() == '' or indent(lines[index]) > base):
                index += 1
            removed += 1
            continue
        kept.append(line)
        index += 1
    return '\n'.join(kept), removed


def main(dry_run: bool) -> int:
    total = 0
    for name in FILES:
        path = pathlib.Path(name)
        original = path.read_text(encoding='utf-8')
        updated, removed = strip(original)
        total += removed
        print(f'{name}: {removed} close control(s)')
        if not dry_run and removed:
            path.write_text(updated, encoding='utf-8')
    print(('would remove' if dry_run else 'removed'), total, 'in total')
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    sys.exit(main(parser.parse_args().dry_run))
