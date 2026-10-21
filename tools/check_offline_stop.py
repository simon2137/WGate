"""Mirror of the "Stop on no network" decision in `AutoTunnel.evaluate()`.

`entry/src/main/ets/service/AutoTunnel.ets` runs the same three guards, but on a
device whose network cannot be unplugged from a shell (`ifconfig eth0 down`
answers "Permission denied", and there is no airplane toggle a third-party app
may flip), the only reliable way to keep the branch honest is a table like the
one `check_wildcards.py` uses for the SSID glob.
"""

# The slice of evaluate() this script mirrors:
#
#   const offline: boolean = !AutoTunnel.hasNetwork();
#   if (offline && SettingsStore.stopOnNoInternet()) {
#     if (started !== null) { stop it; Diag.write(`... the device has no network`); }
#   }
#
# Keep these in step with that file if the rule ever grows another guard.


def stops(offline: bool, switch_on: bool, running: bool) -> bool:
    """Whether evaluate() tears the running tunnel down."""
    if not offline:
        return False
    if not switch_on:
        return False
    return running


CASES = [
    # offline, switch, running, expected
    (True, True, True, True, 'no network and the switch is on: stop'),
    (True, True, False, False, 'nothing to stop'),
    (True, False, True, False, 'switch off: the tunnel stays up'),
    (False, True, True, False, 'still online: leave it alone'),
    (False, False, True, False, 'still online, switch off'),
    (False, True, False, False, 'still online, nothing running'),
]


def main() -> int:
    failures = 0
    for offline, switch_on, running, want, note in CASES:
        got = stops(offline, switch_on, running)
        if got != want:
            failures += 1
            print(f'FAIL offline={offline} switch={switch_on} running={running}: '
                  f'got {got}, want {want} ({note})')
        else:
            print(f'ok   offline={offline!s:<5} switch={switch_on!s:<5} '
                  f'running={running!s:<5} -> {got!s:<5} {note}')
    print(f'{len(CASES)} checks, {failures} failure(s)')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
