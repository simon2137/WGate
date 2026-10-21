import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT, reloadUi } from '../theme/Theme';
import { SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { offeredLocale } from '../i18n/Locales';

interface LocaleOption {
  value: string;
  title: string;
  note: string;
}

/**
 * The three interfaces this build offers. The catalogue still carries every
 * locale the reference ships a translation for (see `i18n/Catalog.ets`), but the
 * picker stays on the languages we can actually stand behind.
 *
 * The titles are written in their own language on purpose: a picker whose own
 * entries need translating cannot label itself while the locale is being
 * switched.
 */
const LOCALES: LocaleOption[] = [
  { value: 'en', title: 'English', note: 'English interface' },
  { value: 'zh_CN', title: '简体中文', note: '简体中文界面' },
  { value: 'zh_TW', title: '繁體中文', note: '繁體中文介面' }
];

/**
 * Folds whatever is stored onto one of the three offered interfaces. The rule
 * lives in `i18n/Locales.ets` so the startup path applies the same one.
 */

@Entry
@Component
struct Language {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State languageValue: string = 'en';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    const stored: string = SettingsStore.language();
    const resolved: string = offeredLocale(stored);
    this.languageValue = resolved;
    if (stored !== resolved) {
      // A language this build no longer offers was stored; rewrite it so the
      // next launch starts on the interface the picker shows.
      SettingsStore.setLanguage(resolved);
      Tr.setLocale(resolved);
    }
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
          Text(Tr.t('Language'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('The language the app is drawn in'))
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
          SectionHeader({ label: Tr.t('Language') })

          ForEach(LOCALES, (option: LocaleOption) => {
            Row() {
              Column() {
                Text(option.title)
                  .fontSize(Type.BODY_LARGE)
                  .fontFamily(FONT)
                  .fontColor(this.languageValue === option.value ? Palette.PRIMARY : Palette.ON_SURFACE)
                  .width('100%')
                Text(option.note)
                  .fontSize(Type.BODY_SMALL)
                  .fontFamily(FONT)
                  .fontColor(Palette.MUTED)
                  .width('100%')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.languageValue === option.value) {
                Image($r('app.media.ic_check_circle'))
                  .width(22)
                  .height(22)
                  .fillColor(Palette.PRIMARY)
              }
            }
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 10, bottom: 10 })
            .backgroundColor(Palette.SURFACE)
            .onClick(() => {
              this.languageValue = option.value;
              SettingsStore.setLanguage(option.value);
              Tr.setLocale(option.value);
              reloadUi();
            })
          }, (option: LocaleOption) => option.value)

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
    .padding({ top: this.safeTop })
  }
}
