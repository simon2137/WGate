/*
 * liveprobe.c — point the real engine at a real WireGuard server.
 *
 * The emulator cannot authorise a VPN, so the only way to prove the engine
 * works against a live endpoint is to run it here on the host: same engine,
 * same protocol code, same timers, with a UDP socket pair standing in for the
 * tun device. It performs the handshake, then pushes one ICMP echo through the
 * tunnel and waits for the reply, which is what "does it actually connect"
 * means in practice.
 *
 *   liveprobe <host> <port> <privateKeyB64> <peerPublicKeyB64> [allowedCIDR] [pingTarget]
 *
 * Example:
 *   liveprobe 113.248.178.155 51820 "+Ah0c..." "K6oZ..." 0.0.0.0/0 114.114.114.114
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "wg_engine.h"

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

static int b64_value(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

/* Decodes exactly 32 bytes; returns 0 on success. */
static int b64_key(const char *text, uint8_t out[32])
{
    int acc = 0;
    int bits = 0;
    size_t written = 0;

    if (text == NULL) {
        return -1;
    }
    for (const char *p = text; *p != '\0'; p++) {
        if (*p == '=' || *p == '\n' || *p == '\r' || *p == ' ' || *p == '\t') {
            continue;
        }
        int v = b64_value(*p);
        if (v < 0) {
            return -1;
        }
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (written >= 32) {
                return -1;
            }
            out[written++] = (uint8_t)((acc >> bits) & 0xFF);
        }
    }
    return written == 32 ? 0 : -1;
}

static int make_tun_pair(sock_t *a, sock_t *b)
{
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    int one = 1;

    *a = socket(AF_INET, SOCK_DGRAM, 0);
    *b = socket(AF_INET, SOCK_DGRAM, 0);
    if (*a == BAD_SOCK || *b == BAD_SOCK) {
        return -1;
    }
#if defined(_WIN32)
    setsockopt(*a, SOL_SOCKET, SO_REUSEADDR, (const char *)&one, sizeof(one));
    setsockopt(*b, SOL_SOCKET, SO_REUSEADDR, (const char *)&one, sizeof(one));
#else
    setsockopt(*a, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(*b, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#endif
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (bind(*a, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    if (bind(*b, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    if (getsockname(*a, (struct sockaddr *)&addr, &alen) != 0) return -1;
    if (connect(*b, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    if (getsockname(*b, (struct sockaddr *)&addr, &alen) != 0) return -1;
    if (connect(*a, (struct sockaddr *)&addr, sizeof(addr)) != 0) return -1;
    return 0;
}

/* IPv4 + ICMP echo request from 10.0.0.6 to the target, with valid checksums. */
static size_t make_icmp_echo(uint8_t *p, const char *target)
{
    struct in_addr dst;

    memset(p, 0, 44);
    p[0] = 0x45;
    p[3] = 44;
    p[8] = 64;
    p[9] = 1;
    p[12] = 10; p[13] = 0; p[14] = 0; p[15] = 6;
    if (inet_pton(AF_INET, target, &dst) != 1) {
        p[16] = 8; p[17] = 8; p[18] = 8; p[19] = 8;
    } else {
        memcpy(p + 16, &dst, 4);
    }
    p[20] = 8; /* echo request */
    p[24] = 0x12; p[25] = 0x34;
    p[26] = 0; p[27] = 1;
    memcpy(p + 28, "wgtunnel-harmony", 16);

    /* ICMP checksum */
    uint32_t sum = 0;
    for (int i = 20; i < 44; i += 2) {
        sum += (uint32_t)((p[i] << 8) | p[i + 1]);
    }
    while ((sum >> 16) != 0) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    uint16_t icmp = (uint16_t)(~sum);
    p[22] = (uint8_t)(icmp >> 8);
    p[23] = (uint8_t)(icmp & 0xFF);

    /* IPv4 header checksum */
    sum = 0;
    for (int i = 0; i < 20; i += 2) {
        sum += (uint32_t)((p[i] << 8) | p[i + 1]);
    }
    while ((sum >> 16) != 0) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    uint16_t ip = (uint16_t)(~sum);
    p[10] = (uint8_t)(ip >> 8);
    p[11] = (uint8_t)(ip & 0xFF);
    return 44;
}

static const char *state_name(wg_engine_state s)
{
    switch (s) {
    case WG_STATE_IDLE: return "idle";
    case WG_STATE_CONNECTING: return "connecting";
    case WG_STATE_UP: return "up";
    case WG_STATE_RETRY: return "retry";
    case WG_STATE_ERROR: return "error";
    case WG_STATE_STOPPED: return "stopped";
    default: return "?";
    }
}

int main(int argc, char **argv)
{
    wg_engine_config cfg;
    wg_engine_info info;
    sock_t tun_a = BAD_SOCK;
    sock_t tun_b = BAD_SOCK;
    uint8_t ping[44];
    size_t ping_len;

    if (argc < 5) {
        printf("usage: %s <host> <port> <privateB64> <peerPublicB64> [allowedCIDR] [pingTarget]\n",
               argv[0]);
        return 2;
    }

#if defined(_WIN32)
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        printf("winsock init failed\n");
        return 2;
    }
#endif

    memset(&cfg, 0, sizeof(cfg));
    if (b64_key(argv[3], cfg.static_priv) != 0) {
        printf("private key is not 32 base64 bytes\n");
        return 2;
    }
    if (b64_key(argv[4], cfg.peers[0].public_key) != 0) {
        printf("peer public key is not 32 base64 bytes\n");
        return 2;
    }
    cfg.mtu = 1420;
    cfg.peer_count = 1;
    cfg.peers[0].keepalive = 15;
    snprintf(cfg.peers[0].host, sizeof(cfg.peers[0].host), "%s", argv[1]);
    cfg.peers[0].port = (uint16_t)atoi(argv[2]);
    cfg.peers[0].allowed_count = 1;
    cfg.peers[0].allowed[0].family = 4;
    cfg.peers[0].allowed[0].bits = 0;
    memset(cfg.peers[0].allowed[0].addr, 0, sizeof(cfg.peers[0].allowed[0].addr));
    if (argc > 5) {
        char cidr[64];
        snprintf(cidr, sizeof(cidr), "%s", argv[5]);
        char *slash = strchr(cidr, '/');
        if (slash != NULL) {
            *slash = '\0';
            cfg.peers[0].allowed[0].bits = (uint8_t)atoi(slash + 1);
        }
        struct in_addr a4;
        if (inet_pton(AF_INET, cidr, &a4) == 1) {
            cfg.peers[0].allowed[0].family = 4;
            memcpy(cfg.peers[0].allowed[0].addr, &a4, 4);
        }
    }

    printf("endpoint   %s:%u\n", cfg.peers[0].host, cfg.peers[0].port);
    printf("peer       %.8s...%s\n", argv[4], argv[4] + strlen(argv[4]) - 6);

    if (make_tun_pair(&tun_a, &tun_b) != 0) {
        printf("cannot create the tun stand-in\n");
        return 2;
    }

    /* The read loop must never block: a silent server is a normal outcome. */
#if defined(_WIN32)
    DWORD rcv_ms = 200;
    setsockopt(tun_b, SOL_SOCKET, SO_RCVTIMEO, (const char *)&rcv_ms, sizeof(rcv_ms));
#else
    struct timeval rcv_tv;
    rcv_tv.tv_sec = 0;
    rcv_tv.tv_usec = 200000;
    setsockopt(tun_b, SOL_SOCKET, SO_RCVTIMEO, &rcv_tv, sizeof(rcv_tv));
#endif

    int udp_fd = wg_engine_open(&cfg);
    printf("udp fd     %d\n", udp_fd);
    if (udp_fd < 0) {
        printf("engine open failed: %d\n", udp_fd);
        return 1;
    }
    if (wg_engine_start((int)tun_a) != 0) {
        printf("engine start failed\n");
        return 1;
    }

    /* Wait for the handshake, reporting transitions. */
    const char *last = "";
    int up_ms = -1;
    for (int i = 0; i < 200; i++) {
        sleep_ms(100);
        wg_engine_info_snapshot(&info);
        const char *now = state_name(info.state);
        if (strcmp(now, last) != 0) {
            printf("  [%5d ms] state=%s handshakes=%u lastErrno=%d\n", i * 100, now,
                   (unsigned)info.handshakes, info.last_errno);
            last = now;
        }
        if (info.state == WG_STATE_UP) {
            up_ms = i * 100;
            break;
        }
    }

    if (up_ms < 0) {
        printf("NO HANDSHAKE within 20 s\n");
    } else {
        printf("handshake  ok at %d ms\n", up_ms);
        const char *target = argc > 6 ? argv[6] : "114.114.114.114";
        ping_len = make_icmp_echo(ping, target);
        int sent = (int)send(tun_b, (const char *)ping, (int)ping_len, 0);
        printf("icmp       sent %d bytes to %s\n", sent, target);

        int got_reply = 0;
        for (int i = 0; i < 60; i++) {
            char buf[2048];
            int n = (int)recv(tun_b, buf, sizeof(buf), 0);
            if (n > 20) {
                int type = (uint8_t)buf[20];
                printf("  [%5d ms] return %d bytes, ip type %d, from %u.%u.%u.%u\n", i * 100,
                       n, type, (uint8_t)buf[12], (uint8_t)buf[13], (uint8_t)buf[14],
                       (uint8_t)buf[15]);
                if (type == 0) {
                    got_reply = 1;
                    break;
                }
            }
            sleep_ms(100);
        }
        printf("icmp reply %s\n", got_reply ? "ok" : "MISSING");
    }

    wg_engine_info_snapshot(&info);
    printf("rx %llu B / tx %llu B, rx %u / tx %u packets, peers up %u, socketGen %u\n",
           (unsigned long long)info.rx_bytes, (unsigned long long)info.tx_bytes, (unsigned)info.rx_packets,
           (unsigned)info.tx_packets, (unsigned)info.peers_up, (unsigned)info.socket_gen);

    char logs[4096];
    size_t used = wg_engine_logs(logs, sizeof(logs), 40);
    printf("---- engine log ----\n%s", logs);
    if (used == 0) {
        printf("(empty)\n");
    }

    wg_engine_stop();
    if (tun_b != BAD_SOCK) close_sock(tun_b);
#if defined(_WIN32)
    WSACleanup();
#endif
    return 0;
}
