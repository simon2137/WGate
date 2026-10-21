"""Pin every sheet to the bottom type so it always comes with a scrim.

On a 2in1 device (PC mode) and on a tablet in a free window, `bindSheet` defaults
to `SheetType.POPUP`, a floating window with no dimming behind it - the panel
appears to hang over an undimmed page. `SheetType.BOTTOM` is what phones get by
default and it always paints the mask. The option is a no-op on a phone.

Idempotent: a file that already names `preferType` is left alone.
"""
import pathlib
import re

ROOT = pathlib.Path('entry/src/main/ets')

SHEETS = [
    'pages/DnsSettings.ets',
    'pages/Home.ets',
    'pages/Index.ets',
    'pages/Monitoring.ets',
    'pages/TunnelConfig.ets',
    'pages/TunnelGlobals.ets',
    'pages/TunnelRecovery.ets',
    'view/TunnelsView.ets',
]

for rel in SHEETS:
    path = ROOT / rel
    text = path.read_text(encoding='utf-8')
    if 'preferType' in text:
        print(f'skip {rel} (already pinned)')
        continue
    lines = text.split('\n')
    target = None
    for i, line in enumerate(lines):
        if 'dragBar: true,' in line:
            target = i
            break
    if target is None:
        raise SystemExit(f'{rel}: no dragBar line to anchor on')
    indent = re.match(r'\s*', lines[target]).group(0)
    lines.insert(target + 1, f'{indent}preferType: SheetType.BOTTOM,')
    path.write_text('\n'.join(lines), encoding='utf-8')
    print(f'pinned {rel}')
