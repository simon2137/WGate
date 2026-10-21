"""Lists rows that both carry a switch and open another page.

The auto-tunnel screen found the hard way that a switch hides the fact that the
row itself is a door: with only a switch on the right, the page behind the row is
never discovered. This scan finds the same shape anywhere else in the app.
"""
import re
from pathlib import Path

ROOT = Path('entry/src/main/ets')
NAV = ('router.pushUrl', 'startAbility', 'openLink')


def main() -> None:
    found = 0
    for path in sorted(ROOT.rglob('*.ets')):
        src = path.read_text(encoding='utf-8')
        for match in re.finditer(r'SurfaceRow\(\{(.*?)\n\s*\}\)', src, re.S):
            body = match.group(1)
            if 'hasSwitch: true' not in body:
                continue
            # Only the row body opening a page needs the extra signal. A switch
            # that opens one on its own (App lock) is a single target, not two.
            # The call is looked for after `onTap:` rather than inside a parsed
            # brace block: the row text is cut at the first nested `})`.
            tap = body.find('onTap:')
            if tap < 0 or not any(call in body[tap:] for call in NAV):
                continue
            line = src[:match.start()].count('\n') + 1
            title = re.search(r'title: ([^\n]*)', body)
            chevron = 'chevron: true' in body
            found += 1
            mark = 'ok' if chevron else 'MISSING'
            print(f'{mark:8} {path}:{line}  {title.group(1).strip() if title else "?"}')
    if found == 0:
        print('no row both toggles and navigates')


if __name__ == '__main__':
    main()
