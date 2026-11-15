import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from './TunnelStore';
import { SettingsStore } from './SettingsStore';
import { startTunnel, stopTunnel } from './VpnControl';
import { publishedTunnelId } from './EngineStatus';
import { Diag } from '../util/Diag';

/**
 * One definition of "the quick action": bring a tunnel up, or take the running
 * one down. The launcher shortcut, the desktop tray and the desktop card's
 * switch all call it, so the three surfaces can never drift apart in what they
 * pick as the target tunnel or in how they report a failure.
 *
 * A card names the tunnel it is showing, because a list with six tunnels has no
 * sensible "the current one" to fall back on: without it, a card that said
 * "failed: Office" retried whichever tunnel happened to be first in the list.
 * With no id — the shortcut and the tray still call it that way — the order is
 * the running tunnel, the one last asked for, the preferred tunnel, and only
 * then the first entry.
 *
 * @param source short label written to the trace, e.g. "shortcut" or "tray"
 * @param tunnelId the tunnel the caller named, '' to use the order above
 * @returns resolves when the request finished (successfully or not), which is
 *   what lets the card show the outcome instead of just the attempt.
 */
export async function toggleTunnel(source: string, tunnelId: string = ''): Promise<void> {
  // "Is something running?" is what the extension published, not what the store
  // remembers: only the app's own list and shortcuts ever wrote the stored id, so
  // a tunnel brought up from the card left it empty and the next tap tried to
  // start that same tunnel again instead of disconnecting it.
  const published: string = publishedTunnelId();
  const activeId: string = published.length > 0 ? published : TunnelStore.activeId();
  const active: WgTunnel | null = activeId.length > 0 ? TunnelStore.find(activeId) : null;
  const tunnel: WgTunnel | null = pick(tunnelId, activeId);
  if (tunnel === null) {
    Diag.write(`${source}: there is no tunnel to toggle`);
    return;
  }

  // Tapping the card of a tunnel that is not the running one means "switch to
  // it": the engine runs one interface at a time, so the old one goes first.
  if (active !== null && active.id !== tunnel.id) {
    Diag.write(`${source}: asked to switch ${active.name} -> ${tunnel.name}`);
    await stopTunnel(active, 'another tunnel was asked for from the quick action');
    await startTunnel(tunnel);
    return;
  }
  if (active !== null) {
    Diag.write(`${source}: asked to disconnect ${tunnel.name}`);
    await stopTunnel(tunnel, 'the quick action asked for it');
    return;
  }
  Diag.write(`${source}: asked to connect ${tunnel.name}`);
  await startTunnel(tunnel);
}

/**
 * The tunnel a toggle acts on: the named one, else the running one, else the one
 * last asked for, else the preferred tunnel, else the first entry.
 */
function pick(tunnelId: string, activeId: string): WgTunnel | null {
  let tunnel: WgTunnel | null = TunnelStore.find(tunnelId);
  if (tunnel !== null) {
    return tunnel;
  }
  if (activeId.length > 0) {
    tunnel = TunnelStore.find(activeId);
    if (tunnel !== null) {
      return tunnel;
    }
  }
  const desired: string = TunnelStore.desiredId();
  if (desired.length > 0) {
    tunnel = TunnelStore.find(desired);
    if (tunnel !== null) {
      return tunnel;
    }
  }
  // The preferred tunnel is the one the user already told the app to favour; it
  // is a better guess than "whatever sorts first".
  tunnel = TunnelStore.find(SettingsStore.preferredTunnelId());
  if (tunnel !== null) {
    return tunnel;
  }
  const all: WgTunnel[] = TunnelStore.list();
  return all.length > 0 ? all[0] : null;
}
