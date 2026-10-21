import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { WgTunnel } from '../model/Tunnel';
import { Palette, Type, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';

/**
 * `ui/screens/autotunnel/preferred/PreferredTunnelScreen.kt`: the tunnel that
 * comes up on one network type. The chosen id is stored per network type so the
 * Wi-Fi, mobile data and Ethernet rows can disagree.
 */
@Entry
@Component
struct PreferredTunnel {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State net: string = 'wifi';
  @State tunnels: WgTunnel[] = [];
  @State chosen: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    const params = router.getParams() as Record<string, string>;
    if (params !== undefined && params !== null && params.net !== undefined) {
      this.net = params.net;
    }
    this.tunnels = TunnelStore.list();
    this.chosen = SettingsStore.preferredFor(this.net);
  }

  private netLabel(): string {
    if (this.net === 'cellular') {
      return 'mobile data';
    }
    if (this.net === 'ethernet') {
      return 'Ethernet';
    }
    return 'Wi-Fi';
  }

  private pick(id: string): void {
    this.chosen = id;
    SettingsStore.setPreferredFor(this.net, id);
    router.back();
  }

  build() {
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
        .onClick(() => {
          router.back();
        })

        Column() {
          Text(Tr.t('Preferred tunnel'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(`Used on ${this.netLabel()}`)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ right: 16 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          SectionHeader({ label: Tr.t('Tunnels') })

          ForEach(this.tunnels, (tunnel: WgTunnel) => {
            SurfaceRow({
              title: tunnel.name,
              description: this.net === 'wifi' ? `via ${tunnel.endpoint()}` : '',
              dotColor: this.chosen === tunnel.id ? Palette.PRIMARY : Palette.MUTED,
              trailingText: this.chosen === tunnel.id ? Tr.t('Selected') : '',
              onTap: () => {
                this.pick(tunnel.id);
              }
            })
          }, (tunnel: WgTunnel) => `${tunnel.id}-${this.chosen === tunnel.id}`)

          SurfaceRow({
            title: Tr.t('Default'),
            description: Tr.t('Let the app choose, preferring the primary tunnel'),
            dotColor: this.chosen.length === 0 ? Palette.PRIMARY : Palette.MUTED,
            trailingText: this.chosen.length === 0 ? Tr.t('Selected') : '',
            onTap: () => {
              this.pick('');
            }
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .padding({ top: this.safeTop })
  }
}
