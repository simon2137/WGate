"""Make every sheet dismiss the same way, and survive being dismissed that way.

With the header "Close" control gone, a sheet is dismissed by dragging it down or
tapping the scrim. Two consequences have to hold for every sheet:

* `showClose: false` — the platform must not add its own close button, otherwise
  the look depends on defaults rather than on what the app asked for;
* `dragBar: true` — the handle is now the only visible hint that the sheet moves;
* an `onDisappear` that clears the open flag — a one-way binding (`this.sheet`)
  does not learn about a gesture dismissal by itself, so without this the sheet
  could never be opened a second time.

`$$` two-way bindings already track dismissal and are left alone.
"""
import pathlib

FIXES = [
    ('entry/src/main/ets/pages/DnsSettings.ets',
     """    .bindSheet(this.sheet, this.editSheet(), {
      height: SheetSize.MEDIUM,
      backgroundColor: Palette.BACKGROUND
    })""",
     """    .bindSheet(this.sheet, this.editSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })"""),
    ('entry/src/main/ets/pages/Monitoring.ets',
     """    .bindSheet(this.sheet, this.intervalSheet(), {
      height: SheetSize.MEDIUM,
      showClose: false,
      backgroundColor: Palette.BACKGROUND
    })""",
     """    .bindSheet(this.sheet, this.intervalSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })"""),
    ('entry/src/main/ets/pages/TunnelGlobals.ets',
     """    .bindSheet(this.sheet, this.configSheet(), {
      height: SheetSize.MEDIUM,
      backgroundColor: Palette.BACKGROUND
    })""",
     """    .bindSheet(this.sheet, this.configSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })"""),
    ('entry/src/main/ets/pages/TunnelRecovery.ets',
     """    .bindSheet(this.sheet, this.delaySheet(), {
      height: SheetSize.MEDIUM,
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })""",
     """    .bindSheet(this.sheet, this.delaySheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })"""),
    ('entry/src/main/ets/pages/Index.ets',
     """    .bindSheet($$this.sheetOpen, this.sheetContent(), {
      height: SheetSize.LARGE,
      backgroundColor: '#101B27',
      dragBar: true,""",
     """    .bindSheet($$this.sheetOpen, this.sheetContent(), {
      height: SheetSize.LARGE,
      backgroundColor: '#101B27',
      dragBar: true,
      showClose: false,"""),
    ('entry/src/main/ets/view/TunnelsView.ets',
     """    .bindSheet(this.sheet !== SHEET_NONE, this.sheetBody(), {
      height: SheetSize.MEDIUM,
      showClose: false,
      backgroundColor: Palette.BACKGROUND
    })""",
     """    .bindSheet(this.sheet !== SHEET_NONE, this.sheetBody(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = SHEET_NONE;
      }
    })"""),
]


def main() -> int:
    for name, old, new in FIXES:
        path = pathlib.Path(name)
        text = path.read_text(encoding='utf-8')
        if old not in text:
            print('MISS', name)
            continue
        path.write_text(text.replace(old, new, 1), encoding='utf-8')
        print('ok  ', name)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
