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
 */
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'Notifier';
const TUNNEL_NOTIFICATION_ID: number = 1001;
const BUNDLE: string = 'com.wgate.app';
const ABILITY: string = 'EntryAbility';

export class Notifier {
  private static agent: WantAgent | null = null;
  /** The text already on screen, so an identical republish is not sent at all. */
  private static lastTitle: string = '';
  private static lastText: string = '';

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

  static async update(title: string, text: string): Promise<void> {
    if (title === Notifier.lastTitle && text === Notifier.lastText) {
      return;
    }
    Notifier.lastTitle = title;
    Notifier.lastText = text;
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
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `publish failed: ${JSON.stringify(err)}`);
    }
  }

  static async clear(): Promise<void> {
    Notifier.lastTitle = '';
    Notifier.lastText = '';
    try {
      await notificationManager.cancel(TUNNEL_NOTIFICATION_ID);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `cancel failed: ${JSON.stringify(err)}`);
    }
  }
}
