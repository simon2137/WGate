import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

const DELAYS: number[] = [5, 15, 30, 60, 120];

/**
 * `ui/screens/settings/recovery/TunnelRecoveryScreen.kt`: seamless recovery and
 * the bounce delay. The engine repairs its own socket, so these two settings are
 * about the tunnel outliving the app: `service/TunnelGuard.ets` restarts the VPN
 * extension when it goes silent, the switch turns that off, and the delay is how
 * long the silence has to last (5 s rounds up to the guard's ten-second check).
 */
@Entry
@Component
struct TunnelRecovery {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State seamless: boolean = true;
  @State delay: number = 30;
  @State sheet: boolean = false;

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.seamless = SettingsStore.seamlessRecovery();
    this.delay = SettingsStore.recoveryDelay();
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
        .margin({ right: 8 })
        .onClick(() => {
          router.back();
        })
        Column() {
          Text(Tr.t('Tunnel recovery'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('Reconnect when the network changes'))
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
          SectionHeader({ label: Tr.t('Tunnel recovery') })

          SurfaceRow({
            title: Tr.t('Seamless tunnel recovery'),
            description: Tr.t('Keeps protection while recovering from DDNS changes, network switches and NAT issues'),
            icon: $r('app.media.ic_autorenew'),
            hasSwitch: true,
            switchOn: this.seamless,
            onSwitch: (on: boolean) => {
              this.seamless = on;
              SettingsStore.setSeamlessRecovery(on);
            }
          })

          SurfaceRow({
            title: Tr.t('Seamless recovery delay'),
            description: Tr.t('How long the tunnel has to stay silent, in seconds, before it is started again'),
            icon: $r('app.media.ic_timer'),
            trailingText: `${this.delay}s`,
            chevron: true,
            onTap: () => {
              this.sheet = true;
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
    .bindSheet(this.sheet, this.delaySheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('recovery'),
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })
    .padding({ top: this.safeTop })
  }

  @Builder
  delaySheet() {
    Column() {
      Row() {
        // Same title as every other settings sheet: 16fp, 24vp inset, no fixed
        // row height — this is a picker, not a screen header.
        Text(Tr.t('Seamless recovery delay'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          // Same size as the other sheets, but the heavier weight is what
          // keeps it reading as the header over 14fp options.
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      // A picker with a handful of rows sizes itself: a `Scroll` needs a
      // bounded height, so under `FIT_CONTENT` the rows sit in a plain column.
      Column() {
        ForEach(DELAYS, (seconds: number) => {
          SurfaceRow({
            title: seconds === 1 ? Tr.t('1 second')
              : `${seconds} ${Tr.t('Seconds').toLowerCase()}`,
            compact: true,
            // The chosen option is the one marked in the accent colour; the word
            // stays for anyone who reads colours poorly.
            tint: this.delay === seconds ? Palette.PRIMARY : Palette.ON_SURFACE,
            trailingText: this.delay === seconds ? Tr.t('Selected') : '',
            onTap: () => {
              this.delay = seconds;
              SettingsStore.setRecoveryDelay(seconds);
              this.sheet = false;
            }
          })
        }, (seconds: number) => `${seconds}-${this.delay === seconds}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ bottom: 48 })
  }
}
