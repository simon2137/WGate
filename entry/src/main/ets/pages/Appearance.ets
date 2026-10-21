import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { localeLabel } from '../i18n/Locales';

/**
 * The trailing text on the theme row. Translated through the catalogue because
 * the names are user-visible words, not identifiers.
 */
function themeLabel(value: string): string {
  if (value === 'automatic') {
    return Tr.t('Automatic');
  } else if (value === 'darker') {
    return Tr.t('Darker');
  } else if (value === 'amoled') {
    return 'AMOLED';
  } else if (value === 'light') {
    return Tr.t('Light');
  }
  return Tr.t('Dark');
}


/**
 * `ui/screens/settings/appearance/AppearanceScreen.kt`: Display (language,
 * display theme) and Notifications. The two Display rows open their own pages,
 * as `LanguageScreen.kt` and `DisplayScreen.kt` do.
 */
@Entry
@Component
struct Appearance {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State themeValue: string = 'dark';
  @State languageValue: string = 'system';
  private timer: number = -1;

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.themeValue = SettingsStore.theme();
    this.languageValue = SettingsStore.language();
    // Returning from either page must refresh the trailing text; router.back()
    // does not re-run aboutToAppear and onPageShow proved unreliable here, so
    // the two values are polled the same way the tunnel screens do it.
    this.timer = setInterval(() => {
      const theme: string = SettingsStore.theme();
      const language: string = SettingsStore.language();
      if (theme !== this.themeValue) {
        this.themeValue = theme;
      }
      if (language !== this.languageValue) {
        this.languageValue = language;
      }
    }, 500);
  }

  // The timer is deliberately not cleared on disappear: pushing either child
  // page stops the callback and router.back() does not restart it, so the row
  // text would stay stale. The callback is cheap and the page owns it.
  onPageShow(): void {
    this.themeValue = SettingsStore.theme();
    this.languageValue = SettingsStore.language();
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
          Text(Tr.t('Appearance'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('Display and notifications'))
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
          SectionHeader({ label: Tr.t('Display') })
          SurfaceRow({
            title: Tr.t('Language'),
            icon: $r('app.media.ic_globe'),
            trailingText: localeLabel(this.languageValue),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Language' });
            }
          })
          SurfaceRow({
            title: Tr.t('Display theme'),
            icon: $r('app.media.ic_star'),
            trailingText: themeLabel(this.themeValue),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Display' });
            }
          })

          SurfaceRow({
            title: Tr.t('Notifications'),
            icon: $r('app.media.ic_doc'),
            description: Tr.t('Live updates and transfer details'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Notifications' });
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
