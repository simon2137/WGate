"""Route every sheet's dismissal through one handler.

For each `bindSheet` host this adds the import of
`components/SheetGestures` and one `onWillDismiss:` line next to the existing
`showClose: false`, so a tap on the mask, a drag down and Back all end in
`sheetWillDismiss(name)` - which logs which gesture fired and closes the panel.

Idempotent: a file that already names `sheetWillDismiss` is left alone.
"""
import pathlib
import re

ROOT = pathlib.Path('entry/src/main/ets')

# file -> (label shown in the log, relative import path)
SHEETS = {
    'pages/DnsSettings.ets': 'dns edit',
    'pages/Home.ets': 'home',
    'pages/Index.ets': 'index',
    'pages/Monitoring.ets': 'monitoring',
    'pages/TunnelConfig.ets': 'tunnel menu',
    'pages/TunnelGlobals.ets': 'tunnel globals',
    'pages/TunnelRecovery.ets': 'recovery',
    'view/TunnelsView.ets': 'tunnels',
}

for rel, label in SHEETS.items():
    path = ROOT / rel
    text = path.read_text(encoding='utf-8')
    if 'sheetWillDismiss' in text:
        print(f'skip {rel} (already wired)')
        continue
    lines = text.split('\n')

    # 1. imports: after the last `import ... from '...';` line
    last_import = max(i for i, line in enumerate(lines) if line.startswith('import '))
    lines.insert(last_import + 1, "import { sheetWillDismiss } from '../components/SheetGestures';")

    # 2. the option object: after the `showClose: false,` that belongs to a sheet
    target = None
    for i, line in enumerate(lines):
        if 'showClose: false,' in line:
            target = i
            break
    if target is None:
        raise SystemExit(f'{rel}: no showClose: false line to anchor on')
    indent = re.match(r'\s*', lines[target]).group(0)
    lines.insert(target + 1, f"{indent}onWillDismiss: sheetWillDismiss('{label}'),")

    path.write_text('\n'.join(lines), encoding='utf-8')
    print(f'wired {rel} as "{label}"')
