import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WgTunnel } from '../model/Tunnel';
import { TunnelStore } from './TunnelStore';

const STORE: string = 'wg_settings';

/**
 * The handful of app-wide preferences the reference app keeps in DataStore:
 * auto-tunnel behaviour, the backend mode, and the appearance setting. Values
 * are strings so a partial read never throws.
 */
export class SettingsStore {
  private static store: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (SettingsStore.store === null) {
      SettingsStore.store = preferences.getPreferencesSync(context, { name: STORE });
    }
  }

  private static ensure(): preferences.Preferences | null {
    return SettingsStore.store;
  }

  private static get(key: string, fallback: string): string {
    const store: preferences.Preferences | null = SettingsStore.ensure();
    if (store === null) {
      return fallback;
    }
    const value = store.getSync(key, fallback);
    return typeof value === 'string' ? value as string : fallback;
  }

  private static put(key: string, value: string): void {
    const store: preferences.Preferences | null = SettingsStore.ensure();
    if (store === null) {
      return;
    }
    store.putSync(key, value);
    store.flush();
  }

  static autoEnabled(): boolean {
    return SettingsStore.get('auto', 'false') === 'true';
  }

  static setAutoEnabled(on: boolean): void {
    SettingsStore.put('auto', on ? 'true' : 'false');
  }

  static preferredTunnelId(): string {
    return SettingsStore.get('preferred', '');
  }

  static setPreferredTunnelId(id: string): void {
    SettingsStore.put('preferred', id);
  }

  /** The SSIDs auto-tunnel should treat as home networks, one per line. */
  static ssids(): string[] {
    return SettingsStore.get('ssids', '').split('\n').filter((s: string) => s.length > 0);
  }

  static addSsid(ssid: string): void {
    const list: string[] = SettingsStore.ssids();
    if (ssid.length === 0 || list.indexOf(ssid) >= 0) {
      return;
    }
    list.push(ssid);
    SettingsStore.put('ssids', list.join('\n'));
  }

  static removeSsid(ssid: string): void {
    const list: string[] = SettingsStore.ssids().filter((s: string) => s !== ssid);
    SettingsStore.put('ssids', list.join('\n'));
  }

  /**
   * True when the rules accept this network.
   *
   * A rule is literal unless "Use wildcards" is on, where `*` stands for any
   * run of characters and `?` for exactly one - the same two the Wi-Fi page
   * describes ("Xiaomi* covers every SSID that starts with it"). A rule that
   * starts with `!` is an exclusion and wins over every inclusion, which is
   * how the reference's `isMatchingToWildcardList` reads its list.
   */
  static trustsSsid(ssid: string): boolean {
    if (ssid.length === 0) {
      return false;
    }
    const rules: string[] = SettingsStore.ssids();
    const wildcards: boolean = SettingsStore.wildcards();
    let included: boolean = false;
    for (let i = 0; i < rules.length; i++) {
      const raw: string = rules[i].trim();
      if (raw.length === 0) {
        continue;
      }
      const exclude: boolean = raw.startsWith('!');
      const pattern: string = exclude ? raw.substring(1) : raw;
      if (!SettingsStore.ruleMatches(pattern, ssid, wildcards)) {
        continue;
      }
      if (exclude) {
        return false;
      }
      included = true;
    }
    return included;
  }

  private static ruleMatches(pattern: string, value: string, wildcards: boolean): boolean {
    const hasWildcard: boolean = pattern.indexOf('*') >= 0 || pattern.indexOf('?') >= 0;
    if (!wildcards || !hasWildcard) {
      return pattern === value;
    }
    // Two-pointer glob with backtracking on the last `*`: no RegExp object per
    // rule, which matters because this runs on every network callback.
    let p: number = 0;
    let v: number = 0;
    let star: number = -1;
    let mark: number = 0;
    while (v < value.length) {
      if (p < pattern.length && (pattern.charAt(p) === '?' || pattern.charAt(p) === value.charAt(v))) {
        p++;
        v++;
      } else if (p < pattern.length && pattern.charAt(p) === '*') {
        star = p;
        mark = v;
        p++;
      } else if (star >= 0) {
        p = star + 1;
        mark++;
        v = mark;
      } else {
        return false;
      }
    }
    while (p < pattern.length && pattern.charAt(p) === '*') {
      p++;
    }
    return p === pattern.length;
  }

  /**
   * The last Wi-Fi name the platform handed us.
   *
   * A fresh process can ask for the associated network before the Wi-Fi
   * service has it and get an empty string back; keeping the last real answer
   * lets the page show a name instead of "no network" while the device is
   * clearly joined to one.
   */
  static lastSsid(): string {
    return SettingsStore.get('last_ssid', '');
  }

  static setLastSsid(ssid: string): void {
    SettingsStore.put('last_ssid', ssid);
  }

  /** The access-point BSSIDs auto-tunnel treats as home, one per line. */
  static bssids(): string[] {
    return SettingsStore.get('bssids', '').split('\n').filter((s: string) => s.length > 0);
  }

  static addBssid(bssid: string): void {
    const list: string[] = SettingsStore.bssids();
    if (bssid.length === 0 || list.indexOf(bssid) >= 0) {
      return;
    }
    list.push(bssid);
    SettingsStore.put('bssids', list.join('\n'));
  }

  static removeBssid(bssid: string): void {
    const list: string[] = SettingsStore.bssids().filter((s: string) => s !== bssid);
    SettingsStore.put('bssids', list.join('\n'));
  }

  /** Wildcards let "Work*" match every SSID that starts with Work. */
  static wildcards(): boolean {
    return SettingsStore.get('auto_wildcards', 'false') === 'true';
  }

  static setWildcards(on: boolean): void {
    SettingsStore.put('auto_wildcards', on ? 'true' : 'false');
  }

  /** Keep the tunnel down while a captive portal is in front of the network. */
  static captivePortal(): boolean {
    return SettingsStore.get('captive_portal', 'false') === 'true';
  }

  static setCaptivePortal(on: boolean): void {
    SettingsStore.put('captive_portal', on ? 'true' : 'false');
  }

  /** 'vpn' (default tunnel mode) or 'lockdown'. */
  static backendMode(): string {
    return SettingsStore.get('backend', 'vpn');
  }

  static setBackendMode(mode: string): void {
    SettingsStore.put('backend', mode);
  }

  /**
   * 'automatic', 'dark', 'light', 'darker' or 'amoled'. `automatic` is the
   * default: a fresh install follows the system appearance. `dynamic` is gone
   * from the picker (HarmonyOS has no accent API), and a device that still has
   * it stored keeps painting what it painted before -- the dark palette.
   */
  static theme(): string {
    const stored: string = SettingsStore.get('theme', 'automatic');
    return stored === 'dynamic' ? 'dark' : stored;
  }

  static setTheme(name: string): void {
    SettingsStore.put('theme', name);
  }

  /** A specific interface ('en', 'zh_CN', 'zh_TW'); zh_CN on a fresh install. */
  static language(): string {
    return SettingsStore.get('language', 'zh_CN');
  }

  static setLanguage(name: string): void {
    SettingsStore.put('language', name);
  }

  /** Notification switches from `NotificationsScreen.kt`. */
  static notification(key: string): boolean {
    return SettingsStore.get(`notify_${key}`, 'true') === 'true';
  }

  static setNotification(key: string, on: boolean): void {
    SettingsStore.put(`notify_${key}`, on ? 'true' : 'false');
  }

  /** Global split tunneling switch; per-app routing itself is not available. */
  static globalSplit(): boolean {
    return SettingsStore.get('global_split', 'false') === 'true';
  }

  static setGlobalSplit(on: boolean): void {
    SettingsStore.put('global_split', on ? 'true' : 'false');
  }

  /** Interface defaults applied to a newly imported tunnel. */
  static defaultMtu(): number {
    return Number.parseInt(SettingsStore.get('default_mtu', '1420'), 10) || 1420;
  }

  static setDefaultMtu(value: number): void {
    SettingsStore.put('default_mtu', value.toString());
  }

  static defaultKeepalive(): number {
    return Number.parseInt(SettingsStore.get('default_keepalive', '25'), 10) || 0;
  }

  static setDefaultKeepalive(value: number): void {
    SettingsStore.put('default_keepalive', value.toString());
  }

  static defaultDns(): string {
    return SettingsStore.get('default_dns', '1.1.1.1');
  }

  static setDefaultDns(value: string): void {
    SettingsStore.put('default_dns', value.length > 0 ? value : '1.1.1.1');
  }

  /** Screen-capture protection from `SecurityScreen.kt`. */
  static screenGuard(): boolean {
    return SettingsStore.get('screen_guard', 'false') === 'true';
  }

  static setScreenGuard(on: boolean): void {
    SettingsStore.put('screen_guard', on ? 'true' : 'false');
  }

  /**
   * The app-lock PIN, stored as a hash so the file never holds the digits.
   * An empty string means the lock is off.
   */
  static pinHash(): string {
    return SettingsStore.get('pin_hash', '');
  }

  static setPin(pin: string): void {
    SettingsStore.put('pin_hash', pin.length === 0 ? '' : SettingsStore.hash(pin));
  }

  static checkPin(pin: string): boolean {
    const stored: string = SettingsStore.pinHash();
    return stored.length > 0 && stored === SettingsStore.hash(pin);
  }

  /** djb2 over the digits; enough to keep the PIN out of plain text. */
  private static hash(text: string): string {
    let value: number = 5381;
    for (let i = 0; i < text.length; i++) {
      value = ((value << 5) + value + text.charCodeAt(i)) | 0;
    }
    return (value >>> 0).toString(16);
  }

  /** Seamless recovery from `TunnelRecoveryScreen.kt`. */
  static seamlessRecovery(): boolean {
    return SettingsStore.get('seamless_recovery', 'true') === 'true';
  }

  static setSeamlessRecovery(on: boolean): void {
    SettingsStore.put('seamless_recovery', on ? 'true' : 'false');
  }

  static recoveryDelay(): number {
    return Number.parseInt(SettingsStore.get('recovery_delay', '30'), 10) || 30;
  }

  static setRecoveryDelay(seconds: number): void {
    SettingsStore.put('recovery_delay', seconds.toString());
  }

  /** Pre/post script support; the reference app runs them through a shell. */
  static scriptsEnabled(): boolean {
    return SettingsStore.get('scripts', 'false') === 'true';
  }

  static setScriptsEnabled(on: boolean): void {
    SettingsStore.put('scripts', on ? 'true' : 'false');
  }

  /** Generic string access for the pages whose settings are only recorded. */
  static raw(key: string, fallback: string): string {
    return SettingsStore.get(key, fallback);
  }

  static setRaw(key: string, value: string): void {
    SettingsStore.put(key, value);
  }

  /** Generic flag access for the pages whose settings are only recorded. */
  static flag(key: string, fallback: boolean): boolean {
    return SettingsStore.get(key, fallback ? 'true' : 'false') === 'true';
  }

  static setFlag(key: string, on: boolean): void {
    SettingsStore.put(key, on ? 'true' : 'false');
  }

  /** Per network type: 'wifi', 'cellular' or 'ethernet'. */
  static netTunnelOn(net: string): boolean {
    const fallback: string = net === 'wifi' ? 'true' : 'false';
    return SettingsStore.get(`net_on_${net}`, fallback) === 'true';
  }

  static setNetTunnelOn(net: string, on: boolean): void {
    SettingsStore.put(`net_on_${net}`, on ? 'true' : 'false');
  }

  /** Tunnel to bring up on that network type, empty means the default one. */
  static preferredFor(net: string): string {
    return SettingsStore.get(`net_pref_${net}`, '');
  }

  static setPreferredFor(net: string, id: string): void {
    SettingsStore.put(`net_pref_${net}`, id);
  }

  static stopOnNoInternet(): boolean {
    return SettingsStore.get('stop_no_internet', 'false') === 'true';
  }

  static setStopOnNoInternet(on: boolean): void {
    SettingsStore.put('stop_no_internet', on ? 'true' : 'false');
  }

  /** Monitoring: live tunnel statistics and their refresh interval in ms. */
  static statisticsEnabled(): boolean {
    return SettingsStore.get('statistics', 'true') === 'true';
  }

  static setStatisticsEnabled(on: boolean): void {
    SettingsStore.put('statistics', on ? 'true' : 'false');
  }

  static statsInterval(): number {
    const raw: string = SettingsStore.get('stats_interval', '1000');
    const value: number = Number.parseInt(raw, 10);
    return Number.isNaN(value) || value <= 0 ? 1000 : value;
  }

  static setStatsInterval(ms: number): void {
    SettingsStore.put('stats_interval', ms.toString());
  }

  /** 'manual', 'name' or 'latency' - the Tunnels list order. */
  static sortMode(): string {
    return SettingsStore.get('sort_mode', 'manual');
  }

  static setSortMode(mode: string): void {
    SettingsStore.put('sort_mode', mode);
  }

  /** Last measured handshake RTT per tunnel, or -1 when never measured. */
  static latency(id: string): number {
    const raw: string = SettingsStore.get(`latency_${id}`, '');
    if (raw.length === 0) {
      return -1;
    }
    const value: number = Number.parseInt(raw, 10);
    return Number.isNaN(value) ? -1 : value;
  }

  static setLatency(id: string, ms: number): void {
    SettingsStore.put(`latency_${id}`, ms.toString());
  }

  static preferredName(tunnels: WgTunnel[]): string {
    const id: string = SettingsStore.preferredTunnelId();
    for (let i = 0; i < tunnels.length; i++) {
      if (tunnels[i].id === id) {
        return tunnels[i].name;
      }
    }
    return 'None';
  }

  /** Per-tunnel flags that the reference app keeps on the tunnel itself. */
  static primaryId(): string {
    return SettingsStore.get('primary', '');
  }

  static setPrimaryId(id: string): void {
    SettingsStore.put('primary', id);
  }

  static isMetered(id: string): boolean {
    return SettingsStore.get('metered', '').split(',').indexOf(id) >= 0;
  }

  static setMetered(id: string, on: boolean): void {
    const list: string[] = SettingsStore.get('metered', '')
      .split(',').filter((s: string) => s.length > 0 && s !== id);
    if (on) {
      list.push(id);
    }
    SettingsStore.put('metered', list.join(','));
  }

  static isDdns(id: string): boolean {
    return SettingsStore.get('ddns', '').split(',').indexOf(id) >= 0;
  }

  static setDdns(id: string, on: boolean): void {
    const list: string[] = SettingsStore.get('ddns', '')
      .split(',').filter((s: string) => s.length > 0 && s !== id);
    if (on) {
      list.push(id);
    }
    SettingsStore.put('ddns', list.join(','));
  }

  /** Per-tunnel split tunneling, IPv6 and multihop preferences. */
  static splitOn(id: string, fallback: boolean): boolean {
    return SettingsStore.raw(`split_on_${id}`, fallback ? '1' : '0') === '1';
  }

  static setSplitOn(id: string, on: boolean): void {
    SettingsStore.setRaw(`split_on_${id}`, on ? '1' : '0');
  }

  /** `include` tunnels the listed apps, `exclude` bypasses them. */
  static splitMode(id: string): string {
    return SettingsStore.raw(`split_mode_${id}`, 'exclude');
  }

  static setSplitMode(id: string, mode: string): void {
    SettingsStore.setRaw(`split_mode_${id}`, mode);
  }

  static splitApps(id: string): number {
    const stored: string = SettingsStore.raw(`split_apps_${id}`, '');
    return stored.length === 0 ? 0 : stored.split(',').length;
  }

  static preferIpv6(id: string, fallback: boolean): boolean {
    return SettingsStore.raw(`ipv6_prefer_${id}`, fallback ? '1' : '0') === '1';
  }

  static setPreferIpv6(id: string, on: boolean): void {
    SettingsStore.setRaw(`ipv6_prefer_${id}`, on ? '1' : '0');
  }

  static restoreIpv6(id: string, fallback: boolean): boolean {
    return SettingsStore.raw(`ipv6_restore_${id}`, fallback ? '1' : '0') === '1';
  }

  static setRestoreIpv6(id: string, on: boolean): void {
    SettingsStore.setRaw(`ipv6_restore_${id}`, on ? '1' : '0');
  }

  static entryTunnel(id: string): string {
    return SettingsStore.raw(`entry_${id}`, '');
  }

  static setEntryTunnel(id: string, entryId: string): void {
    SettingsStore.setRaw(`entry_${id}`, entryId);
  }

  /** Group names in the order the list shows them, including empty groups. */
  static groups(): string[] {
    return SettingsStore.get('groups', '')
      .split('\n').filter((s: string) => s.length > 0);
  }

  static setGroups(names: string[]): void {
    SettingsStore.put('groups', names.filter((s: string) => s.length > 0).join('\n'));
  }

  static addGroup(name: string): void {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      return;
    }
    const names: string[] = SettingsStore.groups();
    if (names.indexOf(trimmed) < 0) {
      names.push(trimmed);
      SettingsStore.setGroups(names);
    }
  }

  /** Renames a group and every tunnel that referenced it. */
  static renameGroup(from: string, to: string): void {
    const trimmed: string = to.trim();
    if (from.length === 0 || trimmed.length === 0 || from === trimmed) {
      return;
    }
    const names: string[] = SettingsStore.groups().map((s: string) => s === from ? trimmed : s);
    SettingsStore.setGroups(names);
    const tunnels: WgTunnel[] = TunnelStore.list();
    for (let i = 0; i < tunnels.length; i++) {
      if (tunnels[i].group === from) {
        tunnels[i].group = trimmed;
        TunnelStore.save(tunnels[i]);
      }
    }
  }

  static removeGroup(name: string): void {
    SettingsStore.setGroups(SettingsStore.groups().filter((s: string) => s !== name));
  }
}
