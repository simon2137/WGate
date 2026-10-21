import { router } from '@kit.ArkUI';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { Tr } from '../i18n/Tr';

/**
 * The privacy policy, in the app rather than behind a link.
 *
 * Everything here is a statement about what this build actually does, so it is
 * kept next to the code that does it: the preferences live in
 * `service/SettingsStore.ets` and `service/TunnelStore.ets`, the trace in
 * `util/Diag.ets`, the permission list in `entry/src/main/module.json5`, and the
 * native core is the only thing that opens a socket.
 */
const PARAGRAPHS: string[] = [
  Tr.t('No accounts, no telemetry, no analytics. This app runs no server of its own and does not upload your configuration anywhere.'),
  Tr.t('Tunnel configurations, private keys included, are stored in the app’s private preferences on this device. They leave it only when you export a backup or show a QR code, and both of those are things you start.'),
  Tr.t('The startup trace under Local logging stays in the app’s private files. It records state changes and errors, not packet contents, and you can clear it or export it at any time.'),
  Tr.t('The permissions are the ones the app is named for: INTERNET and the VPN extension for tunnel traffic, GET_NETWORK_INFO and GET_WIFI_INFO to tell Wi-Fi from mobile data, CAMERA only while you scan a configuration. Nothing else is requested.'),
  Tr.t('No advertising SDK, crash reporter or tracker is linked into this build. The only traffic the app generates is the tunnel itself.'),
  Tr.t('Uninstalling the app removes the stored tunnels, the settings and the trace with it. There is no copy anywhere else.')
];

@Entry
@Component
struct Privacy {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;

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
          Text(Tr.t('Privacy policy'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('What stays on this device, and what never leaves it'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .maxLines(2)
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
          ForEach(PARAGRAPHS, (line: string, index: number) => {
            Text(line)
              .fontSize(Type.BODY_MEDIUM)
              .fontFamily(FONT)
              .fontColor(Palette.ON_SURFACE)
              .width('100%')
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 12, bottom: 12 })
              .backgroundColor(Palette.SURFACE)
              .margin({ top: index === 0 ? 8 : 1 })
          }, (line: string) => line)

          Text(Tr.t('Last updated: October 2026'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 14, bottom: 14 })

          Column().height(BAR_SPACE)
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
