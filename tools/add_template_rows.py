"""Insert the `%1$s` label templates the tunnel row uses.

The reference writes these labels with their punctuation inside the string
(`peer: %1$s`, `handshake: %1$s`, `via %1$s`, `uptime: %1$s`), so the row
composes them with `Tr.tf` instead of gluing a colon on in code.

The script is idempotent and also repairs its own earlier output: a row whose
key looks like one of these templates but is not exactly one of them (for
example `peer: %1` with the `$s` lost to a shell) is dropped before the
canonical rows go in.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'entry' / 'src' / 'main' / 'ets' / 'i18n' / 'Catalog.ets'
RES = ROOT / '_ref_android' / 'app' / 'src' / 'main' / 'res'

SEP_ROW = '\u0001'
SEP_COL = '\u0002'

# English label as the code writes it -> the reference string that carries it.
ROWS = {
    'peer: %1$s': 'peer_template',
    'handshake: %1$s': 'handshake_template',
    'via %1$s': 'via_entry',
    'uptime: %1$s': 'uptime_template',
}

LANGUAGES = {'in': 'id'}
STALE = re.compile(r'^(?:peer|handshake|via|uptime): %1(?!\$s)')


def qualifiers() -> list[str]:
    text = CATALOG.read_text(encoding='utf-8')
    return re.findall(r"\n    \['([a-zA-Z_]+)', '", text)


def locale_for(dirname: str) -> str | None:
    parts = dirname.split('-')[1:]
    if not parts:
        return None
    language = LANGUAGES.get(parts[0], parts[0])
    region = ''
    for part in parts[1:]:
        if part.startswith('r') and len(part) == 3:
            region = part[1:]
    if region:
        return f'{language}_{region}'
    for known in qualifiers():
        if known.split('_')[0] == language:
            return known
    return None


def android_value(path: pathlib.Path, name: str) -> str | None:
    hit = re.search(rf'<string name="{name}">(.*?)</string>',
                    path.read_text(encoding='utf-8'), re.S)
    if hit is None:
        return None
    value = hit.group(1)
    for pair in (("\\'", "'"), ('\\"', '"'), ('\\n', ' '), ('&amp;', '&'),
                 ('&lt;', '<'), ('&gt;', '>'), ('&quot;', '"'), ('\\@', '@')):
        value = value.replace(pair[0], pair[1])
    return value.strip() or None


def escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'")


def main() -> int:
    wanted: dict[str, dict[str, str]] = {}
    for english, resource in ROWS.items():
        wanted[english] = {}
        for directory in sorted(RES.iterdir()):
            if not directory.is_dir() or not directory.name.startswith('values'):
                continue
            locale = locale_for(directory.name)
            if locale is None:
                continue
            value = android_value(directory / 'strings.xml', resource)
            if value is not None:
                wanted[english][locale] = value

    text = CATALOG.read_text(encoding='utf-8')
    repaired = 0
    inserted = 0

    out_lines: list[str] = []
    for line in text.split('\n'):
        stripped = line.strip()
        if not (stripped.startswith("['") and "', '" in stripped and stripped.endswith("'],")):
            out_lines.append(line)
            continue
        locale = stripped[2:stripped.index("'", 2)]
        head = stripped.index("', '") + 4
        rows = stripped[head:stripped.rindex("']")].split(SEP_ROW)
        kept: list[str] = []
        for row in rows:
            key = row.split(SEP_COL)[0]
            if STALE.match(key):
                repaired += 1
                continue
            kept.append(row)
        for english in wanted:
            if any(r.split(SEP_COL)[0] == english for r in kept):
                continue
            value = wanted[english].get(locale)
            if value is None:
                continue
            kept.append(f'{english}{SEP_COL}{escape(value)}')
            inserted += 1
        prefix = line[:len(line) - len(line.lstrip())]
        out_lines.append(f"{prefix}['{locale}', '{SEP_ROW.join(kept)}'],")

    CATALOG.write_text('\n'.join(out_lines), encoding='utf-8')
    print(f'{repaired} malformed row(s) removed, {inserted} row(s) inserted '
          f'({len(wanted)} templates)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
