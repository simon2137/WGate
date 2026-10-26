import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { WgTunnel, toWgQuick, toQrText } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { publishedTunnelId, readStatus, formatBytes, ago, stateLabel } from '../service/EngineStatus';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SectionHeader } from '../components/SurfaceRow';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

const QR_MAX_CHARS: number = 512;

/**
 * The configuration screen from `ConfigScreen.kt`: the wg-quick text in a
 * monospace block with a copy action and a QR code, plus the live counters
 * when opened from "View live tunnel".
 */
@Entry
@Component
struct TunnelConfig {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State tunnel: WgTunnel | null = null;
  @State configText: string = '';
  @State qrText: string = '';
  @State showQr: boolean = false;
  @State showSensitive: boolean = false;
  @State menuOpen: boolean = false;
  @State live: boolean = false;
  @State liveLine: string = '';
  @State toast: string = '';
  private tunnelId: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    const params = router.getParams() as Record<string, string>;
    if (params !== undefined && params !== null) {
      const id = params['id'];
      if (id !== undefined) {
        this.tunnelId = id;
      }
      this.live = params['live'] === '1';
    }
    this.tunnel = TunnelStore.find(this.tunnelId);
    if (this.tunnel !== null) {
      this.configText = toWgQuick(this.tunnel!);
      this.qrText = toQrText(this.tunnel!);
    }
    this.tick();
    if (this.live) {
      this.timer = setInterval(() => {
        this.tick();
      }, 1000);
    }
  }

  /**
   * `router.pushUrl().then()` resolves when the page is pushed, not when the
   * pushed page pops, so the configuration is re-read here instead.
   */
  onPageShow(): void {
    const fresh: WgTunnel | null = TunnelStore.find(this.tunnelId);
    if (fresh !== null) {
      this.tunnel = fresh;
      this.configText = toWgQuick(fresh);
      this.qrText = toQrText(fresh);
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private tick(): void {
    if (!this.live) {
      return;
    }
    const running: boolean = publishedTunnelId() === this.tunnelId;
    const status = readStatus();
    if (!running || status === null) {
      this.liveLine = Tr.t('Disconnected');
      return;
    }
    // The reference draws transfer stats as an arrow plus a size
    // (`TransferStatsRow`), so the arrows stand in for "received"/"sent" here.
    this.liveLine = `${stateLabel(status.state)} · ↓ ${formatBytes(status.rxBytes)} · ` +
      `↑ ${formatBytes(status.txBytes)} · ${status.peersUp}/${status.peerCount} · ${ago(status.handshakeMs)}`;
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2000);
  }

  /** The reference's maskSensitive: keys become 44 dots until revealed. */
  private display(): string {
    if (this.showSensitive) {
      return this.configText;
    }
    const mask: string = '\u2022'.repeat(44);
    const keys: string[] = ['PrivateKey', 'PresharedKey', 'PreSharedKey'];
    const lines: string[] = this.configText.split('\n');
    const out: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const trimmed: string = line.trimStart();
      let sensitive: boolean = false;
      for (let k = 0; k < keys.length; k++) {
        if (trimmed.startsWith(`${keys[k]} =`)) {
          sensitive = true;
        }
      }
      if (sensitive) {
        const eq: number = line.indexOf('=');
        out.push(`${line.substring(0, eq)}= ${mask}`);
      } else {
        out.push(line);
      }
    }
    return out.join('\n');
  }

  private copy(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.configText);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.flash('Configuration copied');
    }).catch(() => {
      this.flash('Could not copy the configuration');
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
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
            Text(this.live ? Tr.t('Live tunnel') : Tr.t('Configuration'))
              .fontSize(Type.TITLE_LARGE)
              .minFontSize(14)
              .maxFontSize(Type.TITLE_LARGE)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontFamily(FONT)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.ON_SURFACE)
              .width('100%')
            Text(this.tunnel === null ? '' : this.tunnel!.name)
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (!this.live) {
            // The reference puts a 24dp icon in a 48dp IconButton; the actions
            // are `Icons.Outlined.Edit`, `RemoveRedEye` and `MoreVert`.
            Column() {
              Image($r('app.media.ic_edit'))
                .width(24)
                .height(24)
                .fillColor(Palette.ON_SURFACE)
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              router.pushUrl({ url: 'pages/ConfigEdit', params: { id: this.tunnelId } })
                .then(() => {
                  this.tunnel = TunnelStore.find(this.tunnelId);
                  if (this.tunnel !== null) {
                    this.configText = toWgQuick(this.tunnel!);
                    this.qrText = toQrText(this.tunnel!);
                  }
                });
            })
            .accessibilityText(Tr.t('Edit tunnel'))
          }
          Column() {
            Image($r('app.media.ic_remove_red_eye'))
              .width(24)
              .height(24)
              .fillColor(Palette.ON_SURFACE)
          }
          .width(48)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showSensitive = !this.showSensitive;
          })
          .accessibilityText(Tr.t('Toggle sensitive data visibility'))
          if (!this.live) {
            Column() {
              Image($r('app.media.ic_more'))
                .width(24)
                .height(24)
                .fillColor(Palette.ON_SURFACE)
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .margin({ right: ROW_PAD_H - 12 })
            .onClick(() => {
              this.menuOpen = true;
            })
            .accessibilityText(Tr.t('More options'))
          }
        }
        .width('100%')
        .height(64)
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            if (this.live) {
              Text(this.liveLine)
                .fontSize(Type.BODY_SMALL)
                .fontFamily(FONT)
                .fontColor(Palette.PRIMARY)
                .width('100%')
                .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 12 })
            }

            Text(this.display())
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(Palette.ON_SURFACE)
              .backgroundColor(Palette.SURFACE)
              .padding(16)
              .borderRadius(8)
              .width('100%')
              .lineHeight(18)



            if (this.showQr) {
              Column() {
                Row() {
                  QRCode(this.qrText)
                    .width('100%')
                    .height('100%')
                    .color('#000000')
                }
                .width(260)
                .height(260)
                .padding(10)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .backgroundColor('#FFFFFF')
                .borderRadius(12)
                Text(Tr.t('Scan this with another device to import the same tunnel.'))
                  .fontSize(Type.BODY_SMALL)
                  .fontFamily(FONT)
                  .fontColor(Palette.MUTED)
                  .textAlign(TextAlign.Center)
                  .margin({ top: 12 })
              }
              .width('100%')
              .padding({ top: 20 })
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('100%')
          .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: BAR_SPACE })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .backgroundColor(Palette.RAISED)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .margin({ bottom: 48 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .bindSheet($$this.menuOpen, this.menuBody(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('tunnel menu'),
      backgroundColor: Palette.SURFACE
    })
    .padding({ top: this.safeTop })
  }

  @Builder
  menuBody() {
    Column() {
      Row() {
        Text(Tr.t('Configuration'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })

      Row() {
        Image($r('app.media.ic_qr'))
          .width(22)
          .height(22)
          .fillColor(Palette.ON_SURFACE)
          .margin({ right: 16 })
        Text(Tr.t('Show QR'))
          .fontSize(Type.BODY_LARGE)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
      .onClick(() => {
        this.menuOpen = false;
        if (this.qrText.length > QR_MAX_CHARS) {
          this.flash('Too long for one QR code, use Copy instead');
          return;
        }
        this.showQr = true;
      })

      Row() {
        Image($r('app.media.ic_copy'))
          .width(22)
          .height(22)
          .fillColor(Palette.ON_SURFACE)
          .margin({ right: 16 })
        Text(Tr.t('Copy'))
          .fontSize(Type.BODY_LARGE)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
      .onClick(() => {
        this.menuOpen = false;
        this.copy();
      })

      if (this.showQr) {
        Text(Tr.t('Tap the QR once more in the list to hide it, or use Copy.'))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
          .padding({ left: ROW_PAD_H, right: ROW_PAD_H, bottom: 16 })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ bottom: 12 })
  }
}
