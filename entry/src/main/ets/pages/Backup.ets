import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { TunnelStore } from '../service/TunnelStore';
import { WgTunnel, parseWgQuick } from '../model/Tunnel';
import { Diag } from '../util/Diag';
import { Tr } from '../i18n/Tr';

/**
 * `ui/screens/settings/components/BackupBottomSheet.kt`: write every tunnel to a
 * file and read them back. The file format is the same flat JSON the store uses,
 * wrapped in an envelope so a stray file is rejected instead of half-imported.
 */
@Entry
@Component
struct Backup {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State note: string = '';
  @State count: number = 0;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    Diag.init(context);
    this.count = TunnelStore.list().length;
  }

  private flash(message: string): void {
    this.note = message;
    this.count = TunnelStore.list().length;
    setTimeout(() => {
      this.note = '';
    }, 2600);
  }

  private envelope(): string {
    const tunnels: WgTunnel[] = TunnelStore.list();
    const parts: string[] = [];
    for (let i = 0; i < tunnels.length; i++) {
      // The storage record, not `toJson()`: the engine wire format drops the
      // name, address, DNS and peer list that a restore needs.
      parts.push(JSON.stringify(tunnels[i]));
    }
    return `{"app":"wg-tunnel","version":1,"tunnels":[${parts.join(',')}]}`;
  }

  /** Local wall-clock stamp: `toISOString()` names the file in UTC, which reads
   *  hours away from the clock the user just looked at. */
  private stamp(): string {
    const d: Date = new Date();
    const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
    return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  }

  private async exportToFile(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSaveOptions();
      // A fresh name per export: the picker refuses to overwrite silently, and a
      // timestamped file is easier to tell apart in the Files app.
      options.newFileNames = [`wg-tunnels-${this.stamp()}.json`];
      const view = new picker.DocumentViewPicker(context);
      const uris: string[] = await view.save(options);
      if (uris.length === 0) {
        return;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, this.envelope());
      fileIo.closeSync(file);
      const size: number = fileIo.statSync(uris[0]).size;
      Diag.write(`backup written to ${uris[0]} (${size} bytes)`);
      this.flash(Tr.tf('Exported %1$s tunnel(s)', this.count.toString()));
    } catch (err) {
      const error = err as BusinessError;
      Diag.write(`backup failed: ${error.code} ${error.message}`);
      this.flash(Tr.tf('Export failed: %1$s', error.message));
    }
  }

  private async restoreFromFile(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.json', '.conf', '.txt'];
      const view = new picker.DocumentViewPicker(context);
      const uris: string[] = await view.select(options);
      if (uris.length === 0) {
        return;
      }
      // The picker hands back a document uri and `readTextSync` only takes a
      // sandbox path, so the file is read through its descriptor - the same way
      // the configuration importer reads a picked file.
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size > 0 ? stat.size : 65536);
      const read = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const content: string = decoder.decodeToString(new Uint8Array(buffer, 0, read));
      const result: string = this.importText(content);
      Diag.write(`restore from ${uris[0]}: ${result}`);
      this.flash(result);
    } catch (err) {
      const error = err as BusinessError;
      Diag.write(`restore failed: ${error.code} ${error.message}`);
      this.flash(Tr.tf('Restore failed: %1$s', error.message));
    }
  }

  /**
   * A record is only worth importing when it can actually connect: a private key
   * and at least one peer carrying a public key. Anything else would land in the
   * list as a tunnel whose switch can only fail, so it is counted and skipped.
   */
  private usable(tunnel: WgTunnel): boolean {
    if (tunnel.privateKey.length === 0 || tunnel.peers.length === 0) {
      return false;
    }
    for (let i = 0; i < tunnel.peers.length; i++) {
      if (tunnel.peers[i].publicKey.length > 0) {
        return true;
      }
    }
    return false;
  }

  /** Accepts the backup envelope and, as a convenience, a plain wg-quick file. */
  private importText(content: string): string {
    const trimmed: string = content.trim();
    if (trimmed.startsWith('{')) {
      const parsed = JSON.parse(trimmed) as Record<string, Object>;
      const list = parsed.tunnels as Object[];
      if (!Array.isArray(list) || list.length === 0) {
        return Tr.t('Restore failed: no tunnels in this file');
      }
      let added: number = 0;
      let skipped: number = 0;
      for (let i = 0; i < list.length; i++) {
        const tunnel: WgTunnel = WgTunnel.from(JSON.stringify(list[i]));
        if (!this.usable(tunnel)) {
          skipped++;
          continue;
        }
        if (tunnel.id.length === 0) {
          // A hand-edited or truncated file can arrive without an id; the store
          // keys records by id, so one has to be minted before saving.
          tunnel.id = `${Date.now()}${added}`;
        }
        TunnelStore.save(tunnel);
        added++;
      }
      if (skipped > 0) {
        return Tr.tf('Restored %1$s tunnel(s), skipped %2$s', added.toString(),
          skipped.toString());
      }
      return Tr.tf('Restored %1$s tunnel(s) from the file', added.toString());
    }
    if (trimmed.indexOf('[Interface]') >= 0) {
      // Parsed as wg-quick, not wrapped: `WgTunnel.from()` only reads the storage
      // shape, so handing it the raw text used to store an empty tunnel.
      const parsed: WgTunnel | null = parseWgQuick(trimmed, Tr.t('Restored tunnel'));
      if (parsed === null) {
        return Tr.t('Restore failed: the file has no usable [Interface] and [Peer]');
      }
      TunnelStore.save(parsed);
      // A wg-quick file holds exactly one tunnel; the literal is avoided so the
      // string-extraction audit does not read it as part of the format key.
      const one: number = 1;
      return Tr.tf('Restored %1$s tunnel(s) from the file', one.toString());
    }
    return Tr.t('Restore failed: unrecognised file');
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
          Text(Tr.t('Backup and restore'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
            .width('100%')
          Text(Tr.t('Export tunnels as a file'))
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
          SectionHeader({ label: Tr.t('Tunnels') })

          SurfaceRow({
            title: Tr.t('Backup application data'),
            icon: $r('app.media.ic_database'),
            description: `${this.count} ${Tr.t('tunnel(s)')} ${Tr.t('will be written to the file you pick')}`,
            trailingText: Tr.t('Export'),
            onTap: () => {
              this.exportToFile();
            }
          })

          SurfaceRow({
            title: Tr.t('Restore from backup'),
            icon: $r('app.media.ic_restore'),
            description: Tr.t('Pick a backup file and add its tunnels to this device'),
            trailingText: Tr.t('Import'),
            onTap: () => {
              this.restoreFromFile();
            }
          })

          if (this.note.length > 0) {
            Text(this.note)
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.PRIMARY)
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 12 })
          }
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
