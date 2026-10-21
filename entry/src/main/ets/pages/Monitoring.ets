import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

const INTERVALS: number[] = [500, 1000, 2000, 5000, 10000, 30000];

/**
 * `ui/screens/settings/monitoring/MonitoringScreen.kt`: whether the tunnel rows
 * show live statistics, and how often they are refreshed.
 */
@Entry
@Component
struct Monitoring {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State liveOn: boolean = true;
  @State interval: number = 1000;
  @State sheet: boolean = false;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    this.liveOn = SettingsStore.statisticsEnabled();
    this.interval = SettingsStore.statsInterval();
  }

  private refreshLabel(): string {
    if (this.interval < 1000) {
      return `${this.interval} ms`;
    }
    return `${this.interval / 1000} s`;
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
          Text(Tr.t('Tunnel monitoring'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('Statistics on the tunnel rows'))
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
          SectionHeader({ label: Tr.t('Statistics') })

          SurfaceRow({
            title: Tr.t('Tunnel statistics'),
            description: Tr.t('Show received and sent totals under a running tunnel'),
            icon: $r('app.media.ic_data'),
            hasSwitch: true,
            switchOn: this.liveOn,
            onSwitch: (on: boolean) => {
              this.liveOn = on;
              SettingsStore.setStatisticsEnabled(on);
            }
          })

          SurfaceRow({
            title: Tr.t('Refresh rate'),
            description: this.refreshLabel(),
            icon: $r('app.media.ic_reorder'),
            chevron: true,
            onTap: () => {
              this.sheet = true;
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
    .bindSheet(this.sheet, this.intervalSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('monitoring'),
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })
    .padding({ top: this.safeTop })
  }

  @Builder
  private intervalSheet() {
    Column() {
      Row() {
        Text(Tr.t('Refresh rate'))
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
          ForEach(INTERVALS, (ms: number) => {
            SurfaceRow({
              title: ms === 1000 ? Tr.t('1 second')
                : `${ms < 1000 ? ms : ms / 1000} ${ms < 1000 ? 'ms' : Tr.t('Seconds').toLowerCase()}`,
              trailingText: this.interval === ms ? Tr.t('Selected') : '',
              onTap: () => {
                this.interval = ms;
                SettingsStore.setStatsInterval(ms);
                this.sheet = false;
              }
            })
          }, (ms: number) => `${ms}-${this.interval === ms}`)
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
  }
}
