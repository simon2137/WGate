/**
 * Ongoing notification: mirrors the tunnel state into the notification shade so
 * the user can see the tunnel is up (and its transfer counters) without
 * reopening the app.  Every call is best effort — a device that has
 * notifications turned off must not break the connect flow.
 */
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'Notifier';
const TUNNEL_NOTIFICATION_ID: number = 1001;

export class Notifier {
  static async update(title: string, text: string): Promise<void> {
    try {
      await notificationManager.publish({
        id: TUNNEL_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: text }
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `publish failed: ${JSON.stringify(err)}`);
    }
  }

  static async clear(): Promise<void> {
    try {
      await notificationManager.cancel(TUNNEL_NOTIFICATION_ID);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `cancel failed: ${JSON.stringify(err)}`);
    }
  }
}
