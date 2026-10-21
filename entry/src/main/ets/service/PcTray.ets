import { common, Want } from '@kit.AbilityKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import statusBarManager from '@hms.pcService.statusBarManager';
import { Diag } from '../util/Diag';
import { TunnelStore } from './TunnelStore';
import { EngineStatus, isRunning, readStatus } from './EngineStatus';
import { toggleTunnel } from './TunnelCommands';
import { Tr } from '../i18n/Tr';

const DOMAIN: number = 0x0003;
const TAG: string = 'PcTray';

/** How often the icon is reconciled with the engine while the app runs. */
const REFRESH_MS: number = 15000;
/** The status bar refuses updates that arrive too often (1010710003). */
const MIN_UPDATE_MS: number = 5000;
/** Height of the left-click pop-up area, in vp.  The icon itself starts the app. */
const QUICK_HEIGHT: number = 1;

const MENU_TOGGLE: string = 'wg-tray-toggle';
const MENU_OPEN: string = 'wg-tray-open';
const BUNDLE: string = 'com.wgate.app';
const ABILITY: string = 'EntryAbility';
const MODULE: string = 'entry';

/**
 * Desktop tray (system status bar) presence for PC / 2-in-1 builds.
 *
 * The tray is a *system* surface: the icon, its hover text and its right-click
 * menu belong to the desktop shell, not to a window, so they survive the window
 * being closed and let a PC user see and toggle the tunnel without the app in
 * front.  Everything here is optional: a phone has no such surface, the module
 * reports that, and the app carries on exactly as before.
 *
 * Only the app process may hold the icon (the API accepts a UIAbilityContext or
 * a service/form extension context), so the state shown in the tray is as fresh
 * as the app process; once the platform freezes the app the tray keeps the last
 * known state instead of lying about a live one, and the trace says so.
 */
export class PcTray {
  private static context: common.Context | null = null;
  private static idleIcon: statusBarManager.StatusBarIcon | null = null;
  private static upIcon: statusBarManager.StatusBarIcon | null = null;
  private static timer: number = -1;
  private static signature: string = '';
  private static lastUpdate: number = 0;
  private static active: boolean = false;
  private static iconClick: ((event: emitter.EventData) => void) | null = null;
  private static menuClick: ((event: emitter.EventData) => void) | null = null;

  /**
   * Puts the icon into the desktop tray when the system has one.  Safe to call
   * on every window stage: it does nothing the second time.
   */
  static async attach(context: common.Context): Promise<void> {
    if (PcTray.active) {
      return;
    }
    try {
      const supported: boolean = await statusBarManager.isStatusBarCapabilitySupported(context);
      if (!supported) {
        Diag.write('pc tray: this system has no app tray, staying out');
        return;
      }
      PcTray.context = context;
      PcTray.idleIcon = await PcTray.buildIcon(context, false);
      PcTray.upIcon = await PcTray.buildIcon(context, true);
      PcTray.installListeners();
      statusBarManager.addToStatusBar(context, PcTray.item(false));
      PcTray.active = true;
      PcTray.signature = '';
      PcTray.lastUpdate = 0;
      Diag.write('pc tray: the icon is in the desktop tray');
      PcTray.timer = setInterval(() => {
        PcTray.sync(false).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, `refresh failed: ${err.message}`);
        });
      }, REFRESH_MS);
      await PcTray.sync(true);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, `attach failed: ${e.code} ${e.message}`);
      Diag.write(`pc tray: could not add the icon (${e.code})`);
      PcTray.active = false;
    }
  }

  /**
   * True while this process owns a tray icon, i.e. while the shell would keep
   * the app reachable after its window is gone.
   */
  static isActive(): boolean {
    return PcTray.active;
  }

  /**
   * Takes the icon away again.  Called when the ability is destroyed; the tray
   * deliberately outlives the window, so this is not tied to the window stage.
   */
  static detach(): void {
    if (!PcTray.active || PcTray.context === null) {
      return;
    }
    if (PcTray.timer >= 0) {
      clearInterval(PcTray.timer);
      PcTray.timer = -1;
    }
    try {
      if (PcTray.iconClick !== null) {
        statusBarManager.off('statusBarIconClick', PcTray.iconClick);
      }
      if (PcTray.menuClick !== null) {
        statusBarManager.off('rightMenuClick', PcTray.menuClick);
      }
      statusBarManager.removeFromStatusBar(PcTray.context);
      Diag.write('pc tray: the icon was removed');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, `detach failed: ${e.code} ${e.message}`);
    }
    PcTray.iconClick = null;
    PcTray.menuClick = null;
    PcTray.context = null;
    PcTray.idleIcon = null;
    PcTray.upIcon = null;
    PcTray.active = false;
    PcTray.signature = '';
  }

  /**
   * Pushes the current tunnel state into the tray.  Only a change is sent (the
   * system rejects a stream of updates), unless `force` is set.
   */
  static async sync(force: boolean): Promise<void> {
    const context: common.Context | null = PcTray.context;
    const idle: statusBarManager.StatusBarIcon | null = PcTray.idleIcon;
    const up: statusBarManager.StatusBarIcon | null = PcTray.upIcon;
    if (!PcTray.active || context === null || idle === null || up === null) {
      return;
    }
    const signature: string = PcTray.stateSignature();
    const now: number = Date.now();
    if (!force) {
      if (signature === PcTray.signature) {
        return;
      }
      if (now - PcTray.lastUpdate < MIN_UPDATE_MS) {
        return;
      }
    }
    const connected: boolean = PcTray.connected();
    try {
      statusBarManager.updateStatusBarIcon(context, connected ? up : idle);
      statusBarManager.updateStatusBarMenu(context, [PcTray.menu(connected)]);
      await statusBarManager.updateStatusBarHoverTips(context, PcTray.tips());
      PcTray.signature = signature;
      PcTray.lastUpdate = now;
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, `sync failed: ${e.code} ${e.message}`);
    }
  }

  private static installListeners(): void {
    PcTray.iconClick = (event: emitter.EventData) => {
      Diag.write('pc tray: the icon was clicked');
      PcTray.openWindow();
    };
    PcTray.menuClick = (event: emitter.EventData) => {
      PcTray.onMenu(codeOf(event));
    };
    statusBarManager.on('statusBarIconClick', PcTray.iconClick);
    statusBarManager.on('rightMenuClick', PcTray.menuClick);
  }

  private static onMenu(code: string): void {
    if (code === MENU_TOGGLE) {
      toggleTunnel('tray');
      PcTray.sync(true).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, `sync after toggle failed: ${err.message}`);
      });
    } else if (code === MENU_OPEN) {
      PcTray.openWindow();
    } else {
      hilog.info(DOMAIN, TAG, `unknown menu code: ${code}`);
    }
  }

  private static openWindow(): void {
    const context: common.Context | null = PcTray.context;
    if (context === null) {
      return;
    }
    const want: Want = { bundleName: BUNDLE, abilityName: ABILITY };
    (context as common.UIAbilityContext).startAbility(want).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, `startAbility failed: ${err.code} ${err.message}`);
    });
  }

  private static item(connected: boolean): statusBarManager.StatusBarItem {
    const item: statusBarManager.StatusBarItem = {
      icons: connected ? PcTray.upIcon as statusBarManager.StatusBarIcon :
        PcTray.idleIcon as statusBarManager.StatusBarIcon,
      // An empty ability name means the click is delivered to the app as an
      // event instead of the shell rendering its own pop-up: left-clicking the
      // icon simply brings the window back.
      quickOperation: { title: 'WGate', height: QUICK_HEIGHT, abilityName: '', moduleName: MODULE },
      statusBarGroupMenu: [PcTray.menu(connected)],
      hoverTips: PcTray.tips()
    };
    return item;
  }

  private static menu(connected: boolean): statusBarManager.StatusBarMenuItem[] {
    const toggle: statusBarManager.StatusBarMenuItem = {
      title: connected ? Tr.t('Disconnect tunnel') : Tr.t('Connect tunnel'),
      menuCode: MENU_TOGGLE,
      menuAction: { abilityName: ABILITY, moduleName: MODULE, notifyOnly: true }
    };
    const open: statusBarManager.StatusBarMenuItem = {
      title: Tr.t('Open main interface'),
      menuAction: { abilityName: ABILITY, moduleName: MODULE }
    };
    // No 退出 of our own: the shell already appends one to every tray menu (it
    // showed up in the first field test right below an identical entry of
    // ours), and that one is the documented exit — the platform stops the VPN
    // when the app that started it goes away. Two items with the same label,
    // one of which does nothing the other does not, is just a confusing menu.
    return [toggle, open];
  }

  private static tips(): string {
    const name: string = PcTray.tunnelName();
    const state: string = PcTray.state();
    if (state === 'up') {
      return name.length > 0 ? `WGate · ${Tr.t('Connected')} ${name}` : `WGate · ${Tr.t('Connected')}`;
    }
    if (state === 'busy') {
      return name.length > 0 ? `WGate · ${Tr.t('Connecting…')} ${name}` : `WGate · ${Tr.t('Connecting…')}`;
    }
    return `WGate · ${Tr.t('Disconnected')}`;
  }

  private static connected(): boolean {
    return PcTray.state() === 'up';
  }

  /** up | busy | off */
  private static state(): string {
    const status: EngineStatus | null = readStatus();
    if (status !== null && status.state === 'up') {
      return 'up';
    }
    const wanted: string = TunnelStore.desiredId();
    if (wanted.length > 0 || (status !== null && isRunning(status.state))) {
      return 'busy';
    }
    return 'off';
  }

  private static tunnelName(): string {
    const activeId: string = TunnelStore.activeId();
    const id: string = activeId.length > 0 ? activeId : TunnelStore.desiredId();
    const tunnel = TunnelStore.find(id);
    return tunnel === null ? '' : tunnel.name;
  }

  private static stateSignature(): string {
    return `${PcTray.state()}|${PcTray.tunnelName()}`;
  }

  private static async buildIcon(context: common.Context, connected: boolean): Promise<statusBarManager.StatusBarIcon> {
    const white: image.PixelMap = await PcTray.pixelMap(context,
      connected ? $r('app.media.tray_up_light') : $r('app.media.tray_idle_light'));
    const black: image.PixelMap = await PcTray.pixelMap(context,
      connected ? $r('app.media.tray_up_dark') : $r('app.media.tray_idle_dark'));
    return { white: white, black: black };
  }

  private static async pixelMap(context: common.Context, res: Resource): Promise<image.PixelMap> {
    const bytes: Uint8Array = await context.resourceManager.getMediaContent(res.id);
    const content: ArrayBuffer = bytes.buffer as ArrayBuffer;
    const source: image.ImageSource = image.createImageSource(content);
    return await source.createPixelMap();
  }
}

/** Reads the menu code the shell echoes back for a right-clicked item. */
function codeOf(event: emitter.EventData): string {
  const data: ESObject = event.data as ESObject;
  if (data === undefined || data === null) {
    return '';
  }
  const value: ESObject = data['menuCode'];
  if (value === undefined || value === null) {
    return '';
  }
  return value.toString();
}
