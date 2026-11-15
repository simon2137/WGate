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
const KEY_LAST_ERROR: string = 'last_error';
const KEY_LAST_ERROR_AT: string = 'last_error_at';
const KEY_LAST_ERROR_TUNNEL: string = 'last_error_tunnel';
const KEY_LAST_ERROR_TUNNEL_ID: string = 'last_error_tunnel_id';

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
    store.flush();
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
