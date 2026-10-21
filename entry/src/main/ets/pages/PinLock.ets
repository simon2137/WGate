import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, FONT, ROW_PAD_H } from '../theme/Theme';
import { PinLockPad } from '../components/PinLockPad';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { Diag } from '../util/Diag';

/**
 * `ui/screens/pin/PinLockScreen.kt`, reached from Security when a PIN is set.
 * Creation writes the hash and turns app lock on; the lock on launch lives in
 * `pages/Home`.
 */
@Entry
@Component
struct PinLock {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State error: string = '';
  @State mode: string = 'create';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    Diag.init(context);
    const params = router.getParams() as Record<string, string>;
    if (params !== undefined && params !== null && params.mode !== undefined) {
      this.mode = params.mode;
    }
  }

  private submit(code: string): void {
    if (this.mode === 'unlock') {
      if (SettingsStore.checkPin(code)) {
        Diag.write('pin: unlocked');
        router.back();
      } else {
        this.error = 'Pin is incorrect';
        setTimeout(() => {
          this.error = '';
        }, 1600);
      }
      return;
    }
    SettingsStore.setPin(code);
    Diag.write('pin: created');
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
        Text(this.mode === 'unlock' ? Tr.t('App lock') : Tr.t('App lock'))
          .fontSize(Type.TITLE_LARGE)
          .fontFamily(FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ right: ROW_PAD_H })
      .alignItems(VerticalAlign.Center)

      PinLockPad({
        title: this.mode === 'unlock' ? 'Enter PIN' : 'Create PIN',
        subtitle: this.mode === 'unlock' ? '' : 'Four digits, asked for when the app opens',
        error: this.error,
        onCode: (code: string) => {
          this.submit(code);
        }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .padding({ top: this.safeTop })
  }
}
