import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { Palette, Type, ROW_PAD_H , FONT} from '../theme/Theme';
import { SectionHeader } from '../components/SurfaceRow';
import { Diag } from '../util/Diag';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';

/**
 * `ui/screens/settings/logs/LogsScreen.kt`: the startup trace the extension
 * shares through `Diag`.
 *
 * The native ring buffer used to be shown here as a second block, but the page
 * runs in the app process, which never opens an engine: `libwgcore.so` answers
 * `logs()` with an empty string there, so the block was permanently empty while
 * the engine's real lines arrive through the trace anyway (`drainEngineLog`
 * writes them as `engine: …`). Reading `wgcore` here also threw and aborted the
 * button handlers, which is why Refresh and Clear looked dead. The page now
 * touches the trace file only.
 */
@Entry
@Component
struct Logs {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State trace: string = '';
  @State empty: boolean = false;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    Diag.init(context);
    this.reload();
  }

  private reload(): void {
    const text: string = Diag.read().trim();
    this.empty = text.length === 0;
    this.trace = text;
  }

  /** The trace plus a header that makes the file self-describing when mailed. */
  private forExport(): string {
    const head: string[] = [
      '# WGate log',
      `# device: ${deviceInfo.productModel} / ${deviceInfo.osFullName}`,
      `# written: ${new Date().toISOString()}`,
      '#'
    ];
    return head.join('\n') + '\n' + (this.empty ? '(nothing recorded)' : this.trace) + '\n';
  }

  /** Local wall-clock stamp, matching the clock in the status bar. */
  private stamp(): string {
    const d: Date = new Date();
    const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
    return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  }

  private async exportTrace(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSaveOptions();
      // A fresh name per export, like the tunnel backup: the picker refuses to
      // overwrite silently and a timestamped file is easy to recognise. The
      // stamp is local wall-clock time, not `toISOString()`, which is UTC.
      options.newFileNames = [`wg-log-${this.stamp()}.txt`];
      const view = new picker.DocumentViewPicker(context);
      const uris: string[] = await view.save(options);
      if (uris.length === 0) {
        return;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, this.forExport());
      fileIo.closeSync(file);
      const name: string = uris[0].substring(uris[0].lastIndexOf('/') + 1);
      // Recording the landed size in the trace is how a failed save becomes
      // visible later: the picker hands back a uri even when the write did not
      // happen, so the toast alone is not evidence.
      const size: number = fileIo.statSync(uris[0]).size;
      Diag.write(`log exported to ${name} (${size} bytes)`);
      promptAction.showToast({ message: Tr.tf('Saved the log to %1$s', name), duration: 2200 });
    } catch (err) {
      const error = err as BusinessError;
      Diag.write(`log export failed: ${error.code} ${error.message}`);
      promptAction.showToast({
        message: Tr.tf('Could not export the log: %1$s', error.message),
        duration: 2600
      });
    }
  }

  private clearTrace(): void {
    Diag.clear();
    this.reload();
    promptAction.showToast({ message: Tr.t('Log cleared'), duration: 1800 });
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
          Text(Tr.t('Local logging'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(Tr.t('What the app and the VPN extension recorded'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(Tr.t('Refresh'))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.PRIMARY)
          .flexShrink(0)
          .padding({ left: 6, right: 6 })
          .onClick(() => {
            this.reload();
          })
        Text(Tr.t('Export'))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.PRIMARY)
          .flexShrink(0)
          .padding({ left: 6, right: 6 })
          .onClick(() => {
            this.exportTrace();
          })
        Text(Tr.t('Clear'))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.ALERT)
          .flexShrink(0)
          .padding({ left: 6 })
          .onClick(() => {
            this.clearTrace();
          })
      }
      .width('100%')
      .height(64)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          SectionHeader({ label: Tr.t('VPN startup trace') })
          Column() {
            Text(this.empty ? Tr.t('Nothing has been recorded yet') : this.trace)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.empty ? Palette.MUTED : Palette.ON_SURFACE)
              .width('100%')
            Text(Tr.t('Send this file when a tunnel misbehaves'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .width('100%')
              .margin({ top: 12 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(12)
          .backgroundColor(Palette.SURFACE)
        }
        .width('100%')
        .padding({ bottom: 24 })
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
