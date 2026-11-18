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
 *
 * `size` may be '' — "nobody has told this file yet" — and that is deliberate.
 * The size decides which of the three layouts the card paints, so a guess is
 * worse than a gap: filling an unknown size in with the 2x2 default is what
 * painted a 2x4 card with the 2x2 layout, switch in the bottom-right corner.
 * Only `onAddForm` (which is handed the dimension), `onSizeChanged`, the
 * launcher's answer in `onUpdateForm` and the launcher's own report
 * (`reconcile`) may fill it in.
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Diag } from '../util/Diag';

const DOMAIN: number = 0x0001;
const TAG: string = 'CardRegistry';
const FILE_NAME: string = 'card_forms.json';
/** A desktop cannot hold more cards than this in any honest scenario. */
const MAX_FORMS: number = 16;

export interface CardEntry {
  /** '1x2' | '2x2' | '2x4', or '' while nobody has reported the size. */
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

  /**
   * Whether a string names one of the three layouts the card page can paint.
   *
   * The page only ever checks for '2x4' and '1x2' and takes the square layout for
   * everything else, so a size this function rejects must never reach a build.
   */
  static knownSize(size: string): boolean {
    return size === '1x2' || size === '2x2' || size === '2x4';
  }

  /** Records a card that was just placed, or that changed size. */
  static put(formId: string, size: string): void {
    if (formId.length === 0 || !CardRegistry.knownSize(size) || Diag.directory().length === 0) {
      return;
    }
    const map: Record<string, CardEntry> = CardRegistry.list();
    const existing: CardEntry | undefined = map[formId];
    const tunnel: string = existing === undefined ? '' : existing.tunnel;
    map[formId] = { size: size, tunnel: tunnel };
    CardRegistry.write(CardRegistry.bounded(map, formId));
  }

  /**
   * Rewrites the sizes from the launcher's own report of the placed cards.
   *
   * This file is a cache, filled by whichever process happens to know the size,
   * and a build that could not write it (or that filled the gap with a default)
   * leaves a 2x4 card recorded as 2x2. A push made from that record paints the
   * wide card with the square layout, which is how the switch ended up in the
   * bottom-right corner. The launcher is the authority on the grid, so its report
   * overwrites the cache; a card it does not name keeps what it had, and a card
   * it names that the file never saw is added — that is the healing path for a
   * desktop that was placed by a build that could not record it.
   */
  static reconcile(sizes: Record<string, string>): void {
    if (Diag.directory().length === 0) {
      return;
    }
    const map: Record<string, CardEntry> = CardRegistry.list();
    const ids: string[] = Object.keys(sizes);
    let changed: boolean = false;
    for (let i = 0; i < ids.length; i++) {
      const id: string = ids[i];
      const size: string = sizes[id];
      if (!CardRegistry.knownSize(size)) {
        continue;
      }
      const existing: CardEntry | undefined = map[id];
      if (existing === undefined) {
        if (Object.keys(map).length >= MAX_FORMS) {
          continue;
        }
        map[id] = { size: size, tunnel: '' };
        changed = true;
      } else if (existing.size !== size) {
        map[id] = { size: size, tunnel: existing.tunnel };
        changed = true;
      }
    }
    if (changed) {
      CardRegistry.write(map);
    }
  }

  /** Pins a card to a tunnel, or releases it with '' for "follow the session". */
  static bind(formId: string, tunnelId: string): void {
    if (formId.length === 0 || Diag.directory().length === 0) {
      return;
    }
    const map: Record<string, CardEntry> = CardRegistry.list();
    const existing: CardEntry | undefined = map[formId];
    // The editor is opened from the card's long-press menu and is handed the form
    // id, not the dimension, so it must not invent one: it keeps whatever the
    // registry already knows and leaves the size unknown when it knows nothing,
    // which the push path treats as "do not paint this card yet".
    const size: string = existing === undefined ? '' : existing.size;
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
        // A missing size stays missing. Older builds wrote the default here, which
        // is the guess that repainted the wide card square.
        size: size === undefined || size === null ? '' : size.toString(),
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
