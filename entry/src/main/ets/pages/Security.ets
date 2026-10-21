import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Diag } from '../util/Diag';
import { Tr } from '../i18n/Tr';

/**
 * `ui/screens/settings/security/SecurityScreen.kt`: screen-capture protection
 * and the app PIN. Screen protection maps to the HarmonyOS privacy mode, which
 * really does blank the window in screenshots and recordings.
 */
@Entry
@Component
struct Security {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State screenGuard: boolean = false;
  @State pinOn: boolean = false;
  @State note: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    Diag.init(context);
    this.screenGuard = SettingsStore.screenGuard();
    this.pinOn = SettingsStore.pinHash().length > 0;
    this.applyGuard(this.screenGuard);
  }

  private applyGuard(on: boolean): void {
    window.getLastWindow(getContext(this) as common.UIAbilityContext)
      .then((win: window.Window) => {
        win.setWindowPrivacyMode(on)
          .then(() => {
            Diag.write(`privacy mode ${on ? 'on' : 'off'}`);
          })
          .catch((err: BusinessError) => {
            Diag.write(`privacy mode failed: ${err.code} ${err.message}`);
          });
      })
      .catch((err: BusinessError) => {
        Diag.write(`privacy mode window failed: ${err.code} ${err.message}`);
      });
  }

  private flash(message: string): void {
    this.note = message;
    setTimeout(() => {
      this.note = '';
    }, 2400);
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
          Text(Tr.t('Security'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('PIN lock and screen protection'))
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
          SectionHeader({ label: Tr.t('Protection') })

          SurfaceRow({
            title: Tr.t('Screen recording protection'),
            description: Tr.t('Hide the tunnel list from screenshots and screen recordings'),
            icon: $r('app.media.ic_screen_lock'),
            hasSwitch: true,
            switchOn: this.screenGuard,
            onSwitch: (on: boolean) => {
              this.screenGuard = on;
              SettingsStore.setScreenGuard(on);
              this.applyGuard(on);
            }
          })

          SurfaceRow({
            title: Tr.t('App lock'),
            description: Tr.t('Ask for a PIN before the tunnel list is shown'),
            icon: $r('app.media.ic_pin'),
            hasSwitch: true,
            switchOn: this.pinOn,
            onSwitch: (on: boolean) => {
              if (!on) {
                SettingsStore.setPin('');
                this.pinOn = false;
                this.flash('App lock turned off');
                return;
              }
              router.pushUrl({ url: 'pages/PinLock', params: { mode: 'create' } })
                .then(() => {
                  this.pinOn = SettingsStore.pinHash().length > 0;
                });
            }
          })

          if (this.note.length > 0) {
            Text(this.note)
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.PRIMARY)
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8 })
          }
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
