import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT, applySchemeAndReload, resolveTheme } from '../theme/Theme';
import { SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';

interface ThemeOption {
  value: string;
  title: string;
  note: string;
}

/**
 * `ThemedTheme` in the reference: Dark, Light, Automatic, Dynamic, Darker,
 * AMOLED. Automatic leads, because it is the default a fresh install starts on;
 * the rest runs from the lightest palette to the darkest; Dynamic is gone, since
 * HarmonyOS has no accent-colour API to follow.
 */
const THEMES: ThemeOption[] = [
  { value: 'automatic', title: Tr.t('Automatic'), note: Tr.t('Follow the system appearance') },
  { value: 'light', title: Tr.t('Light'), note: Tr.t('Light surfaces on a white background') },
  { value: 'dark', title: Tr.t('Dark'), note: Tr.t('The default palette') },
  { value: 'darker', title: Tr.t('Darker'), note: Tr.t('Dim the surfaces a step further') },
  { value: 'amoled', title: Tr.t('AMOLED'), note: Tr.t('True black, for OLED panels') }
];

@Entry
@Component
struct Display {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State themeValue: string = 'dark';

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.themeValue = SettingsStore.theme();
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
          Text(Tr.t('Display theme'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('How the app is drawn'))
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
          SectionHeader({ label: Tr.t('Display') })

          ForEach(THEMES, (option: ThemeOption) => {
            Row() {
              Column() {
                Text(option.title)
                  .fontSize(Type.BODY_LARGE)
                  .fontFamily(FONT)
                  .fontColor(this.themeValue === option.value ? Palette.PRIMARY : Palette.ON_SURFACE)
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

              if (this.themeValue === option.value) {
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
              this.themeValue = option.value;
              SettingsStore.setTheme(option.value);
              // Paint immediately: every screen subscribes to the tick that
              // applyScheme bumps, so the page behind this one is repainted too.
              applySchemeAndReload(resolveTheme(option.value, getContext(this) as common.UIAbilityContext));
            })
          }, (option: ThemeOption) => option.value)

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
