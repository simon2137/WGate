import { connection } from '@kit.NetworkKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SettingsStore } from './SettingsStore';
import { TunnelStore } from './TunnelStore';
import { startTunnel, stopTunnel } from './VpnControl';
import { WgTunnel } from '../model/Tunnel';
import { Diag } from '../util/Diag';
import { publishedTunnelId } from './EngineStatus';

/**
 * The trusted-network watcher behind `AutoTunnelScreen.kt`: the reference app
 * starts the preferred tunnel when a trusted SSID is joined and stops it again
 * when the device leaves, which is what this class does with the network
 * callbacks HarmonyOS exposes.
 *
 * The watcher only ever stops a tunnel it started itself, so a manual connect
 * is never torn down by leaving a trusted network.
 */
export class AutoTunnel {
  private static net: connection.NetConnection | null = null;
  /** Heartbeat that asks the no-network question the callbacks can miss. */
  private static poll: number = -1;
  /** Last answer from that probe, so the log gets one line per change. */
  private static online: boolean = true;
  /** Whether the probe has answered at least once. */
  private static probed: boolean = false;
  private static autoStarted: string = '';
  private static lastSsid: string = '';
  /** Last reported reason the Wi-Fi name is missing; "" when it reads fine. */
  private static nameProblem: string = '';
  /** The stored name last shown in place of a hidden one; "" when reading works. */
  private static hiddenName: string = '';
  /** Whether the last Wi-Fi link read found an associated network. */
  private static linkJoined: boolean = false;
  /** What the last name read did; "sync", "sync-failed(801)", "sync-empty", … */
  private static diag: string = '';
  /** The read outcome already written to the log. */
  private static loggedDiag: string = '';

  /** Begin watching; safe to call more than once. */
  static start(): void {
    if (AutoTunnel.net !== null) {
      return;
    }
    try {
      const net: connection.NetConnection = connection.createNetConnection();
      net.register((err: Error) => {
        if (err) {
          Diag.write(`auto-tunnel: could not watch the network: ${err.message}`);
          return;
        }
        Diag.write('auto-tunnel: watching the network');
      });
      net.on('netAvailable', () => {
        AutoTunnel.evaluate('net available');
      });
      net.on('netLost', () => {
        AutoTunnel.evaluate('net lost');
      });
      net.on('netCapabilitiesChange', () => {
        AutoTunnel.evaluate('capabilities changed');
      });
      AutoTunnel.net = net;
      // Re-check once at startup: the callbacks above only fire on a CHANGE, and
      // the usual case is a device that rejoins the network the rules already
      // trust with nothing running, because the VPN went down with the previous
      // process. Without this the list showed a tunnel that was merely wanted.
      // Deferred because starting a VPN extension wants a visible window.
      setTimeout(() => {
        AutoTunnel.evaluate('app started');
      }, 600);
      // The network callbacks are silent while the VPN itself is the default
      // route, so "Stop on no network" also gets a heartbeat. It only stops.
      if (AutoTunnel.poll === -1) {
        AutoTunnel.poll = setInterval(() => {
          AutoTunnel.pollOffline();
        }, 5000);
      }
    } catch (e) {
      Diag.write(`auto-tunnel: could not start the watcher: ${(e as Error).message}`);
    }
  }

  static stop(): void {
    const net: connection.NetConnection | null = AutoTunnel.net;
    if (net === null) {
      return;
    }
    try {
      net.unregister((err: Error) => {
        if (err) {
          Diag.write(`auto-tunnel: unregister failed: ${err.message}`);
        }
      });
    } catch (e) {
      Diag.write(`auto-tunnel: unregister threw: ${(e as Error).message}`);
    }
    AutoTunnel.net = null;
    if (AutoTunnel.poll !== -1) {
      clearInterval(AutoTunnel.poll);
      AutoTunnel.poll = -1;
    }
  }

  /**
   * The SSID of the connected Wi-Fi network, or "" when there is none.
   *
   * A fresh process can ask for this before the Wi-Fi service has the
   * associated network, and the platform answers with an empty name instead of
   * failing; the caller therefore has to ask again rather than cache the
   * answer once. Every failure is written to the diagnostic log with its code,
   * so a device that keeps hiding the name says why.
   */
  static async currentSsid(): Promise<string> {
    // `getLinkedInfoSync()` (API 18) answers in one call; the promise form is
    // kept as the fallback for devices that do not implement the sync one. Both
    // ask the same question, and `diag` records which one answered so the page
    // can say what is actually happening on a device that hides the name.
    let info: wifiManager.WifiLinkedInfo | null = null;
    try {
      info = wifiManager.getLinkedInfoSync();
      AutoTunnel.diag = 'sync';
    } catch (e) {
      const syncErr: BusinessError = e as BusinessError;
      AutoTunnel.diag = `sync-failed(${syncErr.code})`;
      info = null;
    }
    if (info === null) {
      try {
        info = await wifiManager.getLinkedInfo();
        AutoTunnel.diag = 'async';
      } catch (e) {
        // No Wi-Fi hardware, no permission or no network: treat as "not on a
        // trusted network" rather than failing the whole watcher.
        AutoTunnel.linkJoined = false;
        const err: BusinessError = e as BusinessError;
        AutoTunnel.diag = `async-failed(${err.code})`;
        AutoTunnel.noteNameProblem(`could not read the Wi-Fi name (${err.code} ${err.message})`);
        AutoTunnel.reportDiag();
        return '';
      }
    }
    // The call settling at all means a Wi-Fi link exists, even when the name is
    // withheld: `isConnected()` alone answers false on some devices while the
    // VPN owns the default route.
    AutoTunnel.linkJoined = info !== null;
    if (info === null || info.ssid === undefined || info.ssid.length === 0 ||
      info.ssid === '<unknown ssid>') {
      AutoTunnel.diag = `${AutoTunnel.diag}-empty`;
      AutoTunnel.noteNameProblem('the Wi-Fi name is not available yet');
      AutoTunnel.reportDiag();
      return '';
    }
    AutoTunnel.noteNameProblem('');
    AutoTunnel.reportDiag();
    return info.ssid;
  }

  /** Write the read outcome once per change; the page asks every 1.5 seconds. */
  private static reportDiag(): void {
    if (AutoTunnel.diag === AutoTunnel.loggedDiag) {
      return;
    }
    AutoTunnel.loggedDiag = AutoTunnel.diag;
    Diag.write(`auto-tunnel: name read ${AutoTunnel.diag}`);
  }

  /** What the last name read did: "sync", "async-failed(201)", "sync-empty", … */
  static nameDiag(): string {
    return AutoTunnel.diag;
  }

  /** True when the device is joined to a Wi-Fi network, named or not. */
  static wifiActive(): boolean {
    try {
      if (wifiManager.isWifiActive() && wifiManager.isConnected()) {
        return true;
      }
    } catch (e) {
      // Fall through to what the last link read said.
    }
    return AutoTunnel.linkJoined;
  }

  /**
   * The name the page should show.
   *
   * `getLinkedInfo()` is the only source, but it answers with an empty name
   * while the service is still settling - most visibly right after the process
   * starts. Falling back to the last name the platform did give us keeps the
   * row honest for a device that is plainly joined to a network; on another
   * bearer the stored name would be a lie, so it is only used on Wi-Fi.
   */
  static async displaySsid(): Promise<string> {
    const live: string = await AutoTunnel.currentSsid();
    if (live.length > 0) {
      AutoTunnel.hiddenName = '';
      return live;
    }
    if (AutoTunnel.networkType() !== 'wifi') {
      return '';
    }
    const known: string = SettingsStore.lastSsid();
    if (known.length === 0) {
      return '';
    }
    if (AutoTunnel.hiddenName !== known) {
      AutoTunnel.hiddenName = known;
      Diag.write(`auto-tunnel: the platform hid the name, showing "${known}"`);
    }
    return known;
  }

  /**
   * Record why the name is missing, once per change: the page asks again on
   * every tick, and the log should not grow a line each time.
   */
  private static noteNameProblem(problem: string): void {
    if (problem === AutoTunnel.nameProblem) {
      return;
    }
    AutoTunnel.nameProblem = problem;
    if (problem.length > 0) {
      Diag.write(`auto-tunnel: ${problem}`);
    }
  }

  /** Decide what the current network should do to the tunnel. */
  static async evaluate(reason: string): Promise<void> {
    if (!SettingsStore.autoEnabled()) {
      return;
    }
    const ssid: string = await AutoTunnel.currentSsid();
    if (ssid === AutoTunnel.lastSsid && reason === 'net available') {
      return;
    }
    AutoTunnel.lastSsid = ssid;
    // Remember the name for the page: a later read can come back empty even
    // though the device is joined to this very network.
    if (ssid.length > 0 && ssid !== SettingsStore.lastSsid()) {
      SettingsStore.setLastSsid(ssid);
    }
    // Two independent gates, the way the Auto-tunnel tab presents them: the
    // per-bearer switch ("Wi-Fi tunnel", "Ethernet tunnel", …) says whether this
    // kind of network should carry a tunnel at all, and the Wi-Fi rules say
    // which names count as home. A wildcard rule ("Xiaomi*") has to be honoured
    // here or the switch would look configured while nothing ever matched.
    const net: string = AutoTunnel.networkType();
    const offline: boolean = !AutoTunnel.hasNetwork();
    const running: string = publishedTunnelId();
    // "Stop on no network": whatever tunnel is up goes down once the device has
    // no physical network left. It deliberately does not require that
    // auto-tunnel was the one that started it - the switch reads "stop the
    // tunnel when the device has no network connection", and a tunnel left
    // hanging with no route is useless either way.
    if (offline && SettingsStore.stopOnNoInternet() && running.length > 0) {
      AutoTunnel.stopNoNetwork(running);
      return;
    }
    const bearerOn: boolean = SettingsStore.netTunnelOn(net);
    const trusted: boolean = net === 'wifi' ? SettingsStore.trustsSsid(ssid) : true;
    const onTrusted: boolean = bearerOn && trusted;
    const ruleCount: number = SettingsStore.ssids().length;
    Diag.write(`auto-tunnel: ${reason}, ssid "${ssid}", ${net} tunnel ${bearerOn},` +
      ` trusted ${trusted} (${ruleCount} rule(s), wildcards ${SettingsStore.wildcards()})`);

    if (onTrusted) {
      const wanted: WgTunnel | null = AutoTunnel.pickTunnel();
      if (wanted === null) {
        Diag.write('auto-tunnel: no tunnel to start');
        return;
      }
      if (running === wanted.id) {
        return;
      }
      if (running.length > 0) {
        Diag.write('auto-tunnel: another tunnel is already running, leaving it alone');
        return;
      }
      const problem: string = await startTunnel(wanted);
      if (problem.length === 0) {
        AutoTunnel.autoStarted = wanted.id;
        Diag.write(`auto-tunnel: started ${wanted.name} on "${ssid}"`);
      } else {
        Diag.write(`auto-tunnel: could not start ${wanted.name}: ${problem}`);
      }
      return;
    }

    if (AutoTunnel.autoStarted.length > 0 && running === AutoTunnel.autoStarted) {
      const started: WgTunnel | null = AutoTunnel.byId(AutoTunnel.autoStarted);
      if (started !== null) {
        await stopTunnel(started);
        Diag.write(`auto-tunnel: stopped ${started.name}, "${ssid}" is not trusted`);
      }
    }
    AutoTunnel.autoStarted = '';
  }

  /**
   * Whether the device still has a way out to the internet.
   *
   * The default network is the wrong probe here: while our own VPN is up it *is*
   * the default network, so `getDefaultNetSync()` keeps answering with a handle
   * (bearer `BEARER_VPN`) even after Wi-Fi and mobile data are switched off -
   * which is why the first version of "Stop on no network" never fired on a
   * device that had a tunnel running. Look at every net instead and accept only
   * a physical bearer: Wi-Fi, cellular or Ethernet.
   */
  static hasNetwork(): boolean {
    try {
      const nets: connection.NetHandle[] = connection.getAllNetsSync();
      for (const net of nets) {
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
      }
      return false;
    } catch (e) {
      // The probe failing says nothing about connectivity; do not act on it.
      return true;
    }
  }

  /**
   * The callbacks only fire when a network comes or goes, and taking Wi-Fi down
   * while the VPN is the default route can happen without any such event - the
   * net set still holds the VPN. So the tab also asks this every few seconds;
   * it only ever stops, never starts, so a tunnel the user stopped by hand on a
   * trusted network is not resurrected behind their back.
   */
  static pollOffline(): void {
    const online: boolean = AutoTunnel.hasNetwork();
    // One line on the first probe and one per change, so a device that keeps the
    // tunnel up can say why: `absent` means the switch should have fired,
    // `present` means the platform still reports a physical bearer (a tethered
    // link, a VoLTE registration…).
    if (!AutoTunnel.probed || online !== AutoTunnel.online) {
      AutoTunnel.probed = true;
      AutoTunnel.online = online;
      Diag.write(`auto-tunnel: network ${online ? 'present' : 'absent'}`);
    }
    if (AutoTunnel.autoStarted.length === 0 && publishedTunnelId().length === 0) {
      return;
    }
    if (!SettingsStore.stopOnNoInternet() || online) {
      return;
    }
    const running: string = publishedTunnelId();
    if (running.length === 0) {
      return;
    }
    AutoTunnel.stopNoNetwork(running);
  }

  /** Tears a tunnel down because the device has no network left. */
  private static stopNoNetwork(id: string): void {
    const tunnel: WgTunnel | null = AutoTunnel.byId(id);
    if (tunnel === null) {
      return;
    }
    const mine: boolean = id === AutoTunnel.autoStarted;
    stopTunnel(tunnel).then(() => {
      AutoTunnel.autoStarted = '';
      Diag.write(`auto-tunnel: stopped ${tunnel.name}, the device has no network` +
        ` (${mine ? 'started by auto-tunnel' : 'started by hand'})`);
    });
  }

  /** 'wifi', 'cellular' or 'ethernet'; 'wifi' when unknown. */
  static networkType(): string {    try {
      const caps = connection.getNetCapabilitiesSync(connection.getDefaultNetSync());
      if (caps.bearerTypes !== undefined && caps.bearerTypes.length > 0) {
        const type: connection.NetBearType = caps.bearerTypes[0];
        if (type === connection.NetBearType.BEARER_ETHERNET) {
          return 'ethernet';
        }
        if (type === connection.NetBearType.BEARER_CELLULAR) {
          return 'cellular';
        }
        if (type === connection.NetBearType.BEARER_WIFI) {
          return 'wifi';
        }
      }
    } catch (e) {
      // fall through to the Wi-Fi default
    }
    return 'wifi';
  }

  private static byId(id: string): WgTunnel | null {
    const tunnels: WgTunnel[] = TunnelStore.list();
    for (let i = 0; i < tunnels.length; i++) {
      if (tunnels[i].id === id) {
        return tunnels[i];
      }
    }
    return null;
  }

  /** Preferred tunnel, else the primary tunnel, else the first one. */
  private static pickTunnel(): WgTunnel | null {
    const tunnels: WgTunnel[] = TunnelStore.list();
    if (tunnels.length === 0) {
      return null;
    }
    // The per-network choice from AutoTunnelScreen wins over the global one.
    const perNetwork: string = SettingsStore.preferredFor(AutoTunnel.networkType());
    if (perNetwork.length > 0) {
      const match: WgTunnel | null = AutoTunnel.byId(perNetwork);
      if (match !== null) {
        return match;
      }
    }
    const preferred: string = SettingsStore.preferredTunnelId();
    if (preferred.length > 0) {
      const match: WgTunnel | null = AutoTunnel.byId(preferred);
      if (match !== null) {
        return match;
      }
    }
    const primary: string = SettingsStore.primaryId();
    if (primary.length > 0) {
      const match: WgTunnel | null = AutoTunnel.byId(primary);
      if (match !== null) {
        return match;
      }
    }
    return tunnels[0];
  }
}
