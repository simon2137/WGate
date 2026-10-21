import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';

/**
 * `ui/screens/settings/appearance/notifications/NotificationsScreen.kt`: the
 * live-update switch plus the four detail switches the reference app exposes.
 */
@Entry
@Component
struct Notifications {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State live: boolean = true;
  @State origin: boolean = true;
  @State transfer: boolean = true;
  @State recovery: boolean = true;
  @State failureTint: boolean = true;

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.live = SettingsStore.notification('live');
    this.origin = SettingsStore.notification('origin');
    this.transfer = SettingsStore.notification('transfer');
    this.recovery = SettingsStore.notification('recovery');
    this.failureTint = SettingsStore.notification('failure_tint');
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
          Text(Tr.t('Notifications'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('What the status notification shows'))
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
          SectionHeader({ label: Tr.t('Live updates') })
          SurfaceRow({
            title: Tr.t('Enable'),
            icon: $r('app.media.ic_notifications_active'),
            description: Tr.t('Keep the notification in sync with the tunnel while it runs'),
            hasSwitch: true,
            switchOn: this.live,
            onSwitch: (on: boolean) => {
              this.live = on;
              SettingsStore.setNotification('live', on);
            }
          })
          SurfaceRow({
            title: Tr.t('Show origin'),
            icon: $r('app.media.ic_alt_route'),
            description: Tr.t('Show the interface the traffic leaves from'),
            hasSwitch: true,
            switchOn: this.origin,
            onSwitch: (on: boolean) => {
              this.origin = on;
              SettingsStore.setNotification('origin', on);
            }
          })
          SurfaceRow({
            title: Tr.t('Show transfer'),
            icon: $r('app.media.ic_swap_vert'),
            description: Tr.t('Show received and sent totals'),
            hasSwitch: true,
            switchOn: this.transfer,
            onSwitch: (on: boolean) => {
              this.transfer = on;
              SettingsStore.setNotification('transfer', on);
            }
          })
          SurfaceRow({
            title: Tr.t('Show recovery'),
            icon: $r('app.media.ic_replay'),
            description: Tr.t('Show a recovery line while the tunnel reconnects'),
            hasSwitch: true,
            switchOn: this.recovery,
            onSwitch: (on: boolean) => {
              this.recovery = on;
              SettingsStore.setNotification('recovery', on);
            }
          })
          SurfaceRow({
            title: Tr.t('Failure mark'),
            icon: $r('app.media.ic_warning_amber'),
            description: Tr.t('Mark the notification while the tunnel is down'),
            hasSwitch: true,
            switchOn: this.failureTint,
            onSwitch: (on: boolean) => {
              this.failureTint = on;
              SettingsStore.setNotification('failure_tint', on);
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
    .padding({ top: this.safeTop })
  }
}
