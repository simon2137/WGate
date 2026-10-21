import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from './TunnelStore';
import { withTimeout, isTimeout } from '../util/Async';
import { Diag } from '../util/Diag';

const DOMAIN: number = 0x0001;
const TAG: string = 'VpnControl';
const EXT_ABILITY: string = 'WgVpnExtAbility';
const START_TIMEOUT_MS: number = 20000;
const STOP_TIMEOUT_MS: number = 8000;

function want(tunnel: WgTunnel): Want {
  return {
    bundleName: 'com.wgate.app',
    abilityName: EXT_ABILITY,
    parameters: { 'tunnel': JSON.stringify(tunnel) }
  };
}

/**
 * Asks the system to bring the tunnel up. Resolves to '' on success, or to a
 * sentence that can be shown as-is. The system answers long before the extension
 * has a tun device, so a later failure only shows up in the startup trace.
 */
export async function startTunnel(tunnel: WgTunnel): Promise<string> {
  TunnelStore.setLastError('');
  TunnelStore.setDesired(tunnel.id);
  Diag.write(`connect requested: ${tunnel.name} -> ${tunnel.peers[0].host}:${tunnel.peers[0].port}`);
  try {
    await withTimeout(vpnExtension.startVpnExtensionAbility(want(tunnel)), START_TIMEOUT_MS, 'start');
    Diag.write('startVpnExtensionAbility returned, the extension should be up');
    return '';
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, `start failed: ${e.code} ${e.message}`);
    Diag.write(`startVpnExtensionAbility failed: ${e.code} ${e.message}`);
    TunnelStore.setDesired('');
    const message: string = isTimeout(e) ?
      'The system did not confirm the VPN request' : `Could not start the VPN (${e.code})`;
    TunnelStore.setLastError(message);
    return message;
  }
}

export async function stopTunnel(tunnel: WgTunnel): Promise<void> {
  TunnelStore.setDesired('');
  try {
    await withTimeout(vpnExtension.stopVpnExtensionAbility(want(tunnel)), STOP_TIMEOUT_MS, 'stop');
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, `stop failed: ${e.code} ${e.message}`);
  }
  TunnelStore.setActive('');
}

/**
 * Six seconds after the request, the trace file says whether the extension came
 * up. Returns the first problem line, or '' when the start looks healthy.
 */
export function startupProblem(): string {
  const text: string = Diag.read();
  if (text.length === 0) {
    return '';
  }
  const lines: string[] = text.split('\n').filter((line: string) => line.length > 0);
  for (let i = lines.length - 1; i >= 0 && i >= lines.length - 4; i--) {
    const line: string = lines[i];
    if (line.indexOf('failed') >= 0 || line.indexOf('engine open -> -') >= 0 ||
        line.indexOf('threw') >= 0) {
      return line.substring(line.indexOf('  ') + 2).trim();
    }
  }
  if (text.indexOf('extension onCreate') < 0) {
    return 'The VPN service did not start. Open Logs for the startup trace.';
  }
  return '';
}
