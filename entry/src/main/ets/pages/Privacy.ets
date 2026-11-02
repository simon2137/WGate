import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { Palette, Type, ROW_PAD_H, FONT } from '../theme/Theme';
import { Tr } from '../i18n/Tr';

/**
 * The privacy policy is hosted by Huawei — the agreement the store generates for
 * this app — and it is shown here, inside the page, rather than behind a button:
 * a policy a reader has to ask for twice is a policy nobody reads.
 *
 * The `lang` parameter follows the interface language so the agreement arrives
 * in the language the app is being read in. When the document cannot load (no
 * network, for instance) the page says so and offers the browser as a way out
 * instead of leaving an empty sheet.
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
  @State progress: number = 0;
  @State failed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  private openInBrowser(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.openLink(agreementUrl()).catch(() => {
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

      if (this.failed) {
        Column() {
          Text(Tr.t('Could not load the privacy policy'))
            .fontSize(Type.BODY_MEDIUM)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .textAlign(TextAlign.Center)
          Button(Tr.t('Try again'))
            .height(44)
            .fontSize(Type.LABEL_MEDIUM)
            .fontFamily(FONT)
            .fontColor(Palette.BACKGROUND)
            .backgroundColor(Palette.PRIMARY)
            .borderRadius(22)
            .padding({ left: 24, right: 24 })
            .margin({ top: 16 })
            .onClick(() => {
              this.failed = false;
              this.controller.loadUrl(agreementUrl());
            })
          Text(Tr.t('Open it in the browser'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .decoration({ type: TextDecorationType.Underline })
            .margin({ top: 18 })
            .onClick(() => {
              this.openInBrowser();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 32, right: 32 })
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Top }) {
          Web({ src: agreementUrl(), controller: this.controller })
            .width('100%')
            .height('100%')
            .backgroundColor(Palette.BACKGROUND)
            .darkMode(WebDarkMode.Off)
            .onProgressChange((event) => {
              if (event) {
                this.progress = event.newProgress;
              }
            })
            .onPageEnd(() => {
              this.failed = false;
            })
            .onErrorReceive(() => {
              this.failed = true;
            })

          if (this.progress < 100) {
            Row()
              .width(`${this.progress}%`)
              .height(2)
              .backgroundColor(Palette.PRIMARY)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .padding({ top: this.safeTop })
  }
}
