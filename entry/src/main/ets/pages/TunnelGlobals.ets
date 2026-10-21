import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

/**
 * `ui/screens/settings/globals/TunnelGlobalsScreen.kt`: the global split
 * tunneling switch and the interface defaults a new tunnel inherits.
 */
@Entry
@Component
struct TunnelGlobals {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State mtu: string = '1420';
  @State keepalive: string = '25';
  @State dns: string = '1.1.1.1';
  @State sheet: boolean = false;
  @State note: string = '';

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.mtu = SettingsStore.defaultMtu().toString();
    this.keepalive = SettingsStore.defaultKeepalive().toString();
    this.dns = SettingsStore.defaultDns();
  }

  private flash(message: string): void {
    this.note = message;
    setTimeout(() => {
      if (this.note === message) {
        this.note = '';
      }
    }, 2200);
  }

  @Builder
  private fieldRow(label: string, value: string, key: string) {
    Row() {
      Text(label)
        .fontSize(Type.BODY_MEDIUM)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .width(96)
      TextInput({ text: value })
        .layoutWeight(1)
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(Palette.SURFACE)
        .fontColor(Palette.ON_SURFACE)
        .type(InputType.Normal)
        .onChange((text: string) => {
          if (key === 'mtu') {
            this.mtu = text;
          } else if (key === 'keepalive') {
            this.keepalive = text;
          } else {
            this.dns = text;
          }
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private configSheet() {
    Column() {
      Row() {
        Text(Tr.t('Tunnel configuration'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
        // Same icon button as the DNS sheet: the reference app never writes
        // "Save" out in a settings header, it uses `Icons.Rounded.Save`.
        Row() {
          Image($r('app.media.ic_save'))
            .width(24)
            .height(24)
            .fillColor(Palette.PRIMARY)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(Tr.t('Save'))
        .onClick(() => {
            const mtuValue: number = Number.parseInt(this.mtu, 10);
            const keepValue: number = Number.parseInt(this.keepalive, 10);
            SettingsStore.setDefaultMtu(Number.isNaN(mtuValue) || mtuValue <= 0 ? 1420 : mtuValue);
            SettingsStore.setDefaultKeepalive(Number.isNaN(keepValue) || keepValue < 0 ? 25 : keepValue);
            SettingsStore.setDefaultDns(this.dns);
            // Read the stored values back: an unparsable field ("abc") is saved as
            // the default, and the summary row has to show what was really kept.
            this.mtu = SettingsStore.defaultMtu().toString();
            this.keepalive = SettingsStore.defaultKeepalive().toString();
            this.dns = SettingsStore.defaultDns();
            this.sheet = false;
            this.flash(Tr.t('Interface defaults saved'));
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 12 })

      Text(Tr.t('Applied to a tunnel whose configuration leaves the value out.'))
        .fontSize(Type.BODY_SMALL)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 12 })

      this.fieldRow(Tr.t('MTU'), this.mtu, 'mtu')
      // Deliberately not translated: "keepalive" is the WireGuard field name and
      // reads as itself in every interface, as MTU and DNS already do.
      this.fieldRow('keepalive', this.keepalive, 'keepalive')
      this.fieldRow('DNS', this.dns, 'dns')
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
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
          Text(Tr.t('Tunnel globals'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('Interface defaults'))
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
          SurfaceRow({
            title: Tr.t('Tunnel configuration'),
            icon: $r('app.media.ic_doc'),
            description: `${Tr.t('MTU')} ${this.mtu} · keepalive ${this.keepalive}s · ${Tr.t('DNS')} ${this.dns}`,
            chevron: true,
            onTap: () => {
              this.sheet = true;
            }
          })
        }
        .width('100%')
        .padding({ bottom: BAR_SPACE })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      if (this.note.length > 0) {
        Text(this.note)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.BACKGROUND)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(Palette.PRIMARY)
          .borderRadius(8)
          .margin({ bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .bindSheet(this.sheet, this.configSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('tunnel globals'),
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })
    .padding({ top: this.safeTop })
  }
}
