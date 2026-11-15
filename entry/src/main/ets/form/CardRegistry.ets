/**
 * Which cards exist on the desktop, which layout each one has, and which tunnel
 * a card is pinned to.
 *
 * The card page is built by the form extension process, but the app also pushes
 * updates to the cards after a switch is flipped. Only the launcher knows the
 * ids while the form extension is asleep, so they are written to a file the two
 * processes share (the same `filesDir` the status snapshot uses).
 *
 * `tunnel` is '' for a card that follows the current session — the default, and
 * what every card did before the editor existed. A file written by that build
 * stores the bare size string, which is read as `{size, tunnel: ''}`.
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Diag } from '../util/Diag';

const DOMAIN: number = 0x0001;
const TAG: string = 'CardRegistry';
const FILE_NAME: string = 'card_forms.json';
/** A desktop cannot hold more cards than this in any honest scenario. */
const MAX_FORMS: number = 16;
const DEFAULT_SIZE: string = '2x2';

export interface CardEntry {
  /** '1x2' | '2x2' | '2x4' */
  size: string;
  /** The tunnel this card is pinned to, '' to follow the current session. */
  tunnel: string;
}

export class CardRegistry {
  private static path(): string {
    return `${Diag.directory()}/${FILE_NAME}`;
  }

  /** Every placed card, as form id -> entry. Never null. */
  static list(): Record<string, CardEntry> {
    const dir: string = Diag.directory();
    if (dir.length === 0) {
      return {};
    }
    try {
      if (!fileIo.accessSync(CardRegistry.path())) {
        return {};
      }
      const file = fileIo.openSync(CardRegistry.path(), fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size === 0 || stat.size > 4096) {
        fileIo.closeSync(file);
        return {};
      }
      const buffer = new ArrayBuffer(stat.size);
      const read: number = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const bytes = new Uint8Array(buffer, 0, read);
      let text: string = '';
      for (let i = 0; i < read; i++) {
        text += String.fromCharCode(bytes[i]);
      }
      return CardRegistry.parse(text);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `list failed: ${(err as Error).message}`);
      return {};
    }
  }

  /** The entry for one card, or null when it is not registered. */
  static entryOf(formId: string): CardEntry | null {
    const map: Record<string, CardEntry> = CardRegistry.list();
    const entry: CardEntry | undefined = map[formId];
    return entry === undefined ? null : entry;
  }

  /** The size a form id was last seen with, or '' when it is not registered. */
  static sizeOf(formId: string): string {
    const entry: CardEntry | null = CardRegistry.entryOf(formId);
    return entry === null ? '' : entry.size;
  }

  /** The tunnel a card is pinned to, '' when it follows the session. */
  static tunnelOf(formId: string): string {
    const entry: CardEntry | null = CardRegistry.entryOf(formId);
    return entry === null ? '' : entry.tunnel;
  }

  /** Records a card that was just placed, or that changed size. */
  static put(formId: string, size: string): void {
    if (formId.length === 0 || Diag.directory().length === 0) {
      return;
    }
    const map: Record<string, CardEntry> = CardRegistry.list();
    const existing: CardEntry | undefined = map[formId];
    const tunnel: string = existing === undefined ? '' : existing.tunnel;
    map[formId] = { size: size, tunnel: tunnel };
    CardRegistry.write(CardRegistry.bounded(map, formId));
  }

  /** Pins a card to a tunnel, or releases it with '' for "follow the session". */
  static bind(formId: string, tunnelId: string): void {
    if (formId.length === 0 || Diag.directory().length === 0) {
      return;
    }
    const map: Record<string, CardEntry> = CardRegistry.list();
    const existing: CardEntry | undefined = map[formId];
    const size: string = existing === undefined ? DEFAULT_SIZE : existing.size;
    map[formId] = { size: size, tunnel: tunnelId };
    CardRegistry.write(map);
  }

  /** Forgets a card the launcher removed. */
  static remove(formId: string): void {
    if (formId.length === 0 || Diag.directory().length === 0) {
      return;
    }
    const map: Record<string, CardEntry> = CardRegistry.list();
    const next: Record<string, CardEntry> = {};
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] !== formId) {
        next[keys[i]] = map[keys[i]];
      }
    }
    CardRegistry.write(next);
  }

  /** Keeps the map bounded, with `formId` always surviving the trim. */
  private static bounded(map: Record<string, CardEntry>, formId: string): Record<string, CardEntry> {
    const keys: string[] = Object.keys(map);
    if (keys.length <= MAX_FORMS) {
      return map;
    }
    const next: Record<string, CardEntry> = {};
    let kept: number = 0;
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === formId) {
        continue;
      }
      if (kept < MAX_FORMS - 1) {
        next[keys[i]] = map[keys[i]];
        kept++;
      }
    }
    next[formId] = map[formId];
    return next;
  }

  /** Reads both the current shape and the size-only files older builds wrote. */
  private static parse(text: string): Record<string, CardEntry> {
    const raw = JSON.parse(text) as Record<string, Object>;
    const out: Record<string, CardEntry> = {};
    const keys: string[] = Object.keys(raw);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const value: Object = raw[key];
      if (typeof value === 'string') {
        out[key] = { size: value as string, tunnel: '' };
        continue;
      }
      const fields = value as Record<string, Object>;
      const size: Object | undefined = fields['size'];
      const tunnel: Object | undefined = fields['tunnel'];
      out[key] = {
        size: size === undefined || size === null ? DEFAULT_SIZE : size.toString(),
        tunnel: tunnel === undefined || tunnel === null ? '' : tunnel.toString()
      };
    }
    return out;
  }

  private static write(map: Record<string, CardEntry>): void {
    const target: string = CardRegistry.path();
    const staging: string = `${target}.tmp`;
    try {
      const text: string = JSON.stringify(map);
      const file = fileIo.openSync(staging,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, text);
      fileIo.closeSync(file);
      fileIo.renameSync(staging, target);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `write failed: ${(err as Error).message}`);
    }
  }
}
