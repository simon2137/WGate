/**
 * Keep-alive primitives that HarmonyOS actually offers a VPN app.
 *
 * Three layers exist on this platform and only two of them are ours to control:
 *
 * 1. The VPN extension process. The system starts it through
 *    `vpnExtension.startVpnExtensionAbility()` and keeps it while the tun device
 *    exists, because the connection belongs to the extension. Nothing in this
 *    file is needed for that; it is why the tunnel survives the UI being closed.
 * 2. The application process. It owns the auto-tunnel network watcher
 *    (`AutoTunnel.start()`) and the tunnel guard (`TunnelGuard.start()`), and the
 *    platform freezes a background process after a short grace period. A
 *    transient task ("短时任务") buys three minutes of execution, one minute on a
 *    low battery, out of a daily quota of about ten minutes, which covers the
 *    screen-off and network-handover windows that matter for a rule that reacts
 *    to `netLost` and for a tunnel the system takes away in the background.
 * 3. Anything longer than that. A continuous task would be the tool, but the
 *    task types the platform defines contain no VPN type at all: `taskKeeping`
 *    is PC/2-in-1 only (API 21+) unless the app holds the restricted
 *    KEEP_BACKGROUND_RUNNING_SYSTEM permission, and `dataTransfer` is cancelled
 *    once progress stops being reported. Claiming a type the app does not
 *    perform is checked and gets the process suspended. So there is no legal way
 *    to watch the network indefinitely, and the honest behaviour is to record
 *    when the grace period ended instead of pretending the watcher is still
 *    live.
 */
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Diag } from '../util/Diag';

const REASON: string = 'a tunnel is up or waiting to be reconnected while the screen is off';

export class KeepAlive {
  private static requestId: number = -1;
  private static expiries: number = 0;

  /**
   * Asks for background execution. Called when the window goes to the
   * background; a second call while one is outstanding is a no-op because the
   * platform counts every request against a daily quota.
   */
  static arm(): void {
    if (KeepAlive.requestId >= 0) {
      return;
    }
    try {
      const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
        REASON, () => {
          /*
           * The platform calls this shortly BEFORE the grace period ends and
           * expects the app to hand the task back itself (see the short-time
           * task guide: the sample cancels inside this callback). Letting it
           * run out counts against the daily quota and can get the process
           * suspended, so the id is cancelled here rather than dropped.
           */
          const id: number = KeepAlive.requestId;
          KeepAlive.requestId = -1;
          KeepAlive.expiries += 1;
          if (id >= 0) {
            try {
              backgroundTaskManager.cancelSuspendDelay(id);
            } catch (err) {
              // the task may already be gone; there is nothing left to release
            }
          }
          Diag.write('keep-alive: the grace period is ending, the watcher is about to be frozen');
        });
      KeepAlive.requestId = info.requestId;
      Diag.write(`keep-alive: ${info.actualDelayTime} ms of background time granted`);
    } catch (err) {
      const e = err as BusinessError;
      Diag.write(`keep-alive: the background request failed (${e.code} ${e.message})`);
    }
  }

  /** Gives the unused remainder back; the quota is shared for the whole day. */
  static disarm(): void {
    if (KeepAlive.requestId < 0) {
      return;
    }
    const id: number = KeepAlive.requestId;
    KeepAlive.requestId = -1;
    try {
      backgroundTaskManager.cancelSuspendDelay(id);
      Diag.write('keep-alive: released the background grace period');
    } catch (err) {
      const e = err as BusinessError;
      Diag.write(`keep-alive: the release failed (${e.code} ${e.message})`);
    }
  }

  /** True while the application process is allowed to run in the background. */
  static armed(): boolean {
    return KeepAlive.requestId >= 0;
  }

  /** How many times the grace period has expired in this process. */
  static expiryCount(): number {
    return KeepAlive.expiries;
  }
}
