import { Palette, Type, FONT } from '../theme/Theme';

const KEYS: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];

/**
 * The keypad from `xyz.teamgravity.pin_lock_compose`, which the reference app
 * uses for `PinLockScreen`: four dots above a 3x4 grid, backspace in the last
 * cell. The parent owns the PIN check, the pad only collects four digits.
 */
@Component
export struct PinLockPad {
  @StorageProp('theme_tick') themeTick: number = 0;
  @Prop title: string = 'Enter PIN';
  @Prop subtitle: string = '';
  /** The parent writes the message that should clear the dots. */
  @Prop @Watch('onErrorChanged') error: string = '';
  onCode: (code: string) => void = () => {};

  @State entered: string = '';

  aboutToAppear(): void {
    this.entered = '';
  }

  onErrorChanged(): void {
    if (this.error.length > 0) {
      this.entered = '';
    }
  }

  private press(key: string): void {
    if (key === '<') {
      this.entered = this.entered.slice(0, Math.max(0, this.entered.length - 1));
      return;
    }
    if (key.length === 0 || this.entered.length >= 4) {
      return;
    }
    this.entered = this.entered + key;
    if (this.entered.length === 4) {
      const code: string = this.entered;
      setTimeout(() => {
        this.onCode(code);
      }, 120);
    }
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(Type.TITLE_LARGE)
        .fontFamily(FONT)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.ON_SURFACE)
        .margin({ top: 48 })

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
          .margin({ top: 6 })
      }

      Row({ space: 18 }) {
        ForEach([0, 1, 2, 3], (index: number) => {
          Circle()
            .width(14)
            .height(14)
            .fill(this.entered.length > index ? Palette.PRIMARY : Color.Transparent)
            .stroke(this.entered.length > index ? Palette.PRIMARY : Palette.MUTED)
            .strokeWidth(1.5)
        }, (index: number) => index.toString())
      }
      .margin({ top: 36 })

      Text(this.error.length > 0 ? this.error : ' ')
        .fontSize(Type.BODY_SMALL)
        .fontFamily(FONT)
        .fontColor(Palette.ALERT)
        .margin({ top: 16, bottom: 24 })

      Grid() {
        ForEach(KEYS, (key: string) => {
          GridItem() {
            if (key.length === 0) {
              Blank()
            } else if (key === '<') {
              Image($r('app.media.ic_back'))
                .width(24)
                .height(24)
                .fillColor(Palette.ON_SURFACE)
            } else {
              Text(key)
                .fontSize(26)
                .fontFamily(FONT)
                .fontColor(Palette.ON_SURFACE)
            }
          }
          .width(76)
          .height(68)
          .borderRadius(38)
          .backgroundColor(key.length === 0 ? Color.Transparent : Palette.SURFACE)
          .onClick(() => {
            this.press(key);
          })
        }, (key: string) => key)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(14)
      .columnsGap(20)
      .width(268)
      .height(4 * 68 + 3 * 14)

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }
}
