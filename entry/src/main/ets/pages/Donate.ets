import { router } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { Tr } from '../i18n/Tr';

/**
 * `support/donate/DonateScreen.kt`: the hero letter plus the three options
 * (crypto addresses, GitHub Sponsors, Liberapay).
 */
@Entry
@Component
struct Donate {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State toast: string = '';

  private open(url: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    context.startAbility(want).catch(() => {
      this.flash(url);
    });
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      this.toast = '';
    }, 1800);
  }

  build() {
    Stack() {
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
            Text(Tr.t('Donate'))
              .fontSize(Type.TITLE_LARGE)
              .fontFamily(FONT)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.ON_SURFACE)
            Text(Tr.t('Keep the project free'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
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
            Column() {
              Text(Tr.t('Thank you for considering donating to this project!'))
                .fontSize(Type.BODY_MEDIUM)
                .fontFamily(FONT)
                .fontColor(Palette.ON_SURFACE)
                .width('100%')

              Text(Tr.t('As the sole developer, I work tirelessly to make WGate the best free and ') +
                Tr.t('open-source WireGuard client, but this is only possible with your support.'))
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.MUTED)
                .width('100%')
                .margin({ top: 12 })

              Text(Tr.t('It is my dream to work for you on this project full-time.'))
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.MUTED)
                .width('100%')
                .margin({ top: 12 })

              Text(Tr.t('Gratefully,'))
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.MUTED)
                .width('100%')
                .margin({ top: 12 })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 16 })

            SectionHeader({ label: Tr.t('Options') })

            SurfaceRow({
              title: Tr.t('Cryptocurrency addresses'),
              description: Tr.t('Bitcoin, Monero, Ethereum and ten more'),
              icon: $r('app.media.ic_bolt'),
              chevron: true,
              onTap: () => {
                router.pushUrl({ url: 'pages/Addresses' });
              }
            })

            SurfaceRow({
              title: Tr.t('GitHub Sponsors'),
              description: Tr.t('github.com/sponsors/zaneschepke'),
              icon: $r('app.media.ic_globe'),
              trailingText: '>',
              onTap: () => {
                this.open('https://github.com/sponsors/zaneschepke');
              }
            })

            SurfaceRow({
              title: Tr.t('Liberapay'),
              description: Tr.t('liberapay.com/zaneschepke'),
              icon: $r('app.media.ic_globe'),
              trailingText: '>',
              onTap: () => {
                this.open('https://liberapay.com/zaneschepke');
              }
            })

            Text(Tr.t('Thank you for using WGate!'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 12, bottom: 12 })
              .width('100%')

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

      if (this.toast.length > 0) {
        Row() {
          Text(this.toast)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .maxLines(2)
        }
        .backgroundColor(Palette.RAISED)
        .borderRadius(20)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .margin({ bottom: 40, left: 24, right: 24 })
        .align(Alignment.Bottom)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTop })
  }
}
