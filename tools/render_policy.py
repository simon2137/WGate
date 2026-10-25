"""Render the published policy: desktop light, desktop English, dark, and phone width.

Two facts about headless Edge shape this script:

* it lays the page out about 40 CSS px wider than the PNG it writes, so a
  `--window-size=390` shot crops the right edge and makes a healthy page look broken;
  phone width is therefore checked through a 390 px iframe instead;
* `--force-dark-mode` applies Chrome's own auto-darkening, which is not what a reader
  sees, so the dark view rewrites the media query to `@media all` in a temporary copy.

Run:  python tools/render_policy.py   → build/policy-*.png
"""

import http.server
import re
import socketserver
import subprocess
import threading
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EDGE = Path(r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
SRC = ROOT / 'docs/privacy.html'
OUT = ROOT / 'build'
PORT = 8766

PHONE_PROBE = '''<!DOCTYPE html><html><head><meta charset="utf-8">
<style>body{margin:0;background:#8a8f96;display:flex;gap:24px;padding:24px;
font:12px system-ui}iframe{border:0;background:#fff}</style></head><body>
<iframe src="/docs/privacy.html?lang=zh" width="390" height="1500"></iframe>
<iframe src="/docs/privacy.html?lang=en" width="390" height="1500"></iframe>
</body></html>'''


def serve() -> socketserver.TCPServer:
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(ROOT))
    httpd = socketserver.TCPServer(('127.0.0.1', PORT), handler)
    httpd.RequestHandlerClass.log_message = lambda *a, **k: None
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def shoot(name: str, page: Path, query: str, width: int, height: int) -> Path:
    target = OUT / f'policy-{name}.png'
    subprocess.run([
        str(EDGE), '--headless=new', '--disable-gpu', '--hide-scrollbars',
        f'--user-data-dir={OUT / ("_edge_" + name)}',
        f'--window-size={width},{height}', '--virtual-time-budget=3000',
        f'--screenshot={target}',
        f'http://127.0.0.1:{PORT}/{page.relative_to(ROOT).as_posix()}{query}',
    ], check=False, capture_output=True)
    return target


def main() -> None:
    httpd = serve()
    made = []
    try:
        src = SRC.read_text(encoding='utf-8')
        page = ROOT / 'docs/_render.html'
        dark = ROOT / 'docs/_render_dark.html'

        page.write_text(src, encoding='utf-8')
        made.append(shoot('zh', page, '', 900, 2400))
        made.append(shoot('en', page, '?lang=en', 900, 2400))

        dark.write_text(re.sub(r'@media \(prefers-color-scheme: dark\)', '@media all', src),
                        encoding='utf-8')
        made.append(shoot('dark', dark, '?lang=zh-Hant', 900, 2400))

        probe = ROOT / 'docs/_render_phone.html'
        probe.write_text(PHONE_PROBE, encoding='utf-8')
        made.append(shoot('phone', probe, '', 900, 1600))
    finally:
        httpd.shutdown()
        for leftover in ('docs/_render.html', 'docs/_render_dark.html', 'docs/_render_phone.html'):
            (ROOT / leftover).unlink(missing_ok=True)
    for path in made:
        print(path)


if __name__ == '__main__':
    main()
