/**
 * Persistent tunnel list + connection bookkeeping.
 *
 * The UI, the VPN extension and the background entry all run in the same
 * application process, so a single preferences-backed store is enough; it also
 * survives process restarts, which is what the "reconnect on launch" path uses.
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WgTunnel } from '../model/Tunnel';

const STORE_NAME: string = 'wg_tunnels';
const KEY_LIST: string = 'tunnels';
const KEY_ACTIVE: string = 'active_id';
const KEY_DESIRED: string = 'desired_id';
const KEY_DESIRED_AT: string = 'desired_at';
const KEY_LAST_ERROR: string = 'last_error';
const KEY_LAST_ERROR_AT: string = 'last_error_at';
const KEY_LAST_ERROR_TUNNEL: string = 'last_error_tunnel';
const KEY_LAST_ERROR_TUNNEL_ID: string = 'last_error_tunnel_id';
/**
 * How long a recorded desire still counts as a request in flight.
 *
 * Longer than the 20 s a `startVpnExtensionAbility` request may take, so a slow
 * start keeps its word, and short enough that a desire an earlier session left
 * behind cannot present itself as one: the extension can be reclaimed without
 * `onDestroy`, which leaves the id in the store over a tunnel nobody is bringing
 * up, and a surface that read that as "connecting" said so for good.
 */
const DESIRE_GRACE_MS: number = 60000;

export class TunnelStore {
  private static store: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (TunnelStore.store !== null) {
      return;
    }
    const options: preferences.Options = { name: STORE_NAME };
    TunnelStore.store = preferences.getPreferencesSync(context, options);
  }

  private static ensure(): preferences.Preferences {
    if (TunnelStore.store === null) {
      throw new Error('TunnelStore.init() was not called');
    }
    return TunnelStore.store;
  }

  static list(): WgTunnel[] {
    const raw = TunnelStore.ensure().getSync(KEY_LIST, '') as string;
    if (raw.length === 0) {
      return [];
    }
    let parsed: WgTunnel[] = [];
    try {
      const items = JSON.parse(raw) as string[];
      for (let i = 0; i < items.length; i++) {
        parsed.push(WgTunnel.from(items[i]));
      }
    } catch (e) {
      parsed = [];
    }
    return parsed;
  }

  private static write(tunnels: WgTunnel[]): void {
    const encoded: string[] = [];
    for (let i = 0; i < tunnels.length; i++) {
      encoded.push(JSON.stringify(tunnels[i]));
    }
    const store = TunnelStore.ensure();
    store.putSync(KEY_LIST, JSON.stringify(encoded));
    store.flush();
  }

  static save(tunnel: WgTunnel): void {
    const tunnels = TunnelStore.list();
    let replaced = false;
    for (let i = 0; i < tunnels.length; i++) {
      if (tunnels[i].id === tunnel.id) {
        tunnels[i] = tunnel;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      tunnels.push(tunnel);
    }
    TunnelStore.write(tunnels);
  }

  static remove(id: string): void {
    const tunnels = TunnelStore.list();
    const kept: WgTunnel[] = [];
    for (let i = 0; i < tunnels.length; i++) {
      if (tunnels[i].id !== id) {
        kept.push(tunnels[i]);
      }
    }
    TunnelStore.write(kept);
    if (TunnelStore.activeId() === id) {
      TunnelStore.setActive('');
    }
    if (TunnelStore.desiredId() === id) {
      TunnelStore.setDesired('');
    }
  }

  static find(id: string): WgTunnel | null {
    const tunnels = TunnelStore.list();
    for (let i = 0; i < tunnels.length; i++) {
      if (tunnels[i].id === id) {
        return tunnels[i];
      }
    }
    return null;
  }

  static activeId(): string {
    return TunnelStore.ensure().getSync(KEY_ACTIVE, '') as string;
  }

  static setActive(id: string): void {
    const store = TunnelStore.ensure();
    store.putSync(KEY_ACTIVE, id);
    store.flush();
  }

  static desiredId(): string {
    return TunnelStore.ensure().getSync(KEY_DESIRED, '') as string;
  }

  static setDesired(id: string): void {
    const store = TunnelStore.ensure();
    store.putSync(KEY_DESIRED, id);
    // Stamped so a surface can tell "the user just asked for this" from "a request
    // an earlier session left behind". The desire is durable on purpose — the
    // guard and the cold start read it — but the desktop card and the tray read it
    // as "connecting", and a request whose extension died silently left both
    // saying so for good. The stamp is what lets that reading expire.
    store.putSync(KEY_DESIRED_AT, id.length === 0 ? 0 : Date.now());
    store.flush();
  }

  /**
   * When the current desire was recorded, 0 while there is none.
   *
   * 0 also means "written by a build that did not stamp it", which is an old
   * desire by definition and must not be read as a request in flight.
   */
  static desiredAt(): number {
    return TunnelStore.ensure().getSync(KEY_DESIRED_AT, 0) as number;
  }

  /**
   * Whether the recorded desire is a request that may still be in flight.
   *
   * "There is a desired id" is not the same question: the store keeps the id for
   * the guard and the cold start, long after the request it came from ended, so a
   * surface that reads the id alone says "connecting" over a tunnel that nobody
   * is connecting. This is the reading with a deadline — the card and the tray
   * both use it, and the engine's own snapshots are what say "up".
   */
  static wantedRecently(): boolean {
    if (TunnelStore.desiredId().length === 0) {
      return false;
    }
    const at: number = TunnelStore.desiredAt();
    return at > 0 && Date.now() - at <= DESIRE_GRACE_MS;
  }

  static lastError(): string {
    return TunnelStore.ensure().getSync(KEY_LAST_ERROR, '') as string;
  }

  /**
   * When the last failure was recorded, 0 while there is none.
   *
   * A message alone cannot say whether it describes the request the user just
   * made or one from last week; the desktop card needs that difference to decide
   * between showing a failure and showing an idle tunnel.
   */
  static lastErrorAt(): number {
    return TunnelStore.ensure().getSync(KEY_LAST_ERROR_AT, 0) as number;
  }

  /**
   * The tunnel the last failure belongs to, '' when it is not known.
   *
   * A surface that says "failed" has to name what failed: the requested tunnel
   * is cleared as soon as the request is refused, so the id cannot be recovered
   * from the store afterwards.
   */
  static lastErrorTunnel(): string {
    return TunnelStore.ensure().getSync(KEY_LAST_ERROR_TUNNEL, '') as string;
  }

  /** The id behind lastErrorTunnel, so a retry can name the same tunnel. */
  static lastErrorTunnelId(): string {
    return TunnelStore.ensure().getSync(KEY_LAST_ERROR_TUNNEL_ID, '') as string;
  }

  static setLastError(message: string, tunnelName: string = '', tunnelId: string = ''): void {
    const store = TunnelStore.ensure();
    store.putSync(KEY_LAST_ERROR, message);
    store.putSync(KEY_LAST_ERROR_AT, message.length === 0 ? 0 : Date.now());
    store.putSync(KEY_LAST_ERROR_TUNNEL, message.length === 0 ? '' : tunnelName);
    store.putSync(KEY_LAST_ERROR_TUNNEL_ID, message.length === 0 ? '' : tunnelId);
    store.flush();
  }
}
