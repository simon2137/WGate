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
 *    low battery, out of a daily quota of about ten minutes.
 * 3. Anything longer than that. A continuous task would be the tool, but the
 *    task types the platform defines contain no VPN type at all: `taskKeeping`
 *    is PC/2-in-1 only (API 21+) unless the app holds the restricted
 *    KEEP_BACKGROUND_RUNNING_SYSTEM permission, and `dataTransfer` is cancelled
 *    once progress stops being reported. Claiming a type the app does not
 *    perform is checked and gets the process suspended.
 *
 * So the phone gets a transient grace, spent sparingly (see `arm()`), while the
 * desktop, where `taskKeeping` is legitimate, keeps a continuous task for as
 * long as a tunnel is up or an auto-tunnel rule is armed.
 */
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, common, WantAgent } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { Diag } from '../util/Diag';

const REASON: string = 'a tunnel is up or waiting to be reconnected while the screen is off';
const CONTINUOUS_MODES: string[] = ['taskKeeping'];
/** Below this the daily quota cannot buy a useful grace, so do not spend it. */
const MIN_QUOTA_MS: number = 60000;

function isDesktop(): boolean {
  return deviceInfo.deviceType === '2in1';
}

export class KeepAlive {
  private static requestId: number = -1;
  private static expiries: number = 0;
  private static continuous: boolean = false;

  /**
   * Asks for background execution. Called when the window goes to the
   * background; a second call while one is outstanding is a no-op because the
   * platform counts every request against a daily quota.
   *
   * The quota is read first: a request made with nothing left is refused with
   * 9900002, which used to be the only trace of the app having no grace at all.
   * Logging the remainder instead makes the next report say which of the two
   * happened.
   */
  static async arm(): Promise<void> {
    if (KeepAlive.requestId >= 0) {
      return;
    }
    const quota: number = await KeepAlive.remainingQuota();
    if (quota >= 0 && quota < MIN_QUOTA_MS) {
      Diag.write(`keep-alive: ${quota} ms of daily quota left, not asking for a grace period`);
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

  /**
   * Desktop only: a continuous task keeps the app and its tray alive while a
   * tunnel is up or an auto-tunnel rule is armed. `taskKeeping` is the type the
   * platform offers for a PC app that has to keep working, and the module
   * declares it under the ability's `backgroundModes`.
   */
  static async holdContinuous(context: common.UIAbilityContext): Promise<void> {
    if (KeepAlive.continuous || !isDesktop()) {
      return;
    }
    try {
      const agent: WantAgent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });
      await backgroundTaskManager.startBackgroundRunning(context, CONTINUOUS_MODES, agent);
      KeepAlive.continuous = true;
      Diag.write('keep-alive: continuous task started (desktop)');
    } catch (err) {
      const e = err as BusinessError;
      Diag.write(`keep-alive: the continuous task was refused (${e.code} ${e.message})`);
    }
  }

  /** Ends the desktop continuous task; leaves a phone alone. */
  static async releaseContinuous(context: common.UIAbilityContext): Promise<void> {
    if (!KeepAlive.continuous) {
      return;
    }
    KeepAlive.continuous = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      Diag.write('keep-alive: continuous task released');
    } catch (err) {
      const e = err as BusinessError;
      Diag.write(`keep-alive: the continuous task release failed (${e.code} ${e.message})`);
    }
  }

  /** True while the application process is allowed to run in the background. */
  static armed(): boolean {
    return KeepAlive.requestId >= 0;
  }

  /** True while a desktop continuous task is held. */
  static continuousTask(): boolean {
    return KeepAlive.continuous;
  }

  /** How many times the grace period has expired in this process. */
  static expiryCount(): number {
    return KeepAlive.expiries;
  }

  /** Remaining short-task quota for today, in ms; -1 when it cannot be read. */
  private static async remainingQuota(): Promise<number> {
    try {
      const info: backgroundTaskManager.TransientTaskInfo =
        await backgroundTaskManager.getTransientTaskInfo();
      return info.remainingQuota;
    } catch (err) {
      const e = err as BusinessError;
      Diag.write(`keep-alive: the quota is unreadable (${e.code} ${e.message})`);
      return -1;
    }
  }
}
