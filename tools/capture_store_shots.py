"""Capture the store screenshots from a connected tablet and 2-in-1.

`tools/make_store_shots.py` assembles the five listing frames from raw captures
in `build/store/`; this script takes those captures, so the whole set can be
rebuilt after a change that shows on every screen (the bottom bar's width, for
one). It drives the app the way a person would: tap a tab, tap a row, take a
picture.

The app has to be installed on both devices, and the 2-in-1 window has to be
16:9 — the capture records the window rectangle it measured, and the assembler
crops to it. `uitest` cannot hover a window border, so on an emulator that
resize has to be done with the mouse before running this.

    python tools/capture_store_shots.py                 # both devices, three languages
    python tools/capture_store_shots.py --device tablet
    python tools/capture_store_shots.py --lang en

Writes `build/store/<device>-<frame>.jpeg` for Simplified Chinese and
`build/store/<device>-{en,hant}-<nn>.jpeg` for the other two, which is the
naming `make_store_shots.py` reads, plus `build/store/geometry.json` with the
rectangles the captures were cut from.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / 'build/store'
LAYOUT = STORE / 'layout.json'
SHOT = STORE / 'shot.jpeg'

HDC = Path(r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe')
BUNDLE = 'com.wgate.app'
ABILITY = 'EntryAbility'

# device name -> the serial its emulator comes up on; a real device is found by
# asking hdc for the device type instead.
SERIALS = {'tablet': '127.0.0.1:5557', 'pc': '127.0.0.1:5555'}

# language folder -> (title of its row on the language page, capture suffix)
LANGS = {'zh': ('简体中文', ''), 'zh-Hant': ('繁體中文', '-hant'), 'en': ('English', '-en')}

# the five frames, in listing order
FRAMES = ['01-add', '02-auto', '03-settings', '04-appearance', '05-theme']

# titles the script taps, in every language the app can be showing when it
# starts: a run that switches to English begins on whatever the device held.
APPEARANCE = ['外观', '外觀', 'Appearance']
THEME = ['主题', '主題', 'Display theme']
LANGUAGE = ['语言', '語言', 'Language']

BOUNDS = re.compile(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]')


class Device:
    def __init__(self, serial: str):
        self.serial = serial

    def run(self, *args: str) -> str:
        done = subprocess.run([str(HDC), '-t', self.serial, *args],
                              capture_output=True, timeout=180)
        return (done.stdout + done.stderr).decode('utf-8', 'replace')

    def shell(self, command: str) -> str:
        return self.run('shell', command)

    def start(self) -> None:
        self.shell(f'aa force-stop {BUNDLE}')
        time.sleep(0.5)
        self.shell(f'aa start -b {BUNDLE} -a {ABILITY}')
        time.sleep(4)

    def tap(self, spot: tuple) -> None:
        self.shell(f'uitest uiInput click {int(spot[0])} {int(spot[1])}')
        time.sleep(1.2)

    def back(self) -> None:
        self.shell('uitest uiInput keyEvent Back')
        time.sleep(1.0)

    def tree(self) -> dict:
        self.shell('uitest dumpLayout -p /data/local/tmp/layout.json')
        self.run('file', 'recv', '/data/local/tmp/layout.json', str(LAYOUT))
        return json.loads(LAYOUT.read_text(encoding='utf-8'))

    def capture(self, path: Path) -> None:
        self.shell('snapshot_display -f /data/local/tmp/shot.jpeg')
        self.run('file', 'recv', '/data/local/tmp/shot.jpeg', str(SHOT))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(SHOT.read_bytes())


def nodes(tree: dict):
    """Every node of a `uitest dumpLayout` document, depth first."""
    stack = [tree]
    while stack:
        node = stack.pop()
        if 'attributes' in node:
            yield node
        stack.extend(node.get('children') or [])


def box(node: dict) -> tuple:
    found = BOUNDS.search(node['attributes']['bounds'])
    return int(found.group(1)), int(found.group(2)), int(found.group(3)), int(found.group(4))


def centre(rect: tuple) -> tuple:
    left, top, right, bottom = rect
    return (left + right) / 2, (top + bottom) / 2


def area(rect: tuple) -> int:
    return (rect[2] - rect[0]) * (rect[3] - rect[1])


def app_window(tree: dict) -> tuple:
    """The app's own window, which is the screen when it runs full screen."""
    roots = [box(node) for node in nodes(tree) if node['attributes'].get('type') == 'root']
    if not roots:
        raise SystemExit('no window in the layout')
    return min(roots, key=area)


def find(tree: dict, texts) -> tuple:
    """Centre of the first node whose label is one of `texts`."""
    labels = {text.strip() for text in texts}
    for node in nodes(tree):
        if (node['attributes'].get('text') or '').strip() in labels:
            return centre(box(node))
    raise SystemExit(f'none of {sorted(labels)} is on screen')


def nav_tabs(tree: dict) -> list:
    """The four tab centres of the bottom bar, left to right."""
    bottom = app_window(tree)[3]
    tabs = []
    for node in nodes(tree):
        attributes = node['attributes']
        if attributes.get('type') != 'Stack' or attributes.get('clickable') != 'true':
            continue
        rect = box(node)
        if bottom - 300 < rect[1] < rect[3] <= bottom:
            tabs.append((rect[0], centre(rect)))
    tabs.sort()
    if len(tabs) != 4:
        raise SystemExit(f'expected four tabs in the bottom bar, found {len(tabs)}')
    return [spot for _, spot in tabs]


def open_appearance(device: Device, tree: dict) -> dict:
    """Settings tab -> Appearance page; returns that page's tree."""
    device.tap(nav_tabs(tree)[2])
    tree = device.tree()
    device.tap(find(tree, APPEARANCE))
    return device.tree()


def set_language(device: Device, lang: str) -> None:
    """Pick `lang` on the language page, then come back up in that language."""
    device.start()
    tree = open_appearance(device, device.tree())
    device.tap(find(tree, LANGUAGE))
    device.tap(find(device.tree(), [LANGS[lang][0]]))
    time.sleep(2)


def target(device_name: str, lang: str, frame: str) -> Path:
    if lang == 'zh':
        return STORE / f'{device_name}-{frame}.jpeg'
    return STORE / f'{device_name}{LANGS[lang][1]}-{frame[:2]}.jpeg'


def shoot(device: Device, device_name: str, lang: str) -> tuple:
    """The five frames in `lang`; returns the window rectangle they came from."""
    device.start()
    tree = device.tree()
    window = app_window(tree)

    # 01: the list, as the app opens. The tab is tapped first so a device that
    # came back on another tab still yields the same frame.
    device.tap(nav_tabs(tree)[0])
    device.capture(target(device_name, lang, FRAMES[0]))

    # 02 and 03: the two other tabs.
    for index, frame in ((1, FRAMES[1]), (2, FRAMES[2])):
        device.tap(nav_tabs(device.tree())[index])
        device.capture(target(device_name, lang, frame))

    # 04: the appearance page, 05: the display theme page under it.
    tree = open_appearance(device, device.tree())
    device.capture(target(device_name, lang, FRAMES[3]))
    device.tap(find(tree, THEME))
    device.capture(target(device_name, lang, FRAMES[4]))
    return window


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', choices=sorted(SERIALS), action='append',
                        help='capture one device only (default: both)')
    parser.add_argument('--lang', choices=sorted(LANGS), action='append',
                        help='capture one language only (default: all three)')
    args = parser.parse_args()

    STORE.mkdir(parents=True, exist_ok=True)
    geometry_path = STORE / 'geometry.json'
    geometry = json.loads(geometry_path.read_text(encoding='utf-8')) if geometry_path.exists() else {}

    for device_name in args.device or sorted(SERIALS):
        device = Device(SERIALS[device_name])
        print(f'--- {device_name} ({device.serial})', flush=True)
        for lang in args.lang or sorted(LANGS):
            set_language(device, lang)
            geometry[device_name] = list(shoot(device, device_name, lang))
            print(f'  {lang}: five frames, window {geometry[device_name]}', flush=True)

    geometry_path.write_text(json.dumps(geometry, indent=2) + '\n', encoding='utf-8')
    print(f'wrote {geometry_path}')


if __name__ == '__main__':
    sys.exit(main())
