/**
 * The ongoing notification: what it says, and which process publishes it.
 *
 * The app process is frozen a few minutes into the background — the platform
 * grants a three-minute transient task and no continuous-task type covers a VPN
 * — while the VPN extension keeps running for as long as its tun device exists.
 * A frozen process cannot publish, so the extension's two-second watchdog owns
 * the shade, and the app only publishes when the snapshot says the extension
 * did not (which is what a refusal looks like on a locked-down device).
 *
 * The text is built from the five switches under Appearance -> Notifications
 * instead of hard-coded sentences, and the failure marker is a glyph, because
 * the platform cannot tint a notification: `notificationRequest.color` is
 * documented as "Background color of the notification. Not supported currently."
 */
import { connection } from '@kit.NetworkKit';
import { SettingsStore } from './SettingsStore';
import { Notifier } from './Notifier';
import { WgTunnel } from '../model/Tunnel';
import { BridgeStatus } from '../util/StatusBridge';
import { formatBytes, duration } from './EngineStatus';
import { Tr } from '../i18n/Tr';

export interface TunnelNoticeText {
  /** Identity of this text; publishing is skipped while it did not change. */
  key: string;
  title: string;
  text: string;
}

export class TunnelNotice {
  private static lastKey: string = '';

  /**
   * The bearer the traffic leaves from, as a word for the shade.
   *
   * service/AutoTunnel.ets answers the same question as a *decision* (should
   * the tunnel run on this network?). This one is a label, so it keeps its own
   * mapping and the extension process does not have to pull the watcher in.
   */
  static networkLabel(): string {
    try {
      const caps = connection.getNetCapabilitiesSync(connection.getDefaultNetSync());
      if (caps.bearerTypes !== undefined && caps.bearerTypes.length > 0) {
        const type: connection.NetBearType = caps.bearerTypes[0];
        if (type === connection.NetBearType.BEARER_CELLULAR) {
          return Tr.t('Cellular');
        }
        if (type === connection.NetBearType.BEARER_ETHERNET) {
          return Tr.t('Wired Ethernet');
        }
      }
    } catch (e) {
      // fall through to the Wi-Fi default
    }
    return Tr.t('Wi-Fi');
  }

  /**
   * The transfer counters as they go into the shade, in 64 KiB steps.
   *
   * The text *is* the publish key, so a per-byte counter would republish the
   * notification on every watchdog tick for as long as traffic flows — silent
   * since `isAlertOnce`, but still a publish every two seconds. Rounding makes
   * the text settle between updates instead of racing the counters.
   */
  private static step(bytes: number): number {
    return Math.floor(bytes / 65536) * 65536;
  }

  /** The text for one snapshot, or null when the user turned the shade off. */
  static compose(snapshot: BridgeStatus, tunnel: WgTunnel): TunnelNoticeText | null {
    /*
     * "Recovering" is not a state the engine has: it is the difference between a
     * tunnel that is still trying to come up for the first time and one that was
     * already carrying traffic. The snapshot's handshake age is that difference —
     * zero until the first session exists, then always a positive age — so no
     * extra field is needed to tell a first connection from a reconnection.
     */
    const recovering: boolean = snapshot.handshakeAgeMs > 0 && snapshot.peersUp === 0 &&
      snapshot.state !== 'up' && snapshot.state !== 'stopped';
    return TunnelNotice.composeFor(tunnel.name, snapshot.state, snapshot.peersUp,
      snapshot.rxBytes, snapshot.txBytes, recovering, snapshot.handshakeAgeMs);
  }

  /**
   * The same text from loose values, so the app process can reuse it with the
   * status it reads instead of the raw snapshot.
   */
  static composeFor(name: string, state: string, peersUp: number, rxBytes: number,
    txBytes: number, recovering: boolean, downForMs: number): TunnelNoticeText | null {
    if (!SettingsStore.notification('live')) {
      return null;
    }
    const lines: string[] = [];
    if (state === 'offline') {
      // The session may still be inside its 180 s validity, but nothing can
      // leave the device, so the shade says what the user can act on.
      lines.push(Tr.t('Waiting for the network'));
    } else if (state === 'up') {
      lines.push(Tr.t('Connected'));
    } else if (state === 'error') {
      lines.push(Tr.t('Failed'));
    } else if (recovering && SettingsStore.notification('recovery')) {
      // A tunnel that already carried traffic is coming back, which is a
      // different thing from one that never came up.
      lines.push(Tr.t('Reconnecting…'));
    } else if (state === 'retry' || state === 'connecting' || state === 'handshaking') {
      lines.push(Tr.t('Connecting…'));
    } else {
      lines.push(Tr.t('Disconnected'));
    }
    if (recovering && SettingsStore.notification('recovery') && downForMs >= 5000) {
      /*
       * Bucketed to five seconds on purpose: the text is the publish key, so a
       * per-second counter would republish the shade on every watchdog tick for
       * as long as the reconnection takes.
       */
      const bucket: number = Math.floor(downForMs / 5000) * 5000;
      lines.push(Tr.tf('down for %1$s', duration(bucket)));
    }
    if (state === 'up' && SettingsStore.notification('transfer')) {
      lines.push(`${formatBytes(TunnelNotice.step(rxBytes))} ↓ ${formatBytes(TunnelNotice.step(txBytes))} ↑`);
    }
    if (SettingsStore.notification('origin')) {
      lines.push(Tr.tf('via %1$s', TunnelNotice.networkLabel()));
    }
    let title: string = `WGate · ${name}`;
    const down: boolean = state === 'error' || state === 'stopped' || state === 'idle' ||
      state === 'offline';
    if (down && SettingsStore.notification('failure_tint')) {
      title = `⚠ ${title}`;
    }
    const text: string = lines.join('\n');
    return {
      key: `${state}:${peersUp}:${Math.floor(rxBytes / 65536)}:${title}:${text}`,
      title: title,
      text: text
    };
  }

  /** Publishes at most one update per distinct text; null means "take it away". */
  static async show(notice: TunnelNoticeText | null): Promise<void> {
    if (notice === null) {
      await TunnelNotice.clear();
      return;
    }
    if (notice.key === TunnelNotice.lastKey) {
      return;
    }
    TunnelNotice.lastKey = notice.key;
    await Notifier.update(notice.title, notice.text);
  }

  static async clear(): Promise<void> {
    if (TunnelNotice.lastKey.length === 0) {
      return;
    }
    TunnelNotice.lastKey = '';
    await Notifier.clear();
  }
}
