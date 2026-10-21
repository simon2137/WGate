/**
 * A small append-only trace file shared by the UI and the VPN extension.
 *
 * The two do not reliably share memory: a `VpnExtensionAbility` may run in its
 * own process, and `preferences` caches per process, so an error the extension
 * records there can be invisible to the UI that started it. A file in the app's
 * `filesDir` is the only channel that always crosses that boundary, and it
 * survives the process being killed, which is exactly what happens when the VPN
 * setup fails.
 */
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'Diag';
const FILE_NAME: string = 'vpn_diag.log';
/** Keeps the trace readable in a sheet and bounded on disk. */
const MAX_CHARS: number = 8000;

export class Diag {
  private static dir: string = '';

  static init(context: common.Context): void {
    if (Diag.dir.length === 0) {
      Diag.dir = context.filesDir;
    }
  }

  /** Sandbox directory shared by both processes; '' until init() ran. */
  static directory(): string {
    return Diag.dir;
  }

  private static path(): string {
    return Diag.dir + '/' + FILE_NAME;
  }

  /**
   * Appends one line. Every failure path of the VPN setup calls this, so it is
   * deliberately forgiving: a diagnostic that throws is worse than none.
   */
  static write(message: string): void {
    if (Diag.dir.length === 0) {
      return;
    }
    try {
      const now = new Date();
      const stamp: string = now.toTimeString().substring(0, 8);
      let text: string = Diag.read();
      text += stamp + '  ' + message + '\n';
      if (text.length > MAX_CHARS) {
        text = text.substring(text.length - MAX_CHARS);
      }
      const file = fileIo.openSync(Diag.path(),
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, text);
      fileIo.closeSync(file);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `trace write failed: ${(err as Error).message}`);
    }
  }

  static read(): string {
    if (Diag.dir.length === 0) {
      return '';
    }
    try {
      if (!fileIo.accessSync(Diag.path())) {
        return '';
      }
      const file = fileIo.openSync(Diag.path(), fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      const read = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      return buffer2text(buffer, read);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `trace read failed: ${(err as Error).message}`);
      return '';
    }
  }

  static clear(): void {
    try {
      if (fileIo.accessSync(Diag.path())) {
        fileIo.unlinkSync(Diag.path());
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `trace clear failed: ${(err as Error).message}`);
    }
  }
}

function buffer2text(buffer: ArrayBuffer, length: number): string {
  const view = new Uint8Array(buffer, 0, length);
  let out: string = '';
  for (let i = 0; i < length; i++) {
    out += String.fromCharCode(view[i]);
  }
  return out;
}
