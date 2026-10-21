/**
 * A tunnel that was up when the app left the screen can be torn down minutes
 * later: the system reclaims the VPN extension it started, the tun goes with it
 * and the status bar key disappears. Nothing inside the tunnel notices, because
 * the process that would notice is the one that was reclaimed.
 *
 * This guard is the other side of that. While the UI process is schedulable it
 * reads the snapshot the extension publishes (util/StatusBridge.ets) and, when a
 * tunnel is still wanted but the snapshot stops arriving, asks the system for
 * the extension again. Its onCreate rebuilds the tun and the engine, so the
 * tunnel comes back instead of waiting for the user to open the app and notice.
 *
 * It is deliberately bounded. Only a tunnel the user asked for (the desired id,
 * which stopTunnel clears) can be revived, and only while "seamless recovery" is
 * on; a restart needs the number of silent checks the recovery delay asks for;
 * attempts are spaced out; and a run of failures stops the guard for ten minutes
 * rather than fighting the system for the battery. Every decision is written to
 * the trace, because the interesting case - the extension dying silently while
 * the app is in the background - is exactly the one nobody can watch.
 */
import { Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from './TunnelStore';
import { publishedTunnelId } from './EngineStatus';
import { SettingsStore } from './SettingsStore';
import { BridgeStatus, StatusBridge } from '../util/StatusBridge';
import { Diag } from '../util/Diag';
import { withTimeout } from '../util/Async';

const TAG: string = 'TunnelGuard';
const EXT_ABILITY: string = 'WgVpnExtAbility';
/** How often the published snapshot is checked; the extension writes every 2 s. */
const CHECK_MS: number = 10000;
/** Seconds represented by one check, for turning the recovery delay into checks. */
const SECONDS_PER_CHECK: number = CHECK_MS / 1000;
/** Spacing between restart attempts, in ms. */
const RETRY_MS: number = 60000;
/**
 * Healthy checks per heartbeat. The trace is how a report gets attributed, and
 * the one question it cannot answer today is whether the UI process was still
 * running while the app was in the background: a minute is short enough to
 * appear inside the three-minute window and long enough to leave the trace
 * readable.
 */
const HEARTBEAT_CHECKS: number = 6;
/** Attempts in one stretch before the guard stands down. */
const MAX_ATTEMPTS: number = 5;
/** How long the guard stands down after MAX_ATTEMPTS, in ms. */
const COOLDOWN_MS: number = 600000;
const START_TIMEOUT_MS: number = 20000;

export class TunnelGuard {
  private static timer: number = -1;
  private static silent: number = 0;
  private static attempts: number = 0;
  private static nextAttemptAt: number = 0;
  private static inFlight: boolean = false;
  private static healthy: number = 0;

  /** Idempotent: the first UI process to ask owns the timer. */
  static start(): void {
    if (TunnelGuard.timer >= 0) {
      return;
    }
    Diag.write('guard: watching for a tunnel that goes silent');
    TunnelGuard.timer = setInterval(() => {
      TunnelGuard.check();
    }, CHECK_MS);
  }

  static running(): boolean {
    return TunnelGuard.timer >= 0;
  }

  private static check(): void {
    try {
      const desired: string = TunnelStore.desiredId();
      if (desired.length === 0) {
        // Nothing was asked for, so silence is the correct state.
        TunnelGuard.silent = 0;
        TunnelGuard.attempts = 0;
        TunnelGuard.healthy = 0;
        return;
      }
      if (publishedTunnelId() === desired) {
        // The extension is alive and publishing for this tunnel.
        TunnelGuard.silent = 0;
        TunnelGuard.attempts = 0;
        TunnelGuard.healthy++;
        if (TunnelGuard.healthy % HEARTBEAT_CHECKS === 0) {
          Diag.write(`guard: alive after ${TunnelGuard.healthy * SECONDS_PER_CHECK}s, ` +
            'the tunnel is still publishing');
        }
        return;
      }
      if (!SettingsStore.seamlessRecovery()) {
        // Recovery is off, so a dead tunnel stays down until the user says so.
        TunnelGuard.silent = 0;
        return;
      }
      if (TunnelGuard.inFlight) {
        return;
      }
      const now: number = Date.now();
      if (now < TunnelGuard.nextAttemptAt) {
        return;
      }
      const needed: number = Math.max(1, Math.ceil(SettingsStore.recoveryDelay() / SECONDS_PER_CHECK));
      TunnelGuard.silent++;
      if (TunnelGuard.silent < needed) {
        return;
      }
      if (TunnelGuard.attempts >= MAX_ATTEMPTS) {
        Diag.write(`guard: the tunnel keeps dying after ${TunnelGuard.attempts} restarts, ` +
          'standing down until the app is opened again');
        TunnelGuard.nextAttemptAt = now + COOLDOWN_MS;
        TunnelGuard.attempts = 0;
        TunnelGuard.silent = 0;
        return;
      }
      const tunnel: WgTunnel | null = TunnelStore.find(desired);
      if (tunnel === null) {
        Diag.write(`guard: the wanted tunnel ${desired} is not in the store any more`);
        TunnelStore.setDesired('');
        return;
      }
      TunnelGuard.restart(tunnel, now);
    } catch (err) {
      hilog.warn(0x0000, TAG, `guard check failed: ${(err as Error).message}`);
    }
  }

  private static restart(tunnel: WgTunnel, now: number): void {
    const snapshot: BridgeStatus | null = StatusBridge.read();
    let detail: string = 'no snapshot was ever published';
    if (snapshot !== null) {
      const secs: number = Math.floor((now - snapshot.updated) / 1000);
      detail = `last snapshot ${snapshot.state}, ${secs}s old`;
    }
    Diag.write(`guard: the tunnel went silent (${detail}), restarting the extension`);
    TunnelGuard.inFlight = true;
    TunnelGuard.attempts++;
    const want: Want = {
      bundleName: 'com.wgate.app',
      abilityName: EXT_ABILITY,
      parameters: { 'tunnel': JSON.stringify(tunnel) }
    };
    withTimeout(vpnExtension.startVpnExtensionAbility(want), START_TIMEOUT_MS, 'guard')
      .then(() => {
        TunnelGuard.inFlight = false;
        TunnelGuard.silent = 0;
        TunnelGuard.nextAttemptAt = Date.now() + RETRY_MS;
        Diag.write('guard: the system accepted the restart');
      })
      .catch((err: BusinessError) => {
        TunnelGuard.inFlight = false;
        TunnelGuard.silent = 0;
        TunnelGuard.nextAttemptAt = Date.now() + RETRY_MS;
        Diag.write(`guard: the restart was refused (${err.code} ${err.message})`);
      });
  }
}
