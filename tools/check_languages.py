"""Print the language picker's entries and how a few stored values fold.

Reads the ArkTS sources as text so the check runs without the device: the list is
a literal in `pages/Language.ets`, the folding rule in `i18n/Locales.ets`.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGUAGE = ROOT / 'entry/src/main/ets/pages/Language.ets'
LOCALES = ROOT / 'entry/src/main/ets/i18n/Locales.ets'

OPTION = re.compile(r"\{ value: '([^']+)', title: '([^']+)', note: '([^']+)' \}")


def picker_rows():
    text = LANGUAGE.read_text(encoding='utf-8')
    block = text.split('const LOCALES: LocaleOption[] = [')[1].split('];')[0]
    return OPTION.findall(block)


def fold(stored):
    """Mirror of `offeredLocale`."""
    if stored in ('zh_CN', 'zh', 'zh-CN', 'zh-Hans'):
        return 'zh_CN'
    if stored in ('zh_TW', 'zh-HK', 'zh-Hant', 'zh-TW'):
        return 'zh_TW'
    return 'en'


def main():
    rows = picker_rows()
    print(f'picker offers {len(rows)}:')
    for value, title, note in rows:
        print(f'  {value:6} {title:8} {note}')

    offered = [value for value, _, _ in rows]
    source = LOCALES.read_text(encoding='utf-8')
    match = re.search(r"export const OFFERED: string\[\] = \[([^\]]+)\]", source)
    declared = [part.strip().strip("'") for part in match.group(1).split(',')]
    assert declared == offered, f'OFFERED {declared} != picker {offered}'
    print('OFFERED matches the picker')

    for stored in ['en', 'zh_CN', 'zh_TW', 'zh', 'zh-CN', 'zh-Hans', 'zh-HK',
                   'zh-Hant', 'system', '', 'de_DE', 'ja-JP', 'fr_FR']:
        folded = fold(stored)
        assert folded in offered, f'{stored} folded to {folded}, not offered'
        print(f'  {stored or "<empty>":10} -> {folded}')
    print('every stored value folds onto an offered interface')


if __name__ == '__main__':
    main()
