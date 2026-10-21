/*
 * wg_engine.c — tunnel driver (see wg_engine.h).
 *
 * Threading model: one I/O thread owns the tun fd and the UDP socket and runs
 * everything on them, including the handshake timers of every peer.  Only the
 * status snapshot, the log ring and the "force handshake" flag are touched from
 * other threads (guarded by a mutex).
 *
 * Peer indexing: sender/receiver indices are allocated as (slot << 24) | n, so
 * an incoming packet can be attributed to a peer without a lookup table.  The
 * engine dials up to WG_MAX_PEERS peers over one socket; outbound packets are
 * routed by longest-prefix match over the peers' AllowedIPs.
 */
#include "wg_engine.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "wg_crypto.h"

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET wg_sock_t;
#define WG_BAD_SOCK INVALID_SOCKET
#define wg_close_sock closesocket
#define wg_sock_errno WSAGetLastError()
#else
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int wg_sock_t;
#define WG_BAD_SOCK (-1)
#define wg_close_sock close
#define wg_sock_errno errno
#endif

/* WireGuard timer constants (wireguard-go timers.go). */
#define WG_REKEY_AFTER_MS 120000ULL
#define WG_REJECT_AFTER_MS 180000ULL
#define WG_REKEY_TIMEOUT_MS 5000ULL
#define WG_KEEPALIVE_TIMEOUT_MS 10000ULL
#define WG_MAX_HANDSHAKE_ATTEMPTS 18
#define WG_RETRY_BACKOFF_MS 30000ULL
#define WG_SOCKET_RETRY_MS 2000ULL
#define WG_TICK_MS 100
#define WG_QUEUE_LEN 32
#define WG_JUNK_LEN 8

/* Log ring: newest WG_LOG_LINES entries, kept for the diagnostics screen. */
#define WG_LOG_LINES 80
#define WG_LOG_TEXT 120

typedef struct {
    wg_peer peer;
    wg_peer_config cfg;
    struct sockaddr_storage addr;
    socklen_t addr_len;
    int resolved;
    uint16_t keepalive;
    uint32_t hs_attempts;
    uint64_t next_handshake_ms;
    uint64_t handshake_ms;
    uint32_t handshakes;
    int send_fail_streak;
    int backing_off;
} engine_peer;

typedef struct {
    engine_peer peers[WG_MAX_PEERS];
    uint32_t peer_count;
    wg_sock_t tun_fd;
    wg_sock_t udp_fd;
    int running;
    int forced;
    uint16_t mtu;

    wg_engine_state state;
    uint64_t started_ms;
    uint64_t last_error_ms;
    int last_errno;
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t rx_packets;
    uint64_t tx_packets;
    uint32_t queue_drops;
    uint32_t sock_gen;
    uint32_t peers_up;
    uint64_t next_socket_retry_ms;

    uint8_t *queue[WG_QUEUE_LEN];
    size_t qlen[WG_QUEUE_LEN];
    uint8_t qpeer[WG_QUEUE_LEN];
    int qhead;
    int qcount;

    char log[WG_LOG_LINES][WG_LOG_TEXT];
    uint32_t log_head;  /* next slot to write */
    uint32_t log_count; /* number of valid slots */

#if defined(_WIN32)
    HANDLE thread;
    CRITICAL_SECTION lock;
#else
    pthread_t thread;
    pthread_mutex_t lock;
#endif
} wg_engine_ctx;

static wg_engine_ctx g_eng;
static int g_engine_used;

static void lock_init(void);
static void lock_take(void);
static void lock_give(void);

static uint64_t now_ms(void)
{
#if defined(_WIN32)
    return (uint64_t)GetTickCount64();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
#endif
}

static void engine_log(const char *fmt, ...)
{
    va_list ap;
    uint32_t slot;
    int n;

    lock_take();
    slot = g_eng.log_head;
    n = snprintf(g_eng.log[slot], WG_LOG_TEXT, "%llu ", (unsigned long long)now_ms());
    if (n < 0) {
        n = 0;
    }
    if (n < WG_LOG_TEXT) {
        va_start(ap, fmt);
        vsnprintf(g_eng.log[slot] + n, (size_t)(WG_LOG_TEXT - n), fmt, ap);
        va_end(ap);
    }
    g_eng.log_head = (slot + 1) % WG_LOG_LINES;
    if (g_eng.log_count < WG_LOG_LINES) {
        g_eng.log_count++;
    }
    lock_give();
}

size_t wg_engine_logs(char *out, size_t cap, uint32_t max_lines)
{
    size_t used = 0;
    uint32_t total;
    uint32_t first;
    uint32_t i;

    if (out == NULL || cap == 0) {
        return 0;
    }
    out[0] = '\0';
    if (!g_engine_used) {
        return 0;
    }
    lock_take();
    total = g_eng.log_count;
    if (max_lines > 0 && total > max_lines) {
        total = max_lines;
    }
    first = (g_eng.log_head + WG_LOG_LINES - g_eng.log_count) % WG_LOG_LINES;
    if (g_eng.log_count > total) {
        first = (first + (g_eng.log_count - total)) % WG_LOG_LINES;
    }
    for (i = 0; i < total; i++) {
        const char *line = g_eng.log[(first + i) % WG_LOG_LINES];
        size_t len = strlen(line);
        if (used + len + 2 > cap) {
            break;
        }
        memcpy(out + used, line, len);
        used += len;
        out[used++] = '\n';
        out[used] = '\0';
    }
    lock_give();
    return used;
}

void wg_engine_clear_logs(void)
{
    if (!g_engine_used) {
        return;
    }
    lock_take();
    g_eng.log_head = 0;
    g_eng.log_count = 0;
    lock_give();
}

static void lock_init(void)
{
#if defined(_WIN32)
    InitializeCriticalSection(&g_eng.lock);
#else
    pthread_mutex_init(&g_eng.lock, NULL);
#endif
}

static void lock_take(void)
{
#if defined(_WIN32)
    EnterCriticalSection(&g_eng.lock);
#else
    pthread_mutex_lock(&g_eng.lock);
#endif
}

static void lock_give(void)
{
#if defined(_WIN32)
    LeaveCriticalSection(&g_eng.lock);
#else
    pthread_mutex_unlock(&g_eng.lock);
#endif
}

static void engine_set_state(wg_engine_state state)
{
    g_eng.state = state;
}

/* ---- socket helpers ---------------------------------------------------- */

static long tun_read(void *buf, size_t len)
{
#if defined(_WIN32)
    return (long)recv(g_eng.tun_fd, (char *)buf, (int)len, 0);
#else
    return (long)read((int)g_eng.tun_fd, buf, len);
#endif
}

static long tun_write(const void *buf, size_t len)
{
#if defined(_WIN32)
    return (long)send(g_eng.tun_fd, (const char *)buf, (int)len, 0);
#else
    return (long)write((int)g_eng.tun_fd, buf, len);
#endif
}

/* Resolve one peer endpoint into peer->addr.  Returns 0 on success. */
static int resolve_peer(engine_peer *p)
{
    struct addrinfo hints;
    struct addrinfo *res = NULL;
    char portbuf[8];

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    snprintf(portbuf, sizeof(portbuf), "%u", (unsigned)p->cfg.port);
    if (getaddrinfo(p->cfg.host, portbuf, &hints, &res) != 0 || res == NULL) {
        return -1;
    }
    if (res->ai_addrlen > (socklen_t)sizeof(p->addr)) {
        freeaddrinfo(res);
        return -1;
    }
    memcpy(&p->addr, res->ai_addr, (size_t)res->ai_addrlen);
    p->addr_len = (socklen_t)res->ai_addrlen;
    p->resolved = 1;
    freeaddrinfo(res);
    return 0;
}

/* Open a datagram socket matching the family of `p`. */
static wg_sock_t udp_open_for(const engine_peer *p)
{
    int family = AF_INET;
    wg_sock_t fd;

    if (p->addr.ss_family == AF_INET6) {
        family = AF_INET6;
    }
    fd = (wg_sock_t)socket(family, SOCK_DGRAM, 0);
    return fd;
}

/* Send to the endpoint of peer `slot`. */
static int udp_send_to(uint32_t slot, const uint8_t *buf, size_t len)
{
    engine_peer *p;
    long n;

    if (g_eng.udp_fd == WG_BAD_SOCK || slot >= g_eng.peer_count) {
        return -1;
    }
    p = &g_eng.peers[slot];
    if (!p->resolved) {
        return -1;
    }
    n = (long)sendto(g_eng.udp_fd, (const char *)buf, (int)len, 0,
                     (const struct sockaddr *)&p->addr, p->addr_len);
    if (n < 0) {
        g_eng.last_errno = wg_sock_errno;
        g_eng.last_error_ms = now_ms();
        p->send_fail_streak++;
        return -1;
    }
    p->send_fail_streak = 0;
    return 0;
}

/*
 * The socket is bound to the address family that was resolved when the tunnel
 * came up.  After a Wi-Fi/cellular handover that binding is dead, so every peer
 * is resolved again and the socket replaced.  The caller (the VPN extension)
 * notices the new fd through the status snapshot and protects it.
 */
static void recycle_socket(void)
{
    wg_sock_t fresh = WG_BAD_SOCK;
    uint32_t i;

    for (i = 0; i < g_eng.peer_count; i++) {
        g_eng.peers[i].resolved = 0;
        if (resolve_peer(&g_eng.peers[i]) == 0 && fresh == WG_BAD_SOCK) {
            fresh = udp_open_for(&g_eng.peers[i]);
        }
    }
    if (fresh == WG_BAD_SOCK) {
        /*
         * A handover can happen while DNS is unavailable, and a name that
         * resolved a minute ago may not resolve now.  Hand the tunnel back to
         * the retry branch in engine_tick() instead of leaving the stale fd in
         * place: that branch only runs while udp_fd is bad, and udp_send_to()
         * cannot build a failure streak for a peer that has no address, so a
         * kept fd here would leave every peer unresolved with no timer left to
         * notice - a dead tunnel until the process restarts.
         */
        if (g_eng.udp_fd != WG_BAD_SOCK) {
            wg_close_sock(g_eng.udp_fd);
            g_eng.udp_fd = WG_BAD_SOCK;
        }
        g_eng.next_socket_retry_ms = now_ms() + WG_SOCKET_RETRY_MS;
        engine_log("recycle failed: no endpoint resolved, retrying in %us",
                   (unsigned)(WG_SOCKET_RETRY_MS / 1000));
        return;
    }
    if (g_eng.udp_fd != WG_BAD_SOCK) {
        wg_close_sock(g_eng.udp_fd);
    }
    g_eng.udp_fd = fresh;
    g_eng.sock_gen++;
    for (i = 0; i < g_eng.peer_count; i++) {
        g_eng.peers[i].next_handshake_ms = now_ms();
        g_eng.peers[i].hs_attempts = 0;
        g_eng.peers[i].send_fail_streak = 0;
    }
    engine_set_state(WG_STATE_CONNECTING);
    engine_log("socket recreated (gen %u)", g_eng.sock_gen);
}

/* ---- handshake -------------------------------------------------------- */

static uint32_t fresh_index(uint32_t slot)
{
    uint8_t b[4];
    uint32_t v;
    wg_random_bytes(b, sizeof(b));
    memcpy(&v, b, 4);
    v &= 0x00FFFFFFu;
    if (v == 0) {
        v = 1;
    }
    return (slot << 24) | v;
}

static void send_junk(uint32_t slot)
{
    uint8_t *junks[WG_JUNK_LEN];
    size_t caps[WG_JUNK_LEN];
    uint8_t storage[WG_JUNK_LEN][96];
    engine_peer *p = &g_eng.peers[slot];
    int n;
    int i;

    if (!p->peer.awg.enabled || p->peer.awg.jc == 0) {
        return;
    }
    for (i = 0; i < WG_JUNK_LEN; i++) {
        junks[i] = storage[i];
        caps[i] = sizeof(storage[i]);
    }
    n = wg_awg_junk_packets(&p->peer.awg, junks, caps, WG_JUNK_LEN);
    for (i = 0; i < n; i++) {
        (void)udp_send_to(slot, junks[i], caps[i]);
    }
}

static void send_handshake_initiation(uint32_t slot, uint64_t now)
{
    uint8_t out[WG_MAX_PACKET];
    size_t outlen = 0;
    uint32_t index = fresh_index(slot);
    engine_peer *p = &g_eng.peers[slot];

    send_junk(slot);
    if (wg_handshake_create_initiation(&p->peer, index, out, sizeof(out), &outlen, now) != 0) {
        return;
    }
    if (udp_send_to(slot, out, outlen) != 0) {
        engine_log("peer %u: initiation send failed (%d)", (unsigned)slot, g_eng.last_errno);
    }
    p->hs_attempts++;
    p->next_handshake_ms = now + WG_REKEY_TIMEOUT_MS;
    if (g_eng.state != WG_STATE_UP) {
        engine_set_state(WG_STATE_CONNECTING);
    }
}

static void send_keepalive(uint32_t slot, uint64_t now)
{
    uint8_t out[WG_MAX_PACKET];
    size_t outlen = 0;
    engine_peer *p = &g_eng.peers[slot];

    if (wg_transport_encrypt(&p->peer, NULL, 0, out, sizeof(out), &outlen, now) == 0) {
        (void)udp_send_to(slot, out, outlen);
    }
}

/* ---- routing ---------------------------------------------------------- */

static int allowed_match(const wg_allowed *a, int family, const uint8_t *addr)
{
    int bits = (int)a->bits;
    int i;

    if ((int)a->family != family) {
        return -1;
    }
    if (bits == 0) {
        return 0;
    }
    if (family == 4) {
        if (bits > 32) {
            return -1;
        }
        for (i = 0; i < bits / 8; i++) {
            if (a->addr[i] != addr[i]) {
                return -1;
            }
        }
        if (bits % 8 != 0) {
            uint8_t mask = (uint8_t)(0xFF << (8 - (bits % 8)));
            if ((a->addr[bits / 8] & mask) != (addr[bits / 8] & mask)) {
                return -1;
            }
        }
        return bits;
    }
    /* IPv6: only the default route is honoured. */
    if (bits > 128) {
        return -1;
    }
    for (i = 0; i < bits / 8; i++) {
        if (a->addr[i] != addr[i]) {
            return -1;
        }
    }
    return bits;
}

/* Longest-prefix match of an inner IP packet over every peer's AllowedIPs. */
static int route_peer(const uint8_t *ip, size_t len)
{
    int family;
    const uint8_t *dst;
    int best = -1;
    int best_bits = -1;
    uint32_t i;
    uint32_t j;

    if (len < 20) {
        return 0;
    }
    if ((ip[0] >> 4) == 4) {
        family = 4;
        dst = ip + 16;
    } else if ((ip[0] >> 4) == 6 && len >= 40) {
        family = 6;
        dst = ip + 24;
    } else {
        return 0;
    }
    for (i = 0; i < g_eng.peer_count; i++) {
        const engine_peer *p = &g_eng.peers[i];
        for (j = 0; j < p->cfg.allowed_count; j++) {
            int bits = allowed_match(&p->cfg.allowed[j], family, dst);
            if (bits > best_bits) {
                best_bits = bits;
                best = (int)i;
            }
        }
    }
    return best < 0 ? 0 : best;
}

/* ---- data path -------------------------------------------------------- */

static void flush_queue(uint64_t now)
{
    int kept = 0;
    int i;

    for (i = 0; i < g_eng.qcount; i++) {
        int slot = (g_eng.qhead + i) % WG_QUEUE_LEN;
        uint32_t target = g_eng.qpeer[slot];
        uint8_t out[WG_MAX_PACKET];
        size_t outlen = 0;

        if (target < g_eng.peer_count &&
            wg_transport_encrypt(&g_eng.peers[target].peer, g_eng.queue[slot], g_eng.qlen[slot],
                                 out, sizeof(out), &outlen, now) == 0) {
            if (udp_send_to(target, out, outlen) == 0) {
                continue; /* consumed */
            }
        }
        /* keep this packet for later, preserving order */
        {
            int dst = (g_eng.qhead + kept) % WG_QUEUE_LEN;
            if (dst != slot) {
                memcpy(g_eng.queue[dst], g_eng.queue[slot], g_eng.qlen[slot]);
                g_eng.qlen[dst] = g_eng.qlen[slot];
                g_eng.qpeer[dst] = g_eng.qpeer[slot];
            }
            kept++;
        }
    }
    g_eng.qcount = kept;
}

static void on_tun_read(const uint8_t *buf, size_t len, uint64_t now)
{
    uint8_t out[WG_MAX_PACKET];
    size_t outlen = 0;
    int slot;

    if (len == 0 || len > WG_MAX_PACKET) {
        return;
    }
    slot = route_peer(buf, len);
    if (slot < 0 || slot >= (int)g_eng.peer_count) {
        slot = 0;
    }
    if (!wg_peer_session_usable(&g_eng.peers[slot].peer, now)) {
        if (g_eng.qcount < WG_QUEUE_LEN) {
            int pos = (g_eng.qhead + g_eng.qcount) % WG_QUEUE_LEN;
            memcpy(g_eng.queue[pos], buf, len);
            g_eng.qlen[pos] = len;
            g_eng.qpeer[pos] = (uint8_t)slot;
            g_eng.qcount++;
            g_eng.tx_packets++;
            g_eng.tx_bytes += len;
        } else {
            g_eng.queue_drops++;
        }
        if (g_eng.peers[slot].next_handshake_ms > now) {
            g_eng.peers[slot].next_handshake_ms = now; /* handshake is overdue */
        }
        return;
    }
    if (wg_transport_encrypt(&g_eng.peers[slot].peer, buf, len, out, sizeof(out), &outlen, now) != 0) {
        return;
    }
    (void)udp_send_to((uint32_t)slot, out, outlen);
    /*
     * A packet read from the tun device is one this device is sending to the
     * peer, so it counts as transmitted. The counters used to be the other way
     * round here, which made every screen show the two directions swapped
     * (the peer's traffic appeared as upload and vice versa).
     */
    g_eng.tx_packets++;
    g_eng.tx_bytes += len;
}

/* Strip WireGuard's zero padding using the inner IP header. */
static size_t trim_ip_packet(const uint8_t *p, size_t len)
{
    size_t want;

    if (len < 20) {
        return 0;
    }
    if ((p[0] >> 4) == 4) {
        want = ((size_t)p[2] << 8) | p[3];
        if (want < 20 || want > len) {
            return 0;
        }
        return want;
    }
    if ((p[0] >> 4) == 6) {
        if (len < 40) {
            return 0;
        }
        want = 40 + (((size_t)p[4] << 8) | p[5]);
        if (want > len || want < 40) {
            return 0;
        }
        return want;
    }
    return 0;
}

/* WireGuard message fields are little-endian on the wire. */
static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/*
 * Attribute an incoming datagram to a peer using the receiver index it carries.
 * Returns the peer slot, -2 for an initiation (which carries only a sender
 * index), or -1 when the datagram cannot belong to a configured peer.
 *
 * AmneziaWG prefixes the handshake messages with junk, so the message type and
 * the receiver index are shifted by S1/S2/S3 for those types.
 */
static int packet_peer(const uint8_t *buf, size_t len)
{
    const wg_awg_params *awg = &g_eng.peers[0].peer.awg;
    size_t s1 = awg->enabled ? (size_t)awg->s1 : 0;
    size_t s2 = awg->enabled ? (size_t)awg->s2 : 0;
    size_t s3 = awg->enabled ? (size_t)awg->s3 : 0;
    uint32_t idx;
    uint32_t slot;

    if (len >= 8 && le32(buf) == awg->type_transport) {
        idx = le32(buf + 4);
    } else if (len >= 12 + s2 && le32(buf + s2) == awg->type_response) {
        idx = le32(buf + 8 + s2);
    } else if (len >= 8 + s3 && le32(buf + s3) == awg->type_cookie) {
        idx = le32(buf + 4 + s3);
    } else if (len >= 4 + s1 && le32(buf + s1) == awg->type_init) {
        return -2;
    } else {
        return -1;
    }
    slot = idx >> 24;
    return slot < g_eng.peer_count ? (int)slot : -1;
}

/* Match an unauthenticated initiation to the peer whose endpoint sent it. */
static int peer_from_source(const struct sockaddr_storage *from)
{
    uint32_t i;

    if (from == NULL) {
        return 0;
    }
    for (i = 0; i < g_eng.peer_count; i++) {
        const engine_peer *p = &g_eng.peers[i];
        if (!p->resolved || p->addr.ss_family != from->ss_family) {
            continue;
        }
        if (p->addr_len > 0 && memcmp(&p->addr, from, (size_t)p->addr_len) == 0) {
            return (int)i;
        }
    }
    return 0;
}

static void on_udp_read(const uint8_t *buf, size_t len, const struct sockaddr_storage *from,
                        uint64_t now)
{
    uint8_t out[WG_MAX_PACKET];
    size_t outlen = 0;
    wg_rx_kind kind;
    int slot = packet_peer(buf, len);
#if defined(WG_DEBUG)
    fprintf(stderr, "rx len=%u type=%u slot=%d\n", (unsigned)len, len >= 4 ? (unsigned)le32(buf) : 0u, slot);
#endif

    if (slot == -2) {
        slot = peer_from_source(from);
    } else if (slot < 0) {
        return; /* unknown session */
    }
    {
        engine_peer *p = &g_eng.peers[slot];
        kind = wg_handshake_consume(&p->peer, buf, len, now, out, sizeof(out), &outlen);
        switch (kind) {
        case WG_RX_TRANSPORT: {
            size_t plen = trim_ip_packet(out, outlen);
            if (plen > 0 && g_eng.tun_fd != WG_BAD_SOCK) {
                if (tun_write(out, plen) > 0) {
                    /* Written to the tun device: this is the peer's traffic
                     * arriving, i.e. what the user calls received. */
                    g_eng.rx_packets++;
                    g_eng.rx_bytes += plen;
                }
            }
            break;
        }
        case WG_RX_KEEPALIVE:
            break;
        case WG_RX_RESPONSE:
            p->hs_attempts = 0;
            p->backing_off = 0;
            p->next_handshake_ms = now + WG_REKEY_AFTER_MS;
            p->handshake_ms = now;
            p->handshakes++;
            flush_queue(now);
            engine_log("peer %d: session established", slot);
            engine_set_state(WG_STATE_UP);
            break;
        case WG_RX_INITIATION:
        case WG_RX_COOKIE:
        case WG_RX_NONE:
        case WG_RX_ERROR:
        default:
            break;
        }
    }
}

/* ---- timers ----------------------------------------------------------- */

static int peer_usable(uint32_t slot, uint64_t now)
{
    return wg_peer_session_usable(&g_eng.peers[slot].peer, now);
}

static void engine_tick(uint64_t now)
{
    uint32_t up = 0;
    uint32_t i;
    int backoff = 0;

    if (g_eng.udp_fd == WG_BAD_SOCK) {
        if (now < g_eng.next_socket_retry_ms) {
            return;
        }
        recycle_socket();
        if (g_eng.udp_fd == WG_BAD_SOCK) {
            g_eng.next_socket_retry_ms = now + WG_SOCKET_RETRY_MS;
            return;
        }
    }

    if (g_eng.forced) {
        g_eng.forced = 0;
        for (i = 0; i < g_eng.peer_count; i++) {
            g_eng.peers[i].next_handshake_ms = now;
            g_eng.peers[i].hs_attempts = 0;
            g_eng.peers[i].backing_off = 0;
        }
    }

    for (i = 0; i < g_eng.peer_count; i++) {
        engine_peer *p = &g_eng.peers[i];
        int usable = peer_usable(i, now);

        if (!usable && p->send_fail_streak >= 6) {
            recycle_socket();
            return;
        }
        if (!usable) {
            if (now >= p->next_handshake_ms) {
                if (p->hs_attempts >= WG_MAX_HANDSHAKE_ATTEMPTS) {
                    p->hs_attempts = 0;
                    p->backing_off = 1;
                    p->next_handshake_ms = now + WG_RETRY_BACKOFF_MS;
                    engine_log("peer %u: handshake gave up, retrying in %us", (unsigned)i,
                               (unsigned)(WG_RETRY_BACKOFF_MS / 1000));
                } else {
                    send_handshake_initiation(i, now);
                }
            }
            if (p->backing_off) {
                backoff = 1;
            }
            continue;
        }
        up++;
        /*
         * `usable` above already bounds the session age, so the keepalive needs
         * no second age guard - and the one that used to sit here compared
         * `now - last_send_ms` against WG_REJECT_AFTER_MS, which silenced the
         * keepalive completely: last_send_ms is 0 until the first transport
         * packet, while `now` is the monotonic clock since boot, so on any
         * device up for more than 180 s an idle tunnel never sent a keepalive
         * and only the rekey handshake refreshed its NAT binding.
         * tools/keepalive_probe.c is the regression test for this.
         */
        if (p->keepalive > 0 &&
            now - p->peer.last_send_ms >= (uint64_t)p->keepalive * 1000ULL) {
            send_keepalive(i, now);
            p->peer.last_send_ms = now;
        }
        if (p->peer.curr.is_initiator &&
            wg_peer_session_age_ms(&p->peer, now) > WG_REKEY_AFTER_MS &&
            p->next_handshake_ms <= now && p->hs_attempts == 0) {
            send_handshake_initiation(i, now);
        }
    }

    g_eng.peers_up = up;
    if (up == g_eng.peer_count && g_eng.peer_count > 0) {
        if (g_eng.state != WG_STATE_UP) {
            engine_set_state(WG_STATE_UP);
            flush_queue(now);
        }
    } else if (up > 0) {
        engine_set_state(WG_STATE_RETRY);
    } else {
        engine_set_state(backoff ? WG_STATE_RETRY : WG_STATE_CONNECTING);
    }
}

/* ---- I/O loop --------------------------------------------------------- */

static void handle_io(int ready, uint64_t now)
{
    uint8_t buf[WG_MAX_PACKET];
    long n;

    /* tun -> udp */
    if ((ready & 1) != 0) {
        n = tun_read(buf, sizeof(buf));
        if (n > 0) {
            on_tun_read(buf, (size_t)n, now);
        }
    }

    /* udp -> tun */
    if ((ready & 2) != 0) {
        struct sockaddr_storage from;
        socklen_t fromlen = (socklen_t)sizeof(from);

        memset(&from, 0, sizeof(from));
        n = (long)recvfrom(g_eng.udp_fd, (char *)buf, (int)sizeof(buf), 0,
                           (struct sockaddr *)&from, &fromlen);
        if (n > 0) {
            on_udp_read(buf, (size_t)n, &from, now);
        }
    }
}

static int wait_io(int timeout_ms)
{
#if defined(_WIN32)
    WSAPOLLFD fds[2];
    int rc;
    fds[0].fd = (SOCKET)g_eng.tun_fd;
    fds[0].events = POLLIN;
    fds[0].revents = 0;
    fds[1].fd = (SOCKET)g_eng.udp_fd;
    fds[1].events = POLLIN;
    fds[1].revents = 0;
    rc = WSAPoll(fds, 2, timeout_ms);
    if (rc < 0) {
        return -1;
    }
    return ((fds[0].revents & POLLIN) ? 1 : 0) | ((fds[1].revents & POLLIN) ? 2 : 0);
#else
    struct pollfd fds[2];
    int rc;
    fds[0].fd = (int)g_eng.tun_fd;
    fds[0].events = POLLIN;
    fds[0].revents = 0;
    fds[1].fd = (int)g_eng.udp_fd;
    fds[1].events = POLLIN;
    fds[1].revents = 0;
    rc = poll(fds, 2, timeout_ms);
    if (rc < 0) {
        return -1;
    }
    return ((fds[0].revents & POLLIN) ? 1 : 0) | ((fds[1].revents & POLLIN) ? 2 : 0);
#endif
}

static void *engine_main(void *arg)
{
    (void)arg;
    while (g_eng.running) {
        int ready = wait_io(WG_TICK_MS);
        uint64_t now = now_ms();
        if (ready < 0) {
            engine_log("poll failed (%d)", wg_sock_errno);
            break;
        }
        if (ready > 0) {
            handle_io(ready, now);
        }
        engine_tick(now_ms());
    }
    engine_set_state(WG_STATE_STOPPED);
    return NULL;
}

/* ---- public API ------------------------------------------------------- */

int wg_engine_open(const wg_engine_config *config)
{
    uint32_t i;

    if (config == NULL || config->peer_count == 0 || config->peer_count > WG_MAX_PEERS) {
        return -1;
    }
    if (g_engine_used) {
        wg_engine_stop();
    }
    memset(&g_eng, 0, sizeof(g_eng));
    g_eng.tun_fd = WG_BAD_SOCK;
    g_eng.udp_fd = WG_BAD_SOCK;
    g_eng.mtu = config->mtu;
    g_eng.peer_count = config->peer_count;
    lock_init();
    g_engine_used = 1;

    for (i = 0; i < WG_QUEUE_LEN; i++) {
        g_eng.queue[i] = (uint8_t *)malloc(WG_MAX_PACKET);
        if (g_eng.queue[i] == NULL) {
            return -1;
        }
    }

    for (i = 0; i < config->peer_count; i++) {
        engine_peer *p = &g_eng.peers[i];
        p->cfg = config->peers[i];
        p->keepalive = config->peers[i].keepalive;
        wg_peer_init(&p->peer, config->static_priv, p->cfg.public_key, p->cfg.psk, &config->awg);
        if (resolve_peer(p) != 0) {
            engine_log("peer %u: cannot resolve %s", (unsigned)i, p->cfg.host);
        }
    }

    for (i = 0; i < g_eng.peer_count; i++) {
        if (g_eng.peers[i].resolved) {
            g_eng.udp_fd = udp_open_for(&g_eng.peers[i]);
            if (g_eng.udp_fd != WG_BAD_SOCK) {
                break;
            }
        }
    }
    if (g_eng.udp_fd == WG_BAD_SOCK) {
        /*
         * A phone that is still bringing its network up - and a VPN that has
         * just taken over DNS - may fail to resolve or open the socket once.
         * Tearing the tunnel down here is exactly what makes the status bar icon
         * appear and vanish a second later, so stay in the connecting state and
         * let the tick retry instead.
         */
        g_eng.last_errno = wg_sock_errno;
        g_eng.started_ms = now_ms();
        g_eng.next_socket_retry_ms = now_ms() + WG_SOCKET_RETRY_MS;
        engine_set_state(WG_STATE_CONNECTING);
        engine_log("no endpoint yet, retrying");
        return 0;
    }
    /*
     * A single datagram socket has one address family.  Peers that resolved to
     * the other family would need their own socket, so they are reported and
     * skipped rather than silently sending nowhere.
     */
    {
        int sock_family = 0;
        for (i = 0; i < g_eng.peer_count; i++) {
            if (g_eng.peers[i].resolved) {
                sock_family = g_eng.peers[i].addr.ss_family;
                break;
            }
        }
        for (i = 0; i < g_eng.peer_count; i++) {
            engine_peer *p = &g_eng.peers[i];
            if (p->resolved && p->addr.ss_family != sock_family) {
                engine_log("peer %u: address family differs from the socket", (unsigned)i);
                p->resolved = 0;
            }
        }
    }
    g_eng.started_ms = now_ms();
    engine_set_state(WG_STATE_CONNECTING);
    engine_log("engine open: %u peer(s), fd %d", (unsigned)g_eng.peer_count, (int)g_eng.udp_fd);
    return (int)g_eng.udp_fd;
}

int wg_engine_start(int tun_fd)
{
    uint32_t i;

    g_eng.tun_fd = (wg_sock_t)tun_fd;
    g_eng.running = 1;
    g_eng.started_ms = now_ms();
    for (i = 0; i < g_eng.peer_count; i++) {
        g_eng.peers[i].next_handshake_ms = g_eng.started_ms;
    }
    engine_log("engine start: tun %d", tun_fd);
#if defined(_WIN32)
    g_eng.thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)engine_main, NULL, 0, NULL);
    if (g_eng.thread == NULL) {
        g_eng.running = 0;
        return -1;
    }
#else
    if (pthread_create(&g_eng.thread, NULL, engine_main, NULL) != 0) {
        g_eng.running = 0;
        return -1;
    }
#endif
    return 0;
}

void wg_engine_stop(void)
{
    if (!g_engine_used) {
        return;
    }
    g_eng.running = 0;
#if defined(_WIN32)
    if (g_eng.thread) {
        WaitForSingleObject(g_eng.thread, 2000);
        CloseHandle(g_eng.thread);
        g_eng.thread = NULL;
    }
    if (g_eng.udp_fd != WG_BAD_SOCK) {
        wg_close_sock(g_eng.udp_fd);
        g_eng.udp_fd = WG_BAD_SOCK;
    }
    DeleteCriticalSection(&g_eng.lock);
#else
    if (g_eng.thread) {
        pthread_join(g_eng.thread, NULL);
        g_eng.thread = 0;
    }
    if (g_eng.udp_fd != WG_BAD_SOCK) {
        wg_close_sock(g_eng.udp_fd);
        g_eng.udp_fd = WG_BAD_SOCK;
    }
    pthread_mutex_destroy(&g_eng.lock);
#endif
    g_engine_used = 0;
    engine_set_state(WG_STATE_STOPPED);
}

void wg_engine_force_handshake(void)
{
    g_eng.forced = 1;
}

void wg_engine_info_snapshot(wg_engine_info *out)
{
    uint32_t i;
    uint32_t handshakes = 0;
    uint64_t handshake_ms = 0;
    uint64_t rx_bytes = 0;
    uint64_t tx_bytes = 0;
    uint64_t rx_packets = 0;
    uint64_t tx_packets = 0;

    if (out == NULL) {
        return;
    }
    lock_take();
    for (i = 0; i < g_eng.peer_count; i++) {
        handshakes += g_eng.peers[i].handshakes;
        if (g_eng.peers[i].handshake_ms > handshake_ms) {
            handshake_ms = g_eng.peers[i].handshake_ms;
        }
    }
    rx_bytes = g_eng.rx_bytes;
    tx_bytes = g_eng.tx_bytes;
    rx_packets = g_eng.rx_packets;
    tx_packets = g_eng.tx_packets;
    out->state = g_eng.state;
    out->udp_fd = (int)g_eng.udp_fd;
    out->rx_bytes = rx_bytes;
    out->tx_bytes = tx_bytes;
    out->rx_packets = rx_packets;
    out->tx_packets = tx_packets;
    out->handshake_ms = handshake_ms;
    out->started_ms = g_eng.started_ms;
    out->last_error_ms = g_eng.last_error_ms;
    out->last_errno = g_eng.last_errno;
    out->handshakes = handshakes;
    out->queue_drops = g_eng.queue_drops;
    out->socket_gen = g_eng.sock_gen;
    out->peers_up = g_eng.peers_up;
    lock_give();
}
