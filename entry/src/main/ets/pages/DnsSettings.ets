import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

function dnsText(): string {
  try {
    const net: connection.NetHandle = connection.getDefaultNetSync();
    if (net === null) {
      return 'No active network';
    }
    const props: connection.ConnectionProperties = connection.getConnectionPropertiesSync(net);
    const list: connection.NetAddress[] = props.dnses ?? [];
    // HarmonyOS reports "*" when the resolver is learned dynamically rather
    // than configured, so it is not an address to show.
    const parts: string[] = [];
    for (let i = 0; i < list.length; i++) {
      const address: string = list[i].address;
      if (address.length > 0 && address !== '*') {
        parts.push(address);
      }
    }
    if (parts.length === 0) {
      return 'The resolvers are assigned dynamically by the network';
    }
    return parts.join(', ');
  } catch (e) {
    return 'The DNS servers could not be read';
  }
}

/**
 * `ui/screens/settings/dns/DnsSettingsScreen.kt`, reduced to what HarmonyOS
 * exposes: the resolvers the system currently hands out, and the default the
 * app writes into an imported configuration.
 */
@Entry
@Component
struct DnsSettings {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State systemDns: string = '';
  @State defaultDns: string = '1.1.1.1';
  @State draft: string = '';
  @State sheet: boolean = false;

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.defaultDns = SettingsStore.defaultDns();
    this.systemDns = dnsText();
  }

  @Builder
  private editSheet() {
    Column() {
      Row() {
        Text(Tr.t('Default DNS'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
        // `Icons.Rounded.Save` as an icon button, the way the reference app saves
        // every settings screen (`currentBackStackEntryAsNavbarState.kt`). The
        // word stays in the accessibility label.
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
          SettingsStore.setDefaultDns(this.draft.trim());
          this.defaultDns = SettingsStore.defaultDns();
          this.sheet = false;
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 12 })

      TextInput({ placeholder: '1.1.1.1, 8.8.8.8', text: this.draft })
        .height(48)
        .margin({ left: 24, right: 24 })
        .backgroundColor(Palette.SURFACE)
        .fontColor(Palette.ON_SURFACE)
        .placeholderColor(Palette.MUTED)
        .onChange((text: string) => {
          this.draft = text;
        })

      Text(Tr.t('A tunnel that has no DNS line in its configuration inherits this value.'))
        .fontSize(Type.BODY_SMALL)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .padding({ left: 24, right: 24, top: 12 })
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
          Text(Tr.t('DNS settings'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('Resolvers handed to the tunnel'))
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
          SectionHeader({ label: Tr.t('System') })
          SurfaceRow({
            title: Tr.t('Current system DNS'),
            icon: $r('app.media.ic_globe'),
            description: this.systemDns,
            onTap: () => {
              this.systemDns = dnsText();
            }
          })

          SectionHeader({ label: Tr.t('Tunnel DNS') })
          SurfaceRow({
            title: Tr.t('Default DNS'),
            icon: $r('app.media.ic_dns'),
            description: this.defaultDns,
            chevron: true,
            onTap: () => {
              this.draft = this.defaultDns;
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .bindSheet(this.sheet, this.editSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('dns edit'),
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = false;
      }
    })
    .padding({ top: this.safeTop })
  }
}
