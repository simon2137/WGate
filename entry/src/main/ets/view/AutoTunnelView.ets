import { router } from '@kit.ArkUI';
import { WgTunnel } from '../model/Tunnel';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { AutoTunnel } from '../service/AutoTunnel';
import { publishedTunnelId } from '../service/EngineStatus';
import { Tr } from '../i18n/Tr';

/**
 * `ui/screens/autotunnel/AutoTunnelScreen.kt`: the running row with its
 * Start/Stop button, the Networks group (active network, one row per network
 * type, stop on no internet). The reference's Automation group and its
 * "Start on boot" switch are absent: HarmonyOS gives a third-party app no boot
 * broadcast, so the switch could only promise what the platform will not do.
 */
@Component
export struct AutoTunnelView {
  @StorageProp('theme_tick') themeTick: number = 0;
  @Link tunnels: WgTunnel[];
  onError: (message: string) => void = () => {};
  onPickPreferred: () => void = () => {};

  @State autoOn: boolean = false;
  @State currentSsid: string = '';
  @State netType: string = 'wifi';
  @State wifiOn: boolean = false;
  /** What the last name read did, shown under the row while the name is missing. */
  @State nameDiag: string = '';
  @State onWifi: boolean = true;
  @State onCellular: boolean = false;
  @State onEthernet: boolean = false;
  @State stopOffline: boolean = false;
  @State running: string = '';

  /** Pages pushed from here write their choice while this view is paused. */
  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
    this.readNetwork();
    this.timer = setInterval(() => {
      this.reload();
      // The name is empty until the Wi-Fi service has the association, so ask
      // again on every tick instead of keeping the answer the page opened with.
      this.readNetwork();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private reload(): void {
    this.autoOn = SettingsStore.autoEnabled();
    this.onWifi = SettingsStore.netTunnelOn('wifi');
    this.onCellular = SettingsStore.netTunnelOn('cellular');
    this.onEthernet = SettingsStore.netTunnelOn('ethernet');
    this.stopOffline = SettingsStore.stopOnNoInternet();
    this.running = publishedTunnelId();
  }

  private readNetwork(): void {
    this.netType = AutoTunnel.networkType();
    this.wifiOn = AutoTunnel.wifiActive();
    AutoTunnel.displaySsid().then((ssid: string) => {
      this.currentSsid = ssid;
      this.nameDiag = AutoTunnel.nameDiag();
    });
  }

  private netLabel(): string {
    if (this.netType === 'ethernet') {
      // Shares the notice's row: a plain `Ethernet` key would collide with the
      // reference row "Tunnel on Ethernet", which the catalogue checker rejects.
      return Tr.t('Wired Ethernet');
    }
    if (this.netType === 'cellular') {
      return Tr.t('Mobile data');
    }
    // Being joined to a network whose name the platform hides is still Wi-Fi,
    // not "no network": the second line says the name is missing.
    return this.currentSsid.length > 0 || this.wifiOn ? 'Wi-Fi' : Tr.t('No network');
  }

  /**
   * The hint under the network row, plus what the last read actually did: the
   * platform can answer with an empty name, fail with a code, or not implement
   * the call at all, and only the device can say which.
   */
  private missingName(): string {
    const hint: string = Tr.t('No Wi-Fi name is visible to the app');
    return this.nameDiag.length > 0 ? `${hint} (${this.nameDiag})` : hint;
  }

  private preferredName(net: string): string {
    const id: string = SettingsStore.preferredFor(net);
    for (let i = 0; i < this.tunnels.length; i++) {
      if (this.tunnels[i].id === id) {
        return this.tunnels[i].name;
      }
    }
    return Tr.t('Default');
  }

  private setAuto(next: boolean): void {
    this.autoOn = next;
    SettingsStore.setAutoEnabled(next);
    if (next) {
      AutoTunnel.start();
      AutoTunnel.evaluate('auto-tunnel started');
    } else {
      AutoTunnel.evaluate('auto-tunnel stopped');
    }
    this.reload();
  }

  private toggleAuto(): void {
    this.setAuto(!this.autoOn);
  }

  build() {
    Column() {
      Row() {
        Text(Tr.t('Auto-tunnel'))
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

      Scroll() {
        Column() {
          SurfaceRow({
            title: this.autoOn ? Tr.t('Auto-tunnel running') : Tr.t('Auto-tunnel not running'),
            description: this.autoOn ? Tr.t('Watching the trusted networks') :
              Tr.t('Start to bring a tunnel up on the trusted networks'),
            icon: this.autoOn ? $r('app.media.ic_check_circle') : $r('app.media.ic_info'),
            tint: this.autoOn ? Palette.PRIMARY : Palette.ON_SURFACE,
            hasSwitch: true,
            switchOn: this.autoOn,
            onSwitch: (on: boolean) => {
              this.setAuto(on);
            },
            onTap: () => {
              this.toggleAuto();
            }
          })

          SectionHeader({ label: Tr.t('Networks') })

          SurfaceRow({
            title: `${Tr.t('Active Network')}: ${this.netLabel()}`,
            description: this.netType === 'wifi'
              ? (this.currentSsid.length > 0 ? this.currentSsid : this.missingName())
              : Tr.t('The network the tunnel rules apply to'),
            icon: $r('app.media.ic_globe'),
            onTap: () => {
              this.readNetwork();
            }
          })

          SurfaceRow({
            title: Tr.t('Tunnel on Wi-Fi'),
            description: `${Tr.t('Preferred tunnel')}: ${this.preferredName('wifi')}`,
            icon: $r('app.media.ic_wifi'),
            chevron: true,
            hasSwitch: true,
            switchOn: this.onWifi,
            onSwitch: (on: boolean) => {
              this.onWifi = on;
              SettingsStore.setNetTunnelOn('wifi', on);
              if (this.autoOn) {
                AutoTunnel.evaluate('wi-fi rule changed');
              }
            },
            onTap: () => {
              router.pushUrl({ url: 'pages/WifiSettings' })
                .then(() => {
                  this.reload();
                });
            }
          })

          SurfaceRow({
            title: Tr.t('Tunnel on mobile data'),
            description: `${Tr.t('Preferred tunnel')}: ${this.preferredName('cellular')}`,
            icon: $r('app.media.ic_signal_cellular'),
            chevron: true,
            hasSwitch: true,
            switchOn: this.onCellular,
            onSwitch: (on: boolean) => {
              this.onCellular = on;
              SettingsStore.setNetTunnelOn('cellular', on);
              if (this.autoOn) {
                AutoTunnel.evaluate('mobile data rule changed');
              }
            },
            onTap: () => {
              router.pushUrl({ url: 'pages/PreferredTunnel', params: { net: 'cellular' } })
                .then(() => {
                  this.reload();
                });
            }
          })

          SurfaceRow({
            title: Tr.t('Tunnel on Ethernet'),
            description: `${Tr.t('Preferred tunnel')}: ${this.preferredName('ethernet')}`,
            icon: $r('app.media.ic_settings_ethernet'),
            chevron: true,
            hasSwitch: true,
            switchOn: this.onEthernet,
            onSwitch: (on: boolean) => {
              this.onEthernet = on;
              SettingsStore.setNetTunnelOn('ethernet', on);
              if (this.autoOn) {
                AutoTunnel.evaluate('ethernet rule changed');
              }
            },
            onTap: () => {
              router.pushUrl({ url: 'pages/PreferredTunnel', params: { net: 'ethernet' } })
                .then(() => {
                  this.reload();
                });
            }
          })

          SurfaceRow({
            title: Tr.t('Stop on no network'),
            description: Tr.t('Stop the tunnel when the device has no network connection'),
            icon: $r('app.media.ic_public_off'),
            hasSwitch: true,
            switchOn: this.stopOffline,
            onSwitch: (on: boolean) => {
              this.stopOffline = on;
              SettingsStore.setStopOnNoInternet(on);
              if (this.autoOn) {
                AutoTunnel.evaluate('stop-on-no-network changed');
              }
            }
          })
        }
        .width('100%')
        .padding({ bottom: BAR_SPACE })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }
}