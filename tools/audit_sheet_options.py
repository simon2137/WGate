"""Report the dismissal options of every `bindSheet` call side by side.

Three options decide whether a sheet behaves like the reference app's bottom
sheets, and only one of them is obvious:

* `dragBar: true` — the handle is the visible hint that a sheet can be dragged;
* `showClose: false` — no platform close button, so the look does not depend on a
  default that may change between releases;
* `onDisappear` — a one-way binding (`this.sheet`) never learns about a gesture
  dismissal, so without it the sheet cannot be opened a second time. `$$this.x`
  bindings track it by themselves.
"""
import pathlib

FILES = [
    'entry/src/main/ets/pages/DnsSettings.ets',
    'entry/src/main/ets/pages/Home.ets',
    'entry/src/main/ets/pages/Index.ets',
    'entry/src/main/ets/pages/Monitoring.ets',
    'entry/src/main/ets/pages/TunnelConfig.ets',
    'entry/src/main/ets/pages/TunnelGlobals.ets',
    'entry/src/main/ets/pages/TunnelRecovery.ets',
    'entry/src/main/ets/view/TunnelsView.ets',
]


def main() -> int:
    problems = 0
    for name in FILES:
        text = pathlib.Path(name).read_text(encoding='utf-8')
        block = text[text.index('bindSheet('):][:400]
        binding = block.split(',')[0]
        two_way = '$$' in binding
        drag = 'dragBar: true' in block
        close = 'showClose: false' in block
        disappear = 'onDisappear' in block or two_way
        if not (drag and close and disappear):
            problems += 1
        print(f"{pathlib.Path(name).name:<22}"
              f"{'dragBar' if drag else 'MISSING dragBar':<22}"
              f"{'showClose' if close else 'MISSING showClose':<26}"
              f"{'onDisappear' if disappear else 'MISSING onDisappear'}")
    print('sheets with a problem:', problems)
    return 1 if problems else 0


if __name__ == '__main__':
    raise SystemExit(main())
