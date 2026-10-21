"""Print the header of every sheet builder so they can be compared side by side.

A sheet panel is a `@Builder` whose name ends in `Sheet`, `sheet`, `Panel` or
`panel`; the reference app gives each one a title and nothing else in the header,
so anything else that turns up here is a leftover control.
"""
import pathlib
import re

ROOTS = ['entry/src/main/ets/pages', 'entry/src/main/ets/view']

BUILDER = re.compile(r'^\s*(?:private\s+)?(?:@Builder\s+)?(\w+)\s*\(\s*\)\s*\{\s*$')
NAME = re.compile(r'(Sheet|sheet|Panel|panel)\s*$')


def main() -> int:
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).glob('*.ets')):
            lines = path.read_text(encoding='utf-8').split('\n')
            for index, line in enumerate(lines):
                if not line.strip().startswith('@Builder'):
                    continue
                match = BUILDER.match(lines[index + 1]) if index + 1 < len(lines) else None
                if match is None or not NAME.search(match.group(1)):
                    continue
                name = match.group(1)
                body = []
                for follow in lines[index + 2:index + 14]:
                    if follow.strip():
                        body.append(follow.rstrip())
                    if len(body) >= 5:
                        break
                print(f'--- {path.as_posix()}:{index + 2} {name}')
                for entry in body:
                    print(f'    {entry.strip()}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
