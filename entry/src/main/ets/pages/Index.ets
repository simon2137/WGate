/**
 * Main screen.
 *
 * Responsive across the device types the app ships to:
 *   - phone (narrow):   one column, editor in a bottom sheet
 *   - tablet (medium):  a two-lane card list, editor in a sheet
 *   - 2in1 / large:     master-detail, editor inline in the right pane
 *
 * Breakpoints follow the window width in vp, so folding, rotation and window
 * resizing all re-layout without a restart.
 */
import { vpnExtension } from '@kit.NetworkKit';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, router } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import pasteboard from '@ohos.pasteboard';
import wgcore from 'libwgcore.so';
import { WgTunnel, WgPeer, parseWgQuick, toWgQuick, toQrText } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { TunnelNotice } from '../service/TunnelNotice';
import { withTimeout, isTimeout } from '../util/Async';
import { Diag } from '../util/Diag';
import { BridgeStatus, StatusBridge } from '../util/StatusBridge';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

const DOMAIN: number = 0x0001;
const TAG: string = 'Index';
const EXT_ABILITY: string = 'WgVpnExtAbility';
const BREAK_MEDIUM_VP: number = 600;
const BREAK_WIDE_VP: number = 760;
const START_TIMEOUT_MS: number = 20000;
const STOP_TIMEOUT_MS: number = 8000;
const SHEET_NONE: string = '';
const SHEET_EDITOR: string = 'editor';
const SHEET_LOGS: string = 'logs';
const SHEET_DETAIL: string = 'detail';
const SHEET_QR: string = 'qr';
/** The built-in QRCode component encodes at most this many characters. */
const QR_MAX_CHARS: number = 512;

interface EngineStatus {
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
  lastErrno: number;
  /**
   * True when the extension process published the ongoing notification for this
   * snapshot, in which case this process must keep its hands off the shade.
   */
  notified: boolean;
}

/** What wgcore.probe() reports about one endpoint. */
interface ProbeReport {
  host: string;
  port: number;
  addresses: string[];
  reply: boolean;
  handshake: boolean;
  rttMs: number;
  error: string;
}

/**
 * Turns a probe report into one sentence a user can act on.
 *
 * The interesting case is "we resolved something, nothing answered": that is a
 * DNS answer pointing at the wrong host (very common with filtered resolvers),
 * not a WireGuard problem, so the wording must not send anyone chasing keys.
 */
function describeProbe(report: ProbeReport): string {
  const where: string = report.host + ':' + report.port.toString();
  if (report.error.length > 0) {
    return 'Could not check ' + where + ' — ' + report.error;
  }
  const addrs: string = report.addresses.length > 0 ? report.addresses.join(', ') : 'nothing';
  if (report.handshake) {
    return where + ' answered a handshake in ' + report.rttMs.toString() +
      ' ms (resolved to ' + addrs + ').';
  }
  if (report.reply) {
    return where + ' replied but the handshake did not complete (resolved to ' + addrs +
      '). Check the keys, or that the server knows this peer.';
  }
  return 'No answer from ' + where + ', resolved to ' + addrs +
    '. If that address looks wrong, the DNS answer is the problem, not the tunnel: ' +
    'try another resolver or use the server IP directly.';
}

/**
 * The engine runs inside the VPN extension, which the system gives its own
 * process. `wgcore.status()` here therefore always describes a stopped engine:
 * that is why a working tunnel used to show "Disconnected" with 0 B counters.
 * The extension publishes its snapshot instead, and this is the fresh-enough
 * window for trusting it.
 */
const BRIDGE_FRESH_MS: number = 8000;

function bridgeStatus(): EngineStatus | null {
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
    lastErrno: 0,
    notified: snap.notified === true
  };
  return status;
}

function readStatus(): EngineStatus | null {
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
    // No snapshot in reach means no extension publisher, so this process is the
    // one that has to keep the shade up to date.
    parsed.notified = false;
    return parsed;
  } catch (e) {
    return null;
  }
}

function formatBytes(bytes: number): string {
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

function handshakeAge(ms: number): string {
  if (ms <= 0) {
    return '—';
  }
  const secs = Math.floor((Date.now() - ms) / 1000);
  if (secs < 60) {
    return `${secs}s ago`;
  }
  if (secs < 3600) {
    return `${Math.floor(secs / 60)}m ago`;
  }
  return `${Math.floor(secs / 3600)}h ago`;
}

function maskKey(key: string): string {
  if (key.length <= 12) {
    return key;
  }
  return `${key.substring(0, 6)}…${key.substring(key.length - 4)}`;
}

@Entry
@Component
struct Index {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State tunnels: WgTunnel[] = [];
  @State activeId: string = '';
  @State selectedId: string = '';
  @State engineState: string = 'idle';
  @State rxText: string = '0 B';
  @State txText: string = '0 B';
  @State packetText: string = '0 / 0';
  @State handshakeText: string = '—';
  @State lastError: string = '';
  @State busy: boolean = false;
  @State sheetOpen: boolean = false;
  @State sheetKind: string = SHEET_NONE;
  @State paneEditor: boolean = false;
  @State isMedium: boolean = false;
  @State isWide: boolean = false;
  @State toast: string = '';
  @State toggleEpoch: number = 0;
  @State peersUp: number = 0;
  @State logsText: string = '';
  @State probeText: string = '';
  @State probeBusy: boolean = false;
  @State diagText: string = '';
  /** Pixel map of the QR code rendered for the selected tunnel. */
  @State qrText: string = '';
  @State qrName: string = '';

  // editor state — the form is the source of truth; raw wg-quick text is a view
  @State editorTitle: string = 'New tunnel';
  @State editorId: string = '';
  @State editorName: string = '';
  @State editorAddress: string = '10.66.0.2/32';
  @State editorDns: string = '1.1.1.1';
  @State editorMtu: string = '1420';
  @State editorPrivateKey: string = '';
  @State editorPublicKey: string = '';
  @State editorExcluded: string = '';
  @State editorRaw: boolean = false;
  @State editorText: string = '';
  @State editorAwg: boolean = false;
  /** Shown inside the sheet: page level banners are hidden behind it. */
  @State editorHint: string = '';
  @State editorJc: string = '0';
  @State editorJmin: string = '0';
  @State editorJmax: string = '0';
  @State editorS1: string = '0';
  @State editorS2: string = '0';
  @State editorS3: string = '0';
  @State editorH1: string = '1';
  @State editorH2: string = '2';
  @State editorH3: string = '3';
  @State editorH4: string = '4';
  @State editorPeers: WgPeer[] = [];

  private timer: number = -1;
  private idleTicks: number = 0;
  private win: window.Window | null = null;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    TunnelStore.init(context);
    Diag.init(context);
    this.watchWindow();
    this.refresh();
    this.pollEngine();
    this.restoreDesired();
    this.timer = setInterval(() => {
      this.pollEngine();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.win !== null) {
      this.win.off('windowSizeChange');
      this.win = null;
    }
  }

  /** The scanner page saves tunnels directly, so the list is rebuilt on return. */
  onPageShow(): void {
    if (this.tunnels.length === 0 || this.sheetKind === SHEET_NONE) {
      this.refresh();
    }
  }

  /**
   * Breakpoints follow the window, not the screen: on a 2in1 the window can be
   * resized at will and on a foldable the usable width changes while running.
   */
  private async watchWindow(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      this.win = win;
      this.applyWidth(px2vp(win.getWindowProperties().windowRect.width));
      win.on('windowSizeChange', (size: window.Size) => {
        this.applyWidth(px2vp(size.width));
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'window metrics unavailable');
    }
  }

  private applyWidth(width: number): void {
    this.isMedium = width >= BREAK_MEDIUM_VP;
    const wide = width >= BREAK_WIDE_VP;
    if (wide && !this.isWide) {
      this.sheetOpen = false;
    }
    this.isWide = wide;
  }

  /** Reconnect the tunnel the user last asked for, e.g. after a reboot. */
  private restoreDesired(): void {
    const desired = TunnelStore.desiredId();
    if (desired.length === 0 || TunnelStore.activeId().length > 0) {
      return;
    }
    // The extension records its id in its own process, which may not be visible
    // here; a fresh snapshot means a tunnel is already running.
    const snap: BridgeStatus | null = StatusBridge.read();
    if (snap !== null && Date.now() - snap.updated <= BRIDGE_FRESH_MS && snap.id.length > 0 &&
        snap.state !== 'stopped' && snap.state !== 'idle' && snap.state !== 'error') {
      return;
    }
    const tunnel = TunnelStore.find(desired);
    if (tunnel !== null) {
      this.connect(tunnel);
    }
  }

  private refresh(): void {
    this.tunnels = TunnelStore.list();
    this.activeId = TunnelStore.activeId();
    this.adoptPublishedActive();
    this.lastError = TunnelStore.lastError();
    if (this.selectedId.length === 0 && this.tunnels.length > 0) {
      this.selectedId = this.tunnels[0].id;
    }
  }

  /**
   * `preferences` caches per process, so the id the extension recorded when it
   * came up can be invisible here. The published snapshot carries the id, which
   * makes the list agree with the tunnel that is actually running.
   */
  private adoptPublishedActive(): void {
    const snap: BridgeStatus | null = StatusBridge.read();
    if (snap === null || Date.now() - snap.updated > BRIDGE_FRESH_MS) {
      return;
    }
    if (snap.id.length === 0 || snap.state === 'stopped' || snap.state === 'idle' ||
        snap.state === 'error') {
      return;
    }
    if (snap.id === this.activeId) {
      return;
    }
    this.activeId = snap.id;
    TunnelStore.setActive(snap.id);
  }

  private pollEngine(): void {
    this.adoptPublishedActive();
    const status = readStatus();
    if (status === null) {
      return;
    }
    this.engineState = status.state;
    this.peersUp = status.peersUp ?? 0;
    this.rxText = formatBytes(status.rxBytes);
    this.txText = formatBytes(status.txBytes);
    this.packetText = `${status.rxPackets} / ${status.txPackets}`;
    this.handshakeText = handshakeAge(status.handshakeMs);
    // The extension usually shares this process, but never trust the counter
    // alone: a tunnel that reports idle for a full 15 seconds is gone.
    if (status.state === 'stopped' || status.state === 'idle' || status.state === 'error') {
      this.idleTicks++;
      if (this.idleTicks >= 15 && this.activeId.length > 0) {
        this.activeId = '';
        TunnelStore.setActive('');
        TunnelNotice.clear();
      }
    } else {
      this.idleTicks = 0;
    }
    this.updateNotification(status);
  }

  /**
   * The shade is published by the VPN extension while it runs: that process is
   * the one the system keeps scheduling after this one is frozen, so it can keep
   * the notification truthful. The app only publishes when the snapshot says the
   * extension did not, and takes the notification down when no tunnel is left.
   */
  private updateNotification(status: EngineStatus): void {
    if (this.activeId.length === 0) {
      TunnelNotice.clear();
      return;
    }
    if (status.notified) {
      return;
    }
    const tunnel = TunnelStore.find(this.activeId);
    const name = tunnel !== null ? tunnel.name : 'WireGuard';
    // `handshakeMs` is a wall-clock stamp here (the bridge converts the engine's
    // age), so "how long has it been down" is the distance from it.
    const downFor: number = status.handshakeMs > 0 ? Date.now() - status.handshakeMs : 0;
    const recovering: boolean = downFor > 0 && status.peersUp === 0 &&
      status.state !== 'up' && status.state !== 'stopped';
    TunnelNotice.show(TunnelNotice.composeFor(name, status.state, status.peersUp,
      status.rxBytes, status.txBytes, recovering, downFor));
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2600);
  }

  private extensionWant(tunnel: WgTunnel): Want {
    return {
      bundleName: 'com.wgate.app',
      abilityName: EXT_ABILITY,
      parameters: { 'tunnel': JSON.stringify(tunnel) }
    };
  }

  private async connect(tunnel: WgTunnel): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      TunnelStore.setLastError('');
      TunnelStore.setDesired(tunnel.id);
      Diag.write(`connect requested: ${tunnel.name} -> ${tunnel.peers[0].host}:${tunnel.peers[0].port}`);
      await withTimeout(vpnExtension.startVpnExtensionAbility(this.extensionWant(tunnel)),
        START_TIMEOUT_MS, 'start');
      Diag.write('startVpnExtensionAbility returned, the extension should be up');
      this.activeId = tunnel.id;
      this.flash('Connecting…');
      this.watchStartup();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, `start failed: ${e.code} ${e.message}`);
      Diag.write(`startVpnExtensionAbility failed: ${e.code} ${e.message}`);
      TunnelStore.setDesired('');
      this.lastError = isTimeout(e) ?
        'The system did not confirm the VPN request' : `Could not start the VPN (${e.code})`;
      TunnelStore.setLastError(this.lastError);
      this.flash(this.lastError);
    } finally {
      this.busy = false;
      // Force the switch to be rebuilt: a Toggle only follows its binding when
      // that binding changes, and a failed attempt leaves it untouched.
      this.toggleEpoch++;
    }
  }

  /**
   * The system accepts the start request long before the extension has created
   * the tun device, and a failure there happens in the extension's own process.
   * A few seconds later the trace file says what went wrong; surface it instead
   * of leaving the user with a switch that quietly flipped back.
   */
  private watchStartup(): void {
    setTimeout(() => {
      const text: string = Diag.read();
      if (text.length === 0) {
        return;
      }
      const lines: string[] = text.split('\n').filter((line: string) => line.length > 0);
      for (let i = lines.length - 1; i >= 0 && i >= lines.length - 4; i--) {
        const line: string = lines[i];
        if (line.indexOf('failed') >= 0 || line.indexOf('engine open -> -') >= 0 ||
            line.indexOf('threw') >= 0) {
          this.lastError = line.substring(line.indexOf('  ') + 2).trim();
          this.flash(this.lastError);
          return;
        }
      }
      if (text.indexOf('extension onCreate') < 0) {
        // The system accepted the request but the service never reported in, so
        // nothing in this process knows why it stopped.
        this.lastError = 'The VPN service did not start. Open Logs for the startup trace.';
        this.flash(this.lastError);
      }
    }, 6000);
  }

  private async disconnect(tunnel: WgTunnel): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      TunnelStore.setDesired('');
      await withTimeout(vpnExtension.stopVpnExtensionAbility(this.extensionWant(tunnel)),
        STOP_TIMEOUT_MS, 'stop');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, `stop failed: ${e.code} ${e.message}`);
    } finally {
      this.activeId = '';
      TunnelStore.setActive('');
      this.busy = false;
      this.flash('Disconnected');
    }
  }

  private toggle(tunnel: WgTunnel, on: boolean): void {
    if (on) {
      this.connect(tunnel);
    } else {
      this.disconnect(tunnel);
    }
  }

  private openNew(): void {
    this.editorTitle = 'New tunnel';
    this.editorId = '';
    this.editorName = '';
    this.editorAddress = '10.66.0.2/32';
    this.editorDns = '1.1.1.1';
    this.editorMtu = '1420';
    this.editorPrivateKey = '';
    this.editorPublicKey = '';
    this.editorExcluded = '';
    this.editorAwg = false;
    this.editorJc = '0';
    this.editorJmin = '0';
    this.editorJmax = '0';
    this.editorS1 = '0';
    this.editorS2 = '0';
    this.editorS3 = '0';
    this.editorH1 = '1';
    this.editorH2 = '2';
    this.editorH3 = '3';
    this.editorH4 = '4';
    this.editorPeers = [new WgPeer('', '', '', 51820, '0.0.0.0/0', 25)];
    this.editorRaw = false;
    this.editorText = '';
    this.editorHint = '';
    this.openEditorSurface();
  }

  private openEdit(tunnel: WgTunnel): void {
    this.editorTitle = 'Edit tunnel';
    this.editorId = tunnel.id;
    this.editorName = tunnel.name;
    this.editorAddress = tunnel.address;
    this.editorDns = tunnel.dns;
    this.editorMtu = tunnel.mtu.toString();
    this.editorPrivateKey = tunnel.privateKey;
    this.editorPublicKey = tunnel.publicKey;
    this.editorExcluded = tunnel.excludedApps;
    this.editorAwg = tunnel.awg;
    this.editorJc = tunnel.jc.toString();
    this.editorJmin = tunnel.jmin.toString();
    this.editorJmax = tunnel.jmax.toString();
    this.editorS1 = tunnel.s1.toString();
    this.editorS2 = tunnel.s2.toString();
    this.editorS3 = tunnel.s3.toString();
    this.editorH1 = tunnel.h1.toString();
    this.editorH2 = tunnel.h2.toString();
    this.editorH3 = tunnel.h3.toString();
    this.editorH4 = tunnel.h4.toString();
    this.editorPeers = tunnel.peers.map((p: WgPeer) => p.clone());
    if (this.editorPeers.length === 0) {
      this.editorPeers = [new WgPeer('', '', '', 51820, '0.0.0.0/0', 25)];
    }
    this.editorRaw = false;
    this.editorText = toWgQuick(tunnel);
    this.editorHint = '';
    this.openEditorSurface();
  }

  private openEditorSurface(): void {
    if (this.isWide) {
      this.paneEditor = true;
    } else {
      this.sheetKind = SHEET_EDITOR;
      this.sheetOpen = true;
    }
  }

  private closeEditor(): void {
    this.paneEditor = false;
    this.sheetOpen = false;
    this.sheetKind = SHEET_NONE;
  }

  private numOf(value: string, fallback: number): number {
    const n = Number.parseInt(value.trim(), 10);
    return Number.isNaN(n) ? fallback : n;
  }

  /** Build a tunnel from the structured form. Null when a required field is off. */
  private formToTunnel(): WgTunnel | null {
    const t = new WgTunnel();
    t.id = this.editorId;
    t.name = this.editorName.trim().length > 0 ? this.editorName.trim() : 'WireGuard tunnel';
    t.address = this.editorAddress.trim();
    t.dns = this.editorDns.trim();
    t.mtu = this.numOf(this.editorMtu, 1420);
    t.privateKey = this.editorPrivateKey.trim();
    t.excludedApps = this.editorExcluded.trim();
    t.awg = this.editorAwg;
    t.jc = this.numOf(this.editorJc, 0);
    t.jmin = this.numOf(this.editorJmin, 0);
    t.jmax = this.numOf(this.editorJmax, 0);
    t.s1 = this.numOf(this.editorS1, 0);
    t.s2 = this.numOf(this.editorS2, 0);
    t.s3 = this.numOf(this.editorS3, 0);
    t.h1 = this.numOf(this.editorH1, 1);
    t.h2 = this.numOf(this.editorH2, 2);
    t.h3 = this.numOf(this.editorH3, 3);
    t.h4 = this.numOf(this.editorH4, 4);
    t.peers = [];
    for (let i = 0; i < this.editorPeers.length; i++) {
      const p = this.editorPeers[i];
      if (p.publicKey.trim().length === 0) {
        continue;
      }
      t.peers.push(new WgPeer(p.publicKey.trim(), p.presharedKey.trim(), p.host.trim(), p.port,
        p.allowedIPs.trim().length > 0 ? p.allowedIPs.trim() : '0.0.0.0/0', p.keepalive));
    }
    if (t.privateKey.length === 0 || t.peers.length === 0) {
      return null;
    }
    if (t.peers[0].host.length === 0) {
      return null;
    }
    return t;
  }

  /** Switching to the paste view regenerates the text from the form. */
  private syncTextFromForm(): void {
    const t = this.formToTunnel();
    if (t !== null) {
      this.editorText = toWgQuick(t);
    }
  }

  /** Switching back to the form parses the pasted text into the fields. */
  private syncFormFromText(): void {
    const parsed = parseWgQuick(this.editorText, this.editorName);
    if (parsed === null) {
      this.flash('Need an [Interface] PrivateKey and a [Peer] PublicKey');
      return;
    }
    parsed.id = this.editorId;
    this.editorRaw = false;
    this.editorAddress = parsed.address;
    this.editorDns = parsed.dns;
    this.editorMtu = parsed.mtu.toString();
    this.editorPrivateKey = parsed.privateKey;
    this.editorExcluded = parsed.excludedApps;
    this.editorAwg = parsed.awg;
    this.editorJc = parsed.jc.toString();
    this.editorJmin = parsed.jmin.toString();
    this.editorJmax = parsed.jmax.toString();
    this.editorS1 = parsed.s1.toString();
    this.editorS2 = parsed.s2.toString();
    this.editorS3 = parsed.s3.toString();
    this.editorH1 = parsed.h1.toString();
    this.editorH2 = parsed.h2.toString();
    this.editorH3 = parsed.h3.toString();
    this.editorH4 = parsed.h4.toString();
    this.editorPeers = parsed.peers.map((p: WgPeer) => p.clone());
  }

  private addPeer(): void {
    const peers = this.editorPeers.slice();
    peers.push(new WgPeer('', '', '', 51820, '0.0.0.0/0', 25));
    this.editorPeers = peers;
  }

  private removePeer(index: number): void {
    if (this.editorPeers.length <= 1) {
      this.flash('A tunnel needs at least one peer');
      return;
    }
    const peers = this.editorPeers.slice();
    peers.splice(index, 1);
    this.editorPeers = peers;
  }

  private setPeer(index: number, field: string, value: string): void {
    const peers = this.editorPeers.slice();
    const p = peers[index];
    if (field === 'publicKey') {
      p.publicKey = value;
    } else if (field === 'presharedKey') {
      p.presharedKey = value;
    } else if (field === 'host') {
      p.host = value;
    } else if (field === 'port') {
      p.port = this.numOf(value, 51820);
    } else if (field === 'allowedIPs') {
      p.allowedIPs = value;
    } else if (field === 'keepalive') {
      p.keepalive = this.numOf(value, 0);
    }
    this.editorPeers = peers;
  }

  private saveEditor(): void {
    let parsed: WgTunnel | null;
    if (this.editorRaw) {
      parsed = parseWgQuick(this.editorText, this.editorName);
      if (parsed !== null) {
        parsed.id = this.editorId;
        parsed.excludedApps = this.editorExcluded.trim();
      }
    } else {
      parsed = this.formToTunnel();
    }
    if (parsed === null) {
      hilog.info(DOMAIN, TAG, 'save: form incomplete');
      this.editorHint = 'Private key, peer public key and endpoint are required.';
      return;
    }
    if (parsed.id.length === 0) {
      parsed.id = Date.now().toString();
    }
    parsed.publicKey = wgcore.publicKeyFrom(parsed.privateKey) as string;
    if (parsed.publicKey.length === 0) {
      hilog.info(DOMAIN, TAG, 'save: invalid private key');
      this.editorHint = 'The private key is not a valid WireGuard key.';
      return;
    }
    TunnelStore.save(parsed);
    hilog.info(DOMAIN, TAG, `save: ok ${parsed.id} peers=${parsed.peers.length}`);
    this.closeEditor();
    this.selectedId = parsed.id;
    this.refresh();
    this.flash('Saved');
  }

  private deleteTunnel(tunnel: WgTunnel): void {
    if (tunnel.id === this.activeId) {
      this.disconnect(tunnel);
    }
    TunnelStore.remove(tunnel.id);
    if (this.selectedId === tunnel.id) {
      this.selectedId = '';
    }
    this.closeEditor();
    this.refresh();
    this.flash('Deleted');
  }

  private newKeyPair(): void {
    const generated: string = wgcore.generateKeyPair() as string;
    const pair = JSON.parse(generated) as Record<string, string>;
    this.editorPrivateKey = pair['private'];
    this.editorPublicKey = pair['public'];
    this.flash('New key pair generated');
  }

  /** Put a parsed configuration into the editor so the user can review it. */
  private loadIntoEditor(tunnel: WgTunnel, message: string): void {
    this.editorTitle = 'Import tunnel';
    this.editorId = '';
    this.openEdit(tunnel);
    this.editorTitle = 'Import tunnel';
    this.editorHint = message;
  }

  private async importFromClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      hilog.info(DOMAIN, TAG, `clipboard: ${text.length} chars`);
      const parsed = parseWgQuick(text, 'Imported tunnel');
      if (parsed === null) {
        hilog.info(DOMAIN, TAG, 'clipboard: not a wg-quick configuration');
        this.editorHint = 'The clipboard does not hold a wg-quick configuration.';
        return;
      }
      this.loadIntoEditor(parsed, 'Pasted configuration loaded');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `clipboard read failed: ${JSON.stringify(e)}`);
      this.editorHint = 'HarmonyOS only lets apps read the clipboard with a system ' +
        'permission, so this button cannot work. Long-press the box below and choose ' +
        'Paste instead.';
    }
  }

  private async importFromFile(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.conf', '.txt', '.wg']
      });
      if (uris.length === 0) {
        return;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size > 0 ? stat.size : 65536);
      const read = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const text = decoder.decodeToString(new Uint8Array(buffer, 0, read));
      const parsed = parseWgQuick(text, 'Imported tunnel');
      if (parsed === null) {
        this.editorHint = 'That file is not a wg-quick configuration.';
        return;
      }
      this.loadIntoEditor(parsed, 'Configuration imported');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `file import failed: ${JSON.stringify(e)}`);
      this.editorHint = 'Could not read that file.';
    }
  }

  private async copyConfig(tunnel: WgTunnel): Promise<void> {
    try {
      const text: string = toWgQuick(tunnel);
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      hilog.info(DOMAIN, TAG, `clipboard write: ${text.length} chars`);
      this.flash('Configuration copied');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `clipboard write failed: ${JSON.stringify(e)}`);
      this.flash('Could not access the clipboard');
    }
  }

  private refreshLogs(): void {
    try {
      this.logsText = wgcore.logs() as string;
    } catch (e) {
      this.logsText = 'the native engine is not available';
    }
    this.diagText = Diag.read();
  }

  private openLogs(): void {
    this.refreshLogs();
    this.sheetKind = SHEET_LOGS;
    this.sheetOpen = true;
  }

  /**
   * Resolve the selected tunnel's endpoint and try one handshake against it.
   *
   * When a tunnel never comes up, the reason is usually upstream of the engine:
   * the endpoint hostname resolves to an address nobody is listening on, or the
   * server does not answer. This runs the same resolution the engine would do
   * and prints what came back, so the log answers "is it the network or us".
   */
  private async checkEndpoint(): Promise<void> {
    const tunnel: WgTunnel | null = this.selectedTunnel();
    if (tunnel === null) {
      this.flash('Add a tunnel first');
      return;
    }
    this.probeBusy = true;
    this.probeText = 'Resolving ' + tunnel.endpoint() + ' ...';
    try {
      const raw: string = wgcore.probe(tunnel.toJson()) as string;
      hilog.info(DOMAIN, TAG, `probe raw: ${raw}`);
      if (raw.length === 0) {
        this.probeText = 'The native core returned nothing for ' + tunnel.endpoint();
        this.probeBusy = false;
        return;
      }
      const report: ProbeReport = JSON.parse(raw) as ProbeReport;
      this.probeText = describeProbe(report);
    } catch (e) {
      const err = e as Error;
      this.probeText = 'The endpoint check failed: ' + (err.message ?? String(e));
      hilog.warn(DOMAIN, TAG, `probe failed: ${err.message}`);
    }
    this.probeBusy = false;
  }

  private openDetail(tunnel: WgTunnel): void {
    this.selectedId = tunnel.id;
    this.sheetKind = SHEET_DETAIL;
    this.sheetOpen = true;
  }

  private openScanner(): void {
    router.pushUrl({ url: 'pages/Scan' }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, `scan navigation failed: ${err.code}`);
    });
  }

  /**
   * Render the tunnel as a QR code so another device can scan it.
   *
   * Generation uses the built-in `QRCode` component instead of Scan Kit's
   * `createBarcode`: it needs no HMS service, so it works on every device and on
   * the emulator, and it draws vector code straight into the layout.
   */
  private openQr(tunnel: WgTunnel): void {
    this.qrName = tunnel.name;
    this.qrText = toQrText(tunnel);
    this.sheetKind = SHEET_QR;
    this.sheetOpen = true;
    hilog.info(DOMAIN, TAG, `qr rendered for ${tunnel.id} (${this.qrText.length} chars)`);
  }

  private selectedTunnel(): WgTunnel | null {
    if (this.selectedId.length === 0) {
      return null;
    }
    return TunnelStore.find(this.selectedId);
  }

  // ---------------------------------------------------------------- builders

  @Builder
  statusPill() {
    Row({ space: 6 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(this.activeId.length === 0 ? '#5A6B7D' :
          (this.engineState === 'up' ? '#38E8A0' :
            (this.engineState === 'offline' ? '#5A6B7D' : '#F0B45A')))
      Text(this.activeId.length === 0 ? Tr.t('Disconnected') :
        (this.engineState === 'up' ? Tr.t('Connected') :
          (this.engineState === 'offline' ? Tr.t('No network') : Tr.t('Connecting…'))))
        .fontSize(13)
        .fontColor('#8FA3B8')
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor('#16212F')
    .borderRadius(20)
  }

  @Builder
  toastBar() {
    if (this.toast.length > 0) {
      Row() {
        Text(this.toast).fontSize(13).fontColor('#0E1621')
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor('#38E8A0')
      .borderRadius(20)
      .margin({ bottom: 12 })
    }
  }

  @Builder
  errorBar() {
    if (this.lastError.length > 0) {
      Row() {
        Text(this.lastError).fontSize(12).fontColor('#FFB4A8').layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .margin({ bottom: 10 })
      .backgroundColor('#2A1B1B')
      .borderRadius(12)
    }
  }

  @Builder
  deleteAction(tunnel: WgTunnel) {
    Button(Tr.t('Delete'))
      .fontSize(14)
      .fontColor('#FF6B6B')
      .backgroundColor('#2A1B1B')
      .height('100%')
      .width(88)
      .onClick(() => this.deleteTunnel(tunnel))
  }

  @Builder
  tunnelCard(tunnel: WgTunnel, active: boolean, selected: boolean) {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text(tunnel.name.length > 0 ? tunnel.name : Tr.t('Unnamed tunnel'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#EAF2FB')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(tunnel.endpoint() + (tunnel.awg ? '  ·  AmneziaWG' : ''))
            .fontSize(12)
            .fontColor('#8FA3B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: active })
          .selectedColor('#38E8A0')
          .switchPointColor('#0E1621')
          .onChange((isOn: boolean) => {
            if (isOn !== active) {
              this.toggle(tunnel, isOn);
            }
          })
      }
      .width('100%')

      if (active) {
        Row({ space: 14 }) {
          Text(`↓ ${this.rxText}   ↑ ${this.txText}`).fontSize(12).fontColor('#38E8A0')
          Text(this.handshakeText).fontSize(12).fontColor('#8FA3B8')
        }
        .width('100%')
      } else {
        Text(tunnel.address + '  ·  ' + tunnel.allowedIPs())
          .fontSize(12)
          .fontColor('#5A6B7D')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16212F')
    .borderRadius(16)
    .border({
      width: selected ? 2 : 1,
      color: selected ? '#38E8A0' : (active ? '#2C5A47' : '#1E2C3D')
    })
    .onClick(() => {
      this.selectedId = tunnel.id;
      this.paneEditor = false;
      if (!this.isWide) {
        this.openDetail(tunnel);
      }
    })
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      Text(Tr.t('No tunnels yet')).fontSize(16).fontColor('#EAF2FB')
      Text(Tr.t('Import a wg-quick configuration to get started.'))
        .fontSize(13)
        .fontColor('#8FA3B8')
        .textAlign(TextAlign.Center)
      Row({ space: 10 }) {
        Button(Tr.t('Scan QR'))
          .fontSize(13)
          .fontColor('#0E1621')
          .backgroundColor('#38E8A0')
          .height(38)
          .layoutWeight(1)
          .onClick(() => this.openScanner())
        Button(Tr.t('From file'))
          .fontSize(13)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(38)
          .layoutWeight(1)
          .onClick(() => this.importFromFile())
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      Row({ space: 10 }) {
        Button(Tr.t('From clipboard'))
          .fontSize(13)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(38)
          .layoutWeight(1)
          .onClick(() => this.importFromClipboard())
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
  }

  @Builder
  listPane() {
    Column() {
      this.errorBar()
      List({ space: 12 }) {
        if (this.tunnels.length === 0) {
          ListItem() {
            this.emptyState()
          }
        }
        ForEach(this.tunnels, (tunnel: WgTunnel) => {
          ListItem() {
            this.tunnelCard(tunnel, tunnel.id === this.activeId, tunnel.id === this.selectedId)
          }
          .swipeAction({ end: { builder: () => { this.deleteAction(tunnel) } } })
        }, (tunnel: WgTunnel) => `${tunnel.id}-${this.toggleEpoch}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        Button(Tr.t('New tunnel'))
          .fontSize(15)
          .fontColor('#0E1621')
          .backgroundColor('#38E8A0')
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.openNew())
        Button(Tr.t('Scan'))
          .fontSize(14)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(46)
          .width(72)
          .onClick(() => this.openScanner())
        Button(Tr.t('Logs'))
          .fontSize(14)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(46)
          .width(72)
          .onClick(() => this.openLogs())
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('36%')
    .height('100%')
  }

  @Builder
  statTile(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(18).fontColor('#EAF2FB').fontWeight(FontWeight.Medium)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label).fontSize(11).fontColor('#8FA3B8')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#16212F')
    .borderRadius(14)
    .layoutWeight(1)
  }

  @Builder
  detailRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontColor('#8FA3B8').width(110)
      Text(value)
        .fontSize(12)
        .fontColor('#EAF2FB')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  @Builder
  peerCard(peer: WgPeer, index: number) {
    Column({ space: 8 }) {
      Row() {
        Text(`Peer ${index + 1}`).fontSize(13).fontColor('#8FA3B8').layoutWeight(1)
        if (this.editorPeers.length > 1) {
          Button(Tr.t('Remove'))
            .fontSize(12)
            .fontColor('#FF6B6B')
            .backgroundColor('#2A1B1B')
            .height(28)
            .onClick(() => this.removePeer(index))
        }
      }
      .width('100%')

      TextInput({ text: peer.publicKey, placeholder: Tr.t('Peer public key (base64)') })
        .placeholderColor('#5A6B7D')
        .fontColor('#EAF2FB')
        .backgroundColor('#101B27')
        .borderRadius(10)
        .fontSize(12)
        .onChange((value: string) => this.setPeer(index, 'publicKey', value))
      TextInput({ text: peer.presharedKey, placeholder: Tr.t('Preshared key (optional)') })
        .placeholderColor('#5A6B7D')
        .fontColor('#EAF2FB')
        .backgroundColor('#101B27')
        .borderRadius(10)
        .fontSize(12)
        .onChange((value: string) => this.setPeer(index, 'presharedKey', value))
      Row({ space: 8 }) {
        TextInput({ text: peer.host, placeholder: Tr.t('Endpoint host') })
          .placeholderColor('#5A6B7D')
          .fontColor('#EAF2FB')
          .backgroundColor('#101B27')
          .borderRadius(10)
          .fontSize(12)
          .layoutWeight(3)
          .onChange((value: string) => this.setPeer(index, 'host', value))
        TextInput({ text: peer.port.toString(), placeholder: Tr.t('Port') })
          .placeholderColor('#5A6B7D')
          .fontColor('#EAF2FB')
          .backgroundColor('#101B27')
          .borderRadius(10)
          .fontSize(12)
          .type(InputType.Number)
          .layoutWeight(2)
          .onChange((value: string) => this.setPeer(index, 'port', value))
      }
      .width('100%')
      TextInput({ text: peer.allowedIPs, placeholder: Tr.t('Allowed IPs (10.0.0.0/24, 0.0.0.0/0)') })
        .placeholderColor('#5A6B7D')
        .fontColor('#EAF2FB')
        .backgroundColor('#101B27')
        .borderRadius(10)
        .fontSize(12)
        .onChange((value: string) => this.setPeer(index, 'allowedIPs', value))
      TextInput({ text: peer.keepalive.toString(), placeholder: Tr.t('Persistent keepalive (seconds)') })
        .placeholderColor('#5A6B7D')
        .fontColor('#EAF2FB')
        .backgroundColor('#101B27')
        .borderRadius(10)
        .fontSize(12)
        .type(InputType.Number)
        .onChange((value: string) => this.setPeer(index, 'keepalive', value))
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16212F')
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tunnelDetail(tunnel: WgTunnel) {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text(tunnel.name.length > 0 ? tunnel.name : Tr.t('Unnamed tunnel'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#EAF2FB')
          Text(tunnel.endpoint()).fontSize(13).fontColor('#8FA3B8')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(tunnel.id === this.activeId ? Tr.t('Disconnect') : Tr.t('Connect'))
          .fontSize(14)
          .fontColor(tunnel.id === this.activeId ? '#FF6B6B' : '#0E1621')
          .backgroundColor(tunnel.id === this.activeId ? '#2A1B1B' : '#38E8A0')
          .height(40)
          .onClick(() => this.toggle(tunnel, tunnel.id !== this.activeId))
      }
      .width('100%')

      Row({ space: 10 }) {
        this.statTile(Tr.t('received'), this.rxText)
        this.statTile(Tr.t('sent'), this.txText)
        this.statTile(Tr.t('handshake'), this.handshakeText)
      }
      .width('100%')

      Row({ space: 10 }) {
        this.statTile(Tr.t('peers up'), `${this.peersUp} / ${tunnel.peers.length}`)
        this.statTile(Tr.t('packets in / out'), this.packetText)
      }
      .width('100%')

      Column({ space: 10 }) {
        this.detailRow(Tr.t('Interface'), tunnel.address)
        this.detailRow(Tr.t('DNS'), tunnel.dns.length > 0 ? tunnel.dns : '—')
        this.detailRow(Tr.t('Allowed IPs'), tunnel.allowedIPs())
        this.detailRow(Tr.t('MTU'), `${tunnel.mtu}`)
        this.detailRow(Tr.t('Excluded apps'), tunnel.excludedApps.length > 0 ? tunnel.excludedApps : '—')
        this.detailRow(Tr.t('Private key'), maskKey(tunnel.privateKey))
        if (tunnel.awg) {
          this.detailRow('AmneziaWG',
            `Jc ${tunnel.jc} · ${tunnel.jmin}-${tunnel.jmax} · S1 ${tunnel.s1} · S2 ${tunnel.s2}`)
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#16212F')
      .borderRadius(16)

      Text(`${Tr.t('Peers')} (${tunnel.peers.length})`).fontSize(12).fontColor('#8FA3B8')
      ForEach(tunnel.peers, (peer: WgPeer, index: number) => {
        Column({ space: 6 }) {
          Row() {
            Text(peer.endpoint().length > 0 ? peer.endpoint() : Tr.t('no endpoint'))
              .fontSize(14)
              .fontColor('#EAF2FB')
              .layoutWeight(1)
            // `keepalive` is the WireGuard field name and is left as it is, the
            // same way the Tunnel globals sheet shows it.
            Text(peer.keepalive > 0 ? `keepalive ${peer.keepalive}s` : Tr.t('no keepalive'))
              .fontSize(11)
              .fontColor('#8FA3B8')
          }
          .width('100%')
          Text(peer.allowedIPs).fontSize(11).fontColor('#8FA3B8').width('100%')
          Text(maskKey(peer.publicKey)).fontSize(11).fontColor('#5A6B7D').width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#16212F')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)
      }, (peer: WgPeer, index: number) => `${peer.publicKey}-${index}`)

      Row({ space: 10 }) {
        Button(Tr.t('Show QR'))
          .fontSize(14)
          .fontColor('#0E1621')
          .backgroundColor('#38E8A0')
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.openQr(tunnel))
        Button(Tr.t('Copy config'))
          .fontSize(14)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.copyConfig(tunnel))
      }
      .width('100%')

      Row({ space: 10 }) {
        Button(Tr.t('Edit'))
          .fontSize(14)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.openEdit(tunnel))
        Button(Tr.t('Delete'))
          .fontSize(14)
          .fontColor('#FF6B6B')
          .backgroundColor('#2A1B1B')
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.deleteTunnel(tunnel))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  editorPanel(inline: boolean) {
    Scroll() {
      Column({ space: 14 }) {
        Text(this.editorTitle).fontSize(20).fontWeight(FontWeight.Medium).fontColor('#EAF2FB')

        Row({ space: 8 }) {
          Button(Tr.t('Form'))
            .fontSize(13)
            .fontColor(!this.editorRaw ? '#0E1621' : '#8FA3B8')
            .backgroundColor(!this.editorRaw ? '#38E8A0' : '#16212F')
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              if (this.editorRaw) {
                this.syncFormFromText();
              }
            })
          Button(Tr.t('Paste config'))
            .fontSize(13)
            .fontColor(this.editorRaw ? '#0E1621' : '#8FA3B8')
            .backgroundColor(this.editorRaw ? '#38E8A0' : '#16212F')
            .height(34)
            .layoutWeight(1)
            .onClick(() => {
              if (!this.editorRaw) {
                this.syncTextFromForm();
                this.editorRaw = true;
              }
            })
        }
        .width('100%')

        if (this.editorHint.length > 0) {
          Text(this.editorHint)
            .fontSize(11)
            .fontColor('#FFB86B')
            .width('100%')
            .padding(10)
            .backgroundColor('#2A2118')
            .borderRadius(10)
        }

        TextInput({ text: this.editorName, placeholder: Tr.t('Tunnel name') })
          .placeholderColor('#5A6B7D')
          .fontColor('#EAF2FB')
          .backgroundColor('#16212F')
          .borderRadius(12)
          .onChange((value: string) => {
            this.editorName = value;
          })

        if (this.editorRaw) {
          Button(Tr.t('Import from clipboard'))
            .fontSize(13)
            .fontColor('#EAF2FB')
            .backgroundColor('#1E2C3D')
            .height(36)
            .width('100%')
            .onClick(() => this.importFromClipboard())
          TextArea({
            text: this.editorText,
            placeholder: '[Interface]\nPrivateKey = ...\nAddress = 10.66.0.2/32\n\n[Peer]\nPublicKey = ...\nEndpoint = host:51820\nAllowedIPs = 0.0.0.0/0'
          })
            .placeholderColor('#5A6B7D')
            .fontColor('#EAF2FB')
            .backgroundColor('#16212F')
            .borderRadius(12)
            .fontSize(13)
            .height(inline ? 320 : 260)
            .onChange((value: string) => {
              this.editorText = value;
            })
        } else {
          Text(Tr.t('Interface')).fontSize(12).fontColor('#8FA3B8').width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.editorAddress, placeholder: Tr.t('Address 10.66.0.2/32') })
              .placeholderColor('#5A6B7D')
              .fontColor('#EAF2FB')
              .backgroundColor('#16212F')
              .borderRadius(12)
              .fontSize(13)
              .layoutWeight(3)
              .onChange((value: string) => {
                this.editorAddress = value;
              })
            TextInput({ text: this.editorMtu, placeholder: Tr.t('MTU') })
              .placeholderColor('#5A6B7D')
              .fontColor('#EAF2FB')
              .backgroundColor('#16212F')
              .borderRadius(12)
              .fontSize(13)
              .type(InputType.Number)
              .layoutWeight(2)
              .onChange((value: string) => {
                this.editorMtu = value;
              })
          }
          .width('100%')
          TextInput({ text: this.editorDns, placeholder: Tr.t('DNS 1.1.1.1') })
            .placeholderColor('#5A6B7D')
            .fontColor('#EAF2FB')
            .backgroundColor('#16212F')
            .borderRadius(12)
            .fontSize(13)
            .onChange((value: string) => {
              this.editorDns = value;
            })
          TextInput({ text: this.editorPrivateKey, placeholder: Tr.t('Private key (base64)') })
            .placeholderColor('#5A6B7D')
            .fontColor('#EAF2FB')
            .backgroundColor('#16212F')
            .borderRadius(12)
            .fontSize(13)
            .onChange((value: string) => {
              this.editorPrivateKey = value;
            })
          Row({ space: 8 }) {
            Button(Tr.t('Generate keys'))
              .fontSize(13)
              .fontColor('#EAF2FB')
              .backgroundColor('#1E2C3D')
              .height(36)
              .layoutWeight(1)
              .onClick(() => this.newKeyPair())
            if (this.editorPublicKey.length > 0) {
              Text(`Public ${maskKey(this.editorPublicKey)}`)
                .fontSize(11)
                .fontColor('#5A6B7D')
                .layoutWeight(1)
            }
          }
          .width('100%')

          Text(`Peers (${this.editorPeers.length})`).fontSize(12).fontColor('#8FA3B8').width('100%')
          ForEach(this.editorPeers, (peer: WgPeer, index: number) => {
            this.peerCard(peer, index)
          }, (peer: WgPeer, index: number) => `${index}-${peer.publicKey.length}`)
          Button(Tr.t('Add peer'))
            .fontSize(13)
            .fontColor('#EAF2FB')
            .backgroundColor('#1E2C3D')
            .height(36)
            .width('100%')
            .onClick(() => this.addPeer())

          TextInput({ text: this.editorExcluded, placeholder: Tr.t('Excluded apps (bundle names, comma separated)') })
            .placeholderColor('#5A6B7D')
            .fontColor('#EAF2FB')
            .backgroundColor('#16212F')
            .borderRadius(12)
            .fontSize(13)
            .onChange((value: string) => {
              this.editorExcluded = value;
            })

          Row() {
            Text('AmneziaWG').fontSize(14).fontColor('#EAF2FB').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.editorAwg })
              .selectedColor('#38E8A0')
              .onChange((on: boolean) => {
                this.editorAwg = on;
              })
          }
          .width('100%')

          if (this.editorAwg) {
            Row({ space: 8 }) {
              TextInput({ text: this.editorJc, placeholder: Tr.t('Jc') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorJc = value;
                })
              TextInput({ text: this.editorJmin, placeholder: Tr.t('Jmin') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorJmin = value;
                })
              TextInput({ text: this.editorJmax, placeholder: Tr.t('Jmax') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorJmax = value;
                })
            }
            .width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.editorS1, placeholder: Tr.t('S1') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorS1 = value;
                })
              TextInput({ text: this.editorS2, placeholder: Tr.t('S2') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorS2 = value;
                })
              TextInput({ text: this.editorS3, placeholder: Tr.t('S3') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorS3 = value;
                })
            }
            .width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.editorH1, placeholder: Tr.t('H1') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorH1 = value;
                })
              TextInput({ text: this.editorH2, placeholder: Tr.t('H2') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorH2 = value;
                })
              TextInput({ text: this.editorH3, placeholder: Tr.t('H3') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorH3 = value;
                })
              TextInput({ text: this.editorH4, placeholder: Tr.t('H4') })
                .placeholderColor('#5A6B7D').fontColor('#EAF2FB').backgroundColor('#16212F')
                .borderRadius(12).fontSize(12).type(InputType.Number).layoutWeight(1)
                .onChange((value: string) => {
                  this.editorH4 = value;
                })
            }
            .width('100%')
          }
        }

        Row({ space: 10 }) {
          Button(Tr.t('Save'))
            .fontSize(14)
            .fontColor('#0E1621')
            .backgroundColor('#38E8A0')
            .height(42)
            .layoutWeight(1)
            .onClick(() => this.saveEditor())
          if (inline) {
            Button(Tr.t('Cancel'))
              .fontSize(13)
              .fontColor('#8FA3B8')
              .backgroundColor('#16212F')
              .height(42)
              .layoutWeight(1)
              .onClick(() => this.closeEditor())
          }
        }
        .width('100%')

        if (this.editorId.length > 0) {
          Button(Tr.t('Delete tunnel'))
            .fontSize(14)
            .fontColor('#FF6B6B')
            .backgroundColor('#2A1B1B')
            .height(42)
            .width('100%')
            .onClick(() => {
              const tunnel = TunnelStore.find(this.editorId);
              if (tunnel !== null) {
                this.deleteTunnel(tunnel);
              }
              this.closeEditor();
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: inline ? 0 : 20,
        right: inline ? 0 : 20,
        top: inline ? 0 : 28,
        bottom: inline ? 0 : 24
      })
    }
    .scrollBar(BarState.Off)
    .height(inline ? '100%' : '90%')
  }

  @Builder
  detailPane() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.paneEditor) {
          this.editorPanel(true)
        } else if (this.selectedTunnel() !== null) {
          this.tunnelDetail(this.selectedTunnel() as WgTunnel)
        } else {
          Column({ space: 10 }) {
            Text(Tr.t('Nothing selected')).fontSize(16).fontColor('#EAF2FB')
            Text(Tr.t('Pick a tunnel on the left, or create a new one.'))
              .fontSize(13)
              .fontColor('#8FA3B8')
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 40 })
        }
      }
      .padding({ top: 4, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
    .height('100%')
    .padding({ left: 20 })
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('WGate')
          .fontSize(this.isWide ? 28 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#EAF2FB')
          .maxLines(1)
        if (this.isMedium) {
          Text(Tr.t('WireGuard & AmneziaWG for HarmonyOS'))
            .fontSize(12)
            .fontColor('#8FA3B8')
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      this.statusPill()
      if (this.isMedium) {
        Button(Tr.t('Scan'))
          .fontSize(12)
          .fontColor('#8FA3B8')
          .backgroundColor('#16212F')
          .height(32)
          .margin({ right: 8 })
          .onClick(() => this.openScanner())
        Button(Tr.t('Logs'))
          .fontSize(12)
          .fontColor('#8FA3B8')
          .backgroundColor('#16212F')
          .height(32)
          .onClick(() => this.openLogs())
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 8 })
  }

  @Builder
  logsPanel() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(Tr.t('Engine log')).fontSize(20).fontWeight(FontWeight.Medium).fontColor('#EAF2FB')
          .layoutWeight(1)
        Button(this.probeBusy ? Tr.t('Checking…') : Tr.t('Check endpoint'))
          .fontSize(12)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(32)
          .enabled(!this.probeBusy)
          .onClick(() => {
            this.checkEndpoint();
          })
        Button(Tr.t('Refresh'))
          .fontSize(12)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(32)
          .onClick(() => this.refreshLogs())
      }
      .width('100%')

      if (this.probeText.length > 0) {
        Text(this.probeText)
          .fontSize(12)
          .fontColor('#38E8A0')
          .width('100%')
          .padding(10)
          .backgroundColor('#10202A')
          .borderRadius(10)
      }

      Text(Tr.t('Handshake, keepalive, socket and error events recorded by the native core.'))
        .fontSize(12)
        .fontColor('#8FA3B8')
        .width('100%')

      if (this.diagText.length > 0) {
        Row() {
          Text(Tr.t('VPN startup trace')).fontSize(12).fontColor('#8FA3B8').layoutWeight(1)
          Button(Tr.t('Clear'))
            .fontSize(11)
            .fontColor('#8FA3B8')
            .backgroundColor('#16222F')
            .height(26)
            .onClick(() => {
              Diag.clear();
              this.diagText = '';
            })
        }
        .width('100%')

        Scroll() {
          Text(this.diagText)
            .fontSize(11)
            .fontColor('#C7D6E6')
            .fontFamily('monospace')
            .textAlign(TextAlign.Start)
            .width('100%')
        }
        .width('100%')
        .height(140)
        .align(Alignment.TopStart)
        .padding(10)
        .backgroundColor('#0B131C')
        .borderRadius(10)
        .scrollBar(BarState.Auto)
      }

      Scroll() {
        Text(this.logsText.length > 0 ? this.logsText : 'no log lines yet')
          .fontSize(11)
          .fontColor('#C7D6E6')
          .fontFamily('monospace')
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .padding(12)
      .backgroundColor('#0B131C')
      .borderRadius(12)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  /** One sheet host: its content depends on why it was opened. */
  @Builder
  sheetContent() {
    if (this.sheetKind === SHEET_LOGS) {
      this.logsPanel()
    } else if (this.sheetKind === SHEET_DETAIL) {
      this.detailSheet()
    } else if (this.sheetKind === SHEET_QR) {
      this.qrPanel()
    } else {
      this.editorPanel(false)
    }
  }

  @Builder
  qrPanel() {
    Column({ space: 14 }) {
      Row() {
        Text(Tr.t('Scan to import'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#8FA3B8')
          .layoutWeight(1)
      }
      .width('100%')

      Text(this.qrName)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#EAF2FB')
        .width('100%')

      if (this.qrText.length <= QR_MAX_CHARS) {
        Row() {
          QRCode(this.qrText)
            .width(260)
            .height(260)
            .color('#000000')
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
        }
        .padding(10)
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
      } else {
        Column({ space: 8 }) {
          Text(Tr.t('Too long for one code'))
            .fontSize(14)
            .fontColor('#FFB86B')
          Text(`This configuration needs ${this.qrText.length} characters and a single code holds ` +
            `${QR_MAX_CHARS}. Use Copy config and send the text instead.`)
            .fontSize(12)
            .fontColor('#8FA3B8')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#1A222E')
        .borderRadius(12)
      }

      Text(Tr.t('On the other device open WGate → Scan a tunnel and point the camera here. ') +
        Tr.t('The code holds the whole configuration, keys included, so only scan it with a peer you trust.'))
        .fontSize(12)
        .fontColor('#8FA3B8')
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20, bottom: 24 })
  }

  @Builder
  detailSheet() {
    Column({ space: 12 }) {
      Row() {
        Text(Tr.t('Tunnel details'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#8FA3B8')
          .layoutWeight(1)
      }
      .width('100%')

      Scroll() {
        Column() {
          if (this.selectedTunnel() !== null) {
            this.tunnelDetail(this.selectedTunnel() as WgTunnel)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  narrowBody() {
    Column() {
      this.errorBar()
      List({ space: 12 }) {
        if (this.tunnels.length === 0) {
          ListItem() {
            this.emptyState()
          }
        }
        ForEach(this.tunnels, (tunnel: WgTunnel) => {
          ListItem() {
            this.tunnelCard(tunnel, tunnel.id === this.activeId, tunnel.id === this.selectedId)
          }
          .swipeAction({ end: { builder: () => { this.deleteAction(tunnel) } } })
        }, (tunnel: WgTunnel) => `${tunnel.id}-${this.toggleEpoch}`)
      }
      .width('100%')
      .layoutWeight(1)
      .lanes(this.isMedium ? 2 : 1, 12)
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        Button(Tr.t('New tunnel'))
          .fontSize(15)
          .fontColor('#0E1621')
          .backgroundColor('#38E8A0')
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.openNew())
        Button(Tr.t('Scan'))
          .fontSize(14)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(46)
          .width(72)
          .onClick(() => this.openScanner())
        Button(Tr.t('Logs'))
          .fontSize(14)
          .fontColor('#EAF2FB')
          .backgroundColor('#1E2C3D')
          .height(46)
          .width(72)
          .onClick(() => this.openLogs())
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 20 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.header()
        if (this.isWide) {
          Row() {
            this.listPane()
            Divider()
              .vertical(true)
              .color('#1E2C3D')
              .margin({ left: 16, right: 4 })
            this.detailPane()
          }
          .layoutWeight(1)
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: 20, right: 20, bottom: 16 })
        } else {
          this.narrowBody()
        }
      }
      .width('100%')
      .height('100%')

      this.toastBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0E1621')
    .bindSheet($$this.sheetOpen, this.sheetContent(), {
      height: SheetSize.MEDIUM,
      backgroundColor: '#101B27',
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('index'),
      onDisappear: () => {
        this.sheetKind = SHEET_NONE;
      }
    })
    .padding({ top: this.safeTop })
  }
}
