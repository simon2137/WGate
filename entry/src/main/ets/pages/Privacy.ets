import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { Tr } from '../i18n/Tr';

/**
 * The privacy policy is not written here any more: it is hosted by Huawei, the
 * same agreement the store shows for this app, and this page opens it.
 *
 * The link is the one below. `lang` follows the interface language, so the
 * agreement opens in the language the user is reading the app in.
 */
const AGREEMENT: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html' +
  '?agreementId=2069872513088805568&lang=';

function agreementUrl(): string {
  const locale: string = Tr.locale();
  if (locale === 'en') {
    return AGREEMENT + 'en';
  }
  if (locale === 'zh_TW' || locale === 'zh_HK') {
    return AGREEMENT + 'zh-Hant';
  }
  return AGREEMENT + 'zh';
}

@Entry
@Component
struct Privacy {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;

  private open(): void {
    const url: string = agreementUrl();
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.openLink(url).catch(() => {
      promptAction.showToast({ message: Tr.t('Could not open a browser'), duration: 2500 });
    });
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
          Text(Tr.t('Privacy policy'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('Hosted by Huawei, the same agreement the app store shows'))
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
          Text(Tr.t('The privacy policy is generated from this app’s details by the app store’s agreement service and hosted there. The button below opens it in your browser.'))
            .fontSize(Type.BODY_MEDIUM)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
            .padding({ top: 16, bottom: 16 })

          Button(Tr.t('Open the privacy policy'))
            .width('100%')
            .height(48)
            .fontSize(Type.LABEL_MEDIUM)
            .fontFamily(FONT)
            .fontColor(Palette.BACKGROUND)
            .backgroundColor(Palette.PRIMARY)
            .borderRadius(24)
            .margin({ top: 8 })
            .onClick(() => {
              this.open();
            })

          Text(agreementUrl())
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .padding({ top: 18, bottom: 14 })
            .textAlign(TextAlign.Center)

          Column().height(BAR_SPACE)
        }
        .width('100%')
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
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
