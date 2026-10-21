import { common } from '@kit.AbilityKit';
import { router, window } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { WgTunnel, parseWgQuick, toWgQuick } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { Diag } from '../util/Diag';
import { publishedTunnelId } from '../service/EngineStatus';
import { AutoTunnel } from '../service/AutoTunnel';
import {
  startTunnel, stopTunnel
} from '../service/VpnControl';
import { Palette, Type, ROW_PAD_H , FONT, applyScheme, resolveTheme, isLightScheme, glassCore, glassHalo} from '../theme/Theme';
import { BottomNav, NAV_BAR_WIDTH } from '../components/BottomNav';
import { PinLockPad } from '../components/PinLockPad';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { TunnelsView } from '../view/TunnelsView';
import { AutoTunnelView } from '../view/AutoTunnelView';
import { SettingsView } from '../view/SettingsView';
import { SupportView } from '../view/SupportView';
import { Tr } from '../i18n/Tr';
import { offeredLocale } from '../i18n/Locales';
import { sheetWillDismiss } from '../components/SheetGestures';

const SHEET_NONE: string = '';
const SHEET_IMPORT: string = 'import';
const SHEET_DETAIL: string = 'detail';
const SHEET_LOGS: string = 'logs';
const SHEET_APPEARANCE: string = 'appearance';
const SHEET_PREFERRED: string = 'preferred';

const THEMES: string[] = ['automatic', 'dark', 'darker', 'amoled'];

/** Slide-and-fade used when the capsule switches between the main tabs. */
const TAB_TRANSITION: TransitionEffect = TransitionEffect
  .translate({ y: 24 })
  .combine(TransitionEffect.OPACITY)
  .animation({ duration: 280, curve: Curve.EaseOut });

/**
 * The four-tab shell, matching the reference app's `MainScreen`:
 * Tunnels / Auto-tunnel / Settings / Support, with the tab bar replaced by the
 * HarmonyOS immersive material bar.
 */
@Entry
@Component
struct Home {
  @StorageProp('theme_tick') themeTick: number = 0;
  // System-bar avoid insets (set by EntryAbility): the app draws full screen, so
  // the top inset keeps the tab headers below the status bar and the bottom inset
  // keeps the capsule above the gesture bar.
  @StorageProp('safe_top') safeTop: number = 40;
  @StorageProp('safe_bottom') safeBottom: number = 40;
  @State tab: number = 0;
  // The capsule's light is drawn here rather than inside BottomNav: a child of
  // the node that carries the system material is composited into the material
  // pass, which washes its colour out to a grey smudge.
  @State navGlowX: number = -300;
  @State navGlow: number = 0;
  @State tunnels: WgTunnel[] = [];
  @State activeId: string = '';
  @State toast: string = '';
  @State sheet: string = SHEET_NONE;
  @State detailId: string = '';
  @State importText: string = '';
  @State logsText: string = '';
  @State themeName: string = 'dark';
  @State preferredId: string = '';
  /** Set while the PIN lock is in front of the tabs. */
  @State locked: boolean = false;
  @State pinError: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    Diag.init(context);
    // The reference app ships Inter; registering it through the UI context is
    // the non-deprecated path and takes effect for pages built afterwards.
    try {
      this.getUIContext().getFont().registerFont({
        familyName: 'Inter',
        familySrc: $rawfile('inter.ttf')
      });
      Diag.write('font: registered Inter');
    } catch (e) {
      Diag.write(`font: register failed ${(e as Error).message}`);
    }
    this.reload();
    this.themeName = SettingsStore.theme();
    applyScheme(resolveTheme(this.themeName, context));
    this.syncWindowTheme(context);
    // The interface language is looked up per literal, so it only has to be set
    // once before the first page is built. Only three interfaces are offered, so
    // anything else stored by an earlier build folds onto one of them here too.
    Tr.setLocale(offeredLocale(SettingsStore.language()));
    this.preferredId = SettingsStore.preferredTunnelId();
    this.locked = SettingsStore.pinHash().length > 0;
    AutoTunnel.start();
  }

  aboutToDisappear(): void {
    AutoTunnel.stop();
  }

  onPageShow(): void {
    this.reload();
    this.syncWindowTheme(getContext(this) as common.UIAbilityContext);
    // Resuming after the system took the VPN down leaves the rules intact; ask
    // again so a trusted network puts the tunnel back up without a manual tap.
    AutoTunnel.evaluate('page shown');
  }

  /**
   * Paints the window background and system bars from the APPLIED palette.
   *
   * `configureWindow` runs at startup, before the app has resolved its theme
   * (`context.config.colorMode` is not trustworthy yet for "automatic"), so its
   * guess can leave a mismatched window background behind the transparent bars.
   * Re-applying here — after `applyScheme` has set the real palette — makes the
   * bars follow whatever theme the page drew, in light and dark alike.
   */
  private syncWindowTheme(context: common.UIAbilityContext): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const light: boolean = isLightScheme();
      const fg: string = light ? '#17191B' : '#EAF2FB';
      try {
        win.setWindowBackgroundColor(Palette.BACKGROUND);
      } catch (e) {
        // Not fatal: the page itself still covers the content area.
      }
      win.setWindowSystemBarProperties({
        statusBarContentColor: fg,
        navigationBarContentColor: fg,
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000'
      }).catch((e: Error) => {
        console.error(`ui: sysbar sync failed ${e.message}`);
      });
    }).catch((e: Error) => {
      console.error(`ui: getLastWindow failed ${e.message}`);
    });
  }

  private reload(): void {
    this.tunnels = TunnelStore.list();
    // Only what the extension actually reports counts as running. The stored
    // "desired" tunnel is the intent a killed session left behind: painting it
    // as the active row is what made the list show a switch on next to
    // "Disconnected". Auto-tunnel re-checks the network at startup, and the
    // list adopts the id it publishes.
    this.activeId = publishedTunnelId();
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2600);
  }

  private copyConfig(tunnel: WgTunnel): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, toWgQuick(tunnel));
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.flash('Configuration copied');
    }).catch(() => {
      this.flash('Could not copy the configuration');
    });
  }

  private pasteFromClipboard(): void {
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      this.importText = data.getPrimaryText();
    }).catch(() => {
      this.flash('The clipboard is empty');
    });
  }

  private importConfig(): void {
    const text: string = this.importText.trim();
    if (text.length === 0) {
      this.flash('Paste a configuration first');
      return;
    }
    const parsed: WgTunnel | null = parseWgQuick(text, 'Imported tunnel');
    if (parsed === null) {
      this.flash('That is not a WireGuard configuration');
      return;
    }
    // Re-importing the same keys and endpoint updates the existing tunnel
    // instead of piling up duplicates.
    const existing: WgTunnel[] = TunnelStore.list();
    for (let i = 0; i < existing.length; i++) {
      const other: WgTunnel = existing[i];
      if (other.privateKey === parsed.privateKey && other.peers.length > 0 &&
          parsed.peers.length > 0 && other.peers[0].host === parsed.peers[0].host &&
          other.peers[0].port === parsed.peers[0].port) {
        parsed.id = other.id;
        parsed.name = other.name;
        break;
      }
    }
    TunnelStore.save(parsed);
    this.importText = '';
    this.sheet = SHEET_NONE;
    this.reload();
    this.flash(`Imported ${parsed.name}`);
    this.applyInterfaceDefaults(parsed, text);
  }

  /**
   * `TunnelGlobalsScreen`'s contract: values a configuration leaves out come
   * from the global interface defaults.
   */
  private applyInterfaceDefaults(tunnel: WgTunnel, raw: string): void {
    let changed: boolean = false;
    if (raw.indexOf('MTU') < 0) {
      tunnel.mtu = SettingsStore.defaultMtu();
      changed = true;
    }
    if (raw.indexOf('DNS') < 0) {
      tunnel.dns = SettingsStore.defaultDns();
      changed = true;
    }
    if (raw.indexOf('PersistentKeepalive') < 0 && tunnel.peers.length > 0) {
      const keepalive: number = SettingsStore.defaultKeepalive();
      for (let i = 0; i < tunnel.peers.length; i++) {
        tunnel.peers[i].keepalive = keepalive;
      }
      changed = true;
    }
    if (changed) {
      TunnelStore.save(tunnel);
    }
  }

  private async removeTunnel(tunnel: WgTunnel): Promise<void> {
    if (this.activeId === tunnel.id) {
      await stopTunnel(tunnel);
      this.activeId = '';
    }
    TunnelStore.remove(tunnel.id);
    this.sheet = SHEET_NONE;
    this.reload();
    this.flash('Tunnel deleted');
  }

  private detailTunnel(): WgTunnel | null {
    for (let i = 0; i < this.tunnels.length; i++) {
      if (this.tunnels[i].id === this.detailId) {
        return this.tunnels[i];
      }
    }
    return null;
  }

  @Builder
  private sheetHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(Type.TITLE_LARGE)
        .fontFamily(FONT)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.ON_SURFACE)
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private importSheet() {
    Column() {
      this.sheetHeader(Tr.t('Add tunnel'))
      Column() {
        Text(Tr.t('Paste a WireGuard configuration, or scan its QR code.'))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
          .width('100%')
          .margin({ bottom: 12 })
        TextArea({ text: this.importText, placeholder: '[Interface]\nPrivateKey = …' })
          .height(180)
          .width('100%')
          .backgroundColor(Palette.SURFACE)
          .fontColor(Palette.ON_SURFACE)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .borderRadius(8)
          .onChange((value: string) => {
            this.importText = value;
          })
        Row() {
          Button(Tr.t('Paste'))
            .fontColor(Palette.ON_SURFACE)
            .backgroundColor(Palette.RAISED)
            .layoutWeight(1)
            .onClick(() => {
              this.pasteFromClipboard();
            })
          Button(Tr.t('Scan QR'))
            .fontColor(Palette.ON_SURFACE)
            .backgroundColor(Palette.RAISED)
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => {
              this.sheet = SHEET_NONE;
              router.pushUrl({ url: 'pages/Scan' });
            })
        }
        .width('100%')
        .margin({ top: 12 })
        Button(Tr.t('Import'))
          .fontColor(Palette.BACKGROUND)
          .backgroundColor(Palette.PRIMARY)
          .width('100%')
          .margin({ top: 12 })
          .onClick(() => {
            this.importConfig();
          })
      }
      .width('100%')
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private detailSheet() {
    Column() {
      this.sheetHeader(Tr.t('Tunnel details'))
      if (this.detailTunnel() !== null) {
        Scroll() {
          Column() {
            SurfaceRow({ title: Tr.t('Name'), trailingText: this.detailTunnel()!.name })
            SurfaceRow({
              title: Tr.t('Endpoint'),
              trailingText: this.detailTunnel()!.peers.length > 0 ?
                `${this.detailTunnel()!.peers[0].host}:${this.detailTunnel()!.peers[0].port}` : '—'
            })
            SurfaceRow({ title: Tr.t('Interface'), trailingText: this.detailTunnel()!.address })
            SurfaceRow({ title: 'DNS', trailingText: this.detailTunnel()!.dns })
            SurfaceRow({
              title: Tr.t('Allowed IPs'),
              trailingText: this.detailTunnel()!.peers.length > 0 ?
                this.detailTunnel()!.peers[0].allowedIPs : '—'
            })
            SurfaceRow({ title: Tr.t('MTU'), trailingText: this.detailTunnel()!.mtu.toString() })
            if (this.detailTunnel()!.awg) {
              SurfaceRow({
                title: 'AmneziaWG',
                trailingText: `Jc ${this.detailTunnel()!.jc} · Jmin ${this.detailTunnel()!.jmin}`
              })
            }

            Row() {
              Button(this.activeId === this.detailId ? Tr.t('Disconnect') : Tr.t('Connect'))
                .fontColor(Palette.BACKGROUND)
                .backgroundColor(Palette.PRIMARY)
                .layoutWeight(1)
                .onClick(() => {
                  this.toggleDetail();
                })
              Button(Tr.t('Copy'))
                .fontColor(Palette.ON_SURFACE)
                .backgroundColor(Palette.RAISED)
                .layoutWeight(1)
                .margin({ left: 8 })
                .onClick(() => {
                  this.copyConfig(this.detailTunnel()!);
                })
            }
            .width('100%')
            .margin({ top: 16 })

            Button(Tr.t('Delete'))
              .fontColor(Palette.ALERT)
              .backgroundColor(Palette.RAISED)
              .width('100%')
              .margin({ top: 8 })
              .onClick(() => {
                this.removeTunnel(this.detailTunnel()!);
              })
          }
          .width('100%')
          .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
  }

  private async toggleDetail(): Promise<void> {
    const tunnel: WgTunnel | null = this.detailTunnel();
    if (tunnel === null) {
      return;
    }
    if (this.activeId === tunnel.id) {
      await stopTunnel(tunnel);
      this.activeId = '';
    } else {
      const problem: string = await startTunnel(tunnel);
      if (problem.length > 0) {
        this.flash(problem);
      } else {
        this.activeId = tunnel.id;
        TunnelStore.setActive(tunnel.id);
      }
    }
    this.reload();
  }

  @Builder
  private logsSheet() {
    Column() {
      this.sheetHeader(Tr.t('Engine log'))
      Scroll() {
        Text(this.logsText.length > 0 ? this.logsText : 'no log lines yet')
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontFamily('monospace')
          .fontColor(Palette.MUTED)
          .width('100%')
          .padding(12)
      }
      .layoutWeight(1)
      .backgroundColor(Palette.SURFACE)
      .borderRadius(8)
      .margin({ left: ROW_PAD_H, right: ROW_PAD_H })
      .align(Alignment.Top)
      Button(Tr.t('Clear'))
        .fontColor(Palette.ON_SURFACE)
        .backgroundColor(Palette.RAISED)
        .width('100%')
        .margin({ left: ROW_PAD_H, right: ROW_PAD_H, top: 12, bottom: 12 })
        .onClick(() => {
          Diag.clear();
          this.logsText = '';
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private appearanceSheet() {
    Column() {
      this.sheetHeader(Tr.t('Appearance'))
      Scroll() {
        Column() {
          ForEach(THEMES, (name: string) => {
            SurfaceRow({
              title: name.charAt(0).toUpperCase() + name.substring(1),
              trailingText: this.themeName === name ? Tr.t('Selected') : '',
              onTap: () => {
                this.themeName = name;
                SettingsStore.setTheme(name);
              }
            })
          }, (name: string) => `${name}-${this.themeName === name}`)
          Text(Tr.t('The dark palette is used in this build; the other options are recorded for later.'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 16 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private preferredSheet() {
    Column() {
      this.sheetHeader(Tr.t('Preferred tunnel'))
      Scroll() {
        Column() {
          ForEach(this.tunnels, (tunnel: WgTunnel) => {
            SurfaceRow({
              title: tunnel.name,
              trailingText: this.preferredId === tunnel.id ? Tr.t('Selected') : '',
              onTap: () => {
                this.preferredId = tunnel.id;
                SettingsStore.setPreferredTunnelId(tunnel.id);
                this.sheet = SHEET_NONE;
              }
            })
          }, (tunnel: WgTunnel) => `${tunnel.id}-${this.preferredId === tunnel.id}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private sheetBody() {
    if (this.sheet === SHEET_IMPORT) {
      this.importSheet();
    } else if (this.sheet === SHEET_DETAIL) {
      this.detailSheet();
    } else if (this.sheet === SHEET_LOGS) {
      this.logsSheet();
    } else if (this.sheet === SHEET_APPEARANCE) {
      this.appearanceSheet();
    } else {
      this.preferredSheet();
    }
  }

  /** Halo of the capsule highlight; a white light paints nothing on the light palette. */
  private navHaloColor(): string {
    return glassHalo();
  }

  /** Bright core of the capsule highlight. */
  private navCoreColor(): string {
    return glassCore();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.tab === 0) {
        TunnelsView({
          tunnels: $tunnels,
          activeId: $activeId,
          onOpenTunnel: (id: string) => {
            this.detailId = id;
            router.pushUrl({ url: 'pages/TunnelSettings', params: { id: id } });
          },
          onAdd: () => {
            this.sheet = SHEET_IMPORT;
          },
          onChanged: () => {
            this.reload();
          },
          onError: (message: string) => {
            this.flash(message);
          }
        })
        .transition(TAB_TRANSITION)
      } else if (this.tab === 1) {
        AutoTunnelView({
          tunnels: $tunnels,
          onError: (message: string) => {
            this.flash(message);
          },
          onPickPreferred: () => {
            this.sheet = SHEET_PREFERRED;
          }
        })
        .transition(TAB_TRANSITION)
      } else if (this.tab === 2) {
        SettingsView({
          onOpenLogs: () => {
            this.logsText = Diag.read();
            this.sheet = SHEET_LOGS;
          },
          onOpenAppearance: () => {
            this.sheet = SHEET_APPEARANCE;
          },
          onNote: (message: string) => {
            this.flash(message);
          }
        })
        .transition(TAB_TRANSITION)
      } else {
        SupportView()
          .transition(TAB_TRANSITION)
      }

      // The bar floats over the content so the immersive material has something
      // to refract; every list pads its bottom by BAR_SPACE to make room.
      BottomNav({
        selected: this.tab,
        autoActive: this.activeId.length > 0 && SettingsStore.autoEnabled(),
        onSelect: (index: number) => {
          // Wrapping the branch change in animateTo drives the if/else views'
          // appearance/disappearance transitions, so switching tabs slides and
          // fades instead of snapping.
          animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
            this.tab = index;
          });
          if (index === 0) {
            this.reload();
          }
        },
        onGlow: (x: number, on: boolean) => {
          // The light tracks the finger at once; only the brightness animates, so
          // a moving light never smears behind a quick flick. Faster in, gentler
          // out reads like light switching on and slowly cooling off.
          this.navGlowX = x;
          animateTo({ duration: on ? 100 : 240, curve: Curve.EaseOut }, () => {
            this.navGlow = on ? 1 : 0;
          });
        }
      })

      // The moving highlight, painted over the capsule from outside the material.
      // A radial gradient rather than a solid disc: a hard-edged circle reads as a
      // pasted layer, light has no edge.
      Column()
        .width(NAV_BAR_WIDTH)
        .height(56)
        .radialGradient({
          center: [this.navGlowX, 28],
          radius: 110,
          colors: [
            [this.navCoreColor(), 0.0],
            [this.navHaloColor(), 0.42],
            ['#00FFFFFF', 1.0]
          ] as Array<[ResourceColor, number]>
        })
        .opacity(this.navGlow)
        .borderRadius(28)
        .clip(true)
        .margin({ bottom: 16 + this.safeBottom })
        .hitTestBehavior(HitTestMode.None)

      // The reference app gates the tunnel list behind `PinLockScreen`; here the
      // pad covers the tabs so nothing underneath can be tapped.
      if (this.locked) {
        Column() {
          PinLockPad({
            title: Tr.t('Enter PIN'),
            error: this.pinError,
            onCode: (code: string) => {
              if (SettingsStore.checkPin(code)) {
                this.locked = false;
                this.pinError = '';
                Diag.write('pin: unlocked');
                return;
              }
              this.pinError = 'Pin is incorrect';
              setTimeout(() => {
                this.pinError = '';
              }, 1600);
            }
          })
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Palette.BACKGROUND)
      }

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .backgroundColor(Palette.RAISED)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .margin({ bottom: 96 })
      }
    }
    .width('100%')
    .height('100%')
    // Full-screen rendering: this background fills behind the status bar, and
    // the top inset keeps every tab's header below the status bar.
    .backgroundColor(Palette.BACKGROUND)
    .padding({ top: this.safeTop })
    .bindSheet(this.sheet !== SHEET_NONE, this.sheetBody(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('home'),
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = SHEET_NONE;
      }
    })
  }
}

