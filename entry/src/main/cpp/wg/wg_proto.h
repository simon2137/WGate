/*
 * wg_proto.h - WireGuard Noise IK handshake and transport encryption, with the
 * AmneziaWG 1.5 obfuscation layer (junk packets, header junk prefix and
 * message type override).
 *
 * The functions below operate on caller supplied buffers; they never allocate
 * and never touch a socket, which keeps the protocol testable on the host.
 */
#ifndef WG_PROTO_H
#define WG_PROTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WG_STATIC_LEN 32
#define WG_MSG_INITIATION_BASE 148
#define WG_MSG_RESPONSE_BASE 92
#define WG_MSG_COOKIE_BASE 64
#define WG_MSG_TRANSPORT_HEADER 16
#define WG_MSG_KEEPALIVE 32
#define WG_MAX_PACKET 2048
#define WG_REPLAY_WINDOW_BITS 2048

/* AmneziaWG parameters.  When `enabled` is 0 the tunnel behaves like stock
 * WireGuard (no junk, no header prefix, standard message types). */
typedef struct {
    int enabled;
    uint32_t type_init;     /* H1 / message initiation type  */
    uint32_t type_response; /* H2 / message response type    */
    uint32_t type_cookie;   /* H3 / message cookie type      */
    uint32_t type_transport;/* H4 / message transport type   */
    uint16_t jc;            /* junk packet count before handshake */
    uint16_t jmin;          /* junk packet minimum size */
    uint16_t jmax;          /* junk packet maximum size */
    uint16_t s1;            /* junk prefix bytes on initiation */
    uint16_t s2;            /* junk prefix bytes on response   */
    uint16_t s3;            /* junk prefix bytes on cookie reply */
} wg_awg_params;

typedef enum {
    WG_HS_IDLE = 0,
    WG_HS_INITIATION_CREATED = 1,
    WG_HS_RESPONSE_CONSUMED = 2,
} wg_hs_state;

typedef struct {
    uint8_t chain_key[32];
    uint8_t hash[32];
    uint8_t eph_priv[32];
    uint8_t eph_pub[32];
    uint32_t local_index;
    uint64_t created_ms;
    wg_hs_state state;
} wg_handshake;

typedef struct {
    int valid;
    int is_initiator;
    uint8_t send_key[32];
    uint8_t recv_key[32];
    uint32_t local_index;   /* our index, expected in the receiver field of inbound packets */
    uint32_t remote_index;  /* peer index, written into outbound packets */
    uint64_t send_counter;
    uint64_t recv_last;     /* replay filter: highest accepted counter + 1 */
    uint64_t replay[WG_REPLAY_WINDOW_BITS / 64];
    uint64_t created_ms;
} wg_keypair;

typedef struct {
    uint8_t static_priv[32];
    uint8_t static_pub[32];
    uint8_t peer_static[32];
    uint8_t psk[32];
    uint8_t mac1_key[32];      /* BLAKE2s("mac1----" || peer_static)   */
    uint8_t cookie_key[32];    /* BLAKE2s("cookie--" || peer_static)   */
    wg_awg_params awg;
    wg_handshake hs;
    wg_keypair curr;
    wg_keypair prev;
    uint8_t last_mac1[16];     /* mac1 of the last generated handshake */
    uint8_t cookie[16];
    uint64_t cookie_set_ms;
    uint64_t last_recv_ms;     /* last authenticated packet received */
    uint64_t last_send_data_ms;/* last non-keepalive packet sent */
    uint64_t last_send_ms;
    int have_cookie;
    int last_mac1_valid;
} wg_peer;

typedef enum {
    WG_RX_NONE = 0,
    WG_RX_INITIATION,      /* handshake initiation received (responder role) */
    WG_RX_RESPONSE,        /* handshake response consumed, session derived */
    WG_RX_COOKIE,          /* cookie reply consumed */
    WG_RX_TRANSPORT,       /* transport packet decrypted */
    WG_RX_KEEPALIVE,       /* transport packet, empty payload */
    WG_RX_ERROR,           /* rejected packet */
} wg_rx_kind;

void wg_peer_init(wg_peer *peer, const uint8_t static_priv[32], const uint8_t peer_static[32],
                  const uint8_t psk[32], const wg_awg_params *awg);
int wg_peer_has_session(const wg_peer *peer);
int wg_peer_session_usable(const wg_peer *peer, uint64_t now_ms);
uint64_t wg_peer_session_age_ms(const wg_peer *peer, uint64_t now_ms);

/* Fill `junks` with up to `max` datagrams of random size in [jmin, jmax].
 * Returns the number of datagrams written and stores each datagram length in
 * caps; each entry must point to a buffer of at least WG_MAX_PACKET bytes. */
int wg_awg_junk_packets(const wg_awg_params *awg, uint8_t **junks, size_t *caps, size_t max);

/* Build an initiation (already including junk prefix + macs).  `out` must hold
 * at least WG_MAX_PACKET bytes. */
int wg_handshake_create_initiation(wg_peer *peer, uint32_t local_index, uint8_t *out, size_t cap,
                                   size_t *outlen, uint64_t now_ms);

/* Classify an inbound datagram and handle it (transport, cookie, initiation,
 * response).  For an initiation `peer->hs.local_index` must be preset: it is the
 * index this side assigns to the new session.  Returns what was consumed; for
 * WG_RX_TRANSPORT / WG_RX_KEEPALIVE the plaintext is written to `out`. */
wg_rx_kind wg_handshake_consume(wg_peer *peer, const uint8_t *in, size_t len, uint64_t now_ms,
                                uint8_t *out, size_t cap, size_t *outlen);

/* Initiator role: consume a handshake response and derive the session. */
int wg_handshake_consume_response(wg_peer *peer, const uint8_t *in, size_t len, uint64_t now_ms);

/* Requestor role: consume a cookie reply into `peer->cookie`. */
int wg_handshake_consume_cookie(wg_peer *peer, const uint8_t *in, size_t len, uint64_t now_ms);

/* Responder role: consume an initiation, derive the session and write the
 * response datagram (including any junk prefix) to `out`. */
int wg_handshake_consume_initiation(wg_peer *peer, uint32_t local_index, const uint8_t *in, size_t len,
                                    uint64_t now_ms, uint8_t *out, size_t cap, size_t *outlen);

/* Transport encryption/decryption. */
int wg_transport_encrypt(wg_peer *peer, const uint8_t *pt, size_t ptlen, uint8_t *out, size_t cap,
                         size_t *outlen, uint64_t now_ms);
int wg_transport_decrypt(wg_peer *peer, const uint8_t *in, size_t len, uint8_t *out, size_t cap,
                         size_t *ptlen, uint64_t now_ms);

/* Helpers shared with the tests. */
void wg_tai64n_now(uint8_t out[12]);
uint32_t wg_msg_type(const uint8_t *in, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* WG_PROTO_H */
