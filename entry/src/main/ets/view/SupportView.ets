import { router } from '@kit.ArkUI';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { Tr } from '../i18n/Tr';

const VERSION: string = '1.0.0';

/**
 * The Support tab. The reference app's version of this screen is mostly links
 * out to the upstream project's website, chat room and translation platform;
 * this build keeps only what belongs to this app: the licence and what the
 * build contains, the privacy policy, and the version. The privacy policy is a
 * page in the app rather than a link, so it is readable offline and cannot rot
 * when a site moves.
 */
@Component
export struct SupportView {
  @StorageProp('theme_tick') themeTick: number = 0;
  onNote: (message: string) => void = () => {};

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
          SectionHeader({ label: Tr.t('Open source') })

          SurfaceRow({
            title: Tr.t('Licences'),
            description: Tr.t('GPL-3.0, the components in this build, and where the source is'),
            icon: $r('app.media.ic_balance'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/License' });
            }
          })

          SectionHeader({ label: Tr.t('Your data') })

          SurfaceRow({
            title: Tr.t('Privacy policy'),
            description: Tr.t('What stays on this device, and what never leaves it'),
            icon: $r('app.media.ic_doc'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Privacy' });
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
