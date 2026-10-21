import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import wgcore from 'libwgcore.so';
import { WgTunnel, parseWgQuick } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { schemeFor, resolveTheme } from '../theme/Theme';
import { Diag } from '../util/Diag';
import { KeepAlive } from '../service/KeepAlive';
import { TunnelGuard } from '../service/TunnelGuard';
import { PcTray } from '../service/PcTray';
import { toggleTunnel as toggleTunnelCommand } from '../service/TunnelCommands';
import { withTimeout, isTimeout } from '../util/Async';

const TAG: string = 'WgTunnel';
const ACTION_TOGGLE: string = 'com.wgate.app.action.TOGGLE_TUNNEL';
const EXT_ABILITY: string = 'WgVpnExtAbility';

function param(params: Record<string, Object> | undefined, key: string): string {
  if (params === undefined) {
    return '';
  }
  const value: Object | undefined = params[key];
  if (value === undefined || value === null) {
    return '';
  }
  return value.toString();
}

export default class EntryAbility extends UIAbility {
  // Kept so the window can be put aside and brought back: the desktop tray
  // minimises it instead of letting the close end the app, and its 打开主界面
  // entry has to show the window again (see watchCloseButton below).
  private stage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'EntryAbility onCreate');
    TunnelStore.init(this.context);
    Diag.init(this.context);
    // Watches the published snapshot and rebuilds a tunnel the system took away
    // while this process is still schedulable (see service/TunnelGuard.ets).
    TunnelGuard.start();
    if (this.importTunnel(want)) {
      return;
    }
    if (want.action === ACTION_TOGGLE) {
      this.quickAction();
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // The window may be minimised (the tray put it aside) or behind other
    // windows; starting the ability again is a request to look at it.
    this.raiseWindow();
    if (this.importTunnel(want)) {
      return;
    }
    if (want.action === ACTION_TOGGLE) {
      this.quickAction();
    }
  }

  /**
   * Imports a wg-quick configuration handed over by another application
   * through Want parameters:
   *   wgquick  the whole [Interface]/[Peer] text
   *   name     optional tunnel name
   *   connect  "true" to bring the imported tunnel up right away
   *
   * Returns true when the want carried a configuration.
   */
  private importTunnel(want: Want): boolean {
    const text: string = param(want.parameters, 'wgquick');
    if (text.length === 0) {
      hilog.info(0x0000, TAG, 'import: no configuration in the want');
      return false;
    }
    hilog.info(0x0000, TAG, `import: ${text.length} bytes of configuration`);
    const name: string = param(want.parameters, 'name');
    const parsed = parseWgQuick(text, name.length > 0 ? name : 'Imported tunnel');
    if (parsed === null) {
      hilog.warn(0x0000, TAG, 'import: configuration not usable');
      return true;
    }
    parsed.publicKey = wgcore.publicKeyFrom(parsed.privateKey) as string;
    // Importing the same configuration twice should update the existing tunnel
    // instead of piling up duplicates.
    const same = TunnelStore.list().find((t: WgTunnel) =>
      t.privateKey === parsed.privateKey && t.endpoint() === parsed.endpoint());
    if (same !== undefined) {
      parsed.id = same.id;
      hilog.info(0x0000, TAG, `import: updating ${same.id}`);
    }
    TunnelStore.save(parsed);
    hilog.info(0x0000, TAG, `import: saved ${parsed.id} with ${parsed.peers.length} peer(s)`);
    if (param(want.parameters, 'connect') === 'true') {
      this.connect(parsed);
    }
    return true;
  }

  private connect(tunnel: WgTunnel): void {
    const want: Want = {
      bundleName: 'com.wgate.app',
      abilityName: EXT_ABILITY,
      parameters: { 'tunnel': JSON.stringify(tunnel) }
    };
    TunnelStore.setDesired(tunnel.id);
    withTimeout(vpnExtension.startVpnExtensionAbility(want), 20000, 'start')
      .catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, `import connect failed: ${err.code} ${err.message}`);
        TunnelStore.setLastError(isTimeout(err) ?
          'The system did not confirm the VPN request' : `Could not start the VPN (${err.code})`);
      });
  }

  /**
   * Quick action handler: brings the last used tunnel up, or takes the active
   * one down.  The launcher shortcut and the desktop tray menu both end up here
   * (see service/TunnelCommands.ets), so the two surfaces cannot disagree about
   * which tunnel they act on.
   */
  private quickAction(): void {
    toggleTunnelCommand('launcher shortcut');
  }

  /**
   * The title bar's close button, through the window rather than the ability.
   *
   * A desktop app that owns a tray icon stays alive when its window is closed:
   * otherwise the icon would disappear with the window and the tray would be
   * pointless.  This is done here, on the window, and deliberately *not* with
   * onPrepareToTerminate: that callback also covers the dock's and the tray's
   * own 退出 (the field test showed the shell appends one), so cancelling there
   * would make quitting impossible.  `windowWillClose` (since API 15) fires for
   * the close button only, and its promise decides: true cancels the close.
   */
  private watchCloseButton(stage: window.WindowStage): void {
    try {
      const win: window.Window = stage.getMainWindowSync();
      win.on('windowWillClose', (): Promise<boolean> => {
        if (!PcTray.isActive()) {
          // No tray means nothing would be left to come back to: close.
          return Promise.resolve(false);
        }
        Diag.write('app: the close button was used, staying in the tray');
        hilog.info(0x0000, TAG, 'windowWillClose: staying in the tray');
        PcTray.sync(true).catch((err: Error) => {
          hilog.warn(0x0000, TAG, `tray sync failed: ${err.message}`);
        });
        this.hideWindow();
        return Promise.resolve(true);
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'windowWillClose could not be registered');
      Diag.write('app: the close button could not be watched, closing will quit');
    }
  }

  private hideWindow(): void {
    const stage: window.WindowStage | null = this.stage;
    if (stage === null) {
      return;
    }
    try {
      stage.getMainWindowSync().minimize().catch((e: Error) => {
        hilog.warn(0x0000, TAG, `minimize failed: ${e.message}`);
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'minimize failed');
    }
  }

  private raiseWindow(): void {
    const stage: window.WindowStage | null = this.stage;
    if (stage === null) {
      return;
    }
    try {
      stage.getMainWindowSync().show().catch((e: Error) => {
        hilog.warn(0x0000, TAG, `show failed: ${e.message}`);
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'show failed');
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onDestroy');
    // The desktop tray is removed with the ability, not with the window: a PC
    // user closes the window and expects the icon to stay useful.
    PcTray.detach();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.stage = windowStage;
    // The close button has to leave the app running on a desktop (see the
    // method); on a phone the callback answers false and nothing changes.
    this.watchCloseButton(windowStage);

    windowStage.loadContent('pages/Home', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      const win = windowStage.getMainWindowSync();
      this.configureWindow(win);
      // Desktops (PC / 2-in-1) get an icon in the system tray: the shell keeps
      // it across the window being closed, so the tunnel stays visible and
      // controllable without a window (see service/PcTray.ets).
      PcTray.attach(this.context).catch((err: Error) => {
        hilog.warn(0x0000, TAG, `tray attach failed: ${err.message}`);
      });
    });
  }

  /**
   * Phone: draw behind the system bars in portrait.  Tablet and 2in1 windows
   * keep their own decoration, and 2in1 does not support the full screen
   * layout call at all, so the window is left as the system created it.
   */
  private configureWindow(win: window.Window): void {
    const type: string = deviceInfo.deviceType;
    // Paint the window and system bars with the palette that the resolved theme
    // will draw a moment later, so the bottom strips never clash with the app's
    // own background. The app resolves its theme (Store + resolveTheme) rather
    // than reading the device's dark/light setting directly, because an explicit
    // dark theme on a light system must still get dark bars. This runs before
    // the page applies the scheme, so the palette is derived here instead of
    // read from the active Palette.
    SettingsStore.init(this.context);
    const resolved: string = resolveTheme(SettingsStore.theme(), this.context);
    const barBg: string = schemeFor(resolved).background;
    const light: boolean = barBg.charAt(1) === 'F';
    const barFg: string = light ? '#17191B' : '#EAF2FB';
    try {
      win.setWindowBackgroundColor(barBg);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'setWindowBackgroundColor failed');
    }
    // Draw the app edge-to-edge: the window background fills the whole screen
    // behind the status bar and the gesture bar. ArkUI does not auto-avoid the
    // bars in window-full-screen mode, so the avoided height of each system bar
    // is published for the pages to inset their headers and the capsule.
    if (type === 'phone') {
      win.setWindowLayoutFullScreen(true).then(() => {
        try {
          const topAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          // getWindowAvoidArea reports the avoid areas in physical pixels, so they
          // are normalised to vp before the pages use them as padding (padding
          // numbers are in vp).  Log the raw values too, in case a real device
          // reports a non-standard cutout.
          const density: number = display.getDefaultDisplaySync().densityPixels;
          const topVp: number = Math.round(topAvoid.topRect.height / density);
          const bottomVp: number = Math.round(topAvoid.bottomRect.height / density);
          hilog.info(0x0000, TAG,
            `avoid rawTop=${topAvoid.topRect.height} rawBottom=${topAvoid.bottomRect.height} density=${density} -> top=${topVp} bottom=${bottomVp}`);
          AppStorage.setOrCreate('safe_top', topVp);
          AppStorage.setOrCreate('safe_bottom', bottomVp);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'getWindowAvoidArea failed');
        }
      }).catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'setWindowLayoutFullScreen failed: %{public}s', e.message);
      });
    }
    // Bars are transparent so the themed window background shows through: the
    // bottom then blends with the content instead of leaving a fixed-colour
    // strip wherever the phone reserves its gesture/navigation area.
    win.setWindowSystemBarProperties({
      statusBarContentColor: barFg,
      navigationBarContentColor: barFg,
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000'
    }).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'setWindowSystemBarProperties failed: %{public}s', e.message);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onForeground');
    // The window is visible again, so the process does not need the grace
    // period; giving it back keeps the daily quota for the next screen-off.
    KeepAlive.disarm();
    Diag.write('app: foreground');
    PcTray.sync(true).catch((err: Error) => {
      hilog.warn(0x0000, TAG, `tray sync failed: ${err.message}`);
    });
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onBackground');
    // The auto-tunnel watcher and the tunnel guard both live in this process and
    // the platform freezes a background process shortly after this callback. A
    // transient task keeps it schedulable long enough to notice the tunnel going
    // away and to ask for it again (see service/KeepAlive.ets for what the
    // platform does and does not allow). A tunnel that is up or wanted is reason
    // enough to ask for that window, whether or not the auto-tunnel rule is on.
    const expecting: boolean = TunnelStore.desiredId().length > 0 || TunnelStore.activeId().length > 0;
    if (SettingsStore.autoEnabled() || expecting) {
      KeepAlive.arm();
    }
    // Recorded so the trace shows when the app left the screen: a tunnel that
    // drops a few minutes later can then be lined up against this stamp instead
    // of being guessed at (the extension runs in its own process and keeps
    // writing to the same file; see module.json5).
    Diag.write(`app: background, grace ${KeepAlive.armed() ? 'armed' : 'off'}, ` +
      `tunnel ${expecting ? 'expected' : 'not expected'}`);
    PcTray.sync(true).catch((err: Error) => {
      hilog.warn(0x0000, TAG, `tray sync failed: ${err.message}`);
    });
  }
}

