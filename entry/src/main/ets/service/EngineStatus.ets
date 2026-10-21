import wgcore from 'libwgcore.so';
import { BridgeStatus, StatusBridge } from '../util/StatusBridge';
import { Tr } from '../i18n/Tr';

/** What `wgcore.status()` reports; the extension's snapshot has the same shape. */
export interface EngineStatus {
  state: string;
  udpFd: number;
  rxBytes: number;
  txBytes: number;
  rxPackets: number;
  txPackets: number;
  handshakes: number;
  handshakeMs: number;
  queueDrops: number;
  socketGen: number;
  peersUp: number;
  /** Only the extension's snapshot knows this; the local engine reports 0. */
  peerCount: number;
  lastErrno: number;
  /**
   * True when the extension process published the ongoing notification for this
   * snapshot. The app must not publish while it is set — the extension is the
   * process the system keeps scheduling in the background.
   */
  notified: boolean;
}

/**
 * The engine runs inside the VPN extension, which the system gives its own
 * process, so `wgcore.status()` here always describes a stopped engine. The
 * extension publishes a snapshot instead, and this is how long it stays trusted.
 */
const BRIDGE_FRESH_MS: number = 8000;

/** The published snapshot, or null when it is missing or stale. */
export function bridgeStatus(): EngineStatus | null {
  const snap: BridgeStatus | null = StatusBridge.read();
  if (snap === null || Date.now() - snap.updated > BRIDGE_FRESH_MS) {
    return null;
  }
  const now: number = Date.now();
  const status: EngineStatus = {
    state: snap.state,
    udpFd: snap.udpFd,
    rxBytes: snap.rxBytes,
    txBytes: snap.txBytes,
    rxPackets: snap.rxPackets,
    txPackets: snap.txPackets,
    handshakes: snap.handshakeAgeMs > 0 ? 1 : 0,
    // handshakeAge() compares against Date.now(), so rebuild the stamp from the age.
    handshakeMs: snap.handshakeAgeMs > 0 ? now - snap.handshakeAgeMs : 0,
    queueDrops: 0,
    socketGen: 0,
    peersUp: snap.peersUp,
    peerCount: snap.peerCount,
    lastErrno: 0,
    notified: snap.notified === true
  };
  return status;
}

/** The tunnel id the extension reported, or '' when nothing is running. */
export function publishedTunnelId(): string {
  const snap: BridgeStatus | null = StatusBridge.read();
  if (snap === null || Date.now() - snap.updated > BRIDGE_FRESH_MS) {
    return '';
  }
  if (snap.state === 'stopped') {
    return '';
  }
  return snap.id;
}

/** Fresh snapshot first, then the local engine (which only helps in-process). */
export function readStatus(): EngineStatus | null {
  const shared: EngineStatus | null = bridgeStatus();
  if (shared !== null) {
    return shared;
  }
  try {
    const raw: string = wgcore.status() as string;
    if (raw.length === 0) {
      return null;
    }
    const parsed = JSON.parse(raw) as EngineStatus;
    // The native status JSON has no peer count; only the extension knows it.
    parsed.peerCount = 0;
    // No snapshot means no extension publisher, so the app is responsible.
    parsed.notified = false;
    return parsed;
  } catch (e) {
    return null;
  }
}

export function isRunning(state: string): boolean {
  // `offline` is a wanted tunnel that cannot talk right now: the switch stays on
  // so the tunnel comes back with the network, exactly like `connecting`.
  return state === 'up' || state === 'connecting' || state === 'handshaking' ||
    state === 'offline';
}

/** "Connected", "Connecting…" or "Disconnected", the way the list labels rows. */
export function stateLabel(state: string): string {
  if (state === 'up') {
    return Tr.t('Connected');
  }
  if (state === 'offline') {
    return Tr.t('No network');
  }
  if (state === 'connecting' || state === 'handshaking') {
    return Tr.t('Connecting…');
  }
  if (state === 'error') {
    return Tr.t('Failed');
  }
  return Tr.t('Disconnected');
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/** "12s ago" / "3m ago" / "2h ago" for a CLOCK_MONOTONIC-free timestamp. */
export function ago(stamp: number): string {
  if (stamp <= 0) {
    return '—';
  }
  const secs: number = Math.floor((Date.now() - stamp) / 1000);
  if (secs < 0) {
    return '—';
  }
  if (secs < 60) {
    return `${secs}s ago`;
  }
  if (secs < 3600) {
    return `${Math.floor(secs / 60)}m ago`;
  }
  return `${Math.floor(secs / 3600)}h ago`;
}

/** "1m 20s" for a duration in ms; used by the tunnel up time. */
export function duration(ms: number): string {
  const secs: number = Math.floor(ms / 1000);
  if (secs < 60) {
    return `${secs}s`;
  }
  if (secs < 3600) {
    return `${Math.floor(secs / 60)}m ${secs % 60}s`;
  }
  return `${Math.floor(secs / 3600)}h ${Math.floor((secs % 3600) / 60)}m`;
}

export function maskKey(key: string): string {
  if (key.length <= 12) {
    return key;
  }
  return `${key.substring(0, 6)}…${key.substring(key.length - 4)}`;
}
