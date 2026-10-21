"""Add one row to every locale in the generated string catalogue.

The catalogue is generated from the reference app's `values-*/strings.xml`, but
the generator itself is not kept in this tree, so this patcher adds the rows it
is told about directly:

    python tools/add_catalog_row.py "Active Network" active_network

The reference wording carries its own punctuation (`活跃网络：`, `Active Network: `),
so the trailing colon and spaces are stripped: the Kotlin source puts the string
and the value together, while the ArkTS code writes `<label>: <value>` itself.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'entry' / 'src' / 'main' / 'ets' / 'i18n' / 'Catalog.ets'
RES = ROOT / '_ref_android' / 'app' / 'src' / 'main' / 'res'

SEP_ROW = '\u0001'
SEP_COL = '\u0002'

# Android resource qualifier -> the qualifier the catalogue uses.
LANGUAGES = {
    'in': 'id',
}


def qualifiers() -> list[str]:
    """The locale qualifiers present in the catalogue, in file order."""
    text = CATALOG.read_text(encoding='utf-8')
    return re.findall(r"\n    \['([a-zA-Z_]+)', '", text)


def locale_for(dirname: str) -> str | None:
    """`values-zh-rCN` -> `zh_CN`, `values-in` -> `id_ID`."""
    parts = dirname.split('-')[1:]
    if not parts:
        # `values` is the English source: `Tr.t` already returns the literal.
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
    text = path.read_text(encoding='utf-8')
    hit = re.search(rf'<string name="{name}">(.*?)</string>', text, re.S)
    if hit is None:
        return None
    value = hit.group(1)
    value = value.replace('\\\'', "'").replace('\\"', '"').replace('\\n', ' ')
    value = value.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    value = value.replace('&quot;', '"').replace('\\@', '@').replace('\\?', '?')
    value = value.strip()
    while value and value[-1] in ':：:﹕ ':
        value = value[:-1].rstrip()
    return value or None


def escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    english, resource = argv[1], argv[2]

    wanted: dict[str, str] = {}
    for directory in sorted(RES.iterdir()):
        if not directory.is_dir() or not directory.name.startswith('values'):
            continue
        locale = locale_for(directory.name)
        if locale is None:
            continue
        value = android_value(directory / 'strings.xml', resource)
        if value is not None:
            wanted[locale] = value

    text = CATALOG.read_text(encoding='utf-8')
    added = 0
    for locale, value in wanted.items():
        marker = f"\n    ['{locale}', '"
        at = text.find(marker)
        if at < 0:
            print(f'{locale}: not in the catalogue, skipped')
            continue
        end = text.find("'],", at)
        if end < 0:
            print(f'{locale}: unterminated payload, skipped')
            continue
        if (english + SEP_COL) in text[at:end]:
            continue
        # The payload's last row is not always terminated; without this the new
        # row would merge into the previous translation instead of standing alone.
        prefix = '' if text[at:end].endswith(SEP_ROW) else SEP_ROW
        row = f'{prefix}{english}{SEP_COL}{escape(value)}{SEP_ROW}'
        text = text[:end] + row + text[end:]
        added += 1

    if added:
        text = text.replace(
            '// Regenerate with build/gen_catalog.py; do not edit by hand.',
            '// Regenerate with build/gen_catalog.py; add single rows with\n'
            '// tools/add_catalog_row.py <English> <android_string_name>.')
        CATALOG.write_text(text, encoding='utf-8')
    print(f'{added} locale(s) updated, {len(wanted)} translation(s) found')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
