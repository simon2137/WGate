/*
 * keepalive_probe.c — focused host probe for the persistent-keepalive path.
 *
 * enginetest.c always writes a data packet before it checks for a keepalive,
 * and that write sets peer->last_send_ms through wg_transport_encrypt(). On a
 * machine whose monotonic clock already exceeds WG_REJECT_AFTER_MS (180 s
 * after boot, i.e. every real phone), the keepalive condition in engine_tick()
 *
 *     now - last_send_ms >= keepalive * 1000
 *     now - last_send_ms <  WG_REJECT_AFTER_MS
 *
 * therefore depends on that accidental write, not on the session age it is
 * meant to bound. This probe brings a session up with no traffic at all and
 * asks one question twice:
 *
 *   phase 1  idle from the handshake on       -> keepalive expected within 4 s
 *   phase 2  one data packet, then idle       -> keepalive expected within 4 s
 *   scenario B  a name that never resolves    -> the socket retry keeps
 *               re-arming and udp_fd stays bad
 *
 * Scenario B covers the other half of the same question. recycle_socket() can
 * fail long after a healthy socket existed - a handover while DNS is away. If
 * it keeps the old fd, engine_tick() never retries (its retry branch only runs
 * while udp_fd is bad) and udp_send_to() cannot grow a failure streak for a
 * peer that has no address, so the tunnel stays dead until the process
 * restarts. The check is that the resolver failure is logged again and again.
 *
 * A phase-1 silence with a phase-2 keepalive is the defect: the tunnel only
 * refreshes its NAT binding after the user happens to send something, so an
 * idle tunnel falls back to one rekey handshake per WG_REKEY_AFTER_MS.
 *
 *   zig cc -std=c11 -O2 -I entry/src/main/cpp/wg \
 *       -I entry/src/main/cpp/wg/third_party -o build/keepalive_probe.exe \
 *       tools/keepalive_probe.c entry/src/main/cpp/wg/wg_proto.c \
 *       entry/src/main/cpp/wg/wg_crypto.c entry/src/main/cpp/wg/wg_blake2s.c \
 *       entry/src/main/cpp/wg/third_party/monocypher.c \
 *       entry/src/main/cpp/wg/wg_engine.c -lws2_32
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "wg_crypto.h"
#include "wg_engine.h"
#include "wg_proto.h"

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET sock_t;
#define BAD_SOCK INVALID_SOCKET
#define close_sock closesocket
#define sleep_ms(ms) Sleep(ms)
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int sock_t;
#define BAD_SOCK (-1)
#define close_sock close
#define sleep_ms(ms) usleep((ms) * 1000)
#endif

static uint64_t ms_now(void)
{
#if defined(_WIN32)
    return (uint64_t)GetTickCount64();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
#endif
}

/* ---- tun stand-in: two connected UDP sockets on loopback ------------------ */

typedef struct {
    sock_t a;
    sock_t b;
} tun_pair;

static int make_tun_pair(tun_pair *tp)
{
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    int one = 1;

    tp->a = socket(AF_INET, SOCK_DGRAM, 0);
    tp->b = socket(AF_INET, SOCK_DGRAM, 0);
    if (tp->a == BAD_SOCK || tp->b == BAD_SOCK) {
        return -1;
    }
#if defined(_WIN32)
    setsockopt(tp->a, SOL_SOCKET, SO_REUSEADDR, (const char *)&one, sizeof(one));
    setsockopt(tp->b, SOL_SOCKET, SO_REUSEADDR, (const char *)&one, sizeof(one));
#else
    setsockopt(tp->a, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(tp->b, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#endif
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (bind(tp->a, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    if (bind(tp->b, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    if (getsockname(tp->a, (struct sockaddr *)&addr, &alen) != 0) return -1;
    if (connect(tp->b, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    if (getsockname(tp->b, (struct sockaddr *)&addr, &alen) != 0) return -1;
    if (connect(tp->a, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    return 0;
}

static size_t make_icmp_echo(uint8_t *p)
{
    memset(p, 0, 44);
    p[0] = 0x45;
    p[3] = 44;
    p[8] = 64;
    p[9] = 1;
    p[12] = 10; p[13] = 0; p[14] = 0; p[15] = 2;
    p[16] = 8; p[17] = 8; p[18] = 8; p[19] = 8;
    p[20] = 8;
    p[24] = 0x12; p[25] = 0x34;
    p[26] = 0; p[27] = 1;
    memcpy(p + 28, "wgtunnel-harmony", 16);
    return 44;
}

static int count_occurrences(const char *hay, const char *needle)
{
    int n = 0;
    const char *p = hay;
    size_t len = strlen(needle);
    while ((p = strstr(p, needle)) != NULL) {
        n++;
        p += len;
    }
    return n;
}

/* ---- responder ----------------------------------------------------------- */

typedef struct {
    sock_t sock;
    struct sockaddr_in from;
    wg_peer peer;
    int keepalives;
    int transports;
    int initiations;
} responder;

static void responder_bind(responder *r, uint16_t *port)
{
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    r->sock = socket(AF_INET, SOCK_DGRAM, 0);
    bind(r->sock, (struct sockaddr *)&addr, sizeof(addr));
    getsockname(r->sock, (struct sockaddr *)&addr, &alen);
    *port = ntohs(addr.sin_port);
}

/* Serve the responder socket for `budget_ms`. */
static void responder_pump(responder *r, int budget_ms)
{
    uint64_t deadline = ms_now() + (uint64_t)budget_ms;
    while (ms_now() < deadline) {
        uint8_t buf[2048];
        uint8_t out[2048];
        size_t outlen = 0;
        wg_rx_kind kind;
        struct sockaddr_in from;
        socklen_t flen = sizeof(from);
        int n;
#if defined(_WIN32)
        fd_set set;
        struct timeval tv;
        FD_ZERO(&set);
        FD_SET((SOCKET)r->sock, &set);
        tv.tv_sec = 0;
        tv.tv_usec = 20000;
        if (select(0, &set, NULL, NULL, &tv) <= 0) {
            continue;
        }
#else
        struct pollfd pfd;
        pfd.fd = r->sock;
        pfd.events = POLLIN;
        pfd.revents = 0;
        if (poll(&pfd, 1, 20) <= 0) {
            continue;
        }
#endif
        n = (int)recvfrom(r->sock, (char *)buf, sizeof(buf), 0, (struct sockaddr *)&from, &flen);
        if (n <= 0) {
            continue;
        }
        r->peer.hs.local_index = 0x51515151u;
        kind = wg_handshake_consume(&r->peer, buf, (size_t)n, ms_now(), out, sizeof(out), &outlen);
        if (kind == WG_RX_INITIATION) {
            if (outlen > 0) {
                sendto(r->sock, (const char *)out, (int)outlen, 0, (struct sockaddr *)&from, flen);
            }
            r->initiations++;
            r->from = from;
        } else if (kind == WG_RX_TRANSPORT) {
            r->transports++;
        } else if (kind == WG_RX_KEEPALIVE) {
            r->keepalives++;
        }
    }
}

int main(void)
{
    static const uint8_t ipriv[32] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
                                      17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32};
    static const uint8_t spriv[32] = {0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
                                      0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
                                      0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
                                      0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f};
    uint8_t ipub[32], spub[32], psk[32];
    tun_pair tun;
    responder resp;
    uint16_t port = 0;
    wg_awg_params params;
    int fd;
    int idle_keepalives;
    int after_data_keepalives;
    int unresolved_retries = 0;
    int unresolved_fd = 0;
    int unresolved_state = 0;
    uint64_t t0;

#if defined(_WIN32)
    {
        WSADATA wsa;
        WSAStartup(MAKEWORD(2, 2), &wsa);
    }
#endif

    printf("clock now = %llu ms (WG_REJECT_AFTER_MS = 180000)\n", (unsigned long long)ms_now());

    memset(psk, 0, sizeof(psk));
    wg_x25519_public_key(ipub, ipriv);
    wg_x25519_public_key(spub, spriv);
    memset(&params, 0, sizeof(params));

    if (make_tun_pair(&tun) != 0) {
        printf("FAIL could not create the tun stand-in\n");
        return 1;
    }

    memset(&resp, 0, sizeof(resp));
    responder_bind(&resp, &port);
    wg_peer_init(&resp.peer, spriv, ipub, psk, &params);

    {
        wg_engine_config cfg;
        memset(&cfg, 0, sizeof(cfg));
        memcpy(cfg.static_priv, ipriv, 32);
        cfg.mtu = 1420;
        cfg.peer_count = 1;
        memcpy(cfg.peers[0].public_key, spub, 32);
        memcpy(cfg.peers[0].psk, psk, 32);
        strcpy(cfg.peers[0].host, "127.0.0.1");
        cfg.peers[0].port = port;
        cfg.peers[0].keepalive = 1; /* PersistentKeepalive = 1s */
        cfg.peers[0].allowed_count = 1;
        cfg.peers[0].allowed[0].family = 4;
        cfg.peers[0].allowed[0].bits = 0;
        fd = wg_engine_open(&cfg);
    }
    if (fd < 0) {
        printf("FAIL engine did not open a socket\n");
        return 1;
    }
    if (wg_engine_start((int)tun.a) != 0) {
        printf("FAIL engine did not start\n");
        return 1;
    }

    /* Phase 1: bring the session up with no traffic whatsoever. */
    t0 = ms_now();
    while (ms_now() - t0 < 5000 && resp.initiations == 0) {
        responder_pump(&resp, 100);
    }
    printf("phase 1: handshake initiation seen = %d\n", resp.initiations > 0);
    responder_pump(&resp, 6000); /* the engine must send a keepalive by 1 s idle */
    idle_keepalives = resp.keepalives;
    printf("phase 1: keepalives while idle from the handshake = %d\n", idle_keepalives);

    /* Phase 2: one packet in, then idle again. */
    {
        uint8_t pkt[64];
        size_t len = make_icmp_echo(pkt);
        resp.keepalives = 0;
        send(tun.b, (const char *)pkt, (int)len, 0);
        responder_pump(&resp, 6000);
        after_data_keepalives = resp.keepalives;
        printf("phase 2: plaintext packets seen by the peer = %d\n", resp.transports);
        printf("phase 2: keepalives after one data packet     = %d\n", after_data_keepalives);
    }

    {
        wg_engine_info info;
        wg_engine_info_snapshot(&info);
        printf("engine: state=%d peers_up=%u handshakes=%u socket_gen=%u tx=%llu rx=%llu\n",
               (int)info.state, (unsigned)info.peers_up, (unsigned)info.handshakes,
               (unsigned)info.socket_gen, (unsigned long long)info.tx_bytes,
               (unsigned long long)info.rx_bytes);
    }

    wg_engine_stop();
    close_sock(tun.a);
    close_sock(tun.b);
    close_sock(resp.sock);

    /* ---- Scenario B: an endpoint name that never resolves ----------------- */
    {
        wg_engine_config cfg;
        tun_pair tun2;
        static char logs[65536];
        int retries;

        if (make_tun_pair(&tun2) != 0) {
            printf("FAIL could not create the second tun stand-in\n");
            return 1;
        }
        memset(&cfg, 0, sizeof(cfg));
        memcpy(cfg.static_priv, ipriv, 32);
        cfg.mtu = 1420;
        cfg.peer_count = 1;
        memcpy(cfg.peers[0].public_key, spub, 32);
        memcpy(cfg.peers[0].psk, psk, 32);
        strcpy(cfg.peers[0].host, "no-such-endpoint.invalid");
        cfg.peers[0].port = 51820;
        cfg.peers[0].keepalive = 0;
        cfg.peers[0].allowed_count = 1;
        cfg.peers[0].allowed[0].family = 4;
        cfg.peers[0].allowed[0].bits = 0;
        if (wg_engine_open(&cfg) >= 0) {
            wg_engine_start((int)tun2.a);
        }
        sleep_ms(5000);
        {
            wg_engine_info info;
            wg_engine_info_snapshot(&info);
            wg_engine_logs(logs, sizeof(logs), 200);
            unresolved_fd = info.udp_fd;
            unresolved_state = (int)info.state;
        }
        retries = count_occurrences(logs, "recycle failed");
        unresolved_retries = retries;
        printf("scenario B: resolver failures logged = %d, udp_fd = %d, state = %d\n",
               retries, unresolved_fd, unresolved_state);
        wg_engine_stop();
        close_sock(tun2.a);
        close_sock(tun2.b);
    }

    printf("\n");
    if (idle_keepalives == 0 && after_data_keepalives > 0) {
        printf("VERDICT: DEFECT CONFIRMED - a session with no traffic never sends its\n");
        printf("         persistent keepalive; one data packet unblocks it.\n");
        return 2;
    }
    if (unresolved_fd >= 0 || unresolved_retries < 2 || unresolved_state != WG_STATE_CONNECTING) {
        printf("VERDICT: DEFECT CONFIRMED - a failed socket recycle leaves the tunnel\n");
        printf("         dead (udp_fd = %d, resolver failures logged = %d, state = %d).\n",
               unresolved_fd, unresolved_retries, unresolved_state);
        return 4;
    }
    if (idle_keepalives > 0) {
        printf("VERDICT: keepalive fires on an idle session (defect not present here)\n");
        return 0;
    }
    printf("VERDICT: inconclusive - no keepalive in either phase\n");
    return 3;
}
