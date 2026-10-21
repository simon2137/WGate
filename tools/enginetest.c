/*
 * enginetest.c — host-side exercise of wg_engine.c.
 *
 * Uses a connected UDP socket pair as a stand-in for the tun fd (HarmonyOS'
 * tun fd is read/written exactly like this) and drives a responder peer on
 * loopback, so the whole path is exercised: handshake scheduling, packet
 * queueing while the handshake is in flight, padding trim, keepalives.
 *
 *   gcc/zig: see tools/build_host.sh
 *   ./enginetest [plain|awg]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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

static int failures;

#define CHECK(cond, msg)                                                                           \
    do {                                                                                           \
        if (cond) {                                                                                \
            printf("  ok  %s\n", msg);                                                             \
        } else {                                                                                   \
            printf("  FAIL %s\n", msg);                                                            \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static uint64_t ms_now(void)
{
#if defined(_WIN32)
    return GetTickCount64();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
#endif
}

static void hexprint(const char *tag, const uint8_t *b, size_t n)
{
    printf("%s", tag);
    for (size_t i = 0; i < n; i++) {
        printf("%02x", b[i]);
    }
    printf("\n");
}

/* ---- tun simulation: two connected UDP sockets on loopback ---------------- */

typedef struct {
    sock_t a; /* handed to the engine */
    sock_t b; /* test side */
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

/* ---- a tiny IPv4 ICMP echo request / reply generator -------------------- */

static size_t make_icmp_echo(uint8_t *p, int reply)
{
    memset(p, 0, 44);
    p[0] = 0x45; /* version 4, ihl 5 */
    p[2] = 0;
    p[3] = 44; /* total length */
    p[8] = 64; /* ttl */
    p[9] = 1;  /* icmp */
    /* src 10.0.0.2, dst 8.8.8.8 (or swapped for the reply) */
    if (!reply) {
        p[12] = 10; p[13] = 0; p[14] = 0; p[15] = 2;
        p[16] = 8; p[17] = 8; p[18] = 8; p[19] = 8;
    } else {
        p[12] = 8; p[13] = 8; p[14] = 8; p[15] = 8;
        p[16] = 10; p[17] = 0; p[18] = 0; p[19] = 2;
    }
    p[20] = reply ? 0 : 8; /* echo reply / request */
    p[21] = 0;
    p[24] = 0x12; p[25] = 0x34; /* id */
    p[26] = 0; p[27] = 1;       /* seq */
    memcpy(p + 28, "wgtunnel-harmony", 16);
    return 44;
}

/* ---- responder --------------------------------------------------------- */

typedef struct {
    sock_t sock;
    struct sockaddr_in from;
    int have_from;
    wg_peer peer;
    int awg;
    unsigned char rx_data[2048];
    size_t rx_len;
    int got_data;
    int keepalive_seen;
    int handshake_done;
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

/* Poll the responder socket for up to `budget_ms`, handling every datagram. */
static void responder_pump(responder *r, int budget_ms, uint64_t now_base)
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
        kind = wg_handshake_consume(&r->peer, buf, (size_t)n, now_base + (ms_now() - now_base), out,
                                    sizeof(out), &outlen);
        if (kind == WG_RX_INITIATION) {
            if (outlen > 0) {
                sendto(r->sock, (const char *)out, (int)outlen, 0, (struct sockaddr *)&from, flen);
            }
            r->handshake_done = 1;
            r->from = from;
            r->have_from = 1;
        } else if (kind == WG_RX_TRANSPORT) {
            memcpy(r->rx_data, out, outlen);
            r->rx_len = outlen;
            r->got_data = 1;
            /* answer with an echo reply through the tunnel */
            {
                uint8_t reply[2048];
                uint8_t pkt[64];
                size_t plen = make_icmp_echo(pkt, 1);
                size_t elen = 0;
                if (wg_transport_encrypt(&r->peer, pkt, plen, reply, sizeof(reply), &elen,
                                         now_base + (ms_now() - now_base)) == 0) {
                    sendto(r->sock, (const char *)reply, (int)elen, 0, (struct sockaddr *)&from, flen);
                }
            }
        } else if (kind == WG_RX_KEEPALIVE) {
            r->keepalive_seen = 1;
        }
    }
}

/* ---- test body --------------------------------------------------------- */

static int run_case(int awg)
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
    uint64_t start;
    uint64_t now;
    int fd;
    int ok;

    printf("%s framing\n", awg ? "amneziawg" : "plain wireguard");
    memset(psk, 0, sizeof(psk));
    wg_x25519_public_key(ipub, ipriv);
    wg_x25519_public_key(spub, spriv);

    memset(&params, 0, sizeof(params));
    if (awg) {
        params.enabled = 1;
        params.type_init = 77;
        params.type_response = 88;
        params.type_cookie = 99;
        params.type_transport = 111;
        params.jc = 3;
        params.jmin = 40;
        params.jmax = 90;
        params.s1 = 12;
        params.s2 = 8;
        params.s3 = 0;
    }

    if (make_tun_pair(&tun) != 0) {
        printf("  FAIL could not create the tun stand-in\n");
        return 1;
    }

    memset(&resp, 0, sizeof(resp));
    responder_bind(&resp, &port);
    wg_peer_init(&resp.peer, spriv, ipub, psk, &params);
    resp.awg = awg;

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
        cfg.peers[0].keepalive = 1;
        cfg.peers[0].allowed_count = 1;
        cfg.peers[0].allowed[0].family = 4;
        cfg.peers[0].allowed[0].bits = 0; /* default route */
        cfg.awg = params;
        fd = wg_engine_open(&cfg);
    }
    CHECK(fd >= 0, "engine opens a UDP socket");
    if (fd < 0) {
        return 1;
    }
    CHECK(wg_engine_start((int)tun.a) == 0, "engine starts");

    /* Write one packet immediately: it must be queued behind the handshake and
     * flushed as soon as the session comes up. */
    {
        uint8_t pkt[64];
        size_t len = make_icmp_echo(pkt, 0);
        send(tun.b, (const char *)pkt, (int)len, 0);
        start = ms_now();
        now = start;
        while (ms_now() - start < 5000 && !resp.got_data) {
            responder_pump(&resp, 200, now);
            now = ms_now() - start;
        }
    }
    CHECK(resp.handshake_done, "responder saw a handshake initiation");
    CHECK(resp.got_data, "queued packet was flushed through the tunnel");
    CHECK(resp.rx_len == 44 && memcmp(resp.rx_data + 20, "\x08\x00", 2) == 0,
          "tunnel delivered the original IPv4 echo request");

    /* The echo reply the responder sent must arrive on the tun side. */
    {
        uint8_t buf[2048];
        int n = -1;
        start = ms_now();
        while (ms_now() - start < 3000) {
#if defined(_WIN32)
            fd_set set;
            struct timeval tv = {0, 20000};
            FD_ZERO(&set);
            FD_SET((SOCKET)tun.b, &set);
            if (select(0, &set, NULL, NULL, &tv) <= 0) {
                responder_pump(&resp, 10, now);
                continue;
            }
#else
            struct pollfd pfd = {tun.b, POLLIN, 0};
            if (poll(&pfd, 1, 20) <= 0) {
                responder_pump(&resp, 10, now);
                continue;
            }
#endif
            n = (int)recv(tun.b, (char *)buf, sizeof(buf), 0);
            if (n > 0) {
                ok = (n == 44 && buf[20] == 0); /* ICMP echo reply */
                CHECK(ok, "decrypted reply reached the tun fd with padding trimmed");
                break;
            }
        }
        if (n <= 0) {
            CHECK(0, "decrypted reply reached the tun fd with padding trimmed");
        }
    }

    /* Persistent keepalive is configured to 1s and the tunnel is idle now. */
    start = ms_now();
    while (ms_now() - start < 4000 && !resp.keepalive_seen) {
        responder_pump(&resp, 200, 0);
    }
    CHECK(resp.keepalive_seen, "persistent keepalive was sent when idle");

    /*
     * One more packet, larger than the reply, so the two counters cannot be
     * confused for each other: the direction the device sends in must grow by
     * the size of what it sent, and that is the whole point of the next two
     * checks (they used to pass with the directions swapped, because both sides
     * were 44 bytes).
     */
    {
        uint8_t pkt[256];
        size_t len = make_icmp_echo(pkt, 0);
        memset(pkt + len, 0x5a, 200);
        len += 200;
        pkt[2] = (uint8_t)((len >> 8) & 0xff);
        pkt[3] = (uint8_t)(len & 0xff);
        send(tun.b, (const char *)pkt, (int)len, 0);
        start = ms_now();
        while (ms_now() - start < 1500) {
            responder_pump(&resp, 50, 0);
        }
    }

    {
        wg_engine_info info;
        wg_engine_info_snapshot(&info);
        CHECK(info.state == WG_STATE_UP, "engine reports the tunnel as up");
        CHECK(info.handshakes >= 1, "engine counted a completed handshake");
        CHECK(info.tx_bytes >= 44 + 244, "engine counted the plaintext it sent");
        CHECK(info.rx_bytes >= 44, "engine counted the plaintext it received");
        CHECK(info.rx_bytes < info.tx_bytes,
              "the sent direction is not reported as received");
    }

    wg_engine_stop();
    close_sock(tun.a);
    close_sock(tun.b);
    close_sock(resp.sock);
    return 0;
}

/* Build an IPv4 ICMP echo request towards an arbitrary destination. */
static size_t make_icmp_echo_to(uint8_t *p, const uint8_t dst[4])
{
    size_t len = make_icmp_echo(p, 0);
    memcpy(p + 16, dst, 4);
    return len;
}

/*
 * Two peers over one socket: outbound packets must reach the peer whose
 * AllowedIPs cover the destination, and replies from either peer must come back
 * to the tun fd.
 */
static int run_multi_peer(void)
{
    static const uint8_t ipriv[32] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
                                      0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00,
                                      0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80,
                                      0x90, 0xa0, 0xb0, 0xc0, 0xd0, 0xe0, 0xf0, 0x01};
    static const uint8_t spriv1[32] = {0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
                                       0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30,
                                       0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
                                       0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40};
    static const uint8_t spriv2[32] = {0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
                                       0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60,
                                       0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
                                       0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70};
    uint8_t ipub[32], spub1[32], spub2[32], psk[32];
    tun_pair tun;
    responder r1;
    responder r2;
    uint16_t port1 = 0;
    uint16_t port2 = 0;
    wg_awg_params params;
    wg_engine_config cfg;
    uint64_t start;
    int fd;

    printf("two peers\n");
    memset(psk, 0, sizeof(psk));
    memset(&params, 0, sizeof(params));
    wg_x25519_public_key(ipub, ipriv);
    wg_x25519_public_key(spub1, spriv1);
    wg_x25519_public_key(spub2, spriv2);

    if (make_tun_pair(&tun) != 0) {
        printf("  FAIL could not create the tun stand-in\n");
        return 1;
    }
    memset(&r1, 0, sizeof(r1));
    memset(&r2, 0, sizeof(r2));
    responder_bind(&r1, &port1);
    responder_bind(&r2, &port2);
    wg_peer_init(&r1.peer, spriv1, ipub, psk, &params);
    wg_peer_init(&r2.peer, spriv2, ipub, psk, &params);

    memset(&cfg, 0, sizeof(cfg));
    memcpy(cfg.static_priv, ipriv, 32);
    cfg.mtu = 1420;
    cfg.peer_count = 2;
    memcpy(cfg.peers[0].public_key, spub1, 32);
    memcpy(cfg.peers[0].psk, psk, 32);
    strcpy(cfg.peers[0].host, "127.0.0.1");
    cfg.peers[0].port = port1;
    cfg.peers[0].allowed_count = 1;
    cfg.peers[0].allowed[0].family = 4;
    cfg.peers[0].allowed[0].bits = 24;
    cfg.peers[0].allowed[0].addr[0] = 10;
    cfg.peers[0].allowed[0].addr[1] = 66;
    cfg.peers[0].allowed[0].addr[2] = 0;
    memcpy(cfg.peers[1].public_key, spub2, 32);
    memcpy(cfg.peers[1].psk, psk, 32);
    strcpy(cfg.peers[1].host, "127.0.0.1");
    cfg.peers[1].port = port2;
    cfg.peers[1].allowed_count = 1;
    cfg.peers[1].allowed[0].family = 4;
    cfg.peers[1].allowed[0].bits = 24;
    cfg.peers[1].allowed[0].addr[0] = 10;
    cfg.peers[1].allowed[0].addr[1] = 99;
    cfg.peers[1].allowed[0].addr[2] = 0;
    cfg.awg = params;

    fd = wg_engine_open(&cfg);
    CHECK(fd >= 0, "engine opens one socket for two peers");
    if (fd < 0) {
        return 1;
    }
    CHECK(wg_engine_start((int)tun.a) == 0, "engine starts with two peers");

    /* Bring both sessions up. */
    start = ms_now();
    while (ms_now() - start < 6000 && (!r1.handshake_done || !r2.handshake_done)) {
        responder_pump(&r1, 50, 0);
        responder_pump(&r2, 50, 0);
    }
    CHECK(r1.handshake_done, "first peer completed a handshake");
    CHECK(r2.handshake_done, "second peer completed a handshake");

    /* Destination in 10.99.0.0/24 must be routed to peer 2 only. */
    {
        uint8_t pkt[64];
        static const uint8_t dst[4] = {10, 99, 0, 7};
        size_t len = make_icmp_echo_to(pkt, dst);

        send(tun.b, (const char *)pkt, (int)len, 0);
        start = ms_now();
        while (ms_now() - start < 4000 && !r2.got_data) {
            responder_pump(&r1, 20, 0);
            responder_pump(&r2, 20, 0);
        }
    }
    CHECK(r2.got_data, "packet for 10.99.0.0/24 reached the second peer");
    CHECK(!r1.got_data, "the first peer did not receive it");

    /* Destination in 10.66.0.0/24 must be routed to peer 1. */
    {
        uint8_t pkt[64];
        static const uint8_t dst[4] = {10, 66, 0, 9};
        size_t len = make_icmp_echo_to(pkt, dst);

        send(tun.b, (const char *)pkt, (int)len, 0);
        start = ms_now();
        while (ms_now() - start < 4000 && !r1.got_data) {
            responder_pump(&r1, 20, 0);
            responder_pump(&r2, 20, 0);
        }
    }
    CHECK(r1.got_data, "packet for 10.66.0.0/24 reached the first peer");

    /* A reply from the second peer must reach the tun fd. */
    {
        uint8_t buf[2048];
        int n = -1;

        start = ms_now();
        while (ms_now() - start < 3000) {
#if defined(_WIN32)
            fd_set set;
            struct timeval tv = {0, 20000};
            FD_ZERO(&set);
            FD_SET((SOCKET)tun.b, &set);
            if (select(0, &set, NULL, NULL, &tv) <= 0) {
                responder_pump(&r1, 10, 0);
                responder_pump(&r2, 10, 0);
                continue;
            }
#else
            struct pollfd pfd = {tun.b, POLLIN, 0};
            if (poll(&pfd, 1, 20) <= 0) {
                responder_pump(&r1, 10, 0);
                responder_pump(&r2, 10, 0);
                continue;
            }
#endif
            n = (int)recv(tun.b, (char *)buf, sizeof(buf), 0);
            if (n > 0) {
                break;
            }
        }
        CHECK(n == 44 && buf[20] == 0, "replies from both peers reach the tun fd");
    }

    {
        wg_engine_info info;
        wg_engine_info_snapshot(&info);
        CHECK(info.peers_up == 2, "engine reports both peers up");
    }

    wg_engine_stop();
    close_sock(tun.a);
    close_sock(tun.b);
    close_sock(r1.sock);
    close_sock(r2.sock);
    return 0;
}

int main(int argc, char **argv)
{
    const char *which = argc > 1 ? argv[1] : "all";
#if defined(_WIN32)
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        printf("WSAStartup failed\n");
        return 1;
    }
#endif
    if (strcmp(which, "all") == 0 || strcmp(which, "plain") == 0) {
        run_case(0);
    }
    if (strcmp(which, "all") == 0 || strcmp(which, "awg") == 0) {
        run_case(1);
    }
    if (strcmp(which, "all") == 0 || strcmp(which, "multi") == 0) {
        run_multi_peer();
    }
    printf("%s (%d failures)\n", failures == 0 ? "engine ok" : "engine failures", failures);
#if defined(_WIN32)
    WSACleanup();
#endif
    return failures == 0 ? 0 : 1;
}
