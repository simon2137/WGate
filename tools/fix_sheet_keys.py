"""Make the sheets' ForEach keys depend on the current selection.

`ForEach` only re-runs its item generator when the array or a key changes, so a
row whose `Selected` label or title colour comes from page state keeps the look
it was built with. Folding the selection into the key forces the two affected
items (the old one and the new one) to be rebuilt.
"""
import pathlib

EDITS = [
    ('entry/src/main/ets/pages/Monitoring.ets',
     "      }, (ms: number) => ms.toString())",
     "      }, (ms: number) => `${ms}-${this.interval === ms}`)"),
    ('entry/src/main/ets/pages/TunnelRecovery.ets',
     "      }, (seconds: number) => seconds.toString())",
     "      }, (seconds: number) => `${seconds}-${this.delay === seconds}`)"),
    ('entry/src/main/ets/pages/Home.ets',
     "      }, (name: string) => name)",
     "      }, (name: string) => `${name}-${this.themeName === name}`)"),
    ('entry/src/main/ets/pages/Home.ets',
     "      }, (tunnel: WgTunnel) => tunnel.id)",
     "      }, (tunnel: WgTunnel) => `${tunnel.id}-${this.preferredId === tunnel.id}`)"),
]


def main() -> int:
    for name, old, new in EDITS:
        path = pathlib.Path(name)
        text = path.read_text(encoding='utf-8')
        if old not in text:
            print('MISS', name, old.strip())
            continue
        path.write_text(text.replace(old, new, 1), encoding='utf-8')
        print('ok  ', name, '->', new.strip())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
