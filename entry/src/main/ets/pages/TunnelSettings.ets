import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { Diag } from '../util/Diag';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { stateLabel, readStatus, publishedTunnelId } from '../service/EngineStatus';
import { Tr } from '../i18n/Tr';

/**
 * The per-tunnel settings page, following `TunnelSettingsScreen.kt`: the
 * Configuration / General / Network / Automation sections in the reference
 * order. Entries the engine cannot honour say so rather than doing nothing.
 */
@Entry
@Component
struct TunnelSettings {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State tunnel: WgTunnel | null = null;
  @State primary: boolean = false;
  @State metered: boolean = false;
  @State ddns: boolean = false;
  @State statusText: string = Tr.t('Disconnected');
  @State toast: string = '';
  private tunnelId: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    Diag.init(context);
    const params = router.getParams() as Record<string, string>;
    if (params !== undefined && params !== null) {
      const id = params['id'];
      if (id !== undefined) {
        this.tunnelId = id;
      }
    }
    this.reload();
    this.timer = setInterval(() => {
      this.tick();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private reload(): void {
    this.tunnel = TunnelStore.find(this.tunnelId);
    this.primary = SettingsStore.primaryId() === this.tunnelId;
    this.metered = SettingsStore.isMetered(this.tunnelId);
    this.ddns = SettingsStore.isDdns(this.tunnelId);
    this.tick();
  }

  private tick(): void {
    const running: boolean = publishedTunnelId() === this.tunnelId;
    const status = readStatus();
    this.statusText = running && status !== null ? stateLabel(status.state) : Tr.t('Disconnected');
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2400);
  }

  private openConfig(live: boolean): void {
    router.pushUrl({ url: 'pages/TunnelConfig', params: { id: this.tunnelId, live: live ? '1' : '0' } });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Row() {
            Image($r('app.media.ic_back'))
              .width(24)
              .height(24)
              .fillColor(Palette.ON_SURFACE)
          }
          .width(48)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .margin({ right: 8 })
          .onClick(() => {
            router.back();
          })
          Column() {
            Text(this.tunnel === null ? Tr.t('Tunnel') : this.tunnel!.name)
              .fontSize(Type.TITLE_LARGE)
              .fontFamily(FONT)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.ON_SURFACE)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.statusText)
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height(64)
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            SectionHeader({ label: Tr.t('Configuration') })

            SurfaceRow({
              title: Tr.t('View configuration'),
              icon: $r('app.media.ic_doc'),
              chevron: true,
              onTap: () => {
                this.openConfig(false);
              }
            })
            SurfaceRow({
              title: Tr.t('View live tunnel'),
              icon: $r('app.media.ic_bolt'),
              chevron: true,
              onTap: () => {
                this.openConfig(true);
              }
            })

            SectionHeader({ label: Tr.t('General') })

            SurfaceRow({
              title: Tr.t('Primary tunnel'),
              description: Tr.t('Used as the default tunnel to start'),
              icon: this.primary ? $r('app.media.ic_star_filled') : $r('app.media.ic_star'),
              hasSwitch: true,
              switchOn: this.primary,
              onSwitch: (on: boolean) => {
                this.primary = on;
                SettingsStore.setPrimaryId(on ? this.tunnelId : '');
              }
            })

            SectionHeader({ label: Tr.t('Network') })

            SurfaceRow({
              title: Tr.t('Metered tunnel'),
              description: Tr.t('Connect even when the network is metered'),
              icon: $r('app.media.ic_data'),
              hasSwitch: true,
              switchOn: this.metered,
              onSwitch: (on: boolean) => {
                this.metered = on;
                SettingsStore.setMetered(this.tunnelId, on);
              }
            })

            SectionHeader({ label: Tr.t('Automation') })

            SurfaceRow({
              title: Tr.t('DDNS auto update'),
              description: Tr.t('Re-resolve the endpoint on every connect'),
              icon: $r('app.media.ic_dns'),
              hasSwitch: true,
              switchOn: this.ddns,
              onSwitch: (on: boolean) => {
                this.ddns = on;
                SettingsStore.setDdns(this.tunnelId, on);
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

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .backgroundColor(Palette.RAISED)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .margin({ bottom: 48 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .padding({ top: this.safeTop })
  }
}
