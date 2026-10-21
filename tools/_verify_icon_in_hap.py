"""Prove the built HAP carries the new icon, not just the source tree."""
import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HAP = ROOT / 'entry/build/default/outputs/default/entry-default-unsigned.hap'
SOURCES = [ROOT / 'AppScope/resources/base/media/app_icon.png',
           ROOT / 'entry/src/main/resources/base/media/app_icon.png']


def digest(data):
    return hashlib.sha256(data).hexdigest()[:16]


def main():
    if not HAP.exists():
        raise SystemExit(f'missing {HAP}')
    want = {p: digest(p.read_bytes()) for p in SOURCES}
    for path, sha in want.items():
        print(f'source {path.relative_to(ROOT)}: {sha}')
    hits = 0
    with zipfile.ZipFile(HAP) as hap:
        for info in hap.infolist():
            if info.filename.endswith('.png') and 'icon' in info.filename.lower():
                sha = digest(hap.read(info))
                mark = ''
                for path, expected in want.items():
                    if sha == expected:
                        mark = f'  <-- matches {path.relative_to(ROOT)}'
                        hits += 1
                print(f'hap    {info.filename}: {info.file_size} B {sha}{mark}')
    print('OK' if hits else 'NO MATCH')


if __name__ == '__main__':
    main()
