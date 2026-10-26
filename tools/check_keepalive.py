"""Static audit of the keep-alive path.

The behaviour itself lives on a phone that can keep a VPN up while the screen is
off, so what is checked here is the wiring: that the process asks for background
time when it goes away, gives it back when it returns, that the extension reacts
to a network handover immediately rather than on the next timer tick, and that
nothing claims a continuous task the platform would refuse.

The engine half is checked too, because both ways an idle tunnel dies are
invisible to the ArkTS side: a persistent keepalive gated on something other than
its own interval, and a failed socket recycle that keeps the old fd. The behaviour
behind those two is covered at runtime by tools/keepalive_probe.c and
tools/recycle_probe.c.

Run: python tools/check_keepalive.py
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'entry/src/main/module.json5'
ABILITY = ROOT / 'entry/src/main/ets/entryability/EntryAbility.ets'
KEEPALIVE = ROOT / 'entry/src/main/ets/service/KeepAlive.ets'
EXTENSION = ROOT / 'entry/src/main/ets/vpnext/WgVpnExtAbility.ets'
GUARD_FILE = ROOT / 'entry/src/main/ets/service/TunnelGuard.ets'
BRIDGE = ROOT / 'entry/src/main/ets/util/StatusBridge.ets'
TRAY = ROOT / 'entry/src/main/ets/service/PcTray.ets'
COMMANDS = ROOT / 'entry/src/main/ets/service/TunnelCommands.ets'
RECOVERY = ROOT / 'entry/src/main/ets/pages/TunnelRecovery.ets'
ENGINE = ROOT / 'entry/src/main/cpp/wg/wg_engine.c'
SUITE = ROOT / 'tools/run_host_tests.ps1'
ICONS = ROOT / 'tools/make_tray_icons.py'
NOTICE = ROOT / 'entry/src/main/ets/service/TunnelNotice.ets'
INDEX = ROOT / 'entry/src/main/ets/pages/Index.ets'
STATUS = ROOT / 'entry/src/main/ets/service/EngineStatus.ets'
LOGS = ROOT / 'entry/src/main/ets/pages/Logs.ets'

BACKUP = ROOT / 'entry/src/main/ets/pages/Backup.ets'
SUPPORT = ROOT / 'entry/src/main/ets/view/SupportView.ets'
NAV = ROOT / 'entry/src/main/ets/components/BottomNav.ets'

checks = 0
failures = []


def check(name: str, ok: bool, detail: str = '') -> None:
    global checks
    checks += 1
    if not ok:
        failures.append(f'{name}{" — " + detail if detail else ""}')


def body(text: str, method: str) -> str:
    """Returns a method body: from its declaration to the matching brace.

    Matches the declaration rather than the first mention. onCreate() calls
    watchNetwork() a hundred lines before watchNetwork() is defined, and a call
    site handed back the wrong block - which is why five of these checks were
    failing on correct code.
    """
    match = re.search(r'\b' + re.escape(method) + r'\s*\([^)]*\)\s*(?::\s*[^{;]+)?\{', text)
    if match is None:
        return ''
    brace = match.end() - 1
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[match.start():i + 1]
    return text[match.start():]


manifest = MANIFEST.read_text(encoding='utf-8')
ability = ABILITY.read_text(encoding='utf-8')
keepalive = KEEPALIVE.read_text(encoding='utf-8')
extension = EXTENSION.read_text(encoding='utf-8')
engine = ENGINE.read_text(encoding='utf-8')
guard = GUARD_FILE.read_text(encoding='utf-8')
bridge = BRIDGE.read_text(encoding='utf-8')
recovery = RECOVERY.read_text(encoding='utf-8')
suite = SUITE.read_text(encoding='utf-8')
tray = TRAY.read_text(encoding='utf-8')
commands = COMMANDS.read_text(encoding='utf-8')
notice = NOTICE.read_text(encoding='utf-8')
index = INDEX.read_text(encoding='utf-8')
engine_status = STATUS.read_text(encoding='utf-8')
logs = LOGS.read_text(encoding='utf-8')
support = SUPPORT.read_text(encoding='utf-8')
nav = NAV.read_text(encoding='utf-8')
backup = BACKUP.read_text(encoding='utf-8')

# 1. The manifest must not advertise a background mode the code never requests.
check('the manifest declares no backgroundModes (VPN needs none)',
      '"backgroundModes"' not in manifest)

# 2. A continuous task is not available to this kind of app; asking for one
#    would fail at runtime, so the code must not call it.
check('no continuous-task call anywhere',
      'startBackgroundRunning' not in keepalive and 'startBackgroundRunning' not in ability)

# 3. The transient task is requested on the way out and released on the way back.
check('KeepAlive requests a transient task',
      'requestSuspendDelay(' in keepalive)
check('KeepAlive releases the transient task',
      'cancelSuspendDelay(' in keepalive)
check('a second request is a no-op (the quota is daily)',
      re.search(r'if \(KeepAlive\.requestId >= 0\) \{\s*return;', keepalive) is not None)
check('onBackground arms the grace period',
      'KeepAlive.arm()' in body(ability, 'onBackground'))
check('onForeground releases it',
      'KeepAlive.disarm()' in body(ability, 'onForeground'))
check('the grace period is not tied to the auto-tunnel rule',
      'SettingsStore.autoEnabled()' in body(ability, 'onBackground')
      and 'TunnelStore.desiredId()' in body(ability, 'onBackground'),
      'a plain tunnel needs the same grace period as an auto-tunnel rule')
check('expiry is recorded in the trace',
      'the grace period is ending' in keepalive)
# The platform calls the transient-task callback shortly BEFORE the period ends
# and the guide's own sample cancels the task inside it; letting it lapse counts
# against the daily quota and can get the process suspended.
check('the grace period is handed back when it ends',
      'cancelSuspendDelay(' in body(keepalive, 'arm'),
      'the callback must cancel the task, not just forget the id')

# 4. Extension resilience.
check('the extension watches the network itself',
      "net.on('netAvailable'" in body(extension, 'watchNetwork'))
check('a handover re-protects immediately',
      'this.tick()' in body(extension, 'watchNetwork'))
check('the watcher starts with the extension',
      'this.watchNetwork()' in body(extension, 'onCreate'))
check('the watcher is torn down with the extension',
      'this.unwatchNetwork()' in body(extension, 'shutdown'))
check('the watchdog delegates to a single tick()',
      'this.tick()' in body(extension, 'startWatchdog'))
check('no duplicate interval is created',
      'if (this.watchdog >= 0) {' in body(extension, 'startWatchdog'))
check('the interval is cleared on shutdown',
      'clearInterval(this.watchdog)' in body(extension, 'shutdown'))
check('the network connection is dropped on shutdown',
      'net.unregister(' in body(extension, 'unwatchNetwork'))
# The app process is frozen a few minutes into the background, so the extension
# process - the one the platform keeps alive while the tun device exists - has to
# own the recovery of a tunnel that stopped making progress.
check('the extension revives a stuck tunnel',
      'this.nudgeIfStuck(status)' in body(extension, 'tick'))
check('a tunnel that is up is left alone',
      "status.state === 'up'" in body(extension, 'nudgeIfStuck'))
check('the nudge asks the engine, not the system',
      'forceHandshake()' in body(extension, 'nudgeIfStuck'))
check('the nudge is rate limited',
      'NUDGE_MS' in body(extension, 'nudgeIfStuck'))
# A process the system starts again on its own can arrive without parameters;
# the desired id is the durable record of what the user wanted.
check('a start without a tunnel restores the wanted one',
      'this.wantWithDesiredTunnel(want)' in body(extension, 'onCreate'))
check('the restore only fills in a missing tunnel',
      'TunnelStore.desiredId()' in body(extension, 'wantWithDesiredTunnel')
      and 'tunnelFromWant(want) !== null' in body(extension, 'wantWithDesiredTunnel'))
# The snapshot is the only liveness signal across the two processes, and the
# reader is on a one-second timer in another process: a half-written file parses
# as nothing, which the guard would read as a dead tunnel.
check('the snapshot is replaced atomically',
      'renameSync(' in body(bridge, 'publish'),
      'publish must stage the JSON and rename it into place')
# A reconnect reuses the extension instance, so the tunnel id alone cannot tell
# a fresh snapshot from one left over from the previous session.
check('the snapshot carries the session it belongs to',
      'session:' in body(extension, 'publishStatus'))

# 5. The extension must not read the manifest mode that no longer exists.
document = json.loads(manifest.replace('//', '#') if False else re.sub(r'//[^\n]*', '', manifest))
ability_entries = document['module']['abilities']
check('the entry ability is declared once', len(ability_entries) == 1)
check('the VPN extension is declared as type vpn',
      document['module']['extensionAbilities'][0]['type'] == 'vpn')

# 6. The engine has to hold an idle tunnel up by itself. A persistent keepalive
#    is a message about the session being alive, so the only thing that may
#    decide it is the keepalive interval: gating it on `now - last_send_ms` looks
#    like a session-age bound and is not one, because last_send_ms stays 0 until
#    the first transport packet while `now` counts from boot.
keepalive_test = engine[engine.find('p->keepalive > 0'):]
keepalive_test = keepalive_test[:keepalive_test.find('{')]
check('the persistent keepalive is not gated on the last send time',
      keepalive_test != '' and 'WG_REJECT_AFTER_MS' not in keepalive_test,
      'an idle tunnel would never send one')

# 7. A recycle that fails must hand the tunnel back to the retry branch in
#    engine_tick(), which only runs while udp_fd is bad; keeping the old fd
#    leaves every peer unresolved with no timer left to notice.
recycle = body(engine, 'recycle_socket')
check('a failed socket recycle releases the socket',
      'g_eng.udp_fd = WG_BAD_SOCK;' in recycle)
check('a failed socket recycle schedules the retry',
      'next_socket_retry_ms' in recycle)

# 7b. The two direction counters have to match what the screens call them. A
#     packet read from the tun device is one this device sends, so it is
#     transmitted, not received -- the increments used to be the other way round
#     and every traffic figure was mirrored.
tun_read = body(engine, 'on_tun_read')
check('the send direction is counted as transmitted',
      'g_eng.tx_bytes += len;' in tun_read and 'g_eng.rx_bytes += len;' not in tun_read)
check('inbound plaintext is counted as received',
      'g_eng.rx_bytes += plen;' in engine and 'g_eng.tx_bytes += plen;' not in engine)

# 9. The trace has to say which side of the pair a drop belongs to. The
#    extension runs in its own process (the platform does that for every
#    ExtensionAbility type), so "the tun died while the app was in the
#    background" is only decidable if both processes stamp their lifecycle into
#    the same file: the app when it leaves and returns to the screen, the
#    extension when it is created and when the system tears it down.
check('backgrounding is recorded in the trace',
      'app: background' in body(ability, 'onBackground'))
check('returning to the screen is recorded in the trace',
      'app: foreground' in body(ability, 'onForeground'))
check('the extension records being created',
      'extension onCreate' in body(extension, 'onCreate'))
check('the extension records being torn down',
      'extension onDestroy' in body(extension, 'onDestroy'))
check('the extension runs in its own process by omission',
      'process' not in document['module']['extensionAbilities'][0],
      'module.json5 only accepts "process" for type embeddedUI')
# The system hands the same instance a second tunnel without a new onCreate, so
# the watchdog bookkeeping has to restart with the connection. A device trace
# showed "still no handshake after 20000 ms" one tick after a reconnect that had
# opened the engine two seconds earlier, because startedAt still belonged to the
# previous session.
connect_body = body(extension, 'connect')
check('a reconnect starts the handshake clock over',
      'this.startedAt = Date.now();' in connect_body)
check('a reconnect clears the handshake flags',
      'this.handshakeSeen = false;' in connect_body and 'this.handshakeWarned = false;' in connect_body)
check('a reconnect forgets the protected socket',
      'this.protectedFd = -1;' in connect_body)
# The snapshot reports udpFd 0 before the engine has a socket, and fd 0 is stdin:
# protect(0) answers 2203004, which showed up twice in a device trace.
protect_body = body(extension, 'protectTransportSocket')
check('fd 0 is never handed to protect()',
      'fd <= 0' in protect_body, 'the pre-open snapshot reports 0, and 2203004 follows')

# 10. The guard is the only thing that can put a tunnel back after the system
#     takes the extension away, and it must not become a way to start tunnels
#     nobody asked for: it may only act while the desired id is set, it must wait
#     for silence rather than a single missed snapshot, and it has to stop.
check('the tunnel guard is started with the app',
      'TunnelGuard.start()' in body(ability, 'onCreate'))
check('the guard only revives a tunnel that is still wanted',
      'TunnelStore.desiredId()' in body(guard, 'check'))
check('the guard needs silence, not one missed snapshot',
      'TunnelGuard.silent < needed' in body(guard, 'check'))
check('the recovery delay decides how long the silence must last',
      'SettingsStore.recoveryDelay()' in body(guard, 'check'))
check('the seamless recovery switch can turn the guard off',
      'SettingsStore.seamlessRecovery()' in body(guard, 'check'))
check('the recovery screen does not promise what the app cannot do',
      'This switch only decides whether that happens while the VPN stays up'
      not in recovery)
check('the guard retries through the system, not the engine',
      'startVpnExtensionAbility' in body(guard, 'restart'))
check('the guard gives up instead of looping',
      'MAX_ATTEMPTS' in body(guard, 'check'))
check('the guard records why it restarted',
      'the tunnel went silent' in body(guard, 'restart'))
# A frozen UI process is indistinguishable from a healthy one in the trace unless
# the guard says so out loud, and that is the one question a device report leaves
# open: was the app still running when the tunnel died?
check('the guard heartbeats while the tunnel publishes',
      'the tunnel is still publishing' in body(guard, 'check') and 'HEARTBEAT_CHECKS' in guard)

# 11. On a desktop the app is not a window that stays in front: it is an icon in
#     the system tray, and that icon is the only thing telling a PC user whether
#     the tunnel is up while the window is closed. Three things have to hold or
#     the feature is worse than absent: it must ask the shell whether the surface
#     exists at all (a phone answers no and must not be disturbed), it must not be
#     torn down with the window, and it may not flood an API that rejects
#     repeated calls.
check('the tray is added from the ability window stage',
      'PcTray.attach(this.context)' in body(ability, 'onWindowStageCreate'))
check('the tray only appears where the system has one',
      'isStatusBarCapabilitySupported' in body(tray, 'attach'))
check('the tray icon is removed with the ability',
      'PcTray.detach()' in body(ability, 'onDestroy'))
check('the tray survives the window being destroyed',
      'detach' not in body(ability, 'onWindowStageDestroy'))
check('a click on the tray icon opens the window',
      "statusBarManager.on('statusBarIconClick'" in body(tray, 'installListeners')
      and 'startAbility' in body(tray, 'openWindow'))
check('the tray menu can toggle the tunnel',
      'toggleTunnel(' in body(tray, 'onMenu'))
check('the tray and the launcher shortcut share one toggle',
      'toggleTunnelCommand(' in body(ability, 'quickAction')
      and 'export function toggleTunnel' in commands)
check('tray updates are rate limited',
      'MIN_UPDATE_MS' in body(tray, 'sync'))
check('the tray reports the tunnel state',
      'updateStatusBarHoverTips' in body(tray, 'sync'))
# A tray icon that vanishes with the window is useless, so a desktop close has
# to leave the app running -- but only where there is a tray, and only while
# it holds one, or a phone would stop closing.
check('the close puts the window aside instead of hiding it',
      'minimize()' in body(ability, 'hideWindow'))
check('starting the ability again shows the window',
      'this.raiseWindow()' in body(ability, 'onNewWant')
      and '.show()' in body(ability, 'raiseWindow'))
# The tray menu leaves "quit" to the shell's own item: a second 退出 of our own
# next to it is a duplicate, and the shell's one is the documented exit path
# (the platform stops the VPN when the app that started it goes away).
check('the tray menu leaves quitting to the shell',
      "title: '退出'" not in body(tray, 'menu')
      and 'MENU_QUIT' not in tray and 'terminateSelf' not in tray)
check('the shell exit is not intercepted',
      'onPrepareToTerminate():' not in ability
      and 'onPrepareToTerminateAsync():' not in ability)
# onPrepareToTerminate is not consulted for every close path on a desktop, so
# the main window's own close event has to be caught as well.
watch_close = body(ability, 'watchCloseButton')
check('the close button is caught on the window itself',
      "'windowWillClose'" in watch_close
      and 'this.watchCloseButton(windowStage)' in body(ability, 'onWindowStageCreate'))
check('a close without a tray still quits',
      'PcTray.isActive()' in watch_close and 'Promise.resolve(false)' in watch_close)
check('the tray icon is drawn from the app icon',
      ICONS.exists() and 'app_icon.png' in ICONS.read_text(encoding='utf-8'))

# 8. The ongoing notification is the one piece of UI that has to outlive the app
#    window: while the screen is off only the extension process is still being
#    scheduled, so it has to be the publisher, and the snapshot has to say so.
check('the extension publishes the shade',
      'TunnelNotice.compose(' in body(extension, 'publishStatus')
      and 'TunnelNotice.show(' in body(extension, 'publishStatus'))
check('the snapshot says who published it',
      'notified' in bridge and 'notified: false' in body(extension, 'publishStatus'))
check('the app stays out while the extension publishes',
      'if (status.notified)' in body(index, 'updateNotification'))
check('the shade text comes from the switches',
      all(k in notice for k in
          ("'live'", "'origin'", "'transfer'", "'recovery'", "'failure_tint'")))
check('the old hardcoded sentences are gone',
      'Connected · ' not in index and 'Establishing the tunnel…' not in index)
check('the extension takes the shade down with the tunnel',
      'TunnelNotice.clear()' in body(extension, 'shutdown'))
# The platform cannot tint a notification (`notificationRequest.color` is
# documented as "Not supported currently"), so the failure state is a glyph.
check('the failure mark is a glyph, not a colour',
      '⚠ ' in notice and 'color:' not in notice)
check('the shade is only republished when the text changes',
      'lastKey' in body(notice, 'show'))
# 8b. "Connected" has to mean connected. The engine's own rule keeps a session
#     "usable" for three minutes after the last handshake, so with the radio off
#     the tunnel used to show 已连接 while nothing could leave the device.
check('a tunnel with no network is not shown as connected',
      "'offline'" in body(extension, 'tick')
      and "status.state = 'offline';" in body(extension, 'tick'))
check('the offline state needs a network probe',
      'getAllNetsSync()' in body(extension, 'hasNetwork')
      and 'BEARER_WIFI' in body(extension, 'hasNetwork'))
check('an offline tunnel still counts as running',
      "'offline'" in body(engine_status, 'isRunning'))
check('the shade says it is waiting for a network',
      "'offline'" in body(notice, 'composeFor'))
# 8c. "Show recovery" used to rename the state line only when the engine happened
#     to be in `retry`, which a single-peer tunnel reaches only after 90 s of
#     failed handshakes. It now reacts to the one thing that distinguishes a
#     reconnection from a first connection: a session that already existed.
check('the recovery line needs a session that already worked',
      'handshakeAgeMs > 0' in body(notice, 'compose')
      and 'peersUp === 0' in body(notice, 'compose'))
check('the recovery line is the switch\'s own',
      "SettingsStore.notification('recovery')" in body(notice, 'composeFor'))
check('the recovery line does not republish every tick',
      '5000' in body(notice, 'composeFor') and 'duration(' in body(notice, 'composeFor'))
# The extension writes the shade, so the language has to be resolved in that
# process too: `Tr` starts in English and only the UI pages ever set the locale,
# which is how a Chinese phone ended up showing "Connected / via Cellular".
check('the extension speaks the user\'s language',
      'Tr.setLocale(' in body(extension, 'onCreate'))
# Preferences are per process: without opening the store here, every switch read
# in this process silently answered with its default, so the five notification
# settings (and the language) only ever worked in the window that owns the UI.
check('the extension opens the preferences',
      'SettingsStore.init(this.context)' in body(extension, 'onCreate'))
# The tray menu and its hover text were written as Chinese literals, which stayed
# Chinese on an English device; both now go through the catalogue.
check('the tray is translated',
      'Tr.t(' in body(tray, 'menu') and 'Tr.t(' in body(tray, 'tips'))
# The tray menu and its hover text used to be Chinese literals, which stayed
# Chinese on an English device. Comments may mention Chinese; code may not.
check('the tray has no hardcoded Chinese',
      not [line for line in tray.splitlines()
           if not line.strip().startswith(('//', '*', '/*'))
           and any('\u4e00' <= ch <= '\u9fff' for ch in line)])

# 9. Both behaviours above are proved at runtime; the suite has to run them.
check('the keepalive probe runs in the host suite', 'keepalive_probe' in suite)
check('the recycle probe runs in the host suite', 'recycle_probe' in suite)

# 10. The log page. It used to show a second block fed by libwgcore's ring buffer
#     from the app process, where no engine is ever open, so the block was always
#     empty; worse, reading that module threw and aborted the button handlers, so
#     Refresh and Clear silently did nothing.
check('the log page does not read the engine',
      'wgcore.logs(' not in logs and 'wgcore.clearLogs(' not in logs)
check('the log page has no always-empty engine block',
      "'no engine lines yet'" not in logs)
check('the log page exports the trace to a file',
      'DocumentViewPicker' in body(logs, 'exportTrace') and 'writeSync' in body(logs, 'exportTrace'))
check('the log page confirms the exported size',
      'statSync(' in body(logs, 'exportTrace') and 'Diag.write(' in body(logs, 'exportTrace'))
check('the log page clears what it shows',
      'Diag.clear()' in body(logs, 'clearTrace') and 'this.reload()' in body(logs, 'clearTrace'))

# 11. Backup and restore. A wg-quick file has to go through the wg-quick parser:
#     feeding its text to WgTunnel.from() stored an empty tunnel, because that
#     function only reads the storage shape. The export is the same flat records
#     the store keeps, wrapped in an envelope.
check('the backup is the storage record',
      'JSON.stringify(tunnels[i])' in body(backup, 'envelope'))
check('the backup is wrapped in an envelope',
      '"app":"wg-tunnel"' in body(backup, 'envelope'))
check('a wg-quick file is parsed as wg-quick',
      'parseWgQuick(' in body(backup, 'importText'))
check('a record that cannot connect is skipped',
      'this.usable(' in body(backup, 'importText') and 'tunnel.privateKey.length' in body(backup, 'usable'))
check('a restored record gets an id when the file has none',
      'tunnel.id.length === 0' in body(backup, 'importText'))
check('the backup message goes through the catalogue',
      'Tr.tf(' in body(backup, 'importText') and 'Tr.tf(' in body(backup, 'exportToFile'))
check('the backup reports what it wrote',
      'statSync(' in body(backup, 'exportToFile') and 'Diag.write(' in body(backup, 'exportToFile'))
check('the restore reads the picked file through its descriptor',
      'readTextSync(' not in body(backup, 'restoreFromFile')
      and 'fileIo.readSync(' in body(backup, 'restoreFromFile')
      and 'TextDecoder' in body(backup, 'restoreFromFile'))
check('the exported file is named in local time',
      'toISOString(' not in body(backup, 'stamp') and 'getHours()' in body(backup, 'stamp'))

# 12. The question-mark icon. The reference app draws one: the Support tab, with
#     Icons.Outlined.QuestionMark / Icons.Filled.QuestionMark. No row on any screen
#     uses it, and a hand-drawn ring around the glyph was our invention, so the
#     asset is the Material "question_mark" glyph and only the tab may point at it.
APP = ROOT / 'entry/src/main/ets'
source_text = '\n'.join(
    f.read_text(encoding='utf-8')
    for f in sorted(APP.rglob('*.ets')))
check('only the support tab uses the question mark',
      "'app.media.ic_question'" in nav
      and 'ic_question' not in support
      and source_text.count('ic_question') == 2)
question_asset = (ROOT / 'entry/src/main/resources/base/media/ic_question.svg').read_text(encoding='utf-8')
check('the question mark is the Material glyph, not a drawn ring',
      'question' not in question_asset.lower()
      and 'a10 10 0 1 0 0 20' not in question_asset
      and question_asset.count('fill="#FF000000"') == 1)
check('the licences row uses the reference icon',
      "'app.media.ic_balance'" in support)
check('the support page keeps no borrowed tab icons',
      "'app.media.ic_bolt'" not in support
      and "'app.media.ic_warning_amber'" not in support)

# 13. The name. The product is Wedge; "WG Tunnel" is the upstream project this
#     port comes from, and a stray literal of it in the UI would claim the app is
#     something else. The catalogue is renamed from the same source key, because
#     the key *is* the English sentence: rename one half and the lookup stops
#     matching and the row silently falls back to English.
APP_SCOPE = json.loads((ROOT / 'AppScope/resources/base/element/string.json')
                       .read_text(encoding='utf-8'))
app_strings = {row['name']: row['value'] for row in APP_SCOPE['string']}
check('the app is called WGate', app_strings.get('app_name') == 'WGate')
app_json = (ROOT / 'AppScope/app.json5').read_text(encoding='utf-8')
check('the bundle is named after the app without the word tunnel',
      '"bundleName": "com.wgate.app"' in app_json
      and '"vendor": "wgate"' in app_json
      and 'tunnel' not in app_json.split('bundleName')[1].split('\n')[0])
# The licence page is allowed to name the upstream project: attributing it is
# the point. Everywhere else the earlier names must be gone.
brand_text = '\n'.join(
    f.read_text(encoding='utf-8')
    for f in sorted(APP.rglob('*.ets'))
    if f.name not in ('License.ets', 'Catalog.ets'))
check('no UI source still says an earlier name',
      'WG Tunnel' not in brand_text and 'Wedge' not in brand_text)
catalogue_text = (ROOT / 'entry/src/main/ets/i18n/Catalog.ets').read_text(encoding='utf-8')


def is_attribution(row: str) -> bool:
    """True for the rows that are allowed to name the upstream project."""
    return (row.startswith('WG Tunnel (') or row.startswith('WG Tunnel\uff08')
            or row.startswith('WGate is a port of') or row.startswith('WGate \u662f WG Tunnel'))


stray = [row for row in catalogue_text.split('\u0001')
         if 'WG Tunnel' in row and not is_attribution(row)]
check('the catalogue was renamed with it',
      'Wedge' not in catalogue_text and not stray)
check('the notification and the tray say the new name',
      '`WGate \u00b7 ' in notice and "title: 'WGate'" in tray)
check('the old bundle name is gone',
      'com.wgtunnel.harmony' not in source_text
      and 'com.wgtunnel.harmony' not in manifest)

# 14. The icon. The launcher reads the app-level copy under AppScope and the tray
#     derivation reads the module-level copy, so the two have to be the same
#     drawing -- the first run of tools/make_app_icon.py updated only the module
#     copy and the launcher kept showing the old mark.
launcher_icon = ROOT / 'AppScope/resources/base/media/app_icon.png'
tray_source = ROOT / 'entry/src/main/resources/base/media/app_icon.png'
check('the launcher icon and the tray source are one drawing',
      launcher_icon.read_bytes() == tray_source.read_bytes())
check('the tray icons come from the app icon',
      'app_icon.png' in (ROOT / 'tools/make_tray_icons.py').read_text(encoding='utf-8'))
check('the icon is generated, not hand-edited',
      (ROOT / 'tools/make_app_icon.py').exists()
      and 'Mark box, in final pixels' in (ROOT / 'tools/make_app_icon.py').read_text(encoding='utf-8'))

# 15. The support page, the privacy policy and the first-run defaults.
#     The support tab used to be a mirror of the upstream project's screen: guide
#     rows, a website, a chat room and a translation portal, all of them links
#     out. It now carries what this app owns, plus the two ways out that belong
#     to it — where the source is and how to write to the author — and nothing
#     else: no website, no chat room, no translation portal. The addresses are
#     named constants so a row cannot drift off to a dead link, and the privacy
#     policy is a page rather than a link so it keeps working offline. A fresh
#     install opens on Simplified Chinese and follows the system appearance.
PRIVACY = ROOT / 'entry/src/main/ets/pages/Privacy.ets'
privacy = PRIVACY.read_text(encoding='utf-8')
pages = json.loads((ROOT / 'entry/src/main/resources/base/profile/main_pages.json')
                   .read_text(encoding='utf-8'))
display = (ROOT / 'entry/src/main/ets/pages/Display.ets').read_text(encoding='utf-8')
language = (ROOT / 'entry/src/main/ets/pages/Language.ets').read_text(encoding='utf-8')
globals_text = (ROOT / 'entry/src/main/ets/pages/TunnelGlobals.ets').read_text(encoding='utf-8')
store = (ROOT / 'entry/src/main/ets/service/SettingsStore.ets').read_text(encoding='utf-8')
check('the support page links the source and the author, and nothing else',
      "const SOURCE_URL: string = 'https://github.com/simon2137/WGate'" in support
      and "const AUTHOR_MAIL: string = '273156878@qq.com'" in support
      and support.count('https://') == 1
      and "'mailto:' + AUTHOR_MAIL" in support
      and 'this.open(SOURCE_URL, SOURCE_URL)' in support and 'this.mail()' in support)
# A `mailto:` has to reach the mail client through `openLink`, not through a
# generic implicit want: a browser answers arbitrary URIs and turns the address
# into a web search. `canOpenLink` is deliberately not the gate — it answers
# from the link declarations an app publishes, and a phone with a working mail
# client reported "nothing can open this" because that client publishes none.
check('the support page opens links and copies when nothing can',
      'context.openLink(link)' in support
      and 'bundleManager.canOpenLink(' not in support
      and 'this.offer(fallback)' in support
      and 'pasteboard.MIMETYPE_TEXT_PLAIN' in support
      and "Tr.t('The address is on the clipboard')" in support
      and '"querySchemes"' not in manifest)
check('the support page drops the upstream rows',
      all(f"Tr.t('{label}')" not in support for label in
          ['Getting started', 'Troubleshooting', 'Donate', 'Documentation', 'App website',
           'Help translate the app', 'Join Matrix', 'Join Telegram']))
check('the privacy policy is a page in the app',
      'pages/Privacy' in pages['src'] and PRIVACY.exists()
      and "router.pushUrl({ url: 'pages/Privacy' })" in support)
check('the privacy page says what it has to',
      all(needle in privacy for needle in
          ['private preferences', 'startup trace', 'permissions', 'advertising SDK'])
      and 'https://' not in privacy)
check('a fresh install opens on Simplified Chinese',
      "SettingsStore.get('language', 'zh_CN')" in store)
check('a fresh install follows the system appearance',
      "SettingsStore.get('theme', 'automatic')" in store)
check('following the system leads the theme list',
      display.index("value: 'automatic'") < display.index("value: 'dark'")
      and "'dynamic'" not in display)
check('the explanatory footers are gone',
      'Dark, Darker, AMOLED and Light paint' not in display
      and 'translations come from the reference app' not in language)
check('keepalive is left untranslated',
      'keepalive' in globals_text
      and "Tr.t('keepalive')" not in globals_text
      and "Tr.t('Keepalive')" not in globals_text)

# --- the licence page and the repository notices -----------------------------
# The port descends from an MIT project, so its copyright line and permission
# notice have to travel with the package; the app's own licence is GPL-3.0 and
# the repository has to carry that text verbatim.
license_text = (ROOT / 'entry/src/main/ets/pages/License.ets').read_text(encoding='utf-8')
license_file = ROOT / 'LICENSE'
notices_file = ROOT / 'THIRD-PARTY-NOTICES.md'
notices = notices_file.read_text(encoding='utf-8') if notices_file.exists() else ''
check('the licence page names the upstream project',
      'WG Tunnel (the Android app this port started from)' in license_text
      and "'MIT'" in license_text)
check('the licence page carries the upstream copyright and notice',
      'Zane Schepke' in license_text
      and 'The above copyright notice and this permission notice shall be included in all' in license_text)
check('the licence page says in prose that the app is a port',
      'WGate is a port of WG Tunnel' in license_text
      and 'Text(PORT_NOTE)' in license_text)
check('the licence page claims no licence it cannot back',
      'GPL-2.0' not in license_text and 'BLAKE2s reference implementation' not in license_text)
check('the repository carries the GPL-3.0 text',
      license_file.exists()
      and 'GNU GENERAL PUBLIC LICENSE' in license_file.read_text(encoding='utf-8')
      and 'Version 3, 29 June 2007' in license_file.read_text(encoding='utf-8'))
check('the notices file names every shipped component',
      all(needle in notices for needle in
          ['WG Tunnel', 'Zane Schepke', 'Monocypher', 'Loup Vaillant', 'Inter 4.0',
           'Material Symbols', 'Apache License', 'Zig', 'HarmonyOS SDK']))
check('the notices file is generated, not hand-written',
      (ROOT / 'tools/make_notices.py').exists()
      and 'SHOULD NOT BE EDITED' not in notices)

# 16. A row whose body opens another page has to look like it does. Beside a
#     switch the chevron is the only thing saying so: the auto-tunnel network
#     rows both toggle and open a page, and with the switch alone the page was
#     never found. `tools/check_row_affordance.py` scans every row in the app for
#     the same shape.
auto = (ROOT / 'entry/src/main/ets/view/AutoTunnelView.ets').read_text(encoding='utf-8')
row = (ROOT / 'entry/src/main/ets/components/SurfaceRow.ets').read_text(encoding='utf-8')
check('a switch row that opens a page still shows a chevron',
      'this.hasSwitch && this.chevron' in row
      and auto.count('chevron: true') == 3)

# 18. The ongoing notification is updated for as long as the tunnel carries
#     traffic, and the platform replays the sound and the vibration on every
#     update unless the request says otherwise: an update every two seconds rang
#     and buzzed every two seconds. `isAlertOnce` is what stops that; the payload
#     is also compared with what is already in the shade, and the transfer
#     counters are rounded, so a quiet change does not republish at all.
notifier = (ROOT / 'entry/src/main/ets/service/Notifier.ets').read_text(encoding='utf-8')
notice = (ROOT / 'entry/src/main/ets/service/TunnelNotice.ets').read_text(encoding='utf-8')
check('the tunnel notification only alerts once',
      'isAlertOnce: true' in notifier
      and 'isOngoing: true' in notifier
      and 'if (title === Notifier.lastTitle && text === Notifier.lastText)' in notifier)
check('the transfer counters in the shade move in steps',
      'private static step(bytes: number): number' in notice
      and 'formatBytes(TunnelNotice.step(rxBytes))' in notice)

# 19. The privacy policy exists twice — `docs/PRIVACY.md` for the repository and
#     `docs/privacy.html` for the URL the store listing points at — and the two
#     drifted: the web copy went on advertising a per-app rule list months after
#     the feature was dropped from the app. Whatever the policy claims has to be
#     true of both copies, and neither may claim a per-app proxy: the app has no
#     such screen, only an `ExcludedApps` line it reads out of a wg-quick file.
policy_md = (ROOT / 'docs/PRIVACY.md').read_text(encoding='utf-8')
policy_html = (ROOT / 'docs/privacy.html').read_text(encoding='utf-8')
check('neither copy of the privacy policy claims a per-app proxy',
      '分应用' not in policy_md and '分应用' not in policy_html)
check('both copies of the privacy policy disclaim the upstream app',
      'WG Tunnel' in policy_md and 'WG Tunnel' in policy_html)

# 21. Adding a tunnel has two more doors than the old paste-only sheet: a file or
#     a zip of files, and `Create from scratch`, which is the same editor that
#     edits an existing tunnel. Both are one tap away from the sheet, and the
#     editor has to have a create path at all -- it used to return early when the
#     id was not in the store, so a new tunnel could never be saved.
home = (ROOT / 'entry/src/main/ets/pages/Home.ets').read_text(encoding='utf-8')
editor = (ROOT / 'entry/src/main/ets/pages/ConfigEdit.ets').read_text(encoding='utf-8')
check('the import sheet offers a file or zip',
      'importFromFileOrZip()' in home and 'importFromZip(' in home
      and "'.conf', '.wg', '.txt', '.zip'" in home)
check('the import sheet offers a blank tunnel',
      "router.pushUrl({ url: 'pages/ConfigEdit' })" in home)
check('the editor can create a tunnel, not only edit one',
      'this.creating' in editor and 'prepareNew(' in editor
      and 't.id = Date.now().toString()' in editor)
check('the editor refuses a tunnel without a private key or a peer',
      "Tr.t('A private key is required')" in editor and "Tr.t('Add at least one peer')" in editor)

if failures:
    print('keep-alive audit:')
    for item in failures:
        print(f'  FAIL  {item}')
    sys.exit(1)

print(f'{checks} checks, 0 failures')
