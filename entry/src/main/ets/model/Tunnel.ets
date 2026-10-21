/**
 * Tunnel configuration model and wg-quick (INI) parser.
 *
 * A tunnel has one [Interface] block and any number of [Peer] blocks, like
 * wg-quick.  Storage is flat JSON; `toJson()` doubles as the hand-off format to
 * the C engine (see napi_init.cpp), which expects `peerCount` plus
 * `peer<N><Field>` keys because the NDK has no JSON parser.
 */

export class WgPeer {
  publicKey: string = '';
  presharedKey: string = '';
  host: string = '';
  port: number = 51820;
  /** Comma separated CIDRs routed through this peer. */
  allowedIPs: string = '0.0.0.0/0';
  keepalive: number = 25;

  constructor(publicKey: string, presharedKey: string, host: string, port: number,
              allowedIPs: string, keepalive: number) {
    this.publicKey = publicKey;
    this.presharedKey = presharedKey;
    this.host = host;
    this.port = port;
    this.allowedIPs = allowedIPs;
    this.keepalive = keepalive;
  }

  endpoint(): string {
    return this.host.length > 0 ? `${this.host}:${this.port}` : 'no endpoint';
  }

  clone(): WgPeer {
    return new WgPeer(this.publicKey, this.presharedKey, this.host, this.port, this.allowedIPs,
      this.keepalive);
  }
}

export class WgTunnel {
  id: string = '';
  name: string = '';
  address: string = '10.66.0.2/32';
  dns: string = '1.1.1.1';
  privateKey: string = '';
  publicKey: string = '';
  mtu: number = 1420;
  peers: WgPeer[] = [];
  /** Comma separated bundle names routed *outside* the tunnel. */
  excludedApps: string = '';
  awg: boolean = false;
  jc: number = 0;
  jmin: number = 0;
  jmax: number = 0;
  s1: number = 0;
  s2: number = 0;
  s3: number = 0;
  h1: number = 1;
  h2: number = 2;
  h3: number = 3;
  h4: number = 4;
  /** Group name shown in the list; empty means ungrouped. */
  group: string = '';
  /** Interface ListenPort; 0 means the kernel picks one. */
  listenPort: number = 0;
  /** wg-quick hooks, edited by the config editor and shown in the text. */
  preUp: string = '';
  postUp: string = '';
  preDown: string = '';
  postDown: string = '';

  /** Endpoint of the first peer, for list rows. */
  endpoint(): string {
    return this.peers.length > 0 ? this.peers[0].endpoint() : 'no endpoint';
  }

  /** All AllowedIPs of all peers, de-duplicated, as one comma separated list. */
  allowedIPs(): string {
    const seen: string[] = [];
    for (let i = 0; i < this.peers.length; i++) {
      const parts: string[] = this.peers[i].allowedIPs.split(',');
      for (let j = 0; j < parts.length; j++) {
        const item = parts[j].trim();
        if (item.length > 0 && !seen.includes(item)) {
          seen.push(item);
        }
      }
    }
    return seen.join(', ');
  }

  /** JSON consumed by wgcore.open(). */
  toJson(): string {
    const o: Record<string, Object> = {
      'privateKey': this.privateKey,
      'mtu': this.mtu,
      'peerCount': this.peers.length,
      'awg': this.awg,
      'jc': this.jc,
      'jmin': this.jmin,
      'jmax': this.jmax,
      's1': this.s1,
      's2': this.s2,
      's3': this.s3,
      'h1': this.h1,
      'h2': this.h2,
      'h3': this.h3,
      'h4': this.h4
    };
    for (let i = 0; i < this.peers.length; i++) {
      const p = this.peers[i];
      const n = (i + 1).toString();
      o[`peer${n}PublicKey`] = p.publicKey;
      o[`peer${n}PresharedKey`] = p.presharedKey;
      o[`peer${n}Host`] = p.host;
      o[`peer${n}Port`] = p.port;
      o[`peer${n}Keepalive`] = p.keepalive;
      o[`peer${n}AllowedIPs`] = p.allowedIPs;
    }
    return JSON.stringify(o);
  }

  static from(raw: string): WgTunnel {
    const t: WgTunnel = new WgTunnel();
    try {
      const o = JSON.parse(raw) as Record<string, Object>;
      t.id = (o.id as string) ?? '';
      t.name = (o.name as string) ?? '';
      t.address = (o.address as string) ?? '10.66.0.2/32';
      t.dns = (o.dns as string) ?? '1.1.1.1';
      t.privateKey = (o.privateKey as string) ?? '';
      t.publicKey = (o.publicKey as string) ?? '';
      t.mtu = (o.mtu as number) ?? 1420;
      t.excludedApps = (o.excludedApps as string) ?? '';
      t.awg = (o.awg as boolean) ?? false;
      t.jc = (o.jc as number) ?? 0;
      t.jmin = (o.jmin as number) ?? 0;
      t.jmax = (o.jmax as number) ?? 0;
      t.s1 = (o.s1 as number) ?? 0;
      t.s2 = (o.s2 as number) ?? 0;
      t.s3 = (o.s3 as number) ?? 0;
      t.h1 = (o.h1 as number) ?? 1;
      t.h2 = (o.h2 as number) ?? 2;
      t.h3 = (o.h3 as number) ?? 3;
      t.h4 = (o.h4 as number) ?? 4;
      t.group = (o.group as string) ?? '';
      t.listenPort = (o.listenPort as number) ?? 0;
      t.preUp = (o.preUp as string) ?? '';
      t.postUp = (o.postUp as string) ?? '';
      t.preDown = (o.preDown as string) ?? '';
      t.postDown = (o.postDown as string) ?? '';

      const list = o.peers as WgPeer[] | undefined;
      if (list !== undefined && list.length > 0) {
        for (let i = 0; i < list.length; i++) {
          const p = list[i];
          t.peers.push(new WgPeer(p.publicKey ?? '', p.presharedKey ?? '', p.host ?? '',
            p.port ?? 51820, p.allowedIPs ?? '0.0.0.0/0', p.keepalive ?? 25));
        }
      } else if (((o.host as string) ?? '').length > 0) {
        // records written before multiple peers were supported
        t.peers.push(new WgPeer((o.peerPublicKey as string) ?? '', (o.presharedKey as string) ?? '',
          o.host as string, (o.port as number) ?? 51820, (o.allowedIPs as string) ?? '0.0.0.0/0',
          (o.keepalive as number) ?? 25));
      }
    } catch (e) {
      // keep defaults: a corrupt record should not take the list down
    }
    return t;
  }
}

/** "host:port" / "[v6]:port" splitting used by Endpoint = lines. */
export function splitEndpoint(value: string): string[] {
  const v = value.trim();
  if (v.startsWith('[')) {
    const close = v.indexOf(']');
    if (close > 0) {
      const host = v.substring(1, close);
      const rest = v.substring(close + 1);
      const port = rest.startsWith(':') ? Number.parseInt(rest.substring(1), 10) : 51820;
      return [host, Number.isNaN(port) ? '51820' : port.toString()];
    }
  }
  const idx = v.lastIndexOf(':');
  if (idx > 0 && v.indexOf(':') === idx) {
    const port = Number.parseInt(v.substring(idx + 1), 10);
    if (!Number.isNaN(port)) {
      return [v.substring(0, idx), port.toString()];
    }
  }
  // bare IPv6 address, no port
  return [v, '51820'];
}

function num(value: string, fallback: number): number {
  const n = Number.parseInt(value.trim(), 10);
  return Number.isNaN(n) ? fallback : n;
}

/**
 * Parse a wg-quick style configuration. Returns null when no [Peer] block or
 * no PublicKey is present, which is what makes a paste "invalid".
 */
export function parseWgQuick(text: string, fallbackName: string): WgTunnel | null {
  const t: WgTunnel = new WgTunnel();
  let section = '';
  let sawPeerKey = false;
  let sawPrivateKey = false;
  let peer: WgPeer | null = null;

  // Configurations handed over through an intent or the clipboard sometimes
  // arrive with literal backslash-n instead of real line breaks.
  let body: string = text;
  if (body.indexOf('\\n') >= 0) {
    body = body.split('\\n').join('\n');
  }
  body = body.split('\r').join('');

  const lines: string[] = body.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0 || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    if (line.startsWith('[')) {
      if (peer !== null) {
        t.peers.push(peer);
        peer = null;
      }
      section = line.toLowerCase();
      if (section.startsWith('[peer]')) {
        peer = new WgPeer('', '', '', 51820, '0.0.0.0/0', 0);
      }
      continue;
    }
    const eq = line.indexOf('=');
    if (eq < 0) {
      continue;
    }
    const key = line.substring(0, eq).trim().toLowerCase();
    const value = line.substring(eq + 1).trim();
    if (section.startsWith('[interface]')) {
      if (key === 'privatekey') {
        t.privateKey = value;
        sawPrivateKey = true;
      } else if (key === 'address') {
        t.address = value.split(',')[0].trim();
      } else if (key === 'dns') {
        t.dns = value.split(',')[0].trim();
      } else if (key === 'mtu') {
        t.mtu = num(value, 1420);
      } else if (key === 'listenport') {
        t.listenPort = num(value, 0);
      } else if (key === 'preup') {
        t.preUp = value;
      } else if (key === 'postup') {
        t.postUp = value;
      } else if (key === 'predown') {
        t.preDown = value;
      } else if (key === 'postdown') {
        t.postDown = value;
      } else if (key === 'excludedapps') {
        t.excludedApps = value;
      } else if (key === 'jc' || key === 'junkpacketcount') {
        t.awg = true;
        t.jc = num(value, 0);
      } else if (key === 'jmin' || key === 'junkpacketminsize') {
        t.awg = true;
        t.jmin = num(value, 0);
      } else if (key === 'jmax' || key === 'junkpacketmaxsize') {
        t.awg = true;
        t.jmax = num(value, 0);
      } else if (key === 's1' || key === 'initheaderjunksize') {
        t.awg = true;
        t.s1 = num(value, 0);
      } else if (key === 's2' || key === 'responseheaderjunksize') {
        t.awg = true;
        t.s2 = num(value, 0);
      } else if (key === 's3' || key === 'cookiereplyheaderjunksize') {
        t.awg = true;
        t.s3 = num(value, 0);
      } else if (key === 'h1') {
        t.awg = true;
        t.h1 = num(value, 1);
      } else if (key === 'h2') {
        t.awg = true;
        t.h2 = num(value, 2);
      } else if (key === 'h3') {
        t.awg = true;
        t.h3 = num(value, 3);
      } else if (key === 'h4') {
        t.awg = true;
        t.h4 = num(value, 4);
      }
    } else if (peer !== null) {
      if (key === 'publickey') {
        peer.publicKey = value;
        sawPeerKey = true;
      } else if (key === 'presharedkey') {
        peer.presharedKey = value;
      } else if (key === 'endpoint') {
        const parts = splitEndpoint(value);
        peer.host = parts[0];
        peer.port = num(parts[1], 51820);
      } else if (key === 'allowedips') {
        peer.allowedIPs = value.split(',').map((s: string) => s.trim()).join(', ');
      } else if (key === 'persistentkeepalive') {
        peer.keepalive = num(value, 0);
      }
    }
  }
  if (peer !== null) {
    t.peers.push(peer);
  }

  if (!sawPeerKey || !sawPrivateKey || t.peers.length === 0) {
    return null;
  }
  t.name = fallbackName;
  t.id = Date.now().toString();
  return t;
}

/** Serialise back to wg-quick text (used by the share/copy action). */
export function toWgQuick(t: WgTunnel): string {
  const out: string[] = [];
  out.push('[Interface]');
  out.push(`PrivateKey = ${t.privateKey}`);
  if (t.publicKey.length > 0) {
    out.push(`# PublicKey = ${t.publicKey}`);
  }
  out.push(`Address = ${t.address}`);
  if (t.dns.length > 0) {
    out.push(`DNS = ${t.dns}`);
  }
  if (t.mtu !== 1420) {
    out.push(`MTU = ${t.mtu}`);
  }
  if (t.listenPort > 0) {
    out.push(`ListenPort = ${t.listenPort}`);
  }
  if (t.preUp.length > 0) {
    out.push(`PreUp = ${t.preUp}`);
  }
  if (t.postUp.length > 0) {
    out.push(`PostUp = ${t.postUp}`);
  }
  if (t.preDown.length > 0) {
    out.push(`PreDown = ${t.preDown}`);
  }
  if (t.postDown.length > 0) {
    out.push(`PostDown = ${t.postDown}`);
  }
  if (t.excludedApps.length > 0) {
    out.push(`ExcludedApps = ${t.excludedApps}`);
  }
  if (t.awg) {
    out.push(`Jc = ${t.jc}`);
    out.push(`Jmin = ${t.jmin}`);
    out.push(`Jmax = ${t.jmax}`);
    out.push(`S1 = ${t.s1}`);
    out.push(`S2 = ${t.s2}`);
    out.push(`S3 = ${t.s3}`);
    out.push(`H1 = ${t.h1}`);
    out.push(`H2 = ${t.h2}`);
    out.push(`H3 = ${t.h3}`);
    out.push(`H4 = ${t.h4}`);
  }
  for (let i = 0; i < t.peers.length; i++) {
    const p = t.peers[i];
    out.push('');
    out.push('[Peer]');
    out.push(`PublicKey = ${p.publicKey}`);
    if (p.presharedKey.length > 0) {
      out.push(`PresharedKey = ${p.presharedKey}`);
    }
    out.push(`AllowedIPs = ${p.allowedIPs}`);
    out.push(`Endpoint = ${p.endpoint()}`);
    if (p.keepalive > 0) {
      out.push(`PersistentKeepalive = ${p.keepalive}`);
    }
  }
  return out.join('\n');
}

/**
 * Configuration text for a QR code.
 *
 * The built-in `QRCode` component encodes at most 512 characters, so this drops
 * what a parser does not need: the public-key comment, AmneziaWG keys that are
 * zero (absent means the same) and a zero keepalive. The result is still a valid
 * wg-quick document, which is what the scanner on the other device parses.
 */
export function toQrText(t: WgTunnel): string {
  const out: string[] = [];
  out.push('[Interface]');
  out.push(`PrivateKey = ${t.privateKey}`);
  out.push(`Address = ${t.address}`);
  if (t.dns.length > 0) {
    out.push(`DNS = ${t.dns}`);
  }
  if (t.mtu !== 1420) {
    out.push(`MTU = ${t.mtu}`);
  }
  if (t.listenPort > 0) {
    out.push(`ListenPort = ${t.listenPort}`);
  }
  if (t.preUp.length > 0) {
    out.push(`PreUp = ${t.preUp}`);
  }
  if (t.postUp.length > 0) {
    out.push(`PostUp = ${t.postUp}`);
  }
  if (t.preDown.length > 0) {
    out.push(`PreDown = ${t.preDown}`);
  }
  if (t.postDown.length > 0) {
    out.push(`PostDown = ${t.postDown}`);
  }
  if (t.excludedApps.length > 0) {
    out.push(`ExcludedApps = ${t.excludedApps}`);
  }
  if (t.awg) {
    if (t.jc > 0) {
      out.push(`Jc = ${t.jc}`);
    }
    if (t.jmin > 0) {
      out.push(`Jmin = ${t.jmin}`);
    }
    if (t.jmax > 0) {
      out.push(`Jmax = ${t.jmax}`);
    }
    if (t.s1 > 0) {
      out.push(`S1 = ${t.s1}`);
    }
    if (t.s2 > 0) {
      out.push(`S2 = ${t.s2}`);
    }
    if (t.s3 > 0) {
      out.push(`S3 = ${t.s3}`);
    }
    if (t.h1 > 0) {
      out.push(`H1 = ${t.h1}`);
    }
    if (t.h2 > 0) {
      out.push(`H2 = ${t.h2}`);
    }
    if (t.h3 > 0) {
      out.push(`H3 = ${t.h3}`);
    }
    if (t.h4 > 0) {
      out.push(`H4 = ${t.h4}`);
    }
  }
  for (let i = 0; i < t.peers.length; i++) {
    const p = t.peers[i];
    out.push('[Peer]');
    out.push(`PublicKey = ${p.publicKey}`);
    if (p.presharedKey.length > 0) {
      out.push(`PresharedKey = ${p.presharedKey}`);
    }
    out.push(`AllowedIPs = ${p.allowedIPs}`);
    out.push(`Endpoint = ${p.endpoint()}`);
    if (p.keepalive > 0) {
      out.push(`PersistentKeepalive = ${p.keepalive}`);
    }
  }
  return out.join('\n');
}
