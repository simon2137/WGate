/**
 * Ongoing notification: mirrors the tunnel state into the notification shade so
 * the user can see the tunnel is up (and its transfer counters) without
 * reopening the app.  Every call is best effort — a device that has
 * notifications turned off must not break the connect flow.
 *
 * The request carries a WantAgent for the singleton EntryAbility, so tapping the
 * shade opens the app. A notification without one is a dead rectangle: it lights
 * up, and the tap lands nowhere. The agent is built once and reused, because the
 * extension republishes this notification every two seconds.
 *
 * "Turned off" is a state of its own, not a failure: the switch is per install,
 * so a build installed from the store has never been granted it, and every
 * publish answers 1600004 Notification disabled until the user allows it. The
 * app must ask for that once (requestIfOff), then keep quiet and retry cheaply
 * instead of writing a failure into the trace every two seconds.
 */
import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { Diag } from '../util/Diag';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'Notifier';
const TUNNEL_NOTIFICATION_ID: number = 1001;
const BUNDLE: string = 'com.wgate.app';
const ABILITY: string = 'EntryAbility';
/** 1600004 Notification disabled: this app's notification switch is off. */
const NOT_ALLOWED: number = 1600004;
/** 1600007 The notification does not exist: there is nothing left to cancel. */
const NOT_FOUND: number = 1600007;
/** How often a switch known to be off is re-read, in milliseconds. */
const OFF_PROBE_MS: number = 10000;

export class Notifier {
  private static agent: WantAgent | null = null;
  /** The text already on screen, so an identical republish is not sent at all. */
  private static lastTitle: string = '';
  private static lastText: string = '';
  /** The system refused this app; the answer is re-read at most every OFF_PROBE_MS. */
  private static off: boolean = false;
  private static offAt: number = 0;
  /** The refusal has been written to the trace once, not once per watchdog tick. */
  private static offTraced: boolean = false;
  /** The system's authorization dialog was already asked for in this process. */
  private static asked: boolean = false;

  /**
   * The tap target. `launchType` is `singleton` in module.json5, so a tap while
   * the app is already open brings that instance forward instead of stacking a
   * second one.
   */
  private static async agentFor(): Promise<WantAgent | undefined> {
    if (Notifier.agent !== null) {
      return Notifier.agent;
    }
    try {
      Notifier.agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: BUNDLE, abilityName: ABILITY }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });
      return Notifier.agent;
    } catch (err) {
      // The notification is still worth showing without a tap target.
      hilog.warn(DOMAIN, TAG, `wantAgent failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  /**
   * Whether the system lets this app publish at all.
   *
   * The question costs a call into the notification service, so it is only spent
   * where the answer can change something: while publishing works nothing is
   * asked at all, and after a refusal it is re-read at most every OFF_PROBE_MS.
   * That is what lets a user who turns the switch back on in Settings get the
   * shade within a tick, without a probe on every two-second update.
   */
  private static allowedNow(): boolean {
    if (!Notifier.off) {
      return true;
    }
    if (Date.now() - Notifier.offAt < OFF_PROBE_MS) {
      return false;
    }
    Notifier.offAt = Date.now();
    try {
      Notifier.off = !notificationManager.isNotificationEnabledSync();
    } catch (err) {
      // No answer is not a refusal: let the publish report the real code.
      Notifier.off = false;
    }
    return !Notifier.off;
  }

  /**
   * One trace line per refusal, so the log shows why the shade stayed empty
   * without burying the tunnel's own lines under a repeat every two seconds.
   */
  private static traceOff(): void {
    if (Notifier.offTraced) {
      return;
    }
    Notifier.offTraced = true;
    Diag.write('notice: this app may not post notifications');
  }

  /**
   * Puts the notice up. Resolves false when the system refused it, so the caller
   * keeps the text pending and tries again once the switch comes back on.
   */
  static async update(title: string, text: string): Promise<boolean> {
    // "Unchanged" only matters while the notice is actually on the bar: a tap
    // deletes it, and the payload of a running tunnel stops changing.
    if (title === Notifier.lastTitle && text === Notifier.lastText && await Notifier.onTheBar()) {
      return true;
    }
    if (!Notifier.allowedNow()) {
      Notifier.traceOff();
      return false;
    }
    try {
      const agent: WantAgent | undefined = await Notifier.agentFor();
      await notificationManager.publish({
        id: TUNNEL_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: text }
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        // `isAlertOnce` is the whole point: false (the default) replays the sound
        // and the vibration on every update, and this notification is updated for
        // as long as the tunnel carries traffic. With it, only the first publish
        // alerts and later updates are sent at SlotLevel.LEVEL_LOW.
        isAlertOnce: true,
        isOngoing: true,
        wantAgent: agent
      });
      // Recorded only once the system took the request: a refused publish has to
      // stay pending, or the next tick would think this text is already up.
      Notifier.lastTitle = title;
      Notifier.lastText = text;
      Notifier.off = false;
      Notifier.offTraced = false;
      return true;
    } catch (err) {
      const code: number = (err as BusinessError).code;
      if (code === NOT_ALLOWED) {
        Notifier.off = true;
        Notifier.offAt = Date.now();
        Notifier.traceOff();
        return false;
      }
      hilog.warn(DOMAIN, TAG, `publish failed: ${JSON.stringify(err)}`);
      Diag.write(`notice: publish failed (${code})`);
      return false;
    }
  }

  /**
   * Puts the system's own authorization dialog in front of the user when this
   * app may not post yet.
   *
   * Nothing else can turn the switch on: it belongs to the install, and a build
   * that arrives through the store starts with it off because nobody was ever
   * asked. The dialog needs a window, so only the UI process can ask, and the
   * call is deliberately not awaited — a connect must not wait for a dialog the
   * user may take a while to read. The system shows it once per install: after a
   * refusal the user's way back is Appearance -> Notifications -> Settings,
   * which is why the answer is asked for only once per process.
   */
  static requestIfOff(context: common.UIAbilityContext): void {
    if (Notifier.asked) {
      return;
    }
    Notifier.asked = true;
    let allowed: boolean = false;
    try {
      allowed = notificationManager.isNotificationEnabledSync();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `notification probe failed: ${(err as Error).message}`);
    }
    if (allowed) {
      Notifier.off = false;
      return;
    }
    notificationManager.requestEnableNotification(context).then(() => {
      Notifier.off = false;
      Notifier.offTraced = false;
      Diag.write('notice: notifications were allowed');
    }).catch((err: BusinessError) => {
      Notifier.off = true;
      Notifier.offAt = Date.now();
      Notifier.offTraced = true;
      Diag.write(`notice: this app may not post notifications (${err.code})`);
    });
  }

  /**
   * Whether this app still has the tunnel notice up. A system that refuses the
   * list is treated as "yes": republishing on every tick would work, but there is
   * no reason to when the answer is unknown.
   */
  private static async onTheBar(): Promise<boolean> {
    try {
      const live: notificationManager.NotificationRequest[] =
        await notificationManager.getActiveNotifications();
      for (let i = 0; i < live.length; i++) {
        if (live[i].id === TUNNEL_NOTIFICATION_ID) {
          return true;
        }
      }
      return false;
    } catch (err) {
      return true;
    }
  }

  static async clear(): Promise<void> {
    Notifier.lastTitle = '';
    Notifier.lastText = '';
    try {
      await notificationManager.cancel(TUNNEL_NOTIFICATION_ID);
    } catch (err) {
      const code: number = (err as BusinessError).code;
      if (code === NOT_FOUND) {
        // The state this call asks for. The system already took the notice down
        // (a tap does that), so there is nothing to report.
        return;
      }
      hilog.warn(DOMAIN, TAG, `cancel failed: ${JSON.stringify(err)}`);
      Diag.write(`notice: cancel failed (${code})`);
    }
  }
}
