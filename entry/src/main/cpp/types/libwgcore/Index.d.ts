/**
 * Type declarations for the native wgcore module (entry/src/main/cpp).
 */

/** WireGuard/AmneziaWG core version string. */
export const version: string;

/** Generate a fresh X25519 key pair; returns {"private":"<b64>","public":"<b64>"}. */
export function generateKeyPair(): string;

/** Derive the base64 public key for a base64 private key (empty string on error). */
export function publicKeyFrom(privateKey: string): string;

/**
 * Configure the engine and open its UDP socket.
 *
 * The JSON is flat because the NDK has no JSON parser:
 * `privateKey`, `mtu`, `peerCount`, then for every peer N (1-based)
 * `peer<N>PublicKey`, `peer<N>PresharedKey`, `peer<N>Host`, `peer<N>Port`,
 * `peer<N>Keepalive`, `peer<N>AllowedIPs` ("10.0.0.0/24, 0.0.0.0/0"),
 * plus the AmneziaWG block `awg`, `h1`..`h4`, `jc`, `jmin`, `jmax`, `s1`..`s3`.
 *
 * @returns 0 when the engine is configured, or a negative error code. The UDP
 * fd is not the return value: read it from `status().udpFd`, which stays -1
 * until the endpoint resolves and the socket exists.
 */
export function open(configJson: string): number;

/** Start the tunnel on a tun fd obtained from VpnConnection.create(). */
export function start(tunFd: number): number;

/** Stop the tunnel and close the UDP socket. */
export function stop(): number;

/**
 * JSON snapshot: state, udpFd, rxBytes, txBytes, rxPackets, txPackets,
 * handshakes, handshakeMs, queueDrops, socketGen, peersUp, lastErrno.
 */
export function status(): string;

/** Newest engine log lines, one per line. */
export function logs(): string;

/** Drop every line the engine log ring holds. */
export function clearLogs(): void;

/** Force a new handshake on the next engine tick. */
export function forceHandshake(): number;

/**
 * Resolves the first peer endpoint, sends one handshake attempt at it and
 * reports the outcome, so the UI can explain a tunnel that never comes up.
 * Returns JSON: { host, port, addresses: string[], reply, handshake, rttMs, error }
 */
export function probe(configJson: string): string;

/**
 * Resolves a host name to its first address (IPv4 bare, IPv6 bracketed), or ""
 * when it does not resolve. Call it before VpnConnection.create(): once the
 * tunnel owns the default route, DNS from this process goes into the tunnel and
 * cannot answer.
 */
export function resolve(host: string): string;
