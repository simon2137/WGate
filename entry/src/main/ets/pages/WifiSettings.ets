import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, FONT, ROW_PAD_H, BAR_SPACE } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';

/** A MAC address is six hex pairs; the reference rejects anything else. */
function isBssid(value: string): boolean {
  const parts: string[] = value.split(':');
  if (parts.length !== 6) {
    return false;
  }
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i];
    if (part.length !== 2) {
      return false;
    }
    if (!/^[0-9a-fA-F]{2}$/.test(part)) {
      return false;
    }
  }
  return true;
}

/**
 * `ui/screens/autotunnel/wifi/WifiSettingsScreen.kt`: the Wi-Fi preferences the
 * Auto-tunnel Wi-Fi row opens. General holds the detection method and the
 * wildcard switch; Wi-Fi rules holds the trusted SSID and BSSID editors, the
 * captive-portal switch and the tunnel mapping.
 */
@Entry
@Component
struct WifiSettings {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State ssids: string[] = [];
  @State bssids: string[] = [];
  @State ssidDraft: string = '';
  @State bssidDraft: string = '';
  @State wildcards: boolean = false;
  @State captive: boolean = false;
  @State bssidError: string = '';

  aboutToAppear(): void {
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
    this.reload();
  }

  private reload(): void {
    this.ssids = SettingsStore.ssids();
    this.bssids = SettingsStore.bssids();
    this.wildcards = SettingsStore.wildcards();
    this.captive = SettingsStore.captivePortal();
  }

  private addSsid(): void {
    const name: string = this.ssidDraft.trim();
    if (name.length === 0) {
      return;
    }
    SettingsStore.addSsid(name);
    this.ssidDraft = '';
    this.ssids = SettingsStore.ssids();
  }

  private addBssid(): void {
    const value: string = this.bssidDraft.trim();
    if (value.length === 0) {
      return;
    }
    if (!isBssid(value)) {
      this.bssidError = 'Use six hex pairs, like a4:2b:8c:11:03:9f';
      return;
    }
    this.bssidError = '';
    SettingsStore.addBssid(value.toLowerCase());
    this.bssidDraft = '';
    this.bssids = SettingsStore.bssids();
  }

  @Builder
  private ssidList() {
    if (this.ssids.length === 0) {
      Text(Tr.t('None yet'))
        .fontSize(Type.BODY_MEDIUM)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .width('100%')
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
    } else {
      ForEach(this.ssids, (rule: string) => {
        Row() {
          Text(rule)
            .fontSize(Type.BODY_LARGE)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .layoutWeight(1)
          Text(Tr.t('Remove'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.ALERT)
            .onClick(() => {
              SettingsStore.removeSsid(rule);
              this.ssids = SettingsStore.ssids();
            })
        }
        .width('100%')
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 8 })
      }, (rule: string) => rule)
    }
  }

  @Builder
  private bssidList() {
    if (this.bssids.length === 0) {
      Text(Tr.t('None yet'))
        .fontSize(Type.BODY_MEDIUM)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .width('100%')
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
    } else {
      ForEach(this.bssids, (rule: string) => {
        Row() {
          Text(rule)
            .fontSize(Type.BODY_LARGE)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .layoutWeight(1)
          Text(Tr.t('Remove'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.ALERT)
            .onClick(() => {
              SettingsStore.removeBssid(rule);
              this.bssids = SettingsStore.bssids();
            })
        }
        .width('100%')
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 8 })
      }, (rule: string) => rule)
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
        .margin({ right: 8 })
        .onClick(() => {
          router.back();
        })

        Column() {
          Text(Tr.t('Wi-Fi'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('Detection, rules and mapping'))
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
          SectionHeader({ label: Tr.t('General') })
          SurfaceRow({
            title: Tr.t('Use wildcards'),
            icon: $r('app.media.ic_reorder'),
            description: Tr.t('Match names by prefix, so "Work*" covers Work and Work-5G'),
            hasSwitch: true,
            switchOn: this.wildcards,
            onSwitch: (on: boolean) => {
              this.wildcards = on;
              SettingsStore.setWildcards(on);
            },
            onTap: () => {
              this.wildcards = !this.wildcards;
              SettingsStore.setWildcards(this.wildcards);
            }
          })

          SectionHeader({ label: Tr.t('Wi-Fi rules') })

          Column() {
            Text(Tr.t('Trusted Wi-Fi names'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .width('100%')
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
            this.ssidList()
            if (this.wildcards) {
              Text(Tr.t('A name may end in * to match every SSID with that prefix'))
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.MUTED)
                .width('100%')
                .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
            }
            Row() {
              TextInput({ placeholder: Tr.t('Network name (SSID)'), text: this.ssidDraft })
                .layoutWeight(1)
                .height(44)
                .fontSize(Type.BODY_MEDIUM)
                .fontFamily(FONT)
                .fontColor(Palette.ON_SURFACE)
                .placeholderColor(Palette.MUTED)
                .backgroundColor(Palette.RAISED)
                .borderRadius(22)
                .padding({ left: 16, right: 16 })
                .onChange((text: string) => {
                  this.ssidDraft = text;
                })
              Text(Tr.t('Add'))
                .fontSize(Type.BODY_MEDIUM)
                .fontFamily(FONT)
                .fontColor(Palette.PRIMARY)
                .margin({ left: 16 })
                .onClick(() => {
                  this.addSsid();
                })
            }
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 6, bottom: 12 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')

          Column() {
            Text(Tr.t('Trusted BSSID'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .width('100%')
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
            this.bssidList()
            if (this.wildcards) {
              Text(Tr.t('A BSSID may end in * to match every access point with that vendor prefix'))
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.MUTED)
                .width('100%')
                .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
            }
            if (this.bssidError.length > 0) {
              Text(this.bssidError)
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.ALERT)
                .width('100%')
                .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 6 })
            }
            Row() {
              TextInput({ placeholder: 'a4:2b:8c:11:03:9f', text: this.bssidDraft })
                .layoutWeight(1)
                .height(44)
                .fontSize(Type.BODY_MEDIUM)
                .fontFamily(FONT)
                .fontColor(Palette.ON_SURFACE)
                .placeholderColor(Palette.MUTED)
                .backgroundColor(Palette.RAISED)
                .borderRadius(22)
                .padding({ left: 16, right: 16 })
                .onChange((text: string) => {
                  this.bssidDraft = text;
                })
              Text(Tr.t('Add'))
                .fontSize(Type.BODY_MEDIUM)
                .fontFamily(FONT)
                .fontColor(Palette.PRIMARY)
                .margin({ left: 16 })
                .onClick(() => {
                  this.addBssid();
                })
            }
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 6, bottom: 12 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')

          SurfaceRow({
            title: Tr.t('Stop while captive portal'),
            icon: $r('app.media.ic_public_off'),
            description: Tr.t('Keep the tunnel down until the portal has been passed'),
            hasSwitch: true,
            switchOn: this.captive,
            onSwitch: (on: boolean) => {
              this.captive = on;
              SettingsStore.setCaptivePortal(on);
            },
            onTap: () => {
              this.captive = !this.captive;
              SettingsStore.setCaptivePortal(this.captive);
            }
          })
          SurfaceRow({
            title: Tr.t('Tunnel mapping'),
            icon: $r('app.media.ic_route'),
            description: Tr.t('Which tunnel comes up on Wi-Fi'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/PreferredTunnel', params: { net: 'wifi' } });
            }
          })

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