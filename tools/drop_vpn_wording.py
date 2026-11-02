"""Take the word VPN out of everything the interface shows.

The catalogue is a generated table of `english\\u0002translation` rows, so the
English literal is both the key and the shipped English text.  Rewriting a key
means rewriting every place that asks for it; the report at the end lists what
is still left so the call sites can be fixed in the same pass.
"""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'entry/src/main/ets/i18n/Catalog.ets'
REPORT = ROOT / 'build/_vpn_report.txt'

# Ordered: longer strings first, so a short rule cannot eat a long one.
PAIRS = [
    ('What the app and the VPN extension recorded',
     'What the WireGuard extension recorded'),
    ('应用和 VPN 扩展记录的内容', 'WireGuard 扩展记录的内容'),
    ('應用和 VPN 擴充功能記錄的內容', 'WireGuard 擴充功能記錄的內容'),

    ('VPN startup trace', 'WireGuard startup trace'),
    ('VPN 启动记录', 'WireGuard 启动记录'),
    ('VPN 啟動記錄', 'WireGuard 啟動記錄'),

    ('系统 VPN 开关', '系统 WireGuard 开关'),
    ('系統 VPN 開關', '系統 WireGuard 開關'),

    ('INTERNET and the VPN extension for tunnel traffic',
     'INTERNET and the WireGuard extension for tunnel traffic'),
    ('INTERNET 和 VPN 扩展用于隧道流量', 'INTERNET 和 WireGuard 扩展用于隧道流量'),
    ('INTERNET 和 VPN 擴充功能用於通道流量', 'INTERNET 和 WireGuard 擴充功能用於通道流量'),

    ('the VPN extension resolves endpoints', 'the WireGuard extension resolves endpoints'),
    ('VPN 扩展会经由系统解析器', 'WireGuard 扩展会经由系统解析器'),
    ('VPN 擴充功能會透過系統解析器', 'WireGuard 擴充功能會透過系統解析器'),

    ('while the VPN stays up', 'while WireGuard stays up'),
    ('在 VPN 保持连接期间', '在 WireGuard 保持连接期间'),
    ('在 VPN 保持連線期間', '在 WireGuard 保持連線期間'),

    # The Japanese table labels the list "VPNトンネル"; the list is just tunnels.
    ('VPNトンネル', 'トンネル'),
]

# The same word reaching the screen through code rather than through the table:
# error sentences shown in a toast or in the status line, and one trace line the
# Logs page prints verbatim.
# The two labels the user spelled out by hand: no space between the name and the
# Chinese word, so the catalogue and the authored table have to agree on it.
TIGHT = [
    ('WireGuard 扩展记录的内容', 'WireGuard扩展记录的内容'),
    ('WireGuard 擴充功能記錄的內容', 'WireGuard擴充功能記錄的內容'),
    ('WireGuard 启动记录', 'WireGuard启动记录'),
    ('WireGuard 啟動記錄', 'WireGuard啟動記錄'),
]

CODE = [
    ('The system did not confirm the VPN request', 'The system did not confirm the WireGuard request'),
    ('Could not start the VPN (', 'Could not start WireGuard ('),
    ('The VPN service did not start.', 'The WireGuard service did not start.'),
    ('VPN startup failed (', 'WireGuard startup failed ('),
    ('A previous VPN session could not be released',
     'A previous WireGuard session could not be released'),
    ('VPN creation failed (', 'WireGuard creation failed ('),
    ('the system tore the VPN down', 'the system tore the tunnel down'),
]


def main() -> None:
    text = CATALOG.read_text(encoding='utf-8')
    changed = 0
    for old, new in PAIRS + TIGHT:
        count = text.count(old)
        if count:
            text = text.replace(old, new)
            changed += count
    CATALOG.write_text(text, encoding='utf-8')

    code_changed = 0
    authored = ROOT / 'tools/add_catalog_text.py'
    authored_text = authored.read_text(encoding='utf-8')
    authored_updated = authored_text
    for old, new in PAIRS + TIGHT:
        authored_updated = authored_updated.replace(old, new)
    if authored_updated != authored_text:
        code_changed += 1
        authored.write_text(authored_updated, encoding='utf-8')

    for path in sorted(ROOT.glob('entry/src/main/ets/**/*.ets')):
        if path.name == 'Catalog.ets':
            continue
        source = path.read_text(encoding='utf-8')
        updated = source
        for old, new in CODE:
            updated = updated.replace(old, new)
        if updated != source:
            code_changed += sum(source.count(old) for old, _ in CODE)
            path.write_text(updated, encoding='utf-8')

    report = [f'catalogue replacements: {changed}',
              f'code replacements: {code_changed}']
    report.append('')
    report.append('remaining VPN occurrences outside the catalogue:')
    for path in sorted(ROOT.glob('entry/src/main/ets/**/*.ets')):
        if path.name == 'Catalog.ets':
            continue
        for number, line in enumerate(path.read_text(encoding='utf-8').split('\n'), 1):
            if 'VPN' in line or 'vpn' in line.lower() and 'VPN' in line:
                if 'VPN' in line:
                    report.append(f'  {path.relative_to(ROOT)}:{number}: {line.strip()}')
    report.append('')
    report.append('catalogue rows still holding VPN:')
    for row in text.split('\u0001'):
        if 'VPN' in row:
            report.append('  ' + row.replace('\u0002', '  ||  '))
    REPORT.write_text('\n'.join(report), encoding='utf-8')
    print(f'{changed} replacements, report at {REPORT}')


if __name__ == '__main__':
    main()
