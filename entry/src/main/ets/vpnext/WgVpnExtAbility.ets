/**
 * VPN extension: turns the stored tunnel into an actual VpnConnection, hands
 * the tun fd to the native engine and keeps the engine's UDP socket pinned to
 * the physical network.
 *
 * Lifecycle: ArkTS UI calls vpnExtension.startVpnExtensionAbility(want) with the
 * tunnel JSON in want.parameters; the system shows the consent dialog on first
 * use and then calls onCreate() here. Stopping the extension destroys the tun
 * device, which is why the engine is stopped first.
 */
import { vpnExtension, VpnExtensionAbility, connection } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import wgcore from 'libwgcore.so';
import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { Diag } from '../util/Diag';
import { BridgeStatus, StatusBridge } from '../util/StatusBridge';
import { TunnelNotice, TunnelNoticeText } from '../service/TunnelNotice';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';
import { offeredLocale } from '../i18n/Locales';

const DOMAIN: number = 0x0001;
const TAG: string = 'WgVpnExt';
const TUN_INTERFACE: string = 'vpn-tun';
/** How long an established tunnel may go without a handshake before it is noted. */
const NO_HANDSHAKE_MS: number = 20000;
/**
 * How long the engine may sit in connecting/retry with no new handshake before
 * the extension asks it to try again. The engine itself gives up after eighteen
 * attempts and then retries once every thirty seconds, which is the right pace
 * for a peer that is simply down but leaves a tunnel that never comes back after
 * a network change: the socket is open, the send path works, the attempts just
 * keep failing.
 */
const STUCK_MS: number = 90000;
/** Minimum spacing between those nudges, so a dead peer is not hammered. */
const NUDGE_MS: number = 60000;

interface ParsedAddress {
  address: string;
  prefix: number;
  family: number;
}

interface EngineStatusWire {
  state: string;
  udpFd: number;
  socketGen: number;
  handshakes: number;
  rxBytes: number;
  txBytes: number;
  rxPackets: number;
  txPackets: number;
  peersUp: number;
  handshakeMs: number;
}

export default class WgVpnExtAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunnel: WgTunnel | null = null;
  private protectedFd: number = -1;
  private watchdog: number = -1;
  private net: connection.NetConnection | null = null;
  private lastWant: Want | null = null;
  private retriedCreate: boolean = false;
  private startedAt: number = 0;
  private handshakeSeen: boolean = false;
  private handshakeWarned: boolean = false;
  private engineLogSeen: number = 0;
  /** Monotonic handshake stamp last seen, plus when it was seen on the wall clock. */
  private lastHandshakeRaw: number = 0;
  private lastHandshakeAt: number = 0;
  /** Handshake counter last seen, and since when the engine has made no progress. */
  private lastHandshakes: number = 0;
  private stuckSince: number = 0;
  private lastNudgeAt: number = 0;
  /** Whether the "no network" state has been written to the trace already. */
  private offlineNoted: boolean = false;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    TunnelStore.init(this.context);
    Diag.init(this.context);
    /*
     * Preferences are per process: this one never opened `wg_settings`, so every
     * read here returned its fallback -- the language ('system' -> English) and
     * all five notification switches (always their defaults). Opening the store
     * before anything is composed is what makes both of them real.
     */
    SettingsStore.init(this.context);
    /*
     * The ongoing notification is written by this process, so the language has
     * to be resolved here too: `Tr` starts in English and only the UI pages ever
     * called setLocale, which is why a Chinese phone showed "Connected / via
     * Cellular" until this line existed.
     */
    Tr.setLocale(offeredLocale(SettingsStore.language()));
    Diag.write('extension onCreate');
    // React to a network handover immediately instead of waiting for the next
    // watchdog tick; see watchNetwork().
    this.watchNetwork();
    try {
      this.connect(this.wantWithDesiredTunnel(want));
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, `connect failed: ${e.code} ${e.message}`);
      Diag.write(`connect threw: ${e.code} ${e.message}`);
      TunnelStore.setLastError(`VPN startup failed (${e.code}): ${e.message}`);
      this.shutdown();
    }
  }

  /**
   * The tunnel to start, falling back to the one the user last asked for.
   *
   * A start request normally carries the whole configuration, but a process the
   * system starts again on its own can arrive without parameters. The desired id
   * is the durable record of what the user wanted — it survives the app process
   * being frozen or killed, which the want does not — so a request that says
   * nothing about a tunnel is filled in from it. When nothing was wanted either,
   * the caller's own error is left to stand.
   */
  private wantWithDesiredTunnel(want: Want): Want {
    if (this.tunnelFromWant(want) !== null) {
      return want;
    }
    const wanted: string = TunnelStore.desiredId();
    if (wanted.length === 0) {
      return want;
    }
    const tunnel: WgTunnel | null = TunnelStore.find(wanted);
    if (tunnel === null) {
      return want;
    }
    Diag.write(`extension onCreate had no tunnel, restoring ${tunnel.name} from the desired state`);
    const filled: Want = { parameters: { 'tunnel': JSON.stringify(tunnel) } };
    return filled;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    Diag.write('extension onDestroy (the system tore the VPN down)');
    this.shutdown();
  }

  /** Copies whatever the native ring buffer gained since the last tick. */
  private drainEngineLog(): void {
    try {
      const text: string = wgcore.logs() as string;
      if (text.length <= this.engineLogSeen) {
        return;
      }
      const fresh: string = text.substring(this.engineLogSeen);
      this.engineLogSeen = text.length;
      const lines: string[] = fresh.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const line: string = lines[i].trim();
        if (line.length > 0) {
          Diag.write('engine: ' + line);
        }
      }
    } catch (err) {
      // logging must never be the reason the tunnel fails
    }
  }

  private startWatchdog(): void {
    if (this.watchdog >= 0) {
      return;
    }
    this.startedAt = Date.now();
    this.watchdog = setInterval(() => {
      this.tick();
    }, 2000);
  }

  /**
   * One watchdog pass: re-protect the socket, publish the snapshot for the UI,
   * mirror new engine lines, note a tunnel that never handshakes, and revive a
   * tunnel that has stopped making progress.
   */
  private tick(): void {
    if (this.vpnConnection === null) {
      return;
    }
    try {
      const raw: string = wgcore.status() as string;
      const status = JSON.parse(raw) as EngineStatusWire;
      /*
       * The engine calls itself up while the newest session is younger than
       * REJECT_AFTER (180 s), which is the right rule for WireGuard but a
       * misleading word for a user: with the radio off the session is still
       * "valid" for three minutes while nothing can leave the device. The
       * published state is the one the screens and the shade read, so it says
       * "offline" for exactly as long as the system reports no usable network.
       */
      const offline: boolean = !this.hasNetwork();
      if (offline && status.state !== 'offline' && status.state !== 'stopped') {
        status.state = 'offline';
        if (!this.offlineNoted) {
          this.offlineNoted = true;
          Diag.write('vpn extension: no network, the tunnel is waiting for one');
        }
      } else if (!offline && this.offlineNoted) {
        this.offlineNoted = false;
        Diag.write(`vpn extension: the network is back (state ${status.state})`);
      }
      // A new socket after a handover has to be protected again.
      this.protectTransportSocket();
      // The UI cannot read this process' engine, so publish a snapshot it can.
      this.publishStatus(status);
      // The engine's own ring buffer lives in this process, so the UI cannot
      // read it; mirror new lines into the trace while we are up.
      this.drainEngineLog();
      // The app process is frozen in the background, so recovery for a tunnel
      // that stopped making progress has to happen here.
      this.nudgeIfStuck(status);
      // A tunnel that stays up but never handshakes is the other half of the
      // "it does not work" reports: keep that fact in the trace as well.
      if (!this.handshakeSeen && status.handshakes > 0) {
        this.handshakeSeen = true;
        Diag.write(`handshake completed after ${Date.now() - this.startedAt} ms`);
      } else if (!this.handshakeSeen && !this.handshakeWarned &&
                 Date.now() - this.startedAt > NO_HANDSHAKE_MS) {
        this.handshakeWarned = true;
        Diag.write(`still no handshake after ${NO_HANDSHAKE_MS} ms (state ${status.state})`);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'status read failed');
    }
  }

  /**
   * Asks the engine for an immediate handshake when the tunnel has been stuck.
   *
   * This is the one recovery step the platform lets a third-party VPN take on
   * its own: the extension process is kept alive by the system while the tun
   * device exists (`wg_engine_force_handshake` skips the engine's retry
   * backoff), whereas the app process — which owns the guard in
   * service/TunnelGuard.ets — is frozen a few minutes into the background and
   * cannot help. A tunnel that is up is left alone, because the engine already
   * rekeys it on its own schedule.
   */
  private nudgeIfStuck(status: EngineStatusWire): void {
    if (status.state === 'up' || status.state === 'idle' || status.state === 'stopped') {
      this.stuckSince = 0;
      return;
    }
    const now: number = Date.now();
    if (status.handshakes !== this.lastHandshakes) {
      this.lastHandshakes = status.handshakes;
      this.stuckSince = 0;
      return;
    }
    if (this.stuckSince === 0) {
      this.stuckSince = now;
      return;
    }
    if (now - this.stuckSince < STUCK_MS || now - this.lastNudgeAt < NUDGE_MS) {
      return;
    }
    this.lastNudgeAt = now;
    Diag.write(`vpn extension: no handshake for ${Math.round((now - this.stuckSince) / 1000)}s ` +
      `(state ${status.state}), asking the engine to try again`);
    wgcore.forceHandshake();
  }

  /**
   * Re-protects the socket the moment the underlying network changes.
   *
   * The two-second watchdog already does this, but it runs on a timer: after a
   * Wi-Fi to mobile handover the engine opens a new UDP socket, and until that
   * socket is protected its datagrams are routed back into our own tun device.
   * The network callbacks make the reaction immediate instead of up to two
   * seconds late, which is the difference between a stutter and a dead tunnel.
   */
  private watchNetwork(): void {
    if (this.net !== null) {
      return;
    }
    try {
      const net: connection.NetConnection = connection.createNetConnection();
      net.register((err: Error) => {
        if (err) {
          Diag.write(`vpn extension: could not watch the network: ${err.message}`);
          return;
        }
        Diag.write('vpn extension: watching the network');
      });
      net.on('netAvailable', () => {
        Diag.write('vpn extension: network available, re-protecting');
        this.tick();
      });
      net.on('netLost', () => {
        this.tick();
      });
      net.on('netCapabilitiesChange', () => {
        this.tick();
      });
      this.net = net;
    } catch (e) {
      Diag.write(`vpn extension: the network watcher failed: ${(e as Error).message}`);
    }
  }

  private unwatchNetwork(): void {
    const net: connection.NetConnection | null = this.net;
    if (net === null) {
      return;
    }
    this.net = null;
    try {
      net.unregister((err: Error) => {
        if (err) {
          Diag.write(`vpn extension: unregister failed: ${err.message}`);
        }
      });
    } catch (e) {
      // tearing down must never throw
    }
  }

  /**
   * Mirrors the engine snapshot into the sandbox for the UI process, which owns
   * no engine of its own, and publishes the ongoing notification from this
   * process — the only one of the two the system still schedules while the
   * screen is off. Written on every watchdog tick.
   */
  private publishStatus(status: EngineStatusWire): void {
    const tunnel = this.tunnel;
    if (tunnel === null) {
      return;
    }
    // The engine reports the monotonic clock reading of the last handshake, which
    // the UI cannot compare with Date.now(); publish an age instead.
    if (status.handshakeMs !== this.lastHandshakeRaw) {
      this.lastHandshakeRaw = status.handshakeMs;
      this.lastHandshakeAt = status.handshakeMs > 0 ? Date.now() : 0;
    }
    const age: number = this.lastHandshakeAt === 0 ? 0 : Date.now() - this.lastHandshakeAt;
    const snapshot: BridgeStatus = {
      id: tunnel.id,
      state: status.state,
      rxBytes: status.rxBytes,
      txBytes: status.txBytes,
      rxPackets: status.rxPackets,
      txPackets: status.txPackets,
      peersUp: status.peersUp,
      peerCount: tunnel.peers.length,
      handshakeAgeMs: age,
      udpFd: status.udpFd,
      updated: Date.now(),
      session: this.startedAt,
      notified: false
    };
    const notice: TunnelNoticeText | null = TunnelNotice.compose(snapshot, tunnel);
    snapshot.notified = notice !== null;
    StatusBridge.publish(snapshot);
    TunnelNotice.show(notice);
  }

  /**
   * True while the device has a usable physical network.
   *
   * Mirrors `AutoTunnel.hasNetwork()`: only Wi-Fi, cellular and Ethernet count,
   * because the tun device itself is a bearer this probe would otherwise see.
   * A probe that throws says nothing about connectivity, so it answers "yes" and
   * the engine's own state stands.
   */
  private hasNetwork(): boolean {
    let nets: connection.NetHandle[] = [];
    try {
      nets = connection.getAllNetsSync();
    } catch (e) {
      // A probe that throws says nothing about the link; the engine's own state
      // stands rather than being overridden on a guess.
      return true;
    }
    for (const net of nets) {
      try {
        const caps = connection.getNetCapabilitiesSync(net);
        const bearers: connection.NetBearType[] =
          caps.bearerTypes === undefined ? [] : caps.bearerTypes;
        for (const bearer of bearers) {
          if (bearer === connection.NetBearType.BEARER_WIFI ||
            bearer === connection.NetBearType.BEARER_CELLULAR ||
            bearer === connection.NetBearType.BEARER_ETHERNET) {
            return true;
          }
        }
      } catch (e) {
        // A net that disappeared between the two calls tells us nothing.
      }
    }
    return false;
  }

  /**
   * Asks the system to route the engine's UDP socket outside the tunnel. The fd
   * only becomes valid once the endpoint has resolved, so this is safe to call
   * repeatedly and from the watchdog.
   */
  private protectTransportSocket(): void {
    const conn = this.vpnConnection;
    if (conn === null) {
      return;
    }
    let fd: number = -1;
    try {
      const status = JSON.parse(wgcore.status() as string) as EngineStatusWire;
      fd = status.udpFd;
    } catch (err) {
      return;
    }
    if (fd <= 0 || fd === this.protectedFd) {
      // 0 is what the snapshot reports before the engine has a socket; fd 0 is
      // stdin, and protect() answers 2203004 for it.
      return;
    }
    const target: number = fd;
    conn.protect(target).then(() => {
      this.protectedFd = target;
      Diag.write(`protected the transport socket ${target}`);
      hilog.info(DOMAIN, TAG, `protected the transport socket ${target}`);
    }).catch((err: BusinessError) => {
      Diag.write(`protect failed for fd ${target}: ${err.code}`);
      hilog.warn(DOMAIN, TAG, `protect failed: ${err.code}`);
    });
  }

  private shutdown(): void {
    Diag.write('extension shut down');
    // The shade belongs to this process while the tunnel exists; take it down
    // with the tunnel instead of leaving a stale "Connected" behind.
    TunnelNotice.clear();
    if (this.watchdog >= 0) {
      clearInterval(this.watchdog);
      this.watchdog = -1;
    }
    this.unwatchNetwork();
    try {
      wgcore.stop();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'engine stop failed');
    }
    if (this.vpnConnection !== null) {
      const conn = this.vpnConnection;
      this.vpnConnection = null;
      conn.destroy().catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `destroy failed: ${err.code}`);
      });
    }
    if (this.tunnel !== null) {
      const going: string = this.tunnel.id;
      TunnelStore.setActive('');
      this.tunnel = null;
      StatusBridge.publish({
        id: going, state: 'stopped', rxBytes: 0, txBytes: 0, rxPackets: 0, txPackets: 0,
        peersUp: 0, peerCount: 0, handshakeAgeMs: 0, udpFd: -1, updated: Date.now(),
        session: 0, notified: false
      });
    }
  }

  /**
   * The tunnel to bring up.
   *
   * `want.parameters` is only delivered from API 22 onwards ("the parameters
   * field in want can be passed when the VPN is started for the first time"), so
   * on older devices the extension starts with an empty want. The UI records the
   * pending tunnel in the store before it starts us, which makes that path work
   * too — and it is the reason a tunnel still comes up if the system restores
   * the extension on its own.
   */
  private tunnelFromWant(want: Want): WgTunnel | null {
    const raw = want.parameters?.['tunnel'] as string;
    if (raw !== undefined && raw.length > 0) {
      hilog.info(DOMAIN, TAG, 'tunnel taken from the start request');
      return WgTunnel.from(raw);
    }
    const wanted: string = TunnelStore.desiredId();
    if (wanted.length > 0) {
      const stored: WgTunnel | null = TunnelStore.find(wanted);
      if (stored !== null) {
        hilog.info(DOMAIN, TAG, 'tunnel taken from the pending selection');
        return stored;
      }
    }
    const all: WgTunnel[] = TunnelStore.list();
    if (all.length > 0) {
      hilog.info(DOMAIN, TAG, 'tunnel taken from the first stored profile');
      return all[0];
    }
    return null;
  }

  private connect(want: Want): void {
    const resolved: WgTunnel | null = this.tunnelFromWant(want);
    if (resolved === null) {
      throw new Error('no tunnel configuration was passed to the extension');
    }
    const tunnel = resolved;
    this.tunnel = tunnel;
    this.lastWant = want;
    /*
     * The system hands the same extension instance a second tunnel without a
     * new onCreate, so the watchdog's bookkeeping belongs to the connection and
     * not to the process: a stale startedAt made the first tick of every
     * reconnect warn "still no handshake after 20000 ms" against an engine that
     * had opened a moment earlier, and a stale protectedFd could skip protecting
     * the new socket.
     */
    this.startedAt = Date.now();
    this.handshakeSeen = false;
    this.handshakeWarned = false;
    this.protectedFd = -1;
    this.lastHandshakes = 0;
    this.stuckSince = 0;
    this.lastNudgeAt = 0;
    this.offlineNoted = false;
    if (tunnel.peers.length === 0 || tunnel.privateKey.length === 0 || tunnel.peers[0].host.length === 0) {
      throw new Error('tunnel configuration is incomplete');
    }

    this.vpnConnection = vpnExtension.createVpnConnection(this.context);

    /*
     * Resolve the endpoint while DNS still leaves over the physical network.
     * Once create() has installed a default route, a name lookup from this
     * process is routed into the tun device, whose peer has no session yet, so
     * the engine's own getaddrinfo can never answer. The address replaces the
     * name only inside the JSON handed to the engine; the stored tunnel keeps
     * the name the user typed.
     */
    const firstPeer = tunnel.peers[0];
    const endpointName: string = firstPeer.host;
    const resolvedAddress: string = wgcore.resolve(endpointName) as string;
    let engineConfig: string = '';
    if (resolvedAddress.length > 0 && resolvedAddress !== endpointName) {
      Diag.write(`resolved ${endpointName} -> ${resolvedAddress} before the tunnel came up`);
      // resolve() brackets IPv6 for display; getaddrinfo wants the bare form.
      const literal: string = resolvedAddress.startsWith('[') && resolvedAddress.endsWith(']') ?
        resolvedAddress.substring(1, resolvedAddress.length - 1) : resolvedAddress;
      const keep: string = firstPeer.host;
      firstPeer.host = literal;
      engineConfig = tunnel.toJson();
      firstPeer.host = keep;
    } else {
      Diag.write(`endpoint ${endpointName} did not resolve before startup`);
      engineConfig = tunnel.toJson();
    }

    const addresses = this.parseAddresses(tunnel.address);
    const vpnConfig: vpnExtension.VpnConfig = {
      addresses: addresses.map((a: ParsedAddress) => {
        const link: vpnExtension.LinkAddress = {
          address: { address: a.address, family: a.family },
          prefixLength: a.prefix
        };
        return link;
      }),
      routes: this.parseRoutes(tunnel.allowedIPs(), addresses),
      dnsAddresses: tunnel.dns.length > 0 ? tunnel.dns.split(',').map((d: string) => d.trim()) : [],
      mtu: tunnel.mtu >= 576 && tunnel.mtu <= 1500 ? tunnel.mtu : 1420,
      isIPv4Accepted: true,
      isIPv6Accepted: tunnel.allowedIPs().indexOf(':') >= 0,
      isBlocking: false,
      isInternal: false
    };
    const excluded = tunnel.excludedApps.split(',').map((a: string) => a.trim()).filter((a: string) => a.length > 0);
    if (excluded.length > 0) {
      vpnConfig.blockedApplications = excluded;
    }

    this.vpnConnection.create(vpnConfig).then((tunFd: number) => {
      hilog.info(DOMAIN, TAG, `tun fd ${tunFd}`);
      Diag.write(`vpn created, tun fd ${tunFd}`);
      const opened: number = wgcore.open(engineConfig) as number;
      Diag.write(`engine open -> ${opened}`);
      if (opened < 0) {
        TunnelStore.setLastError(`could not open the tunnel socket (${opened})`);
        Diag.write(`tunnel socket failed, code ${opened}`);
        this.shutdown();
        return;
      }
      // Keep the transport socket on the physical network: without this the
      // encrypted datagrams are routed back into our own tun device. The socket
      // can still be pending when the endpoint had not resolved, so the fd comes
      // from status() and the watchdog protects it as soon as it exists.
      this.protectTransportSocket();
      const started: number = wgcore.start(tunFd) as number;
      Diag.write(`engine start -> ${started}`);
      if (started !== 0) {
        TunnelStore.setLastError(`could not start the tunnel engine (${started})`);
        Diag.write(`engine start failed, code ${started}`);
        this.shutdown();
        return;
      }
      this.protectedFd = -1;
      TunnelStore.setActive(tunnel.id);
      TunnelStore.setLastError('');
      this.startWatchdog();
      Diag.write('engine started, waiting for a handshake');
      hilog.info(DOMAIN, TAG, 'tunnel engine started');
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `VpnConnection.create failed: ${err.code} ${err.message}`);
      Diag.write(`vpn create failed: ${err.code} ${err.message}`);
      // 2203002: a tun device from a previous session is still alive. Tear it
      // down and retry once before reporting the failure to the user.
      if (err.code === 2203002 && !this.retriedCreate) {
        this.retriedCreate = true;
        const stale = this.vpnConnection;
        const want = this.lastWant;
        this.vpnConnection = null;
        if (stale !== null) {
          stale.destroy().then(() => {
            if (want !== null) {
              this.connect(want);
            }
          }).catch(() => {
            TunnelStore.setLastError('A previous VPN session could not be released');
            this.shutdown();
          });
        } else {
          this.shutdown();
        }
        return;
      }
      TunnelStore.setLastError(`VPN creation failed (${err.code}): ${err.message}`);
      this.shutdown();
    });
  }

  private parseAddresses(spec: string): ParsedAddress[] {
    const out: ParsedAddress[] = [];
    const items = spec.split(',');
    for (let i = 0; i < items.length; i++) {
      const value = items[i].trim();
      if (value.length === 0) {
        continue;
      }
      const slash = value.indexOf('/');
      const addr = slash > 0 ? value.substring(0, slash) : value;
      const prefix = slash > 0 ? Number.parseInt(value.substring(slash + 1), 10) : 32;
      out.push({
        address: addr,
        prefix: Number.isNaN(prefix) ? 32 : prefix,
        family: addr.indexOf(':') >= 0 ? 2 : 1
      });
    }
    if (out.length === 0) {
      out.push({ address: '10.66.0.2', prefix: 32, family: 1 });
    }
    return out;
  }

  private parseRoutes(spec: string, addresses: ParsedAddress[]): vpnExtension.RouteInfo[] {
    const out: vpnExtension.RouteInfo[] = [];
    const items = spec.split(',');
    for (let i = 0; i < items.length; i++) {
      const value = items[i].trim();
      if (value.length === 0) {
        continue;
      }
      const slash = value.indexOf('/');
      const dest = slash > 0 ? value.substring(0, slash) : value;
      const prefix = slash > 0 ? Number.parseInt(value.substring(slash + 1), 10) : 32;
      const family = dest.indexOf(':') >= 0 ? 2 : 1;
      out.push({
        interface: TUN_INTERFACE,
        destination: {
          address: { address: dest, family: family },
          prefixLength: Number.isNaN(prefix) ? 32 : prefix
        },
        gateway: { address: family === 2 ? '::' : '0.0.0.0', family: family, port: 0 },
        hasGateway: false,
        isDefaultRoute: prefix === 0
      });
    }
    if (out.length === 0 && addresses.length > 0) {
      out.push({
        interface: TUN_INTERFACE,
        destination: {
          address: { address: '0.0.0.0', family: 1 },
          prefixLength: 0
        },
        gateway: { address: '0.0.0.0', family: 1, port: 0 },
        hasGateway: false,
        isDefaultRoute: true
      });
    }
    return out;
  }
}
