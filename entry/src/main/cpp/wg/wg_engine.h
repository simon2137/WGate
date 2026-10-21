/*
 * wg_engine — tunnel driver: owns the UDP socket and the tun fd, runs the
 * handshake state machine and the data path for every peer of one tunnel.
 *
 * One engine instance per process (one active tunnel), which matches the app:
 * the VPN extension creates exactly one VpnConnection.  A tunnel may carry
 * several peers (wg-quick allows any number of [Peer] sections); outbound
 * packets are routed by longest-prefix match over each peer's AllowedIPs.
 */
#ifndef WG_ENGINE_H
#define WG_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#include "wg_proto.h"

#define WG_MAX_PEERS 8
#define WG_MAX_ALLOWED 16
#define WG_HOST_LEN 128

typedef enum {
    WG_STATE_IDLE = 0,
    WG_STATE_CONNECTING,
    WG_STATE_UP,
    WG_STATE_RETRY,
    WG_STATE_ERROR,
    WG_STATE_STOPPED,
} wg_engine_state;

/* One AllowedIPs entry.  IPv6 entries only support a /0 default route. */
typedef struct {
    uint8_t family; /* 4 or 6 */
    uint8_t bits;
    uint8_t addr[16]; /* network byte order, IPv4 in the first four bytes */
} wg_allowed;

typedef struct {
    uint8_t public_key[32];
    uint8_t psk[32]; /* all zero when the peer has no preshared key */
    char host[WG_HOST_LEN];
    uint16_t port;
    uint16_t keepalive; /* seconds, 0 disables */
    uint32_t allowed_count;
    wg_allowed allowed[WG_MAX_ALLOWED];
} wg_peer_config;

typedef struct {
    uint8_t static_priv[32];
    uint16_t mtu;
    uint32_t peer_count;
    wg_peer_config peers[WG_MAX_PEERS];
    wg_awg_params awg;
} wg_engine_config;

typedef struct {
    wg_engine_state state;
    int udp_fd;
    uint64_t rx_bytes; /* plaintext the peer sent us (written to the tun device) */
    uint64_t tx_bytes; /* plaintext we sent to the peer (read from the tun device) */
    uint64_t rx_packets;
    uint64_t tx_packets;
    uint64_t handshake_ms; /* completion time of the newest session, 0 if none */
    uint64_t started_ms;
    uint64_t last_error_ms;
    int last_errno;
    uint32_t handshakes; /* completed handshakes since start */
    uint32_t queue_drops;
    uint32_t socket_gen; /* bumped whenever the UDP socket is recreated */
    uint32_t peers_up;   /* peers holding a usable session */
} wg_engine_info;

/* Configure the engine and resolve/connect the UDP socket.
 * Returns the UDP socket fd (>= 0) or -1 with errno set.  The caller is
 * expected to hand this fd to VpnConnection.protect() so the tunnel keeps
 * using the physical network, then call wg_engine_start(). */
int wg_engine_open(const wg_engine_config *config);

/* Start the I/O thread with a connected tun fd.  Returns 0 on success. */
int wg_engine_start(int tun_fd);

/* Stop the I/O thread and close the UDP socket.  The tun fd is not closed. */
void wg_engine_stop(void);

void wg_engine_info_snapshot(wg_engine_info *out);

/* Called by the NAPI layer when the caller wants to force a new handshake. */
void wg_engine_force_handshake(void);

/* Copy the newest `max` log lines (oldest first, '\n' separated) into out.
 * Returns the number of bytes written, always NUL terminated. */
size_t wg_engine_logs(char *out, size_t cap, uint32_t max_lines);

/* Drop every line held by the log ring (the diagnostics screen's Clear button). */
void wg_engine_clear_logs(void);

#ifdef __cplusplus
}
#endif
#endif /* WG_ENGINE_H */
