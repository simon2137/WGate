import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from './TunnelStore';
import { startTunnel, stopTunnel } from './VpnControl';
import { Diag } from '../util/Diag';

/**
 * One definition of "the quick action": bring the last used tunnel up, or take
 * the running one down.  The launcher shortcut and the desktop tray both call
 * it, so the two surfaces can never drift apart in what they pick as the target
 * tunnel or in how they report a failure.
 *
 * @param source short label written to the trace, e.g. "shortcut" or "tray"
 */
export function toggleTunnel(source: string): void {
  const activeId: string = TunnelStore.activeId();
  const targetId: string = activeId.length > 0 ? activeId : TunnelStore.desiredId();
  let tunnel: WgTunnel | null = TunnelStore.find(targetId);
  if (tunnel === null) {
    const all: WgTunnel[] = TunnelStore.list();
    tunnel = all.length > 0 ? all[0] : null;
  }
  if (tunnel === null) {
    Diag.write(`${source}: there is no tunnel to toggle`);
    return;
  }
  if (activeId.length > 0) {
    Diag.write(`${source}: asked to disconnect ${tunnel.name}`);
    stopTunnel(tunnel);
  } else {
    Diag.write(`${source}: asked to connect ${tunnel.name}`);
    startTunnel(tunnel);
  }
}
