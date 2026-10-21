"""Assemble THIRD-PARTY-NOTICES.md from the texts that actually ship.

The texts are copied out of the files in this tree (the upstream Android
project's LICENSE, the Monocypher header) or downloaded verbatim from their
canonical locations (OFL, Apache-2.0), so nothing here is retyped by hand.
Download the two web texts first:

    curl -o build/ofl-inter.txt https://raw.githubusercontent.com/rsms/inter/master/LICENSE.txt
    curl -o build/apache-2.0.txt  https://www.apache.org/licenses/LICENSE-2.0.txt

Then run from the repository root:  python tools/make_notices.py
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
OUT = ROOT / 'THIRD-PARTY-NOTICES.md'

mit = (ROOT / '_ref_android' / 'LICENSE').read_text(encoding='utf-8').strip()

mono_src = (ROOT / 'entry/src/main/cpp/wg/third_party/monocypher.c').read_text(encoding='utf-8')
end = mono_src.index('OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.')
mono_lines = []
for line in mono_src[:end].splitlines():
    text = line[3:] if line.startswith('// ') else line[2:] if line.startswith('//') else line
    mono_lines.append(text.rstrip())
while mono_lines and not mono_lines[0].strip():
    mono_lines.pop(0)
mono = '\n'.join(mono_lines)
mono = mono[mono.index('This file is dual-licensed.'):]

ofl = (BUILD / 'ofl-inter.txt').read_text(encoding='utf-8').strip()
apache = (BUILD / 'apache-2.0.txt').read_text(encoding='utf-8').strip()

zig = """MIT License

Copyright (c) Zig contributors

Zig is used as the C compiler for the native core (libwgcore.so) while the
package is built. It is not redistributed inside the package."""

lines = [
    '# Third-party notices for WGate',
    '',
    'WGate itself is licensed under the GNU General Public License, version 3 or',
    'later; the full text is in `LICENSE`. This file carries the notices of the',
    'works WGate is built from, ports or redistributes.',
    '',
    '---',
    '',
    '## WG Tunnel - the Android app this port started from',
    '',
    'WGate ports the interface, the wording and the interaction flows of WG Tunnel',
    '(`com.zaneschepke.wireguardautotunnel`) by Zane Schepke. The Android sources are',
    'not redistributed in this repository or in the package, but the port is a',
    'derivative of that work, so its notice is carried here and shown in the app',
    'under Support -> Licences.',
    '',
    '```',
    mit,
    '```',
    '',
    '---',
    '',
    '## Monocypher (git snapshot, `wg/third_party/monocypher.c`)',
    '',
    'X25519 and the ChaCha20-Poly1305 IETF construction compiled into',
    '`libwgcore.so` come from Monocypher, dual-licensed BSD-2-Clause or CC0-1.0',
    '(this build relies on the BSD-2-Clause form):',
    '',
    '```',
    mono,
    '```',
    '',
    '---',
    '',
    '## Inter 4.0',
    '',
    'The typeface bundled as `entry/src/main/resources/rawfile/inter.ttf`:',
    '',
    '```',
    ofl,
    '```',
    '',
    '---',
    '',
    '## Material Symbols',
    '',
    'The icons in `entry/src/main/resources/base/media` are drawn from Google',
    'Material Symbols (Apache-2.0); the paths are re-projected to the 24x24 grid',
    'this project uses.',
    '',
    '```',
    apache,
    '```',
    '',
    '---',
    '',
    '## Zig',
    '',
    '```',
    zig,
    '```',
    '',
    '---',
    '',
    '## HarmonyOS SDK and ArkUI',
    '',
    'The package links against the HarmonyOS SDK (API 26, Huawei). The SDK is not',
    'redistributed; its use is governed by the Huawei SDK licence accepted when the',
    'SDK was installed.',
    '',
    '---',
    '',
    '## Algorithms with no separate code notice',
    '',
    'The WireGuard handshake, the AmneziaWG obfuscation parameters, BLAKE2s (RFC',
    '7693) and the WireGuard KDF are implemented in `entry/src/main/cpp/wg` as part',
    'of WGate itself, from the published specifications, and are covered by the GPL',
    'text in `LICENSE`.',
    '',
]

OUT.write_text('\n'.join(lines), encoding='utf-8')
print('{0}: {1} B'.format(OUT.name, OUT.stat().st_size))
