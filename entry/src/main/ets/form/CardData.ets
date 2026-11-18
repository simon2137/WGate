/**
 * What a desktop card shows, built in whichever process asks for one.
 *
 * Two processes render this card: the form extension (the launcher asks it to
 * build the page) and the app itself (it pushes a fresh snapshot after the user
 * flips a switch somewhere). They cannot share memory, so everything here is
 * derived from files and the published snapshot:
 *
 *   vpn_status.json   the VPN extension's two-second snapshot (id, name, state,
 *                     counters, session start)
 *   wg_tunnels        the stored list, for the name a stopped card still shows
 *   wg_settings       the interface language and the notification switches
 *
 * `size` is a string ('1x2', '2x2', '2x4') rather than a FormDimension because
 * the card page switches layouts on it, and a number in the binding data would
 * have to be mapped back by hand on the other side.
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { BridgeStatus, StatusBridge } from '../util/StatusBridge';
import { Diag } from '../util/Diag';
import { formatBytes, duration } from '../service/EngineStatus';
import { TunnelNotice } from '../service/TunnelNotice';
import { Tr } from '../i18n/Tr';
import { offeredLocale } from '../i18n/Locales';

/** How long a snapshot is still believed; the publisher writes every 2s. */
const FRESH_MS: number = 8000;
/**
 * How long a failed request keeps the card on "failed". Longer than the start
 * timeout (20 s) so the outcome is visible, short enough that yesterday's
 * failure does not read as today's.
 */
const FAILED_WINDOW_MS: number = 120000;

/**
 * The words the card paints, kept here so the card page itself never imports the
 * interface catalogue. Cards run a stripped runtime, and every string they need
 * arrives as binding data instead.
 */
export class CardData {
  /**
   * Prepares this process to read the shared state.
   *
   * Idempotent per process: `TunnelStore` and `SettingsStore` cache their
   * preferences and only read them again when the process restarts. That is
   * enough here — a card shows the last published snapshot rather than a live
   * store, and the snapshot is a file that is re-read on every build.
   */
  static init(context: common.Context): void {
    TunnelStore.init(context);
    SettingsStore.init(context);
    Diag.init(context);
    Tr.setLocale(offeredLocale(SettingsStore.language()));
  }

  /**
   * Whether the card paints dark.
   *
   * Follows the interface theme the app was set to, not the system alone: a user
   * who picked the light palette on a dark phone gets a light card, which is what
   * "the same product" means. `automatic` is the only setting that asks the
   * device, and `colorMode` is whatever this process was configured with.
   */
  static dark(context: common.Context, colorMode: number | undefined): boolean {
    const setting: string = SettingsStore.theme();
    if (setting === 'light') {
      return false;
    }
    if (setting !== 'automatic') {
      return true;
    }
    return colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  /** The layout a form dimension asks for. */
  static sizeOf(dimension: number): string {
    if (dimension === 1) {
      return '1x2';
    }
    if (dimension === 3) {
      return '2x4';
    }
    return '2x2';
  }

  /**
   * The binding data for one card.
   *
   * Every value is a string or a boolean: the launcher passes this object through
   * JSON, and a nested object would have to be flattened on the card side anyway.
   *
   * `bound` pins the card to one tunnel (the editor writes it through
   * CardRegistry). A pinned card only ever reports its own tunnel: when another
   * tunnel is running, the pinned one is simply not connected — which is the
   * truth, and the reason pinning is worth doing at all.
   */
  static build(context: common.Context, size: string, colorMode: number | undefined,
    bound: string = ''): Record<string, Object> {
    CardData.init(context);
    const snapshot: BridgeStatus | null = StatusBridge.read();
    const fresh: boolean = snapshot !== null && Date.now() - snapshot.updated <= FRESH_MS;
    const tunnels: WgTunnel[] = TunnelStore.list();
    const empty: boolean = tunnels.length === 0;
    const pinned: WgTunnel | null = bound.length > 0 ? TunnelStore.find(bound) : null;
    const state: string = CardData.resolveState(snapshot, fresh, empty, pinned !== null ? bound : '');

    // The id is resolved first and the name follows it, so the tunnel the card
    // names is exactly the one its switch will act on: a card that said "failed:
    // Office" used to retry whichever tunnel happened to be first in the list.
    const id: string = pinned !== null ? pinned.id : CardData.tunnelIdFor(snapshot, state, tunnels);
    // The store is where a rename lands, so it answers first; the snapshot is the
    // fallback for a process that cannot read the store, and it carries the name
    // the tunnel had when the session started.
    const known: WgTunnel | null = pinned !== null ? pinned : TunnelStore.find(id);
    let name: string = known !== null ? known.name : '';
    if (name.length === 0 && snapshot !== null && snapshot.id === id) {
      name = snapshot.name;
    }
    if (name.length === 0) {
      name = TunnelStore.lastErrorTunnel();
    }
    if (name.length === 0) {
      name = CardData.nameFromStore(tunnels);
    }

    const stateText: string = CardData.stateText(state);
    const subject: WgTunnel | null = TunnelStore.find(id);
    const endpoint: string = subject !== null ? subject.endpoint() : '';
    const up: boolean = state === 'up';
    const peers: string = up && snapshot !== null ?
      `${snapshot.peersUp}/${snapshot.peerCount}` : '';
    const rx: string = up && snapshot !== null ? formatBytes(snapshot.rxBytes) : '';
    const tx: string = up && snapshot !== null ? formatBytes(snapshot.txBytes) : '';
    const uptime: string = up && snapshot !== null && snapshot.session > 0 ?
      Tr.tf('uptime: %1$s', duration(Date.now() - snapshot.session)) : '';
    // The source line is the notification's "show origin" switch, so the card and
    // the shade agree about which interface the traffic leaves from.
    const origin: string = up && SettingsStore.notification('origin') ?
      Tr.tf('via %1$s', TunnelNotice.networkLabel()) : '';

    return {
      'layout': size,
      'dark': CardData.dark(context, colorMode),
      'state': empty ? 'empty' : state,
      'stateText': empty ? '' : stateText,
      'name': name,
      'tunnelId': id,
      'peers': peers,
      'rx': rx,
      'tx': tx,
      'uptime': uptime,
      'origin': origin,
      'endpoint': endpoint,
      'emptyTitle': Tr.t('No tunnels yet'),
      'emptyHint': Tr.t('Add tunnel')
    };
  }

  /**
   * The state one card is in, which for a pinned card means "its" tunnel only.
   *
   * A card pinned to Office while the Home NAS tunnel runs is not connected; the
   * snapshot describes a session this card is not about, so it is ignored.
   */
  private static resolveState(snapshot: BridgeStatus | null, fresh: boolean,
    empty: boolean, bound: string): string {
    if (empty) {
      return 'down';
    }
    const mine: boolean = bound.length === 0 || (snapshot !== null && snapshot.id === bound);
    if (fresh && snapshot !== null && mine) {
      if (snapshot.state === 'up') {
        return 'up';
      }
      if (snapshot.state === 'error') {
        return 'error';
      }
      if (snapshot.state === 'connecting' || snapshot.state === 'handshaking') {
        return 'starting';
      }
      if (snapshot.state === 'offline') {
        return 'offline';
      }
    }
    const desired: string = TunnelStore.desiredId();
    const asking: boolean = bound.length > 0 ? desired === bound : desired.length > 0;
    if (asking && TunnelStore.wantedRecently()) {
      // A start was asked for and the extension has not published yet: the card
      // says "connecting" instead of dropping back to idle under the user's
      // finger. The store keeps the desire for the guard and the cold start, so
      // only this reading has a deadline (see TunnelStore.wantedRecently): an old
      // desire is not a request in flight, and the card falls through to the
      // failure or idle state below instead of promising a connection nobody is
      // making.
      return 'starting';
    }
    const failed: boolean = TunnelStore.lastError().length > 0 &&
      Date.now() - TunnelStore.lastErrorAt() < FAILED_WINDOW_MS;
    if (failed && (bound.length === 0 || TunnelStore.lastErrorTunnelId() === bound)) {
      // A request that never became a session (the system refusing the VPN start,
      // for instance) leaves no snapshot behind, only an error.
      return 'error';
    }
    return 'down';
  }

  /**
   * The tunnel this card is about.
   *
   * A running (or last run) tunnel is what the snapshot reports; after a failed
   * request it is the tunnel that failed; otherwise the same order the quick
   * action uses, ending on the first entry only when nothing else answers.
   */
  private static tunnelIdFor(snapshot: BridgeStatus | null, state: string,
    tunnels: WgTunnel[]): string {
    if (snapshot !== null && snapshot.id.length > 0) {
      return snapshot.id;
    }
    if (state === 'error' && TunnelStore.lastErrorTunnelId().length > 0) {
      return TunnelStore.lastErrorTunnelId();
    }
    if (TunnelStore.desiredId().length > 0) {
      return TunnelStore.desiredId();
    }
    if (TunnelStore.activeId().length > 0) {
      return TunnelStore.activeId();
    }
    if (TunnelStore.find(SettingsStore.preferredTunnelId()) !== null) {
      return SettingsStore.preferredTunnelId();
    }
    return tunnels.length > 0 ? tunnels[0].id : '';
  }



  /** The tunnel a stopped card names: the one last asked for, else the first. */
  private static nameFromStore(tunnels: WgTunnel[]): string {
    if (tunnels.length === 0) {
      return '';
    }
    const wanted: string = TunnelStore.desiredId().length > 0 ?
      TunnelStore.desiredId() : TunnelStore.activeId();
    if (wanted.length > 0) {
      for (let i = 0; i < tunnels.length; i++) {
        if (tunnels[i].id === wanted) {
          return tunnels[i].name;
        }
      }
    }
    return tunnels[0].name;
  }

  private static stateText(state: string): string {
    if (state === 'up') {
      return Tr.t('Connected');
    }
    if (state === 'starting') {
      return Tr.t('Connecting…');
    }
    if (state === 'error') {
      return Tr.t('Failed');
    }
    if (state === 'offline') {
      return Tr.t('No network');
    }
    return Tr.t('Disconnected');
  }
}
