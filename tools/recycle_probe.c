/*
 * recycle_probe.c — white-box test for the socket-recycle failure path.
 *
 * recycle_socket() re-resolves every peer and opens a fresh socket. It can
 * fail: a handover happens while DNS is away, or the name that resolved when
 * the tunnel came up no longer does. What must not happen is a failed recycle
 * that keeps the old fd, because engine_tick() only retries while udp_fd is
 * bad, and udp_send_to() cannot grow a failure streak for a peer that has no
 * address - the tunnel would then stay dead until the process restarted, with
 * a status snapshot that still shows a socket.
 *
 * The failure cannot be produced through the public API on a host with working
 * DNS, so this translation unit includes wg_engine.c and breaks the peer's
 * name between the open and the recycle. That makes the test discriminating:
 * the previous code left udp_fd valid here and never retried again.
 *
 *   zig cc -std=c11 -O2 -I entry/src/main/cpp/wg \
 *       -I entry/src/main/cpp/wg/third_party -o build/recycle_probe.exe \
 *       tools/recycle_probe.c entry/src/main/cpp/wg/wg_proto.c \
 *       entry/src/main/cpp/wg/wg_crypto.c entry/src/main/cpp/wg/wg_blake2s.c \
 *       entry/src/main/cpp/wg/third_party/monocypher.c -lws2_32
 *
 * exit 0 = the failed recycle releases the socket and the engine keeps retrying
 * exit 5 = the stale socket survived the failed recycle
 * exit 6 = the retry was not scheduled
 * exit 7 = the engine stopped retrying after the first failure
 */
#include "wg_engine.c"

#include <stdio.h>
#include <string.h>

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

#if defined(_WIN32)
static void sleep_ms(unsigned ms)
{
    Sleep(ms);
}
#else
static void sleep_ms(unsigned ms)
{
    usleep(ms * 1000u);
}
#endif

int main(void)
{
    static const uint8_t ipriv[32] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
                                      17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32};
    static const uint8_t spub[32] = {0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1,
                                     0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9,
                                     0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1,
                                     0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9};
    static char logs[65536];
    wg_engine_config cfg;
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    wg_sock_t tun;
    int opened;
    int before;
    int after;
    uint64_t retry_at;
    int retries;
    int scheduled_ok;

#if defined(_WIN32)
    {
        WSADATA wsa;
        WSAStartup(MAKEWORD(2, 2), &wsa);
    }
#endif

    memset(&cfg, 0, sizeof(cfg));
    memcpy(cfg.static_priv, ipriv, 32);
    cfg.mtu = 1420;
    cfg.peer_count = 1;
    memcpy(cfg.peers[0].public_key, spub, 32);
    strcpy(cfg.peers[0].host, "127.0.0.1");
    cfg.peers[0].port = 51820;
    cfg.peers[0].keepalive = 0;
    cfg.peers[0].allowed_count = 1;
    cfg.peers[0].allowed[0].family = 4;
    cfg.peers[0].allowed[0].bits = 0;

    opened = wg_engine_open(&cfg);
    before = (int)g_eng.udp_fd;
    printf("open: returned %d, udp_fd = %d, peer resolved = %u\n",
           opened, before, (unsigned)g_eng.peers[0].resolved);
    if (opened < 0 || before == (int)WG_BAD_SOCK) {
        printf("FAIL the engine did not come up with a socket\n");
        return 1;
    }

    /* The name that resolved a moment ago stops resolving: the handover case. */
    memset(g_eng.peers[0].cfg.host, 0, sizeof(g_eng.peers[0].cfg.host));
    strcpy(g_eng.peers[0].cfg.host, "no-such-endpoint.invalid");
    recycle_socket();
    after = (int)g_eng.udp_fd;
    retry_at = g_eng.next_socket_retry_ms;
    scheduled_ok = retry_at > now_ms();
    printf("recycle: udp_fd = %d, peer resolved = %u, retry scheduled in %lld ms\n",
           after, (unsigned)g_eng.peers[0].resolved,
           scheduled_ok ? (long long)(retry_at - now_ms()) : -1LL);

    /* Give the I/O thread a change to retry on its own. */
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    tun = (wg_sock_t)socket(AF_INET, SOCK_DGRAM, 0);
    if (tun == WG_BAD_SOCK || bind(tun, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        printf("FAIL could not create the tun stand-in\n");
        return 1;
    }
    (void)alen;
    if (wg_engine_start((int)tun) != 0) {
        printf("FAIL the engine did not start\n");
        return 1;
    }
    sleep_ms(4500);
    wg_engine_logs(logs, sizeof(logs), 200);
    retries = count_occurrences(logs, "recycle failed");
    printf("retries logged = %d\n", retries);
    wg_engine_stop();
    wg_close_sock(tun);

    printf("\n");
    if (after != (int)WG_BAD_SOCK) {
        printf("VERDICT: DEFECT CONFIRMED - a failed recycle kept udp_fd %d, so\n", after);
        printf("         engine_tick() never retries again and the tunnel is dead\n");
        printf("         until the process restarts.\n");
        return 5;
    }
    if (!scheduled_ok) {
        printf("VERDICT: DEFECT CONFIRMED - the failure did not schedule a retry.\n");
        return 6;
    }    if (retries < 2) {
        printf("VERDICT: DEFECT CONFIRMED - the engine stopped retrying after the\n");
        printf("         first resolver failure (%d logged).\n", retries);
        return 7;
    }
    printf("VERDICT: a failed recycle releases the socket and the engine retries\n");
    return 0;
}
