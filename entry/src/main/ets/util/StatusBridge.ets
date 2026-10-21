/**
 * The engine runs inside the VPN extension, which lives in its own process, so
 * `wgcore.status()` in the UI process knows nothing about it: it reports a
 * stopped engine with zero counters even while the tunnel carries traffic.
 *
 * `preferences` cannot be trusted across processes either (it caches per
 * process), so the extension publishes a small JSON snapshot every couple of
 * seconds into the shared sandbox and the UI reads that instead. The file
 * carries the tunnel id and a timestamp, which is what lets the UI both pick the
 * right row and notice that the publisher stopped.
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Diag } from './Diag';

const DOMAIN: number = 0x0001;
const TAG: string = 'StatusBridge';
const FILE_NAME: string = 'vpn_status.json';

export interface BridgeStatus {
  id: string;
  state: string;
  rxBytes: number;
  txBytes: number;
  rxPackets: number;
  txPackets: number;
  peersUp: number;
  peerCount: number;
  /** Milliseconds since the last handshake, 0 when there never was one. */
  handshakeAgeMs: number;
  udpFd: number;
  updated: number;
  /**
   * When this connection was started (milliseconds since the epoch).
   *
   * The tunnel id says which row a snapshot belongs to, but the system hands the
   * same extension instance a new tunnel without a new process, so a stale
   * snapshot and a fresh one can carry the same id. This tells them apart, which
   * is what the UI needs to notice that a reconnect happened.
   */
  session: number;
  /**
   * True when the extension process published the ongoing notification for this
   * snapshot, false when it deliberately did not (the shade switch is off, or
   * there is still no tunnel).
   *
   * The extension outlives the app in the background, so it owns the shade; the
   * app reads this to know whether it is the one that has to publish.
   */
  notified: boolean;
}

export class StatusBridge {
  private static path(): string {
    return Diag.directory() + '/' + FILE_NAME;
  }

  /**
   * Writes the snapshot through a temporary file and renames it into place.
   *
   * The reader is on a different process and on a one-second timer, so a write
   * it catches half finished would parse as nothing at all — and "no snapshot"
   * is the signal the guard uses for a dead extension, so a torn read would look
   * like a dead tunnel. `rename` within one directory is atomic on this
   * filesystem, so a reader sees either the previous snapshot or the new one.
   */
  static publish(status: BridgeStatus): void {
    if (Diag.directory().length === 0) {
      return;
    }
    const target: string = StatusBridge.path();
    const staging: string = target + '.tmp';
    try {
      const text: string = JSON.stringify(status);
      const file = fileIo.openSync(staging,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, text);
      fileIo.closeSync(file);
      fileIo.renameSync(staging, target);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `publish failed: ${(err as Error).message}`);
    }
  }

  /** Returns null when nothing was published yet or the file is unreadable. */
  static read(): BridgeStatus | null {
    if (Diag.directory().length === 0) {
      return null;
    }
    try {
      if (!fileIo.accessSync(StatusBridge.path())) {
        return null;
      }
      const file = fileIo.openSync(StatusBridge.path(), fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size === 0 || stat.size > 4096) {
        fileIo.closeSync(file);
        return null;
      }
      const buffer = new ArrayBuffer(stat.size);
      const read = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const view = new Uint8Array(buffer, 0, read);
      let text: string = '';
      for (let i = 0; i < read; i++) {
        text += String.fromCharCode(view[i]);
      }
      return JSON.parse(text) as BridgeStatus;
    } catch (err) {
      return null;
    }
  }

  static clear(): void {
    try {
      if (fileIo.accessSync(StatusBridge.path())) {
        fileIo.unlinkSync(StatusBridge.path());
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `clear failed: ${(err as Error).message}`);
    }
  }
}
