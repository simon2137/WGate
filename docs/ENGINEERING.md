# WGate for HarmonyOS

> **工程说明（英文，面向要改代码的人）。** 想先了解这个应用是做什么的，看仓库根目录的
> [README](../README.md)。
>
> 文中引用的 `build/...png` 截图、`_ref_android/` 等参考工程只存在于开发机上，仓库里没有；
> 它们是当年核对界面时留下的现场记录，不影响按本文修改代码。

WGate is a native HarmonyOS port of [WG Tunnel](https://github.com/wgtunnel/android): a
WireGuard® / AmneziaWG VPN client whose tunnel is implemented in C, driven
through NAPI from ArkTS, and hosted by a `VpnExtensionAbility`. (The name is
new; the bundle is `com.wgate.app`. Every mention of "WG Tunnel" left in this
file refers to that upstream project, not to this app.)

### The name and the mark

`WGate` is the product name; `WG Tunnel` is the Compose project this port comes
from, and the two must not be confused in the UI or the store listing.
`WireGuard` appears only descriptively ("WireGuard-compatible"), because the
WireGuard trademark policy does not allow it in a product name.

* `app_name` in `AppScope/resources/base/element/string.json`, `vendor` and
  `bundleName` in `AppScope/app.json5`. The bundle name is what the store keys
  an app by: changing it after the first upload makes a new app, and every
  existing install loses its tunnels (the preferences live in the old sandbox).
  It is `com.wgate.app` here, without the word `tunnel`: nothing has been published yet, so the store has not fixed it.
* The old name is also baked into the generated string catalogue, where the
  English sentence *is* the lookup key. `python tools/rename_brand.py` rewrites
  both halves (key and every translation) and is idempotent, so it can be run
  again after regenerating `Catalog.ets` from the reference `strings.xml`.
* The mark is a **doorway**: a wall with an arch cut through it, and a bar of
  light (the theme's aqua `#76BEBD`) lying on the sill. `tools/icon_studio.py`
  draws it on the icon's original plate -- the `#21272A` rounded square, round
  terminals, the same single weight and margins the original artwork used. It is
  not the letter W: at 24 px a W's feet and its second stroke end up 30 px apart,
  less than the stroke is wide, and every letterform tried (faithful re-cut,
  carved slab, hollow outline, italic, plate-scale) either lost its shape or read
  as a different letter. The doorway survives because it is one silhouette with
  one hole in it.
  `python tools/icon_studio.py decide` draws the shortlist -- `sheet` and
  `sheet5`..`sheet9` keep the rounds that produced it -- at 168 / 48 / 24 px, and
  `install <name>` swaps one in.
  `tools/make_app_icon.py` writes the chosen mark to **both** copies,
  `AppScope/.../app_icon.png` (what the launcher shows) and `entry/.../app_icon.png`
  (what `tools/make_tray_icons.py` cuts the tray glyphs out of). Writing only the
  second one leaves the launcher on the old icon, which is exactly what happened
  here once.

```
┌─────────────┐   preferences    ┌────────────────────┐
│  Index.ets  │◀────────────────▶│    TunnelStore     │
│  (ArkUI UI) │                  └────────────────────┘
└──────┬──────┘                            ▲
       │ startVpnExtensionAbility(want)     │ tunnel JSON
       ▼                                    │
┌─────────────────────────────┐   tun fd    │
│    WgVpnExtAbility          │──────┐      │
│  VpnConnection.create()     │      ▼      │
│  protect(udpFd)             │ ┌───────────┴──────────┐
└──────────┬──────────────────┘ │   libwgcore.so       │
           │ unix fd            │  napi_init.cpp       │
           └───────────────────▶│  wg_engine.c (I/O)   │
                                │  wg_proto.c (Noise)  │
                                │  wg_crypto.c         │
                                │  wg_blake2s.c        │
                                │  monocypher 4.0.2    │
                                └──────────────────────┘
```

## Features

| | |
|---|---|
| WireGuard protocol | Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s, handshake, transport, keepalives, cookie replies, replay window (2048 packets) |
| AmneziaWG | `H1–H4` type obfuscation, `Jc` junk datagrams, `S1`/`S2` junk prefixes, `S3` parsed |
| Multiple tunnels | stored in preferences, rename/edit/delete, swipe to delete |
| Multiple peers per tunnel | up to 8 peers, each with its own endpoint, preshared key, `AllowedIPs` and keepalive; IPv4/IPv6 traffic is demultiplexed by longest prefix match |
| Structured editor | form mode (name, addresses, MTU, DNS, keys, per-peer cards, AmneziaWG parameters) or paste mode, switchable both ways |
| Import | paste a `wg-quick` configuration into the editor, pick a `.conf` file through the system picker, receive one from another app, or scan a QR code |
| Export | copy the tunnel back out as `wg-quick` text |
| Import from another app | `Want` parameters `wgquick` (the whole configuration, real or literal `\n` line breaks), `name`, `connect` |
| Key handling | generate key pairs and derive public keys in the native core |
| Always-on resume | the last active tunnel is reconnected when the app restarts |
| Split tunnelling | `ExcludedApps` bundle names bypass the tunnel |
| Live stats | rx/tx bytes, handshake age, peers up, engine state, refreshed once per second |
| Engine log | the native core keeps a ring of handshake/keepalive/socket events, shown in a sheet |
| Endpoint check | resolves the selected tunnel's endpoint and sends one handshake at it, so a tunnel that never comes up can be told apart from a network or DNS problem |
| Status notification | a service notification mirrors tunnel state, interface and transferred bytes, published by the VPN extension so it keeps updating while the app is in the background |
| Quick action | `com.wgtunnel.harmony.action.TOGGLE_TUNNEL` flips the tunnel on/off |
| Desktop tray | on PC / 2-in-1 an icon in the system tray shows the tunnel state, closing the window minimises to the tray instead of ending the app, and the menu offers connect / disconnect, open, quit |
| Roaming | the UDP socket is re-created and re-protected when the network changes |
| QR codes | show a tunnel as a QR code, scan one with the camera, or decode one from a screenshot, so a configuration can move between devices without typing |

## Layout

```
AppScope/                                application manifest and icon
entry/src/main/
  ets/entryability/EntryAbility.ets      UI ability, quick-toggle action, import intents
  ets/pages/Home.ets                     four-tab shell: Tunnels, Auto-tunnel, Settings, Support
  ets/pages/TunnelSettings.ets           per-tunnel settings (configuration, general, network, automation)
  ets/pages/TunnelConfig.ets             wg-quick text, copy action and QR code
  ets/pages/Appearance.ets               display language, theme picker, notifications entry
  ets/pages/Notifications.ets            live-update switches for the status notification
  ets/pages/TunnelGlobals.ets            global split switch and interface defaults
  ets/pages/DnsSettings.ets              system resolvers and the default tunnel DNS
  ets/pages/Logs.ets                     startup trace and engine ring, refresh and clear
  ets/pages/Security.ets                 privacy mode and the app-lock PIN
  ets/pages/TunnelRecovery.ets           seamless recovery switch and bounce delay
  ets/pages/TunnelScripting.ets          pre/post script switch and what cannot run
  ets/pages/Backup.ets                   export tunnels to a file and restore them
  ets/pages/Scan.ets                     QR scanner page (Scan Kit camera, image decode)
  ets/pages/Index.ets                    previous single-screen UI, kept until parity is complete
  ets/view/TunnelsView.ets               tunnel list: groups, selection mode, group actions, sorting, state dot, statistics
  ets/view/AutoTunnelView.ets            auto-tunnel switch, per-network rows, behaviour rows
  ets/view/SettingsView.ets              settings rows in the reference app's order
  ets/view/SupportView.ets               getting started, licence, version
  ets/components/BottomNav.ets           icon bar drawn with the immersive system material
  ets/components/SurfaceRow.ets          the reference app's row/tile primitive
  ets/theme/Theme.ets                    colours and type scale from the Compose theme
  ets/model/Tunnel.ets                   tunnel/peer model, wg-quick parsing and export
  ets/service/TunnelStore.ets            preferences-backed persistence
  ets/service/SettingsStore.ets          auto-tunnel, backend mode and appearance settings
  ets/service/EngineStatus.ets           status snapshot reading, formatting helpers
  ets/service/VpnControl.ets             start/stop the extension, startup trace inspection
  ets/service/TunnelCommands.ets         the one quick-toggle action shared by shortcut and tray
  ets/service/PcTray.ets                 desktop tray icon, hover text, right-click menu (PC / 2-in-1)
  ets/service/TunnelGuard.ets            restarts the extension when the published snapshot goes silent
  ets/service/KeepAlive.ets              transient background window around a tunnel being up
  ets/service/Notifier.ets               the notification publish/cancel calls
  ets/service/TunnelNotice.ets           what the notification says, and which process publishes it
  ets/util/Async.ets                     promises bounded by a timeout
  ets/util/Diag.ets                      startup trace shared with the extension process
  ets/util/StatusBridge.ets              engine snapshot published by the extension for the UI
  ets/vpnext/WgVpnExtAbility.ets         VPN extension: tun device + engine host
  cpp/napi_init.cpp                      NAPI surface (flat JSON in, JSON status out)
  cpp/wg/wg_engine.c                     I/O thread: tun ↔ UDP, multi-peer demux, timers, queue
  cpp/wg/wg_proto.c                      handshake, transport, AmneziaWG framing
  cpp/wg/wg_crypto.c                     HMAC-BLAKE2s, KDF1/2/3, AEAD wrappers
  cpp/wg/wg_blake2s.c                    BLAKE2s (keyed, 128/256-bit output)
  cpp/wg/wg_json.h                       base64 and flat-JSON helpers for the bridge
  cpp/wg/third_party/monocypher.c        X25519, ChaCha20, Poly1305, XChaCha20
tools/                                   host test harnesses (see below)
```

## Matching the original interface

The app is a port of [WG Tunnel](https://github.com/Zaneschepke/wg-tunnel-compose),
and the interface follows that app's Compose implementation rather than a generic
HarmonyOS layout: the same four tabs in the same order, the same row primitive
(`SurfaceRow`: 16dp sides, 8dp vertical, 42dp minimum height, surface colour,
primary-tinted while selected), the same colours (`BalticSea` background,
`Shark` surface, `Aqua` primary) and the same type scale.

One element is deliberately different: the bottom navigation. Instead of a bar
glued to the bottom edge it is a floating capsule (`entry/src/main/ets/components/BottomNav.ets`):
a 56 vp pill with 28 vp corners, 16 vp side margins and a 16 vp gap to the edge,
drawn with `uiMaterial.ImmersiveMaterial` (API 26, `ImmersiveStyle.THIN`) through
`.systemMaterial()`, so it behaves like the system's own glass surfaces — it
refracts the list scrolling under it. The material is given a light `#26` veil of
the surface colour: a completely opaque tint blocks the filter, which is why the
veil is barely visible now.
`.backgroundBlurStyle(COMPONENT_ULTRA_THICK)` and a soft shadow back the capsule up
on devices that render the material without its blur, and a hairline keeps the edge
visible in both themes. `isImmersiveMaterialSupported()`, `getMaterialInfo().state`
and the material level are written to the diagnostic trace on every launch, which is
how the effect was confirmed here (`nav: immersive supported=true state=0 level=0`).

The moving light is drawn outside the capsule. The platform's `lightEffect` (the
`immersive light` feedback) only shows on hardware that composites the material
with a real GPU pass, and it stayed invisible on this device even with
`interactive: true` and a low-alpha tint, so the API option stays switched on *and*
the app paints its own highlight. That highlight has to live **one level up**:
`entry/src/main/ets/components/BottomNav.ets` reports the pointer through
`onGlow(x, on)`, and `entry/src/main/ets/pages/Home.ets` draws the discs in its own
`Stack`, above the bar. A child of the node that carries `.systemMaterial()` is
composited into the material pass, which washes a 90%-opaque accent disc down to a
grey smudge - that is what three rounds of "make it brighter" were actually
fighting. `.blur()` on that child is worse still: it smears whatever sits behind it,
icons included. The light is therefore a single capsule-sized `radialGradient`
centred on the finger (core `#6676BEBD` at the centre, halo `#2676BEBD` at 42 %,
transparent at the rim, white on the dark palettes) - a solid disc with a hard edge
reads as a pasted layer, light has no edge. It fades out over 260 ms on release,
is clipped to the capsule, and `nav: pointer down on the material` in the trace
confirms the pointer reaches it.

Icons are not Material fonts (HarmonyOS has none); `tools/make_icons.py` draws
the same silhouettes as 24dp SVGs into `resources/base/media`, tinted at runtime
with `Image.fillColor`. A leading icon on a settings row is 24 vp
(`entry/src/main/ets/components/SurfaceRow.ets`), matching the default size of the
reference's Material `Icon`. Most glyphs are hand-written path data; the ones taken
from google/material-design-icons keep their original coordinates, and Material
Symbols glyphs (960-unit canvas, y from -960 to 0) are baked onto the 24 grid by
`tools/svg_symbols_to_24.py <d> [y-offset]` rather than wrapped in a
`<g transform>`. Three helpers keep this honest without a device:
`tools/audit_row_icons.py` lists `SurfaceRow`s that render without a leading icon,
`tools/rasterize_svg.py` rasterises our own SVG subset to PNG (there is no ImageMagick,
Inkscape, rsvg or Chrome on this machine and Edge's headless screenshot drops SVG),
and `tools/icon_strip.py` composes the glyphs into `build/icons_*.png` for review.
The Auto-tunnel network rows carry the reference's own choices rather than
look-alikes: `ic_wifi`, `ic_signal_cellular` and `ic_settings_ethernet` are the
paths of `Icons.Outlined.Wifi`, `Icons.Outlined.SignalCellular4Bar` and
`Icons.Outlined.SettingsEthernet` (fetched out of the `@material-design-icons/svg`
package), and the active-network row uses `ic_globe`, which is the reference's
`res/drawable/globe.xml` rewritten from its 960 viewport onto 24 with a zero y
offset (`tools/svg_symbols_to_24.py "<d>" 0`). The running row swaps
`ic_check_circle` (the reference's `Icons.Outlined.CheckCircle`) for
`ic_info` (`Icons.Outlined.Info`) when auto-tunnel is off; both are drawn as an
even-odd ring plus solid strokes so the result does not depend on sub-path
winding.

The launcher icon is drawn by `tools/icon_studio.py`, not copied: the original
project's artwork (`_ref_android/app/src/main/ic_launcher-playstore.png`, 512x512,
sha256 `7fa3c749…`) is a three-stroke W whose two right-hand strokes end 30 px
apart, so at 24 px they merge — it is kept as the reference the palette, the plate
and the stroke weight come from, and `build/icon-studio/before-after.png` puts the
two side by side at 72 / 48 / 24 px. The installed icon is the doorway described
above, written to both
`AppScope/resources/base/media/app_icon.png` for the application and
`entry/src/main/resources/base/media/app_icon.png` for the ability and the start
window. The plate is still the original `#21272A` and the corners still carry the
reference's radius (112 of 512), baked in, so a launcher that rounds again only
softens it. `build-profile` needs no change: `$media:app_icon` resolves by name,
whichever extension is present.

The colour and preview tools (`tools/rasterize_icon.py`, `tools/icon_contact_sheet.py`,
`tools/icon_variants.py`, `tools/rasterize_svg.py`) are kept because they are how the
row glyphs and any future artwork get reviewed without a device on hand. `tools/wg_emblem.py`
and `tools/svg_path_transform.py` remain as the working recipe for baking an official
SVG mark onto the icon grid — scale and offset have to go into the path data because
`<g transform>` is untested in the platform's SVG subset, and a leading lowercase `m`
is absolute per the spec, not relative.

Tapping a tunnel opens the same settings screen as the original app, with its
four groups in the same order: Configuration (view the wg-quick text, or the same
page with the live counters), General (primary tunnel, entry tunnel), Network
(split tunneling, IPv6, metered) and Automation (DDNS auto update). The three
switches persist in `SettingsStore`; the entries this engine cannot honour say so
instead of silently doing nothing - HarmonyOS has no per-app routing, multihop
needs a second tunnel the engine does not implement, and only IPv4 is handled.

The configuration page shows the exact text that would be imported, with Copy and
a QR code. The built-in `QRCode` component holds at most 512 characters, so long
configurations say so and point at Copy instead of drawing a truncated code.

### Bottom sheets

Every sheet is opened with `bindSheet` and carries a title only: the reference app
dismisses a sheet by dragging it down or tapping the scrim, so no sheet has a
"Close" control in its header. Ten were removed — nine `Text`/`Button` controls
across five files by `tools/strip_sheet_close.py`, plus the icon in `Home`'s shared
`sheetHeader`. The script deliberately matches whole statements only, because the
close *glyph* at `TunnelsView` leaves selection mode and has to stay. Form sheets
keep their own `Save` action, so nothing became unreachable.

Two rules make the row that opened a sheet show the new value as soon as the sheet
writes it, and both are easy to get wrong:

- `SurfaceRow` declares everything it draws as `@Prop`. A plain member is assigned
  once when the child is constructed and is *not* refreshed when the parent
  rebuilds, so a row whose trailing text came from page state (`30s`, the preferred
  tunnel name) kept showing the value it was born with. Callbacks stay plain.
- A `ForEach` only re-runs its item generator when the array or a key changes, so
  the `Selected` label inside a sheet went stale. The keys now fold the selection
  in — `` `${seconds}-${this.delay === seconds}` `` in `TunnelRecovery`, likewise in
  `Monitoring`, `Home` (appearance, preferred tunnel) and `PreferredTunnel` — which
  rebuilds exactly the two affected rows. `TunnelsView` already used the same trick
  with its `epoch`.

Losing the header control is only safe if every sheet can still be dismissed *and*
survives being dismissed that way. `tools/audit_sheet_options.py` checks the three
options on all eight call sites; `tools/audit_sheets.py` prints the header of all
eighteen panels so the titles can be compared in one screen.

All eight hosts also register `onWillDismiss: sheetWillDismiss(name)` from
`components/SheetGestures.ets`. Registering that callback is what takes the default
dismissal away, so the callback has to close the panel itself — it logs
`sheet: <name> dismissed by <outside tap|back|close button>` and calls
`action.dismiss()`. That is the one place a tap on the mask is handled explicitly,
and the log line is how a panel that refuses to leave is diagnosed: if no line
appears, the gesture never reached ArkUI. `tools/add_sheet_dismiss.py` wires a host
idempotently, so a new sheet only needs its file added to the table there.

No sheet is full height any more: `Home` and `Index` asked for `SheetSize.LARGE`,
which left only the status-bar strip as mask, so a tap "outside" had nowhere to land
and those five panels could only be left with Back or a drag. Both now use
`SheetSize.MEDIUM`, like the other six hosts (`TunnelConfig` stays `FIT_CONTENT`
because its menu is three rows). Verified on the Mate 90 Pro emulator, with the log
line as the proof: `t7`/`t8` (recovery, tap above the sheet), `u1`/`u2` (add tunnel
after the height change), `v4`/`v5` (configuration menu) and `v6`/`v7` (tunnel list
menu) all end in `dismissed by outside tap`, and Back logs `dismissed by back`.

Every host also pins `preferType: SheetType.BOTTOM`. Left alone, ArkUI picks the
presentation per device, and on tablet landscape and in PC (2in1) mode the default is
a floating `POPUP` card that draws **no mask at all**: the 2880x1920 tablet build
showed the add-tunnel card hovering over an undimmed tunnel list, and a tap on the
list simply hit the list. `tools/pin_sheet_type.py` puts the line after `dragBar: true`
in all eight hosts. Verified on a `Harmony_Tablet_26` instance (MatePad Pro 13,
HarmonyOS 7.0.0, 2880x1920): with the panel open the page background read
rgb(28,27,32) before the change (identical to no panel) and rgb(22,22,24) after —
that is the scrim; the panel is now full width at the bottom, and a tap at (1400,300)
logs `sheet: home dismissed by outside tap`.

The four selection panels share one shape: a header row (56 vp tall, `TITLE_LARGE`
at `FontWeight.Medium`, `ROW_PAD_H` on both sides) over a `Scroll` of `SurfaceRow`s
whose `trailingText` is `Selected` on the current value. `Tunnel monitoring` used to
build its own rows (52 vp, `TITLE_MEDIUM`, selected label tinted `PRIMARY`), which
read as a different panel next to `Tunnel recovery`; both now use the shared shape,
and the `Scroll` wrapper stops ArkUI from squeezing the rows into the panel height (a
five-row list in a MEDIUM sheet was compressing 48 vp rows down to 37). Numbers print
`500 ms`, `1 second`, `5 seconds`; the singular is the authored key `1 second` because
`Second` is a prefix of `Seconds` and `check_catalog_rows.py` rejects prefix keys.

| Sheet host | Panels | Value shown back on the page |
|---|---|---|
| `pages/Home.ets` | Add tunnel, Tunnel details, Engine log, Appearance, Preferred tunnel | theme, preferred tunnel |
| `pages/Index.ets` | Editor (form and raw), Engine log, Tunnel details, Scan to import | editor title, tunnel list |
| `view/TunnelsView.ets` | Move to group, Group actions, Reorder, Actions | groups, sort mode |
| `pages/DnsSettings.ets` | Default DNS (form, `Save`) | the default resolver row |
| `pages/TunnelGlobals.ets` | Tunnel configuration (form, `Save`) | the MTU / keepalive / DNS row |
| `pages/Monitoring.ets` | Refresh rate | the refresh row |
| `pages/TunnelRecovery.ets` | Seamless recovery delay | the `30s` row |
| `pages/TunnelConfig.ets` | Configuration menu | — |

Four of them (DNS, monitoring, globals, tunnel list) bound the sheet to a one-way
`this.sheet` and had no `onDisappear`, so the "Close" control was the *only* way to
clear that flag: a sheet dismissed by a swipe left it set, and the next tap was a
no-op. They now mirror what `TunnelRecovery` already did, and every call site asks
for `dragBar: true` and `showClose: false` so the handle is the visible hint and no
platform close button can appear regardless of defaults.

The tunnel list follows `TunnelList.kt` too. Holding a row for 400 ms enters
selection mode: the title becomes "N selected", the switches give way to round
check boxes, and the overflow button opens the reference app's actions - select
all, move to group, copy config, ungroup, delete. Groups are headers above their
children with a folder icon, a `1 tunnel` / `2 tunnels` count, an `N active`
counter while a child is up, and a chevron that collapses the group. Group names
live in `SettingsStore` and each tunnel carries its own `group` field, so groups
survive a restart and may exist empty - exactly like the `TunnelGroup` table.

The Settings tab's subpages follow the reference app's screens:

- **Appearance** - Display (language picker, display-theme picker listing the six
  reference themes) and the Notifications entry. `NotificationsScreen.kt`'s five
  switches live on their own page and persist in `SettingsStore`.
- **Tunnel globals** - the global split switch plus one interface configuration
  (MTU, keepalive, DNS). A tunnel whose configuration omits one of those values
  inherits it on import, which is what `ConfigGlobal` does in the reference app.
- **DNS settings** - the resolvers `ConnectionProperties.dnses` reports for the
  active network, read live, and the default DNS a new tunnel starts from.
  HarmonyOS has no equivalent of Android's private-DNS mode, and the page says so
  instead of inventing a row.
- **Local logging** - the startup trace the extension writes through `Diag`, read
  back in place, with Refresh, Export and Clear. The page shows one block now: it
  used to add a second block fed by the native ring buffer from the *app* process,
  which never opens an engine, so that block was permanently empty - and reading
  the module threw inside the button handlers, which is why Refresh and Clear
  looked dead. Export writes the trace to a file the user picks (with a device and
  timestamp header) and records the landed size in the trace, because the picker
  hands back a uri even when a write fails.
- **Security** - screen-recording protection and the app lock. Protection is not
  a flag that is merely remembered: it calls `setWindowPrivacyMode(true)`, so the
  window really is blank in screenshots and recordings (checked on the emulator -
  a capture taken with the switch on comes back black). The PIN is kept as a djb2
  hash in `SettingsStore` rather than as digits.
- **Tunnel recovery** - the seamless-recovery switch and the bounce delay
  (5/15/30/60/120 s). The engine already re-resolves and re-opens its socket on
  its own, so this records the intent the reference app exposes.
- **Tunnel scripting** - the pre/post switch and the explanation. A HarmonyOS VPN
  extension is sandboxed and cannot fork a shell, so the setting and the per-tunnel
  script fields are kept but nothing is executed; the page says that plainly.
- **Backup and restore** - tunnel records are written to a picked file and read
  back. The format is the store's own flat JSON wrapped in an envelope, so the
  backup is readable text, includes the private keys (as the configuration page
  does), and a stray file is rejected instead of half-imported. Each export gets a
  timestamped name because the picker refuses silent overwrites.
  Restoring a `wg-quick` `.conf` goes through `parseWgQuick()`, not through
  `WgTunnel.from()`: the latter only understands the storage shape, so handing it
  raw text used to store a tunnel with no key and no peers. Records that cannot
  connect (no private key, no peer with a public key) are counted and skipped
  rather than added as switches that can only fail, and a restored record with no
  id is given one, because the store keys by id. The picked file is read through
  its descriptor — `readTextSync()` takes a sandbox path and fails with
  `13900002` on a document uri, which is exactly what the restore did before.
  File names use local wall-clock time; `toISOString()` would name them in UTC.

The auto-tunnel tab drives a real watcher: `@kit.NetworkKit` registrations for
`netAvailable`/`netLost`/`netCapabilitiesChange` call `AutoTunnel.evaluate()`,
which reads the SSID through `wifiManager.getLinkedInfo()` (a `system_grant`
permission, so no prompt), compares it with the trusted list and starts or stops
a tunnel accordingly - only tunnels it started itself are stopped again, so a
manually connected tunnel is left alone. Every decision lands in the startup
trace, which is how the wiring is verified on the emulator, whose only network is
Ethernet (`ssid ""`, `trusted false`).

`getLinkedInfo()` needs nothing but `GET_WIFI_INFO` here: a phone that granted
that permission returns the real name (`ssid "Xiaomi_90FA_5G_Game"` in the
trace), so the location grant an Android build needs for the same value is not
asked for on this platform. The name can still be missing for a moment while the
Wi-Fi service reports the association, and the call answers `""` (or
`<unknown ssid>`) instead of failing - so the tab re-reads the name on its 1.5 s
tick instead of keeping what it read when the page appeared, and it says `Wi-Fi`
rather than `No network` whenever the device is joined but the name is missing.
A name that stays missing is written to the trace once per change, with the
error code when the call itself fails, so a device that keeps hiding it says why.

Two behaviour switches sit under the per-network rows, both from the reference's
own strings. **Stop on no network** (`stop_on_no_internet`) tears down the running
tunnel as soon as the device has no physical network left. Two details matter and
both were wrong in the first cut:

- `AutoTunnel.hasNetwork()` must not look at the *default* network. While our own
  VPN is up, the VPN **is** the default network, so `getDefaultNetSync()` keeps
  answering with a handle even after Wi-Fi and mobile data are switched off -
  which is exactly why the switch appeared to do nothing on a phone with a tunnel
  running. The probe walks `connection.getAllNetsSync()` instead and accepts only
  a physical bearer (Wi-Fi, cellular, Ethernet), ignoring `BEARER_VPN`.
- The `netLost` / `netCapabilitiesChange` callbacks can stay silent for the same
  reason (the net set still holds the VPN), so `AutoTunnel.start()` also installs a
  5 s heartbeat that only ever *stops* - a tunnel the user stopped by hand on a
  trusted network is not resurrected. The heartbeat logs
  `auto-tunnel: network present|absent` on the first answer and on every change,
  so a device that keeps the tunnel up says which side of the question it is on.

The rule stops whatever tunnel is running, not just one auto-tunnel started: the
string says "stop the tunnel when the device has no network connection", and a
tunnel with no route is useless either way; the trace line records which case it
was (`started by auto-tunnel` / `started by hand`). `tools/check_offline_stop.py`
mirrors the guards as a six-case table (`6 checks, 0 failure(s)`).

The reference's second behaviour row, **Start on boot** (`restart_at_boot`), is
deliberately absent: HarmonyOS does not let a third-party app subscribe to the boot
broadcast (`RECEIVE_BOOT_COMPLETED` is not in `PermissionDefinitions.json`, and
`StaticSubscriberExtensionAbility` is not exported in the SDK), so the switch could
only promise something the platform does not deliver. The reference also has a
second path for boot (`isRestoreOnBootEnabled`, "start the default tunnel on
boot", disabled while Always-On is on) that has no counterpart here because this
build has no default-tunnel-at-boot UI.


## Build

Requirements: DevEco Studio 6 with the HarmonyOS SDK (API 26), Node.js and
CMake/Ninja bundled with the SDK.

```powershell
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon
```

The HAP is written to `entry/build/default/outputs/default/entry-default-unsigned.hap`.
Configure a signing profile in DevEco Studio before installing on a device —
`VpnExtensionAbility` and the `vpn` extension type require a real signature.

### Permissions

Only `normal` level permissions are requested: `INTERNET`, `GET_NETWORK_INFO`,
`KEEP_BACKGROUND_RUNNING`, `GET_WIFI_INFO`, `PRIVACY_WINDOW` and `CAMERA` (the
QR scanner, granted at first use). No `backgroundModes` is declared: the VPN
extension is kept alive by the system while its tunnel exists, and the UI
process asks for a transient task when it goes away (`service/KeepAlive.ets`).
An earlier revision also asked for `ohos.permission.START_ABILITIES_FROM_BACKGROUND`
from the UI and inside the extension; that permission is `system_basic`
(`toolchains/lib/PermissionDefinitions.json`), so on a retail device the installer
rejects the whole package with *"权限申请失败，请按 ACL 签名指导申请受限权限"* —
the APK never gets a chance to run. Both call sites are in the foreground, so it
is not needed and was removed. Do not add restricted permissions back unless the
signing profile is ACL-enabled on AGC.

The HAP is compiled with `compatibleSdkVersion` 26, so it installs only on
HarmonyOS 6.0 (API 26) or newer.

Two clipboard facts shaped the UI. Writing the clipboard needs no permission, so
**Copy** works. Reading it needs `ohos.permission.READ_PASTEBOARD`, which is
`system_basic` as well, so an app signed the normal way cannot call
`getSystemPasteboard().getData()` — it throws. "Import from clipboard" therefore
explains the restriction inside the sheet and asks the user to long-press the
configuration box and choose Paste, which the system performs on a user gesture.

Installing needs an explicit VPN consent: the first
`startVpnExtensionAbility()` call raises the system dialog. The extension runs as
a dedicated VPN service process, which is what keeps the tunnel alive when the
UI goes to the background.

### A tunnel that dies while the app is away

"Connected" has to survive the phone deciding to reclaim background work, and on
a retail build it does not always: the extension can be torn down a few minutes
after the app leaves the screen, and the tun — with the status bar key — goes with
it. Two things are in place for that.

`service/TunnelGuard.ets` runs in the UI process and reads the snapshot the
extension publishes every two seconds. When a tunnel is still wanted (the desired
id is set, which "stop" clears) but the snapshot stops arriving for three checks
in a row, it asks the system for the extension again: `onCreate` rebuilds the tun
and the engine, so the tunnel comes back by itself. It waits for silence rather
than one missed snapshot, spaces its attempts a minute apart, and stands down for
ten minutes after five failures instead of fighting the system for the battery.
Every decision it takes is written to the trace.

The guard needs the UI process to be schedulable, so `EntryAbility.onBackground`
asks for the transient task whenever a tunnel is up or wanted — not only when the
auto-tunnel rule is on. That window is three minutes (one on a low battery), and
after it expires the platform freezes the process: from then on a dead tunnel
stays dead until the app is opened again, where `restoreDesired()` reconnects it.
There is no legal long-running task for a third-party VPN on this platform, so
that limit is stated rather than papered over.

The trace is what makes the next report decidable: `app: background`,
`app: foreground`, `extension onCreate`, `extension onDestroy` and the guard's
lines share one file, so a drop can be attributed to the app leaving, the system
tearing the extension down, or the extension dying without `onDestroy` at all.

The third layer is the one that survives that freeze. The platform keeps the
*extension* process alive for as long as its tun device exists, so the
extension's own watchdog is where recovery has to happen once the UI is frozen:
`vpnext/WgVpnExtAbility.ets` watches the handshake counter, and when a tunnel has
sat in `connecting`/`retry` for ninety seconds without one — the engine gives up
after eighteen attempts and then only tries once every thirty seconds — it calls
`wgcore.forceHandshake()` and records `vpn extension: no handshake for Ns` in the
trace. A tunnel that is up is never touched; the engine already rekeys it.

A start request normally carries the whole configuration, but the system can
start the extension again on its own with an empty want. `wantWithDesiredTunnel()`
therefore falls back to `TunnelStore.desiredId()` — the durable record the app
writes when the user connects — and logs
`extension onCreate had no tunnel, restoring <name> from the desired state` when
it has to. What the user wanted, and not a callback the system may skip, decides
whether a tunnel comes back.

### What the platform actually requires

The rules below come from the OpenHarmony VPN guide, the continuous-task and
transient-task documents, and Huawei's own answers on the developer forum. The
column on the right is this app.

| Rule | Implementation | Verdict |
| --- | --- | --- |
| The system stops the VPN when the process that called `startVpnExtensionAbility` exits | The app process is frozen, not exited; the guard runs until the transient window ends | Shielded for 3 minutes |
| The system stops the VPN when the VPN service process is destroyed | Nothing the app can do from outside; the extension re-arms itself when the system starts it again | Platform-owned |
| The extension process is kept alive by the platform once the tun exists | Relied upon for the nudge and the two-second watchdog | Used |
| Show the connection state and statistics in a notification, tap to return to the app | `service/TunnelNotice.ets` builds the text from the five switches and `WgVpnExtAbility` publishes it on every watchdog tick, so it keeps updating while the app is frozen; `pages/Index.ets` publishes only when the snapshot says the extension did not, and clears when the tunnel is gone | Met |
| Offer manual start and stop | The list switches and the detail page | Met |
| One VPN at a time, and `stopVpnExtensionAbility` only stops your own | `VpnControl` stops only what it started | Met |
| Continuous tasks define no VPN type; `taskKeeping` is PC/2-in-1 or a restricted ACL; `dataTransfer` is cancelled once progress stops | Only a transient task is used | No legal alternative |
| A transient task is 3 minutes, 1 on a low battery, ~10 minutes a day, at most 3 outstanding, and should be cancelled inside its own callback | `service/KeepAlive.ets` requests it when a tunnel is up or wanted and cancels it in the callback | Met |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` is the continuous-task permission | Declared in `module.json5` although no continuous task is requested | **Gap** |
| Always-on is not available to ordinary applications, and a frozen app is not resumed by the system | `restoreDesired()` reconnects when the app is opened again | Platform limit |
| The user must allow background activity for a VPN to stay up on EMUI/HarmonyOS phones | Nothing in the app says so; it is in this file only | **Gap** |
| Persist what the user asked for, and reconcile against it on a cold start — a low-memory kill can skip `onDestroy` entirely | `TunnelStore.setDesired()` is written on connect and cleared only by stop; `restoreDesired()` reconciles when the app opens, and `wantWithDesiredTunnel()` fills in a start request that arrives without parameters | Met |
| A desktop user closes the window and expects the app to stay reachable, with the tunnel state still visible | The icon lives in the system tray and is removed with the ability, not with the window | Met |
| `onDestroy` is a diagnostic signal, not the recovery trigger | The guard keys on the published snapshot going silent, never on `onDestroy` | Met |
| An ordinary app cannot watch another process — `RUNNING_STATE_OBSERVER` is for system and enterprise apps — so the extension has to report itself | The extension publishes a snapshot every two seconds, renamed into place so a reader never catches a half-written one; `EngineStatus` treats it stale after eight seconds, and the guard needs three silent checks | Met |
| A successful `startVpnExtensionAbility` only means the request was accepted, not that the tunnel is up | The UI shows the engine's own state from the snapshot; the request itself is never treated as "connected" | Met |
| `dataTransfer` is not a VPN keep-alive, and fake traffic to satisfy the consistency check gets the task cancelled | Only a transient task is used, and the keepalives are WireGuard's own, not traffic invented to look busy | Met |
| A scheduler job is the last resort once both processes are gone, but it has no timing guarantee (shortest repeat is twenty minutes) | Not used | **Gap** |
| `MANAGE_VPN` / always-on is a system permission | — | Not possible |

### The desktop tray (PC / 2-in-1)

On a desktop the app is not a window that stays in front, so it also puts an icon
in the system tray — the same surface as the clock and the battery. The feature
comes from DesktopExtensionKit (`@hms.pcService.statusBarManager`, since 5.0.0(12),
with `isStatusBarCapabilitySupported` since 26.0.0); a phone answers *no* to that
question and the app does nothing different.

| Part | What it does |
|---|---|
| Icon | `tray_idle_*` while no tunnel is up, `tray_up_*` while one is (the same mark plus a green dot), each in a white and a dark glyph for the shell's own theme. The glyph is the mark without its plate: `tools/make_tray_icons.py` cuts it out of `resources/base/media/app_icon.png` by brightness, and `tools/icon_studio.py` hands over `build/icon-studio/tray-mark.png` when the crop would be wrong. For the doorway mark that file holds the icon's own silhouette -- the wall with the door cut out of its foot: at 16-24 vp a slab with a notch holds its shape where the thin arch on its own disappears. `tools/tray_compare.py` renders both candidates at 16 / 20 / 24 / 32 px on both bar colours, and `TRAY_MARKS` in `tools/icon_studio.py` is one line to switch |
| Hover text | `WGate · 已连接 <name>` / `正在连接` / `未连接` |
| Left click | Delivers `statusBarIconClick` (the quick-operation area is declared empty on purpose) and the app brings its window back |
| Right click | `连接隧道` / `断开隧道`, `打开主界面` (the first is a `notifyOnly` item, so the shell hands the `menuCode` back instead of starting an ability). Quitting is left to the platform, which appends its own `退出` to every tray menu — a second one of ours was in the first field build and only looked like a duplicate |
| Lifecycle | Attached from `onWindowStageCreate`, removed in `onDestroy`: closing the window leaves the icon and the app running, which is the whole point |
| Closing the window | The main window's `windowWillClose` (API 15; the promise resolves `true` = cancel the close) answers "stay" only while `PcTray.isActive()`, and turns the close into `window.minimize()`. Deliberately *not* `onPrepareToTerminate`: that callback also covers the dock's and the tray's own `退出`, so cancelling there would make quitting impossible. A phone has no tray, so there the close ends the app exactly as before |
| Coming back | Starting the ability again (the tray's `打开主界面`, or the launcher) calls `window.show()`, so a minimised window is raised instead of a second one appearing |

Three limits are worth stating, because they are the platform's and not choices:

- Only the app process may hold the icon (the API takes a UIAbilityContext, or a
  service/form extension context), so once the platform freezes the app in the
  background the icon keeps the **last known state** instead of inventing a live
  one. The trace says `pc tray: …` when it is added, removed or unable to be
  added at all.
- The status bar rejects updates that arrive too often (error `1010710003`), so
  `service/PcTray.ets` sends one only when the state string changes, at most once
  every five seconds, and reconciles on a fifteen-second timer.
- The menu can only toggle the tunnel that `service/TunnelCommands.ets` picks —
  the same function the launcher shortcut uses — so a tray click and a shortcut
  can never act on different tunnels.

### The status notification

One notification, id `1001`, `SERVICE_INFORMATION`, and a rule about who owns it:
**the VPN extension publishes, the app only falls back.** The app process is
frozen a few minutes into the background — a three-minute transient task and no
continuous-task type covers a VPN — while the extension keeps its two-second
watchdog for as long as the tun device exists. A frozen process cannot publish,
so the shade would otherwise freeze on "Connecting…" and stay there.

| Part | What it does |
|---|---|
| Text | `service/TunnelNotice.ets` composes it from the five switches under Appearance → Notifications: state line always, transfer totals while up, the bearer the traffic leaves from, a `⚠` marker while the tunnel is down, and — while a tunnel that already worked is coming back — 正在重新连接… plus 已断开 Ns, bucketed to five seconds so the shade is not republished on every tick |
| Published by | `WgVpnExtAbility.publishStatus()`, every watchdog tick, at most one publish per distinct text (the platform rate-limits notifications); the snapshot carries `notified` so the app process knows it is not the publisher |
| App process | `pages/Index.ets` publishes only when `status.notified` is false, and clears the shade when no tunnel is selected |
| Taken down by | `WgVpnExtAbility.shutdown()` and the app's idle path: a stale "Connected" over a dead tunnel is worse than no notification |
| Not a tint | The switch is called *Failure mark* rather than *Failure tint* because `notificationRequest.color` is documented as "Background color of the notification. Not supported currently." — the marker is a glyph, not a colour |

What this does not do: it does not keep the app awake, and it is not a 实况窗
(LiveView). A LiveView needs an AppGallery entitlement reviewed per scenario
(errors `1003500004`/`1003500005`), is push-updated by the app — so a frozen
process leaves a stale card — and the only documented tie to background time is
the other way round: a `dataTransfer` long task must report its progress *as* a
LiveView or be cancelled after ten minutes without an update.

Two things had to be moved into the extension along with the publisher, because
both live in per-process state that a second process starts out empty:

| Needs opening in that process | Why |
|---|---|
| `SettingsStore.init(context)` | Preferences are per process. Without it every read answered with its default, so the five switches were always "on" there and the language always `system` → English |
| `Tr.setLocale(offeredLocale(SettingsStore.language()))` | `Tr` starts in English and only the UI pages ever set the locale; the shade came out as "Connected / via Cellular" on a Chinese phone |

### "Connected" has to mean connected

The engine follows WireGuard's own rule: a session stays usable for
`REJECT_AFTER` (180 s) after its last handshake, so a tunnel whose peer went
away still reports `up` for up to three minutes — and with the radio off it can
report `up` indefinitely as long as something keeps re-handshaking on a link
that carries nothing. That is correct for the protocol and wrong for a status
line.

`WgVpnExtAbility.tick()` therefore overrides the published state to `offline`
whenever `hasNetwork()` finds no Wi-Fi, cellular or Ethernet bearer in
`connection.getAllNetsSync()`. The engine keeps running — the wanted tunnel must
come back by itself — but everything the user reads says what is true:

| Surface | With no network |
|---|---|
| Tunnel list row | 无网络, switch stays on |
| Status pill on the home screen | grey dot, 无网络 |
| Status notification | `Waiting for the network`, with the `⚠` marker |
| PC tray | still on, hover text keeps the last known state |

`service/EngineStatus.ets` treats `offline` as running (`isRunning`) so nothing
mistakes it for a user-initiated disconnect and clears `desiredId`; clearing the
request would lose the auto-reconnect. A probe that throws answers "the network
is there", because a failed query is not evidence of a missing link.

## QR codes

A tunnel can leave the device as a QR code and arrive as one, without copying
text by hand.

| Direction | Path | How it works |
|---|---|---|
| Out | detail sheet → Show QR | the built-in `QRCode` component draws the configuration; no HMS service is involved, so it works on the emulator too |
| In (camera) | Scan → point the camera | Scan Kit `customScan` renders the preview into an `XComponent` surface and decodes frames itself |
| In (image) | Scan → Image | `detectBarcode.decode({uri})` on a screenshot or photo of a code, through the system file picker |

Three things are worth knowing:

- **The built-in renderer stops at 512 characters.** `QRCode` is a plain ArkUI
  component with that limit, so the encoder emits `toQrText()` — no public-key
  comment, and no AmneziaWG key whose value is zero (absent means the same).
  A typical one- or two-peer tunnel is ~460 characters. A tunnel that still does
  not fit is reported in the sheet, with Copy config as the way out.
- **Scan Kit's *generator* is unavailable on the emulator** (`804: The capability
  is not supported on the emulator at this time`), which is why generation uses
  the component, while Scan Kit's *decoder* works there.
- **The camera needs the `ohos.permission.CAMERA` user grant**; the Scan page
  asks for it on first open and, if the device never delivers a preview frame,
  says so after 6 s and points at Image and the paste path.

Both directions were checked on the emulator: the code rendered by the app was
decoded by OpenCV, and the decoded text was imported back into the app
(`image decode: 466 chars` → `saved <id> peers=2`). A code generated by an
independent Python encoder was also decoded by Scan Kit on the device.

## How the tunnel works

1. The UI writes the selected tunnel into preferences and calls
   `vpnExtension.startVpnExtensionAbility()` with the tunnel JSON in
   `want.parameters`. Older platforms only deliver `want.parameters` from
   API 22 on ("the parameters field in want can be passed when the VPN is
   started for the first time"), so the extension falls back to the tunnel the
   UI recorded just before the call, and then to the first stored profile.
2. `WgVpnExtAbility.onCreate()` builds a `VpnConfig` (addresses, routes, DNS,
   MTU, `blockedApplications` for split tunnelling) and obtains a tun fd from
   `VpnConnection.create()`.
3. `wgcore.open()` resolves every peer endpoint and opens one UDP socket per
   address family; the extension calls `VpnConnection.protect(udpFd)` so the
   encrypted datagrams leave over the physical network instead of looping back
   into the tun device.
4. `wgcore.start(tunFd)` launches the engine thread: `poll()` on both descriptors,
   one handshake per peer, a 32-packet queue while a session is not yet up, and
   all WireGuard timers (5 s retransmit, 90 s give-up then a 30 s back-off,
   120 s rekey, 180 s reject, 10 s keepalive). Outbound packets are matched
   against each peer's `AllowedIPs` by longest prefix, inbound ones are demuxed
   by the receiver index in the transport header.
5. Every 2 s the extension re-reads the engine status; when the engine has
   replaced its socket after a network change, the new fd is protected again.

## Diagnosing a tunnel that will not connect

When a tunnel never comes up, the reason is usually outside the engine, and the
app has one button for that case: **Engine log → Check endpoint**. It resolves
the selected tunnel's first peer exactly the way the engine would, sends one
handshake initiation from the app process, waits up to 3 s and reports what came
back:

| Report | Meaning |
|---|---|
| `answered a handshake in N ms (resolved to …)` | the profile, the key pair and the server are all fine; look at the VPN permission dialog or the device network |
| `replied but the handshake did not complete` | something answers on that port but rejects the key: wrong `PublicKey`/`PresharedKey`, or the server does not know this peer |
| `No answer from …, resolved to …` | either the port is blocked (UDP is often filtered on mobile data) or the DNS answer points somewhere wrong; compare the address with what a public resolver returns |

The last case is worth spelling out: a filtered or hijacked resolver can return
an address that no server is listening on, which looks exactly like a broken
tunnel. The check prints the address it used, so it can be compared directly.

### The status bar icon appears and disappears

That is the signature of the system bringing the VPN up and then tearing it down
again, and it happens in the VPN extension's own process, where the UI cannot see
anything. The app therefore keeps a startup trace in `vpn_diag.log` inside its
own sandbox: the UI writes what it asked for, the extension writes what it
managed to do (`extension onCreate`, `vpn created, tun fd N`, `engine open -> N`,
`engine start -> N`, the engine's own log lines, `extension onDestroy`), and the
**Engine log** sheet shows it under *VPN startup trace*. A trace that stops after
`connect requested` means the service never started; one that stops after
`vpn created` means the engine refused the configuration.

Things that are handled already:

- A device that is still bringing its network up - or whose DNS is being replaced
  by the VPN it is starting - can fail to resolve the endpoint once. The engine
  used to treat that as fatal; it now stays in the connecting state and retries
  the socket every 2 s. That includes the handover case, where the name resolved
  when the tunnel came up and stops resolving later: a failed recycle releases
  the old socket, because the retry branch only runs while there is no socket at
  all (`tools/recycle_probe.c`).
- The endpoint name is resolved **before** `VpnConnection.create()`, while DNS
  still leaves over the physical network, and the address is handed to the engine
  in place of the name. After the tun device owns the default route, a lookup
  from the extension is routed into the tunnel whose peer has no session yet, so
  the engine could never resolve anything on its own.
- The transport socket has to be protected or its datagrams are routed back into
  the tun device. Its fd is read from `status().udpFd` (not from `open()`'s
  return value) and protected through the watchdog, which also re-protects the
  replacement socket after a network handover.
- Extensions started by a system older than API 22 receive an empty
  `want.parameters`, so the configuration is looked up through the store instead.

If the trace says `protect failed: 2203004`, the fd is not a socket the system
recognises - the tunnel cannot carry anything until that is resolved, because its
own handshake packets are being fed back into it.

### Why the list said "Disconnected" while the tunnel worked

The engine lives inside the `VpnExtensionAbility`, which the system runs in a
separate process. `wgcore.status()` called from the UI therefore describes a
stopped engine with zero counters, and `preferences` caches per process, so the
id the extension recorded was invisible too. The extension now publishes a
snapshot (`vpn_status.json`: id, state, byte and packet counters, peers up, age of
the last handshake) on every watchdog tick, and the UI prefers that snapshot while
it is fresher than 8 s, adopting its tunnel id as the active one. A snapshot that
stops being updated is how the UI notices the extension is gone.

### Why the switch said "started" while the row said "Disconnected"

A switch is a claim about the present, not a wish: it follows the id the
extension published, never the id merely stored as wanted. Two defects made the
two disagree on a cold start:

- `TunnelStore` keeps `active` (written by whoever brings the tunnel up) next to
  `desired` (the intent). `desired` survives the process being killed - the
  extension clears `active` on shutdown but never `desired` - so reopening the
  app restored the intent into `activeId` and the switch painted on.
- `AutoTunnel.start()` only subscribed to `netAvailable`, `netLost` and
  `netCapabilitiesChange`. Those fire on a change; the usual case after a
  restart is a device that never changed network, so nothing brought the tunnel
  back and the engine really was stopped.

Now `TunnelsView.refresh()` adopts the published id when there is one and clears
`activeId` once the grace window (8 s, given to an optimistic start) has passed
and `readStatus()` reports nothing running; `Home.reload()` adopts the published
id only. `AutoTunnel.start()` also re-evaluates once, deferred by 600 ms so the
window is up, which is what makes a trusted network bring the tunnel back by
itself. The switch therefore turns off first and on again within a tick or two,
in the order the engine actually reports.

### Group actions, sorting and the typeface

Long-pressing a group header opens the reference app's GroupActionsSheet: the
name field renames the group (the tunnels that point at it follow), **Export
group** writes one .conf holding every tunnel in the group, **Delete group**
only ungroups its tunnels, and **Delete group and tunnels** removes both.

The reorder button in the top bar opens the same two options as
TunnelsScreen.kt: **Sort** orders by name, **Sort by latency** asks the engine
to perform a handshake with each endpoint first (the same probe the endpoint
check uses), stores the measured RTT and orders by it. Tunnels that never
answered keep the previous order at the end. The choice is remembered in
SettingsStore (sort_mode, latency_<id>).

The reference app ships Inter; 
esources/rawfile/inter.ttf is registered
through getUIContext().getFont().registerFont() in Home and applied with
FONT from the theme, so the interface uses the same face. The deprecated
ont.registerFont call from an ability does not take effect, which is why the
registration lives in the page.

### The Auto-tunnel tab and the two new Settings pages

`ui/screens/autotunnel/AutoTunnelScreen.kt` is reproduced row for row: the
**Auto-tunnel running / not running** row with its Start/Stop button, then the
**Networks** group with the active network (the type this build reads from
`connection.getNetCapabilitiesSync`, plus the SSID when it is Wi-Fi), one row per
network type - **Tunnel on Wi-Fi**, **Tunnel on mobile data**, **Tunnel on
Ethernet** - each with its own switch and its own preferred tunnel, and **Stop on
no internet**; then the **Automation** group with **Restart at boot**. The
cellular and Ethernet rows open `PreferredTunnel`, which stores `net_pref_<type>`,
and `AutoTunnel.pickTunnel()` honours that choice before the global preferred
tunnel. The Wi-Fi row opens `WifiSettings` instead, the way
`Route.WifiPreferences` is pushed in the reference. The Android-only location
banners have no counterpart and are omitted rather than faked. There is no manual
refresh control on this tab, matching the reference: the view re-reads the network
and the settings on a 1.5 s tick, every rule switch calls `AutoTunnel.evaluate()`
itself, and a tap on the active-network row re-reads it, so a Refresh button had
nothing of its own to do.

The one deliberate divergence in this tab is the running row: the reference puts a
text `Button` (Start/Stop) there, this build uses the same `Toggle` switch as every
other row, because the two looked like different controls on the same screen. The
switch and the row body both drive `AutoTunnelView.setAuto(next)`; a tap on the
switch is consumed by the `Toggle`, so it does not double-fire through the row's
`onTap`.

`Tunnel monitoring` (the reference's `MonitoringScreen`) holds the tunnel
statistics switch and the refresh rate; both are read by the Tunnels list, so the
interval chosen there is the interval the counters update at. `Backend mode`
opens the lockdown switches, and `System integrations` lists what HarmonyOS does
and does not expose (native kill switch and always-on VPN are not available, boot
start is).

### Split tunnelling, IPv6 and the entry tunnel

`ui/screens/tunnels/config` in the reference builds the tunnel screen from four
groups; the three rows this build only records are now real pages. `App split
tunneling` opens **App split tunnelling** with the switch, the include/exclude
choice and the app list; on HarmonyOS a VPN extension cannot see other apps'
sockets, so the list says so instead of pretending, and the switch plus the
choice are stored per tunnel (`split_on_<id>`, `split_mode_<id>`). `IPv6
settings` opens **Peer endpoints** with Prefer IPv6 and Restore IPv6, which the
engine records for a future IPv6 dialler; the row description says `IPv4
endpoints only` while that is the case. `Entry tunnel` opens **Multihop** with
None plus every other tunnel, and the chosen name is shown on the tunnel row.

The rows read their state through the page's own tick rather than only in
`aboutToAppear`: `router.back()` does not re-run it, so a sub-page choice would
otherwise appear on the next visit rather than immediately. `Entry tunnel`
resolves the stored id when it draws, so the label cannot lag behind the write.

### Support, licences and the privacy policy

The Support tab no longer mirrors `SupportScreen.kt`. That screen is mostly exit
ramps into the upstream project — a guide, a website, a chat room, a translation
portal, a donation page — and every one of them would send the reader of *this*
app somewhere that is not this app. What is left is what the app owns:

* **Open source** → **Licences** (`pages/License`): the page is split the way the
  obligations actually run. *This app* is WGate under GPL-3.0 (full text in
  `LICENSE`). *Upstream project* is WG Tunnel by Zane Schepke under MIT — the port
  descends from it, so its copyright line and permission notice travel with the
  package and are printed verbatim in the last section of the page. *Third-party
  components* are Monocypher (BSD-2-Clause/CC0-1.0, © Loup Vaillant), Inter (SIL
  OFL 1.1), Material Symbols (Apache-2.0), Zig (MIT, build time only) and the
  HarmonyOS SDK. Below them: where the corresponding source is — GPL-3.0 §3 wants
  it reachable by anyone holding the binary — and the GPL-3.0 warranty notice.
  `THIRD-PARTY-NOTICES.md` at the repository root carries every one of those texts
  in full; `tools/make_notices.py` regenerates it from `_ref_android/LICENSE`, the
  vendored Monocypher header and the canonical OFL/Apache texts, so the file is
  generated rather than typed. The page deliberately claims nothing it cannot
  back: an earlier draft listed the native core as a separate GPL-2.0 component
  and a "BLAKE2s reference implementation" as CC0, but both files were written
  here from the published specifications, so they fall under the project licence.
* **Your data** → **Privacy policy** (`pages/Privacy`): a page rather than a
  URL, so it reads offline and cannot rot when a site moves. Six paragraphs, each
  one a claim that can be checked against the code: no account and no telemetry,
  tunnels and keys only in the app's private preferences, the startup trace local
  and content-free, the four permissions and what each is for, no advertising or
  crash SDK in the build, and uninstall taking the data with it.
* **About** → the version, and the sign-off.

Donate and the cryptocurrency address list still exist as pages
(`pages/Donate`, `pages/Addresses`), but nothing links to them any more; they are
kept because they are the upstream author's, not this project's.

### First run

A fresh install opens on **Simplified Chinese** and on **follow the system
appearance**:

* `SettingsStore.language()` defaults to `zh_CN`; `offeredLocale` still folds
  anything unknown onto the three interfaces the picker offers.
* `SettingsStore.theme()` defaults to `automatic`, and `pages/Display` lists
  Automatic first, because the list should read the way the app behaves. Rows
  offer Automatic, Dark, Light, Darker and AMOLED — **Dynamic** is gone, since
  HarmonyOS exposes no accent-colour API to follow. A device that still has
  `dynamic` stored keeps painting the dark palette it always painted.
* Neither page ends in an explanatory footer any more; the rows say what they do.

`keepalive` is deliberately **not** translated, on the Tunnel globals page or in
its sheet — it is the WireGuard field name and reads as itself next to `MTU` and
`DNS`.

Icons follow the reference, and the question mark is the reference's alone.
`Route.kt:170` gives `Tab.SUPPORT` `Icons.Outlined.QuestionMark` /
`Icons.Filled.QuestionMark` — a bare glyph with no ring — and no row on any
screen uses it. This build used to draw a hand-made ring around a shaped `?`; the
asset is now the Material Symbols `question_mark` path, projected onto the 24 grid
by `tools/svg_symbols_to_24.py` through `tools/make_support_icons.py`, and only
`components/BottomNav.ets` points at it. The tab keeps the filled/outlined pair
the reference uses — the tint is what changes between them. The licence row wears
the reference's `Icons.Outlined.Balance` (`ic_balance`).

**Background location disclosure** (`pages/LocationDisclosure`) is opened once
from the Auto-tunnel tab, like `LocationDisclosureScreen.kt` before the tab is
usable. The flag `location_disclosure_shown` is written by the page, so it never
returns; clearing the settings brings it back. HarmonyOS hands the connected
network to the app without a location grant, so the page explains why this build
never asks for location instead of pretending to request it. Pushing the page
from `aboutToAppear` left the page transition half drawn, so the push is
deferred by 600 ms.

### The Wi-Fi preferences page

`WifiSettingsScreen.kt` is a page of its own in the reference, and the Wi-Fi row
of the Auto-tunnel tab is what opens it (`Route.WifiPreferences`), not a tunnel
picker — so `pages/WifiSettings` now sits behind that row and the two standalone
rows that used to sit below it (a bare trusted-network list and the detection
method) are gone, because both live inside the page:

* **General** — `Wi-Fi detection method: <Default|Legacy|Root|Shizuku>` (opens
  `WifiDetection`) and the **Use wildcards** switch, whose note explains that
  `Work*` then covers `Work` and `Work-5G`.
* **Wi-Fi rules** — **Trusted Wi-Fi names** and **Trusted BSSID**, each an
  editor with its current rules, a `Remove` action per rule and an input to add
  one. A BSSID is validated as six hex pairs and the page shows the same
  rejection text as the reference instead of storing a malformed value. Turning
  wildcards on reveals the per-editor note that a rule may end in `*`.
* **Stop while captive portal** and **Tunnel mapping** (which opens
  `PreferredTunnel` for Wi-Fi).

Everything is stored under `ssids`, `bssids`, `auto_wildcards` and
`captive_portal`, so the rules survive a restart the same way the other settings
do. One ArkUI detail cost a build: a `@Builder` that takes the list as a
by-value parameter does not re-render when the list changes, so the two list
builders read `this.ssids` / `this.bssids` directly.

The rules only mean something if the watcher reads them the way the page
describes them, and it did not: `AutoTunnel.evaluate()` compared the joined SSID
against each rule with `indexOf`, so `Xiaomi*` - a rule the page itself invites -
matched nothing, and with no match nothing ever came up. `SettingsStore.trustsSsid()`
now owns the decision: a rule is literal while **Use wildcards** is off, and with
it on `*` covers any run of characters and `?` exactly one; a rule prefixed with
`!` is an exclusion and wins over every inclusion. The glob is a two-pointer
match rather than a `RegExp`, because it runs on every network callback. The
same call also folds in the per-bearer switch (`net_on_wifi` and friends): the
Auto-tunnel tab presents "Wi-Fi tunnel", "Ethernet tunnel" and the mobile-data
one as gates of their own, so a bearer whose switch is off is never started even
when its name is trusted. `tools/check_wildcards.py` transliterates the matcher
and asserts the table (`Xiaomi*` vs `Xiaomi_90FA_5G_Game`, `*Guest*`, trailing
`?`, wildcards off).

### Language and display theme

`AppearanceScreen.kt` pushes two screens; the two rows did the same here, so the
last two pickers that were sheets became pages:

* **Language** (`pages/Language`) offers three interfaces: English, Simplified
  Chinese and Traditional Chinese, with the current one ticked. The catalogue still
  carries all twenty-eight locales the reference ships — nothing was thrown away —
  but the picker only reaches the three we can stand behind. `i18n/Locales.ets`
  owns the rule: `OFFERED` is the list, `offeredLocale()` folds anything else onto
  it (`de_DE`, the old `system` sentinel, the region tags a device reports), so a
  value stored by an earlier build can never leave the picker with nothing ticked.
  `Home` applies the same fold before the first page is built, and the Language
  page rewrites the stored value when it had to fold, so the next launch starts on
  the interface that is actually painted.

The translations are imported rather than retyped. `build/gen_catalog.py` read
`_ref_android/app/src/main/res/values-*/strings.xml` and wrote
`entry/src/main/ets/i18n/Catalog.ets`, one payload per locale, rows encoded as
`english<col>translation` and joined with `<row>`. That generator was a one-off and
is not in the tree; single rows are added by
`python tools/add_catalog_row.py "<English>" <android_string_name>`, which reads the
same `values-*` folders and is safe to re-run. The reference sometimes carries its
own punctuation — `active_network` is `活跃网络：` with the colon, because the Kotlin
`append`s the value straight after it — so the patcher strips a trailing colon and
spaces, and the ArkTS code writes `<label>: <value>` itself.
`entry/src/main/ets/i18n/Tr.ets` parses the catalogue once and answers
`Tr.t(<english literal>)`; `Home` sets the locale before the first page is built and
the picker rebuilds the stack through `reloadUi()`.

The catalogues are keyed by the English text, which keeps the mapping honest: a
literal the reference words differently simply stays English instead of showing a
wrong translation. Today both Chinese payloads carry 348 rows against the 333
literals the source asks for, and the fifteen that still do not resolve are
deliberate — `AMOLED`, `DNS`, `H1`–`H4`, `Jc`/`Jmax`/`Jmin`, `S1`–`S3`, `WGate`,
`Liberapay`, and the two donation URLs, which neither Chinese folder
translates in the reference either. `python tools/check_coverage.py` prints that gap
per offered locale (it joins `Tr.t('a ' + 'b')` before comparing, so a wrapped
sentence is not mistaken for a missing key) and exits non-zero on anything else.

Labels whose punctuation belongs to the sentence are templates, not concatenation.
The reference writes `peer: %1$s`, `handshake: %1$s`, `via %1$s` and `uptime: %1$s`,
and the Chinese folder answers `节点：%1$s` and `握手：%1$s` — the colon is full-width
there, so gluing `': '` on in code would be wrong. `Tr.tf(<english template>, …)`
translates first and then substitutes, and
`python tools/add_template_rows.py` inserts those four rows from the reference
(`peer_template`, `handshake_template`, `via_entry`, `uptime_template`); the tunnel
row's peer line, handshake line, `via` line and uptime now go through it.

Rows arrive three ways. Copied from the reference with
`python tools/add_catalog_row.py`, authored here with
`python tools/add_catalog_text.py` (the table in that file is the English wording of
every HarmonyOS-only note, so re-wording one means editing the table and the call
site together), and converted for Traditional Chinese with
`python tools/add_traditional.py`, which fills the rows `values-zh-rTW` lacks by
running `zh_CN` through OpenCC's `s2twp` profile — the reference itself only
translates about half of what Simplified does, so without this the Traditional
interface would be half English. `python tools/remove_catalog_keys.py` retracts a row
that was inserted with the wrong wording, and `python tools/check_catalog_rows.py`
asserts that every row starts at a separator, that no key is glued into a
neighbouring translation, and that authored rows still match their table.

`python tools/set_catalog_row.py <locale> "<English key>" "<translation>"` replaces
the wording of a row that already exists in one locale. It exists for rows whose
reference translation is a sentence where the surrounding rows are noun labels — the
mobile-data row read "允许隧道使用数据流量" next to "Wi-Fi 隧道" / "以太网隧道", so
Simplified spells it "移动数据隧道" and Traditional "行動數據隧道" here. The override is
a recorded decision; re-running the script with the reference wording undoes it.
`python tools/show_catalog_row.py <locale> "<English key>"` prints one row with
`\uXXXX` escapes so it can be checked without fighting the console code page.

A row label only translates when it is interpolated — `${Tr.t('Active Network')}:
${value}` — because the lookup is keyed on the literal. Text typed straight into the
template string stays English in every locale, which is how `Active network` and the
Ethernet row's `Preferred tunnel` reached the device untranslated while the rows above
them were Chinese. The same trap caught the tunnel row, whose `peer `, `handshake `,
`via ` and `up ` prefixes were template literals: they now go through
`Tr.tf('peer: %1$s', …)` and friends, and `tools/audit_literals.py` treats `Tr.tf(` as
translated so a bare `label:` / `title:` literal is still reported.
* **Display theme** (`pages/Display`) offers the six `ThemedTheme` entries — Dark,
  Light, Automatic, Dynamic, Darker, AMOLED — and each one paints the app now.

Making the theme real took two changes, both in `entry/src/main/ets/theme/Theme.ets`:

1. `Palette` is no longer a class of `static readonly` strings. Each colour is a
   getter over the scheme that was applied last (`DARK`, `DARKER`, `AMOLED`,
   `LIGHT`), so a read at build time returns the colour of the current theme.
2. A repaint alone is not enough. ArkUI re-applies the modifiers whose expression
   changed with a state variable, but a `Palette` read inside a modifier that did
   not change is not re-applied — the first attempt left black surfaces under
   light text. `applySchemeAndReload` therefore applies the scheme and then
   rebuilds the page stack (`router.clear()` + `replaceUrl('pages/Home')`), which
   recreates every node so each colour is read again. The user lands on the tunnel
   list, in the new theme, in one step.

`automatic` resolves through the ability configuration (a light device gets the
light palette); `dynamic` has no accent API on HarmonyOS and paints the dark
palette, which its row says. The choice persists in `theme`, and `Home` applies it
before the first frame, so a restart comes up in the chosen theme.

Both Appearance rows show the stored value. `router.back()` neither re-runs
`aboutToAppear` nor restarts a timer stopped by `aboutToDisappear`, and
`onPageShow` did not fire on return either, so the two values are polled every
500 ms by a timer that is deliberately left running.

The theme work also uncovered a data bug worth naming: the group list lives in its
own preference, so it can be lost while tunnels still point at the group — those
tunnels then rendered nowhere. `TunnelsView` now adopts an orphaned group on
reload (`SettingsStore.addGroup`) and, failing that, shows the tunnel under the
ungrouped section.

### Backend mode and the proxy settings

`Backend mode` in Settings is a chooser now, the way `SettingsScreen.kt` routes
`TunnelMode`: **VPN** keeps the HarmonyOS VPN extension, **Lockdown** opens the
kill-switch page, and **Proxy server** opens the SOCKS5/HTTP page behind
`TunnelMode.PROXY`. The chosen mode is stored under `backend`, so the row keeps
saying which one is active.

`Proxy server` mirrors `ProxySettingsScreen.kt`: a SOCKS5 group (switch, bind
address, Allow SOCKS4), an HTTP group (switch, bind address) and the optional
username/password pair, with the credential rows appearing only once a listener
is on. The Android build starts those listeners inside the tunnel; this build
records the same fields so a shared configuration keeps them, and the page says
plainly that the listeners are not opened yet — a HarmonyOS VPN extension owns
the tun device and the SDK has no app-facing proxy contract.

### Reading and editing the configuration

The reference splits the tunnel screen's `View configuration` into two pages: a
read-only view with an eye and an overflow menu, and a form editor. This build
has both. The view masks every `PrivateKey` / `PresharedKey` line with 44 dots
(matching `maskSensitive`), the eye in the top bar reveals the text, and the
overflow menu holds **Show QR** and **Copy** — the two buttons that used to sit
under the text. **Edit** appears only for a saved tunnel, because a live tunnel
is a running interface rather than a file.

`Edit tunnel` follows the reference's sections: Interface (name, private key with
**Rotate**, derived public key with **Copy**, addresses, listen port, DNS, MTU),
the optional Amnezia values behind `Show Amnezia options`, the four `PreUp` /
`PostUp` / `PreDown` / `PostDown` hooks behind `Show scripts`, and one card per
peer with its public key, preshared key, keepalive, endpoint and allowed IPs,
plus Add peer and Delete. Rotate builds a real X25519 pair through
`cryptoFramework` and writes both keys back, so the derived public key is the one
the engine will present — it is not a placeholder.

Saving writes the tunnel through `TunnelStore.save()` and re-renders the
configuration text on the way back. That last part needed `onPageShow()`: a
`router.pushUrl().then()` resolves when the page is pushed, not when the pushed
page pops, so the first version showed the pre-edit text until the screen was
reopened.

## Verification

Everything except the ArkUI layer is host-testable. One command builds and runs
the whole suite (requires Zig, which acts as a portable clang, and Python 3 with
the `cryptography` package):

```powershell
pwsh -File tools/run_host_tests.ps1
```

| Suite | What it covers | Result |
|---|---|---|
| `tools/wgtest.c selftest` | BLAKE2s vectors, RFC 8439 AEAD, RFC 7748 X25519, handshake and transport in both roles, replay rejection, AmneziaWG framing | 37 checks, 0 failures |
| `tools/interop.py` | the C core against an independently written Python implementation of WireGuard, both directions, plain and AmneziaWG | all four cases pass |
| `tools/enginetest.c` | the real engine loop against a simulated tun device and a test responder: queueing before the handshake, padding trim, keepalives, byte counters with a larger packet in one direction so the two cannot be confused; plus a two-peer run covering routing, demultiplexing and `peers_up` | 0 failures (plain, AmneziaWG, two peers) |
| `tools/keepalive_probe.c` | an idle tunnel on a host whose clock is past 180 s: a persistent keepalive from the handshake on, with no data packet first, and the socket retry loop after a name stops resolving | keepalive on an idle session, retries re-armed |
| `tools/recycle_probe.c` | a socket recycle whose re-resolve fails after a healthy socket existed: the fd is released so `engine_tick()` retries instead of leaving an unresolved tunnel with a live-looking socket | failed recycle releases the fd, retries continue |
| `tools/jsontest.cpp` | the base64/flat-JSON configuration bridge that `open()` relies on, including the `peerCount` / `peerN<Field>` hand-off | 33 checks, 0 failures |
| `tools/check_keepalive.py` | static audit of the keep-alive design against the platform's rules: one VPN extension, the network watcher, the transient-task window and the hand-back inside its callback, `TunnelGuard`, the extension-side nudge, the cold-start reconciliation, the atomic snapshot, the desktop tray and its close-to-tray path, who publishes the status notification and which process resolves its language and switches, that a tunnel with no network is never labelled connected, that the recovery line needs a session that already worked, the two engine invariants the probes below prove by running, that the log page keeps no always-empty block and can export and clear its trace, that a restore parses wg-quick, skips records that cannot connect and reads the picked file through its descriptor, and that the support page links nowhere, the privacy policy is a page, a fresh install opens on Simplified Chinese and follows the system appearance, and keepalive stays untranslated | 125 checks, 0 failures |

Screens checked on the emulator after the last build:

| Screenshot | What it shows |
|---|---|
| `build/s7.jpeg` | tunnel screen after both choices: `Entry tunnel — TwoPeers`, `Split tunneling — On: the selected apps bypass the tunnel` |
| `build/r4.jpeg` | App split tunnelling with the switch on: Exclude apps (checked) and Include apps appear, Apps row says N/A |
| `build/s3.jpeg` | IPv6 settings: Prefer IPv6 and Restore IPv6, both off |
| `build/s6.jpeg` | Multihop / entry tunnel: None plus the other tunnel, TwoPeers checked |
| `build/t3.jpeg` | configuration page: `PrivateKey` replaced by 44 dots |
| `build/t4.jpeg` | the eye in the top bar reveals the key |
| `build/t5.jpeg` | overflow menu with Show QR and Copy |
| `build/t9.jpeg` | QR drawn from the menu, below the configuration text |
| `build/u1.jpeg` | Edit tunnel: name, private key with Rotate, derived public key, addresses, port, DNS, MTU |
| `build/u4.jpeg` | the four hook fields after Show scripts |
| `build/v1.jpeg` | Rotate replaced the key pair and the public key field filled in |
| `build/u8.jpeg` | after Save: `PostUp = echo hi` in the configuration text, re-read by `onPageShow()` |
| `build/w6.jpeg` | SOCKS 5 on: bind address and Allow SOCKS4 appear, credentials below |
| `build/x3.jpeg` | Settings after choosing Proxy server: the Backend mode row reads `Proxy` |
| `build/y1.jpeg` | Support tab: Open source, Your data, About |
| `build/y2.jpeg` | Donate page: the letter and the three options |
| `build/y3.jpeg` | Cryptocurrency addresses: all thirteen coins |
| `build/y5.jpeg` | Tapping an address copies it (`Address copied`) |
| `build/y6.jpeg` | Licences: the included components and the GPL-3.0 notice |
| `build/z1.jpeg` | Background location disclosure before the tab is usable |
| `build/z3.jpeg` | The disclosure never returns: `location_disclosure_shown` is set |
| `build/aa2.jpeg` | Appearance with Language and Display theme as their own rows |
| `build/aa3.jpeg` | Language page: system default ticked, the shipped locales below |
| `build/aa4.jpeg` | Display theme page: the six entries, Dark ticked |
| `build/ab4.jpeg` | after choosing Deutsch and AMOLED the two rows read `Deutsch` and `AMOLED` |
| `build/ac1.jpeg` | Auto-tunnel tab after the change: no standalone trusted-network or detection row, the Wi-Fi row is the way in |
| `build/ac2.jpeg` | Wi-Fi page: detection method, Use wildcards, both rule editors, captive portal, Tunnel mapping |
| `build/ac4.jpeg` | wildcards on: both editors show the note about a trailing `*` |
| `build/ac6.jpeg` | a malformed BSSID is refused with the reference message about six hex pairs |
| `build/ad4.jpeg` | `Home` added as a trusted SSID, rendered in the list with its Remove action |
| `build/u1t.jpeg` | the light palette applied at startup from the stored theme |
| `build/u4.jpeg` | AMOLED picked in Display: the stack is rebuilt and the list comes up true black |
| `build/w3i.jpeg` | Language page lists all twenty-eight reference locales |
| `build/w4i.jpeg` | after picking 中文（简体） the list title reads 隧道列表: the catalogue is live |
| `build/w5i.jpeg` | Settings in Chinese: 设置, DNS 设置, 全局隧道, 隧道监控, 常规, 外观, 安全 translated, own wordings left English |
| `build/nb2.jpeg` | the nav is a floating capsule now; the row behind it shows through the glass |
| `build/nb4.jpeg` | with the veil and the blur the row behind the capsule is muted, not readable |
| `build/nk1.jpeg` | mid-drag, the light follows the finger inside the capsule |
| `build/no4.jpeg` | the capsule after the failed sibling-stack experiment was rolled back |
| `build/nq1.jpeg` | press at the left end: the light appears under the finger, icons stay crisp |
| `build/nq2.jpeg` | same drag further right: the light tracks the finger across the bar |
| `build/u7.jpeg` | Appearance reads `English` and `AMOLED` after the two picks |
| `build/u8.jpeg` | Light picked from a black session repaints the whole app |
| `build/v1t.jpeg` | restart: light theme kept, and the orphaned `Work2` group is back with its tunnel |
System.Object[]

`tools/dbgdiff.py` and the `#ifdef WG_DEBUG` tracing in `wg_proto.c` were used to
compare intermediate Noise hashes and keys against the reference implementation
while bringing the handshake up; they are kept for future protocol work.

**Status:** the application runs on a HarmonyOS 6.0 (API 26, x86_64) emulator
and the protocol, engine and configuration layers pass every host test.

Verified on the emulator:

| Check | Result |
|---|---|
| HAP installs unsigned, `libwgcore.so` loads from `libs/x86_64` | ok |
| Tunnel import, list, editor sheet, delete, preferences persistence across a process restart | ok |
| Multi-peer import (two `[Peer]` sections, AmneziaWG parameters) and the detail sheet listing both peers with their routes | ok |
| Structured editor: form/paste modes, per-peer cards, add/remove peer, key generation | ok |
| Engine log sheet reading the native ring buffer | ok (empty until the engine opens) |
| Save from the editor writes the tunnel, closes the sheet and survives a reboot | ok (`save: ok … peers=2`) |
| Importing the same configuration twice updates the existing tunnel | ok (`import: updating <id>`) |
| Clipboard **write** (Copy) | ok (`clipboard write: 534 chars`) |
| Clipboard **read** (Import from clipboard) | refused by the OS; the sheet explains why and points at long-press → Paste |
| `generateKeyPair()` / `publicKeyFrom()` in the native core | ok (X25519 + base64 on device) |
| `wgcore.status()` polling drives the detail pane (`idle`, `0 / 0` packets, `0 / 2` peers up) | ok |
| Breakpoint layout (single column on phone, two panes on wide windows) | ok |
| `startVpnExtensionAbility` when the system authorisation surface is missing | reports `The system did not confirm the VPN request` after 20 s instead of hanging |
| Show QR renders a code that an independent decoder reads back as the full configuration | ok (466 characters, OpenCV) |
| Scan → Image decodes a code from a file and imports it | ok (`image decode: 466 chars` → `saved <id> peers=2`) |
| Scan page camera start, permission prompt and the 6 s no-preview hint | ok (no frames on the emulator, hint shown, no crash) |
| Check endpoint on a real profile | ok — `www.002049.xyz:51820 answered a handshake in 8 ms (resolved to 28.0.1.136)` |
| Long-press a row enters selection mode (`N selected`, round check boxes, switches hidden) | ok |
| Selection actions: select all, move to group, copy, ungroup, delete | ok (a single tunnel moved into a new group) |
| Group header with folder icon, tunnel count, collapse chevron; group and membership survive a process restart | ok |
| Appearance page with the theme picker (five entries, current one marked `Selected`) and the notifications entry | ok |
| Notifications page with the five switches, all persisted, and each one changing the shade the extension publishes | ok |
| Tunnel globals: global split switch plus the MTU/keepalive/DNS sheet applied to imports | ok |
| DNS settings showing the live system resolvers (`ConnectionProperties.dnses`) | ok |
| Local logging showing the one shared trace; Refresh re-reads it, Export writes it to a picked file, Clear empties it | ok (`log exported to wg-log-….txt (484 bytes)` in the trace; a stale view refreshed to lines written while the app was away) |
| Auto-tunnel: watcher registered, trusted network added, decision logged on every network callback | ok (`auto-tunnel: watching the network` / `… capabilities changed, ssid "", trusted false`; the emulator has no Wi-Fi) |
| Security: screen-recording protection actually blanks the window | ok (a capture with the switch on came back black; `privacy mode on/off` in the trace) |
| Tunnel recovery switch and the 5/15/30/60/120 s bounce delay sheet | ok |
| Tunnel scripting page states what cannot run; the switch persists | ok |
| Backup exported two tunnels to the picked file | ok (`backup written to …/wg-tunnels-2026-10-20T16-04-46-208Z.json (1343 bytes)`) |
| Restore of that backup onto the same device | ok, `已恢复 2 个隧道`, count unchanged at 3 — records are keyed by id, so a re-import replaces instead of duplicating |
| Restore of a `wg-quick` `.conf` | ok, `已恢复 1 个隧道`; the new tunnel opens with its private key, DNS, all AmneziaWG parameters and both peers |
| Restore of a picked `.txt` log | rejected, `恢复失败：无法识别的文件` — reading works now, the content is simply not a configuration |
| Support: nothing on the page leaves the app | ok (no links; Licences and Privacy open pages) |
| Group actions: long-press a header renames the group and keeps its tunnel | ok (`Work` → `Work2`, still `1 tunnel`, survives a restart) |
| Group actions: export writes one `.conf` through the save picker | ok (`Work2-2026-10-17T17-56-29-709Z.conf` offered, file written) |
| Reorder sheet offers Sort and Sort by latency | ok (both rows present; sorting by name persists) |
| Sort by latency probes each endpoint and reports how many answered | ok (`sort by latency: 1 of 2 measured`; the 10.0.2.2 test tunnel has no peer) |
| Inter registered and visibly used | ok (`font: registered Inter`; the title measures 282 px against 267 px with the system face) |
| Auto-tunnel tab rebuilt to the reference structure | ok (`Auto-tunnel running` + Stop, Networks group with the active network, three per-network rows, Stop on no internet, Automation group) |
| Preferred tunnel is stored per network type | ok (`net_pref_wifi` = Scanned tunnel, the Wi-Fi row reads `Preferred tunnel: Scanned tunnel`) |
| Tunnel monitoring page drives the list | ok (statistics switch and a 1 s refresh rate; the Tunnels list reads both) |
| System integrations page | ok (kill switch and always-on VPN marked N/A, boot start switch, remote control link) |
| Backend mode opens the lockdown switches | ok (kill switch, allow LAN, metered, dual stack) |

Importing through `--ps` needs a single-line payload: multi-line values make hdc
answer `invalid number of parameters for option --ps`. Either join the lines with
literal `\n` (the parser normalises them) or paste the text into the editor.

```powershell
$cfg = (Get-Content wg-test.conf) -join '\n'
hdc shell "aa start -a EntryAbility -b com.wgtunnel.harmony --ps wgquick '$cfg' --ps name LabPeer"
```

**What could not be executed here:** the emulator image does not ship the VPN
authorisation dialog. The framework log on every connect attempt says so:

```
W C01123/BMSCommon: bundle not exist -n com.huawei.hmos.vpndialog
I C01121/BMSQuery: ExplicitQueryExtension size:0 -n com.huawei.hmos.vpndialog -e VpnServiceExtAbility
```

`bm dump -a` lists 67 bundles and none of them is that dialog, so the system never
grants the VPN and `VpnConnection.create()` is never reached. `aa start -E` on the
extension is refused with `10107102` (process permission) — by design, extension
abilities can only be started by their own application. Everything downstream of
the tun descriptor is therefore unverified on a device.

To exercise the tunnel end to end on real hardware, start a peer on a machine the
phone can reach and import the configuration it writes:

```powershell
# host: WireGuard responder that answers ICMP through the tunnel
python -u tools/wgserver.py --endpoint 192.168.1.10 --port 51820 --out wg-test.conf
# device: import it (also usable from any app through these Want parameters)
$cfg = (Get-Content wg-test.conf) -join '\n'
hdc shell "aa start -a EntryAbility -b com.wgtunnel.harmony --ps wgquick '$cfg' --ps name LabPeer --ps connect true"
hdc shell ping -c 3 10.99.99.99
```

The configuration routes `10.99.0.0/16` into the tunnel, so the ping is answered
by `wgserver.py`; its log shows the handshake and every packet it decrypted.
Three device-level behaviours to watch while doing this:

1. `poll()` reporting readiness on the tun descriptor returned by
   `VpnConnection.create()` (the engine's read path depends on it).
2. The consent dialog and `protect()` on the transport socket.
3. Roaming: switching between Wi-Fi and cellular should recycle the socket and
   re-protect it within a few seconds (watch `socketGen` in `wgcore.status()`).


## AmneziaWG scope

Implemented: `H1–H4` message-type replacement, `Jc` junk datagrams sent before
each handshake, `S1`/`S2` junk prefixes on initiation/response, `S3` parsed.
Not implemented: the AmneziaWG 2.0/3.x tag machinery (`I1–I5` special junk
packets, per-packet header protection), which is a different protocol
generation than the widely deployed 1.5 configurations.

Note that AmneziaWG 1.5 servers expect exact handshake sizes on receive, so a
non-zero `S1`/`S2` is only honoured by peers that strip the prefix (as this
client does).

## Reference material

The upstream sources consulted while porting are checked out in `_ref_android/`
(the Android client), `_ref_arkts/` (an earlier community HarmonyOS client),
`_ref_wg/` (wireguard-go and amneziawg-go) and `_ref_vpn_napi.cpp` (Huawei's
VPN sample). They are development references only — nothing under them is
compiled into the app, and the whole set can be deleted.

## Licensing

WGate is licensed under the GNU General Public License, version 3 or later; the
full text is `LICENSE`. The port descends from WG Tunnel — the Android app by
Zane Schepke, MIT — so `THIRD-PARTY-NOTICES.md` carries that project's copyright
line and permission notice, together with the notices of everything else that
ships in the package: Monocypher (vendored under its dual BSD-2-Clause / CC0
licence, `entry/src/main/cpp/wg/third_party/`), the Inter typeface (SIL OFL 1.1),
Material Symbols (Apache-2.0) and Zig (MIT, build time only). WireGuard is a
registered trademark of Jason A. Donenfeld; the name is used here only to say
what protocol the app speaks.
