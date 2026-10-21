import { promptAction, router } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { Tr } from '../i18n/Tr';

const DOMAIN: number = 0x0001;
const TAG: string = 'Support';

const VERSION: string = '1.0.0';
/** Where the source of this build lives; GPL-3.0 also points at it. */
const SOURCE_URL: string = 'https://github.com/simon2137/WGate';
/** The author's address, without the scheme: the row shows it when no mail app is installed. */
const AUTHOR_MAIL: string = '273156878@qq.com';

/**
 * The Support tab. The reference app's version of this screen is mostly links
 * out to the upstream project's website, chat room and translation platform;
 * this build keeps only what belongs to this app: the licence and what the
 * build contains, the privacy policy, the ways to reach the author, and the
 * version. The privacy policy is a page in the app rather than a link, so it is
 * readable offline and cannot rot when a site moves.
 *
 * The licence list and the privacy policy are one section: they are the two
 * pages of legal text this app ships, and separating them asked the reader to
 * guess which of two near-identical headers a page was filed under.
 */
@Component
export struct SupportView {
  @StorageProp('theme_tick') themeTick: number = 0;

  /**
   * `openLink` asks the system which app registers for the link's scheme, which
   * is the difference between handing the address to a mail client and handing
   * a `mailto:` string to whatever takes arbitrary URIs (a browser turns it into
   * a web search). Asking `canOpenLink` first keeps a device with no mail client
   * from raising the system's own "nothing can open this" dialog: the address
   * goes to the clipboard with a toast, which is what the user needs to act on
   * it from a webmail or a second device.
   */
  private open(link: string, fallback: string): void {
    if (!this.canOpen(link)) {
      hilog.warn(DOMAIN, TAG, 'no handler for %{public}s', link);
      this.offer(fallback);
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.openLink(link).catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'openLink %{public}s rejected: %{public}s', link, String(error.code));
        this.offer(fallback);
      });
    } catch (error) {
      // `openLink` can also throw before it hands back a promise.
      hilog.warn(DOMAIN, TAG, 'openLink %{public}s threw: %{public}s', link,
        String((error as BusinessError).code));
      this.offer(fallback);
    }
  }

  /**
   * Nothing on the device can open the link, so the text itself becomes the
   * answer: copy it, then say so. A platform toast rather than the home page's
   * flash, because this one has to be readable while the tap is still fresh.
   */
  private offer(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: Tr.t('The address is on the clipboard'), duration: 2200 });
    }).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'clipboard rejected: %{public}s', String(error.code));
      promptAction.showToast({ message: text, duration: 2600 });
    });
  }

  /**
   * `canOpenLink` throws 17700055 for a malformed link and 17700056 when the
   * scheme is not listed under `querySchemes` in module.json5; both mean the
   * same thing to the caller.
   */
  private canOpen(link: string): boolean {
    try {
      return bundleManager.canOpenLink(link);
    } catch (error) {
      return false;
    }
  }

  private mail(): void {
    this.open('mailto:' + AUTHOR_MAIL, AUTHOR_MAIL);
  }

  build() {
    Column() {
      Row() {
        Text(Tr.t('Support'))
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
          SectionHeader({ label: Tr.t('Legal information') })

          SurfaceRow({
            title: Tr.t('Licences'),
            description: Tr.t('GPL-3.0, the components in this build, and where the source is'),
            icon: $r('app.media.ic_balance'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/License' });
            }
          })

          SurfaceRow({
            title: Tr.t('Privacy policy'),
            description: Tr.t('What stays on this device, and what never leaves it'),
            icon: $r('app.media.ic_doc'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Privacy' });
            }
          })

          SectionHeader({ label: Tr.t('Contact') })

          SurfaceRow({
            title: Tr.t('Project on GitHub'),
            icon: $r('app.media.ic_code'),
            trailingIcon: $r('app.media.ic_launch'),
            onTap: () => {
              this.open(SOURCE_URL, SOURCE_URL);
            }
          })

          SurfaceRow({
            title: Tr.t('Send me an email'),
            icon: $r('app.media.ic_mail'),
            trailingIcon: $r('app.media.ic_launch'),
            onTap: () => {
              this.mail();
            }
          })

          SectionHeader({ label: Tr.t('About') })

          SurfaceRow({
            title: Tr.t('Version'),
            trailingText: VERSION
          })

          Text(Tr.t('Thank you for using WGate!'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 12, bottom: 12 })
            .width('100%')
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
  }
}
