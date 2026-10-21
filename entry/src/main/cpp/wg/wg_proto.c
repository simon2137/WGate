/*
 * wg_proto.c - WireGuard Noise IKpsk2 handshake + transport data messages with
 * the AmneziaWG 1.5 obfuscation layer.
 *
 * Message layouts (all integers little endian):
 *
 *   initiation = [junk(S1)] type:4 sender:4 ephemeral:32 static:48 ts:28 mac1:16 mac2:16
 *   response   = [junk(S2)] type:4 sender:4 receiver:4 ephemeral:32 empty:16 mac1:16 mac2:16
 *   cookie     = [junk(S3)] type:4 receiver:4 nonce:24 cookie:32
 *   transport  = type:4 receiver:4 counter:8 ciphertext tag:16
 */
#include <string.h>
#include <time.h>
#include <stdio.h>

#ifdef WG_DEBUG
#include <stdint.h>
static void wg_dbg(const char *tag, const uint8_t *b, size_t n)
{
    size_t i;
    fprintf(stderr, "dbg %s ", tag);
    for (i = 0; i < n; i++) {
        fprintf(stderr, "%02x", b[i]);
    }
    fprintf(stderr, "\n");
}
#define WG_LOG(tag, b, n) wg_dbg(tag, b, n)
#else
#define WG_LOG(tag, b, n) ((void)0)
#endif

#include "wg_crypto.h"
#include "wg_proto.h"

#define WG_MSG_INITIATION_TYPE 1u
#define WG_MSG_RESPONSE_TYPE 2u
#define WG_MSG_COOKIE_TYPE 3u
#define WG_MSG_TRANSPORT_TYPE 4u

#define WG_INIT_MAC1_OFFSET (WG_MSG_INITIATION_BASE - 32)
#define WG_RESP_MAC1_OFFSET (WG_MSG_RESPONSE_BASE - 32)

static const char WG_CONSTRUCTION[] = "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s";
static const char WG_IDENTIFIER[] = "WireGuard v1 zx2c4 Jason@zx2c4.com";
static const char WG_LABEL_MAC1[] = "mac1----";
static const char WG_LABEL_COOKIE[] = "cookie--";

static uint8_t g_initial_chain[32];
static uint8_t g_initial_hash[32];
static int g_initialized = 0;

static void wg_proto_init_once(void)
{
    if (g_initialized) {
        return;
    }
    wg_blake2s(g_initial_chain, 32, WG_CONSTRUCTION, sizeof(WG_CONSTRUCTION) - 1);
    memcpy(g_initial_hash, g_initial_chain, 32);
    {
        wg_blake2s_ctx ctx;
        wg_blake2s_init(&ctx, 32);
        wg_blake2s_update(&ctx, g_initial_chain, 32);
        wg_blake2s_update(&ctx, WG_IDENTIFIER, sizeof(WG_IDENTIFIER) - 1);
        wg_blake2s_final(&ctx, g_initial_hash);
    }
    g_initialized = 1;
}

/* ---- byte helpers ------------------------------------------------------- */

static uint32_t wg_get32_le(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t wg_get64_le(const uint8_t *p)
{
    return (uint64_t)wg_get32_le(p) | ((uint64_t)wg_get32_le(p + 4) << 32);
}

static void wg_put32_le(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static void wg_put64_le(uint8_t *p, uint64_t v)
{
    wg_put32_le(p, (uint32_t)v);
    wg_put32_le(p + 4, (uint32_t)(v >> 32));
}

static int wg_is_zero32(const uint8_t *p)
{
    uint8_t acc = 0;
    int i;
    for (i = 0; i < 32; i++) {
        acc |= p[i];
    }
    return acc == 0;
}

/* ---- noise helpers ------------------------------------------------------ */

static void mix_hash(uint8_t hash[32], const void *data, size_t len)
{
    wg_blake2s_ctx ctx;
    wg_blake2s_init(&ctx, 32);
    wg_blake2s_update(&ctx, hash, 32);
    wg_blake2s_update(&ctx, data, len);
    wg_blake2s_final(&ctx, hash);
}

static void mix_key(uint8_t chain[32], uint8_t key[32], const void *data, size_t len)
{
    wg_kdf2(chain, key, chain, data, len);
}

static int mix_precomputed(uint8_t chain[32], uint8_t key[32], const uint8_t ss[32])
{
    if (wg_is_zero32(ss)) {
        return -1;
    }
    mix_key(chain, key, ss, 32);
    return 0;
}

void wg_tai64n_now(uint8_t out[12])
{
    struct timespec ts;
    uint64_t sec;
    uint32_t nsec;
    const uint64_t tai_label = 0x400000000000000Au;
    int i;

    /* C11 timespec_get: available on OHOS, Linux and the mingw host build. */
    timespec_get(&ts, TIME_UTC);
    sec = (uint64_t)ts.tv_sec + tai_label;
    nsec = (uint32_t)ts.tv_nsec;
    for (i = 0; i < 8; i++) {
        out[i] = (uint8_t)(sec >> (56 - 8 * i));
    }
    for (i = 0; i < 4; i++) {
        out[8 + i] = (uint8_t)(nsec >> (24 - 8 * i));
    }
}

uint32_t wg_msg_type(const uint8_t *in, size_t len)
{
    if (len < 4) {
        return 0;
    }
    return wg_get32_le(in);
}

static void wg_derive_label_key(uint8_t out[32], const char *label, const uint8_t pub[32])
{
    wg_blake2s_ctx ctx;
    wg_blake2s_init(&ctx, 32);
    wg_blake2s_update(&ctx, label, strlen(label));
    wg_blake2s_update(&ctx, pub, 32);
    wg_blake2s_final(&ctx, out);
}

/* ---- peer setup --------------------------------------------------------- */

void wg_peer_init(wg_peer *peer, const uint8_t static_priv[32], const uint8_t peer_static[32],
                  const uint8_t psk[32], const wg_awg_params *awg)
{
    wg_proto_init_once();
    memset(peer, 0, sizeof(*peer));
    memcpy(peer->static_priv, static_priv, 32);
    wg_x25519_public_key(peer->static_pub, peer->static_priv);
    memcpy(peer->peer_static, peer_static, 32);
    if (psk != NULL) {
        memcpy(peer->psk, psk, 32);
    }
    wg_derive_label_key(peer->mac1_key, WG_LABEL_MAC1, peer->peer_static);
    wg_derive_label_key(peer->cookie_key, WG_LABEL_COOKIE, peer->peer_static);
    if (awg != NULL) {
        peer->awg = *awg;
    }
    if (peer->awg.type_init == 0) {
        peer->awg.type_init = WG_MSG_INITIATION_TYPE;
    }
    if (peer->awg.type_response == 0) {
        peer->awg.type_response = WG_MSG_RESPONSE_TYPE;
    }
    if (peer->awg.type_cookie == 0) {
        peer->awg.type_cookie = WG_MSG_COOKIE_TYPE;
    }
    if (peer->awg.type_transport == 0) {
        peer->awg.type_transport = WG_MSG_TRANSPORT_TYPE;
    }
}

int wg_peer_has_session(const wg_peer *peer) { return peer->curr.valid; }

uint64_t wg_peer_session_age_ms(const wg_peer *peer, uint64_t now_ms)
{
    if (!peer->curr.valid || now_ms < peer->curr.created_ms) {
        return 0;
    }
    return now_ms - peer->curr.created_ms;
}

int wg_peer_session_usable(const wg_peer *peer, uint64_t now_ms)
{
    return peer->curr.valid && wg_peer_session_age_ms(peer, now_ms) < 180000u;
}

/* ---- keypairs ----------------------------------------------------------- */

static void replay_clear(wg_keypair *kp)
{
    memset(kp->replay, 0, sizeof(kp->replay));
    kp->recv_last = 0;
}

static void wg_new_keypair(wg_peer *peer, int is_initiator, const uint8_t chain[32],
                           uint32_t local_index, uint32_t remote_index, uint64_t now_ms)
{
    uint8_t send_key[32];
    uint8_t recv_key[32];

    if (is_initiator) {
        wg_kdf2(send_key, recv_key, chain, NULL, 0);
    } else {
        wg_kdf2(recv_key, send_key, chain, NULL, 0);
    }

    if (peer->curr.valid) {
        peer->prev = peer->curr;
        peer->prev.valid = 1;
        peer->prev.created_ms = peer->curr.created_ms;
    }
    memset(&peer->curr, 0, sizeof(peer->curr));
    memcpy(peer->curr.send_key, send_key, 32);
    memcpy(peer->curr.recv_key, recv_key, 32);
    peer->curr.valid = 1;
    peer->curr.is_initiator = is_initiator;
    peer->curr.local_index = local_index;
    peer->curr.remote_index = remote_index;
    peer->curr.created_ms = now_ms;
    replay_clear(&peer->curr);
    wg_memzero(send_key, sizeof(send_key));
    wg_memzero(recv_key, sizeof(recv_key));
}

/* ---- replay filter ------------------------------------------------------ */

static void replay_shift(wg_keypair *kp, uint64_t n)
{
    const size_t words = WG_REPLAY_WINDOW_BITS / 64;
    size_t wshift;
    size_t bshift;
    size_t i;

    if (n >= WG_REPLAY_WINDOW_BITS) {
        memset(kp->replay, 0, sizeof(kp->replay));
        return;
    }
    wshift = (size_t)(n / 64);
    bshift = (size_t)(n % 64);
    for (i = words; i-- > 0;) {
        uint64_t v = 0;
        if (i >= wshift) {
            v = kp->replay[i - wshift] << bshift;
            if (bshift != 0 && i > wshift) {
                v |= kp->replay[i - wshift - 1] >> (64 - bshift);
            }
        }
        kp->replay[i] = v;
    }
}

static int replay_precheck(const wg_keypair *kp, uint64_t counter)
{
    uint64_t c;
    uint64_t index;

    if (counter >= (uint64_t)0xFFFFFFFFFFFFE000ULL) {
        return -1;
    }
    c = counter + 1;
    if (c > kp->recv_last) {
        return 0;
    }
    index = kp->recv_last - c;
    if (index >= WG_REPLAY_WINDOW_BITS) {
        return -1;
    }
    return ((kp->replay[index / 64] >> (index % 64)) & 1u) ? -1 : 0;
}

static void replay_advance(wg_keypair *kp, uint64_t counter)
{
    uint64_t c = counter + 1;

    if (c > kp->recv_last) {
        replay_shift(kp, c - kp->recv_last);
        kp->recv_last = c;
        kp->replay[0] |= 1u;
    } else {
        uint64_t index = kp->recv_last - c;
        if (index < WG_REPLAY_WINDOW_BITS) {
            kp->replay[index / 64] |= (uint64_t)1 << (index % 64);
        }
    }
}

/* ---- mac1/mac2 ---------------------------------------------------------- */

static void wg_compute_mac1(const wg_peer *peer, const uint8_t *msg, size_t body_len, uint8_t mac1[16])
{
    wg_blake2s_keyed(mac1, 16, peer->mac1_key, 32, msg, body_len);
}

/* ---- handshake: initiation --------------------------------------------- */

int wg_handshake_create_initiation(wg_peer *peer, uint32_t local_index, uint8_t *out, size_t cap,
                                   size_t *outlen, uint64_t now_ms)
{
    size_t junk = peer->awg.enabled ? peer->awg.s1 : 0;
    size_t total = WG_MSG_INITIATION_BASE + junk;
    uint8_t *m;
    uint8_t hash[32];
    uint8_t chain[32];
    uint8_t key[32];
    uint8_t ss[32];
    uint8_t ts[12];
    uint8_t nonce[12] = {0};

    if (out == NULL || outlen == NULL || cap < total) {
        return -1;
    }
    wg_proto_init_once();

    if (junk > 0) {
        wg_random_bytes(out, junk);
    }
    m = out + junk;

    wg_random_bytes(peer->hs.eph_priv, 32);
    wg_x25519_public_key(peer->hs.eph_pub, peer->hs.eph_priv);

    wg_put32_le(m, peer->awg.type_init);
    wg_put32_le(m + 4, local_index);
    memcpy(m + 8, peer->hs.eph_pub, 32);

    memcpy(hash, g_initial_hash, 32);
    memcpy(chain, g_initial_chain, 32);

    mix_hash(hash, peer->peer_static, 32);
    mix_key(chain, key, peer->hs.eph_pub, 32);
    mix_hash(hash, peer->hs.eph_pub, 32);

    wg_x25519(ss, peer->hs.eph_priv, peer->peer_static);
    if (mix_precomputed(chain, key, ss) != 0) {
        wg_memzero(chain, sizeof(chain));
        return -1;
    }

    /* encrypted static key */
    WG_LOG("create.static.hash", hash, 32);
    WG_LOG("create.static.key", key, 32);
    wg_aead_encrypt(m + 40, m + 40 + 32, key, nonce, hash, 32, peer->static_pub, 32);
    mix_hash(hash, m + 40, 48);

    /* encrypted timestamp */
    wg_x25519(ss, peer->static_priv, peer->peer_static);
    if (mix_precomputed(chain, key, ss) != 0) {
        wg_memzero(chain, sizeof(chain));
        return -1;
    }
    wg_tai64n_now(ts);
    wg_aead_encrypt(m + 88, m + 88 + 12, key, nonce, hash, WG_KEY_LEN, ts, 12);
    mix_hash(hash, m + 88, 28);

    /* macs: they authenticate ONLY the bare message, never the junk prefix
     * (amneziawg-go appends the junk header after AddMacs). */
    {
        uint8_t mac1[16];
        wg_compute_mac1(peer, m, WG_INIT_MAC1_OFFSET, mac1);
        memcpy(m + WG_INIT_MAC1_OFFSET, mac1, 16);
        memcpy(peer->last_mac1, mac1, 16);
        peer->last_mac1_valid = 1;
        memset(m + WG_INIT_MAC1_OFFSET + 16, 0, 16);
        if (peer->have_cookie && (now_ms - peer->cookie_set_ms) < 120000u) {
            uint8_t mac2[16];
            wg_blake2s_keyed(mac2, 16, peer->cookie, 16, m, WG_INIT_MAC1_OFFSET + 16);
            memcpy(m + WG_INIT_MAC1_OFFSET + 16, mac2, 16);
        }
    }

    memcpy(peer->hs.chain_key, chain, 32);
    memcpy(peer->hs.hash, hash, 32);
    peer->hs.local_index = local_index;
    peer->hs.created_ms = now_ms;
    peer->hs.state = WG_HS_INITIATION_CREATED;

    wg_memzero(chain, sizeof(chain));
    wg_memzero(key, sizeof(key));
    wg_memzero(ss, sizeof(ss));
    *outlen = total;
    return 0;
}

/* ---- handshake: response consumption (initiator) ----------------------- */

int wg_handshake_consume_response(wg_peer *peer, const uint8_t *in, size_t len, uint64_t now_ms)
{
    size_t junk = peer->awg.enabled ? peer->awg.s2 : 0;
    const uint8_t *m;
    uint8_t hash[32];
    uint8_t chain[32];
    uint8_t key[32];
    uint8_t tau[32];
    uint8_t ss[32];
    uint8_t remote_eph[32];
    uint8_t nonce[12] = {0};
    uint32_t sender;
    uint32_t receiver;

    if (in == NULL || len != WG_MSG_RESPONSE_BASE + junk) {
        return -1;
    }
    if (peer->hs.state != WG_HS_INITIATION_CREATED) {
        return -1;
    }
    m = in + junk;
    if (wg_get32_le(m) != peer->awg.type_response) {
        return -1;
    }
    sender = wg_get32_le(m + 4);
    receiver = wg_get32_le(m + 8);
    if (receiver != peer->hs.local_index) {
        return -1;
    }

    memcpy(hash, peer->hs.hash, 32);
    memcpy(chain, peer->hs.chain_key, 32);
    memcpy(remote_eph, m + 12, 32);

    mix_hash(hash, remote_eph, 32);
    mix_key(chain, key, remote_eph, 32);

    wg_x25519(ss, peer->hs.eph_priv, remote_eph);
    if (mix_precomputed(chain, key, ss) != 0) {
        return -1;
    }
    wg_x25519(ss, peer->static_priv, remote_eph);
    if (mix_precomputed(chain, key, ss) != 0) {
        return -1;
    }

    wg_kdf3(chain, tau, key, chain, peer->psk, 32);
    mix_hash(hash, tau, 32);

    {
        uint8_t dummy[1];
        if (wg_aead_decrypt(dummy, m + 44, key, nonce, hash, WG_KEY_LEN, m + 44, 0) != 0) {
            wg_memzero(chain, sizeof(chain));
            wg_memzero(key, sizeof(key));
            return -1;
        }
    }
    mix_hash(hash, m + 44, 16);

    wg_new_keypair(peer, 1, chain, peer->hs.local_index, sender, now_ms);
    peer->hs.state = WG_HS_RESPONSE_CONSUMED;
    peer->last_recv_ms = now_ms;

    wg_memzero(chain, sizeof(chain));
    wg_memzero(key, sizeof(key));
    wg_memzero(ss, sizeof(ss));
    return 0;
}

/* ---- handshake: cookie reply ------------------------------------------- */

int wg_handshake_consume_cookie(wg_peer *peer, const uint8_t *in, size_t len, uint64_t now_ms)
{
    size_t junk = peer->awg.enabled ? peer->awg.s3 : 0;
    const uint8_t *m;
    uint8_t cookie[16];

    if (in == NULL || len != WG_MSG_COOKIE_BASE + junk) {
        return -1;
    }
    m = in + junk;
    if (wg_get32_le(m) != peer->awg.type_cookie) {
        return -1;
    }
    if (!peer->last_mac1_valid) {
        return -1;
    }
    if (wg_xaead_decrypt(cookie, m + 48, peer->cookie_key, m + 8, peer->last_mac1, 16, m + 32, 16) != 0) {
        return -1;
    }
    memcpy(peer->cookie, cookie, 16);
    peer->have_cookie = 1;
    peer->cookie_set_ms = now_ms;
    wg_memzero(cookie, sizeof(cookie));
    return 0;
}

/* ---- handshake: initiation consumption (responder role) ---------------- */

int wg_handshake_consume_initiation(wg_peer *peer, uint32_t local_index, const uint8_t *in, size_t len,
                                    uint64_t now_ms, uint8_t *out, size_t cap, size_t *outlen)
{
    size_t junk_in = peer->awg.enabled ? peer->awg.s1 : 0;
    size_t junk_out = peer->awg.enabled ? peer->awg.s2 : 0;
    size_t out_total = WG_MSG_RESPONSE_BASE + junk_out;
    const uint8_t *m;
    uint8_t hash[32];
    uint8_t chain[32];
    uint8_t key[32];
    uint8_t tau[32];
    uint8_t ss[32];
    uint8_t remote_eph[32];
    uint8_t remote_static[32];
    uint8_t resp_eph_priv[32];
    uint8_t resp_eph_pub[32];
    uint8_t nonce[12] = {0};
    uint8_t *r;
    uint32_t sender;
    uint8_t mac1_key_self[32];
    uint8_t mac1[16];

    if (in == NULL || out == NULL || outlen == NULL || cap < out_total) {
        return -1;
    }
    if (len != WG_MSG_INITIATION_BASE + junk_in) {
        return -1;
    }
    m = in + junk_in;
    if (wg_get32_le(m) != peer->awg.type_init) {
        return -1;
    }

    wg_proto_init_once();
    wg_derive_label_key(mac1_key_self, WG_LABEL_MAC1, peer->static_pub);
    wg_blake2s_keyed(mac1, 16, mac1_key_self, 32, m, WG_INIT_MAC1_OFFSET);
    if (wg_compare16(mac1, m + WG_INIT_MAC1_OFFSET) != 0) {
        return -1;
    }

    sender = wg_get32_le(m + 4);
    memcpy(remote_eph, m + 8, 32);

    memcpy(hash, g_initial_hash, 32);
    memcpy(chain, g_initial_chain, 32);

    mix_hash(hash, peer->static_pub, 32);
    mix_hash(hash, remote_eph, 32);
    mix_key(chain, key, remote_eph, 32);

    wg_x25519(ss, peer->static_priv, remote_eph);
    if (mix_precomputed(chain, key, ss) != 0) {
        return -1;
    }

    WG_LOG("resp.static.hash", hash, 32);
    WG_LOG("resp.static.key", key, 32);
    if (wg_aead_decrypt(remote_static, m + 72, key, nonce, hash, WG_KEY_LEN, m + 40, 32) != 0) {
        return -1;
    }
    if (wg_compare16(remote_static, peer->peer_static) != 0) {
        return -1;
    }
    mix_hash(hash, m + 40, 48);

    /* static-static dh (psk-like mixing of the pre-shared long term secret) */
    wg_x25519(ss, peer->static_priv, peer->peer_static);
    if (mix_precomputed(chain, key, ss) != 0) {
        return -1;
    }

    {
        uint8_t ts[12];
        if (wg_aead_decrypt(ts, m + 100, key, nonce, hash, WG_KEY_LEN, m + 88, 12) != 0) {
            return -1;
        }
    }
    mix_hash(hash, m + 88, 28);

    /* build the response */
    if (junk_out > 0) {
        wg_random_bytes(out, junk_out);
    }
    r = out + junk_out;
    wg_random_bytes(resp_eph_priv, 32);
    wg_x25519_public_key(resp_eph_pub, resp_eph_priv);

    mix_hash(hash, resp_eph_pub, 32);
    mix_key(chain, key, resp_eph_pub, 32);
    wg_x25519(ss, resp_eph_priv, remote_eph);
    if (mix_precomputed(chain, key, ss) != 0) {
        return -1;
    }
    wg_x25519(ss, resp_eph_priv, remote_static);
    if (mix_precomputed(chain, key, ss) != 0) {
        return -1;
    }

    wg_kdf3(chain, tau, key, chain, peer->psk, 32);
    mix_hash(hash, tau, 32);

    wg_put32_le(r, peer->awg.type_response);
    wg_put32_le(r + 4, local_index);
    wg_put32_le(r + 8, sender);
    memcpy(r + 12, resp_eph_pub, 32);

    wg_aead_encrypt(r + 44, r + 44, key, nonce, hash, WG_KEY_LEN, NULL, 0);
    mix_hash(hash, r + 44, 16);

    /* responder sends with the peer mac1 key (the initiator is the receiver).
     * Only the bare message is authenticated, never the junk prefix. */
    wg_blake2s_keyed(mac1, 16, peer->mac1_key, 32, r, WG_RESP_MAC1_OFFSET);
    memcpy(r + WG_RESP_MAC1_OFFSET, mac1, 16);
    memset(r + WG_RESP_MAC1_OFFSET + 16, 0, 16);

    wg_new_keypair(peer, 0, chain, local_index, sender, now_ms);
    peer->last_recv_ms = now_ms;
    peer->hs.state = WG_HS_RESPONSE_CONSUMED;

    wg_memzero(chain, sizeof(chain));
    wg_memzero(key, sizeof(key));
    wg_memzero(ss, sizeof(ss));
    wg_memzero(resp_eph_priv, sizeof(resp_eph_priv));
    *outlen = out_total;
    return 0;
}

/* ---- transport --------------------------------------------------------- */

int wg_transport_encrypt(wg_peer *peer, const uint8_t *pt, size_t ptlen, uint8_t *out, size_t cap,
                         size_t *outlen, uint64_t now_ms)
{
    wg_keypair *kp = &peer->curr;
    size_t total = WG_MSG_TRANSPORT_HEADER + ptlen + WG_TAG_LEN;
    uint8_t nonce[12] = {0};
    uint64_t counter;

    if (!kp->valid || out == NULL || outlen == NULL || cap < total) {
        return -1;
    }
    if (now_ms - kp->created_ms >= 180000u) {
        return -2;
    }
    if (kp->send_counter >= (uint64_t)0xFFFFFFFFFFFFE000ULL) {
        return -2;
    }
    counter = kp->send_counter++;

    wg_put32_le(out, peer->awg.type_transport);
    wg_put32_le(out + 4, kp->remote_index);
    wg_put64_le(out + 8, counter);
    memcpy(nonce + 4, out + 8, 8);
    wg_aead_encrypt(out + WG_MSG_TRANSPORT_HEADER, out + WG_MSG_TRANSPORT_HEADER + ptlen, kp->send_key,
                    nonce, NULL, 0, pt, ptlen);

    *outlen = total;
    peer->last_send_ms = now_ms;
    if (ptlen > 0) {
        peer->last_send_data_ms = now_ms;
    }
    return 0;
}

int wg_transport_decrypt(wg_peer *peer, const uint8_t *in, size_t len, uint8_t *out, size_t cap,
                         size_t *ptlen, uint64_t now_ms)
{
    uint32_t receiver;
    uint64_t counter;
    size_t clen;
    uint8_t nonce[12] = {0};
    wg_keypair *kp = NULL;

    if (in == NULL || out == NULL || ptlen == NULL || len < WG_MSG_KEEPALIVE || len > WG_MAX_PACKET) {
        return -1;
    }
    receiver = wg_get32_le(in + 4);
    if (peer->curr.valid && peer->curr.local_index == receiver) {
        kp = &peer->curr;
    } else if (peer->prev.valid && peer->prev.local_index == receiver) {
        kp = &peer->prev;
    } else {
        return -1;
    }

    counter = wg_get64_le(in + 8);
    if (replay_precheck(kp, counter) != 0) {
        return -1;
    }
    clen = len - WG_MSG_TRANSPORT_HEADER - WG_TAG_LEN;
    if (cap < clen) {
        return -1;
    }
    memcpy(nonce + 4, in + 8, 8);
    if (wg_aead_decrypt(out, in + WG_MSG_TRANSPORT_HEADER + clen, kp->recv_key, nonce, NULL, 0,
                        in + WG_MSG_TRANSPORT_HEADER, clen) != 0) {
        return -1;
    }
    replay_advance(kp, counter);
    if (kp == &peer->curr) {
        peer->last_recv_ms = now_ms;
    }
    *ptlen = clen;
    return 0;
}

/* ---- AmneziaWG junk ---------------------------------------------------- */

int wg_awg_junk_packets(const wg_awg_params *awg, uint8_t **junks, size_t *caps, size_t max)
{
    int n = 0;
    int i;

    if (awg == NULL || !awg->enabled || awg->jc == 0 || junks == NULL || caps == NULL) {
        return 0;
    }
    for (i = 0; i < (int)awg->jc && (size_t)i < max; i++) {
        size_t sz;
        size_t span;

        if (awg->jmax <= awg->jmin) {
            sz = awg->jmin;
        } else {
            uint8_t rnd[4];
            uint32_t r;
            wg_random_bytes(rnd, sizeof(rnd));
            r = wg_get32_le(rnd);
            span = (size_t)(awg->jmax - awg->jmin) + 1u;
            sz = awg->jmin + (size_t)(r % (uint32_t)span);
        }
        if (sz < 1) {
            sz = 1;
        }
        if (sz > caps[i]) {
            sz = caps[i];
        }
        if (sz == 0) {
            continue;
        }
        wg_random_bytes(junks[i], sz);
        caps[i] = sz;
        n++;
    }
    return n;
}

/* ---- dispatcher -------------------------------------------------------- */

wg_rx_kind wg_handshake_consume(wg_peer *peer, const uint8_t *in, size_t len, uint64_t now_ms,
                                uint8_t *out, size_t cap, size_t *outlen)
{
    size_t ptlen = 0;

    if (peer == NULL || in == NULL || len < 4) {
        return WG_RX_ERROR;
    }
    wg_proto_init_once();

    /* transport: length varies, so it must be matched before the fixed-size
     * handshake types (which also share the 1..4 type space). */
    if (len >= WG_MSG_KEEPALIVE && len <= WG_MAX_PACKET &&
        wg_get32_le(in) == peer->awg.type_transport) {
        if (wg_transport_decrypt(peer, in, len, out, cap, &ptlen, now_ms) != 0) {
            return WG_RX_ERROR;
        }
        if (outlen != NULL) {
            *outlen = ptlen;
        }
        return ptlen == 0 ? WG_RX_KEEPALIVE : WG_RX_TRANSPORT;
    }

    if (len == WG_MSG_COOKIE_BASE && wg_get32_le(in) == peer->awg.type_cookie) {
        return wg_handshake_consume_cookie(peer, in, len, now_ms) == 0 ? WG_RX_COOKIE : WG_RX_ERROR;
    }

    /* response: plain framing first, then the amnezia junk-prefixed framing */
    if (len == WG_MSG_RESPONSE_BASE && wg_get32_le(in) == peer->awg.type_response) {
        return wg_handshake_consume_response(peer, in, len, now_ms) == 0 ? WG_RX_RESPONSE : WG_RX_ERROR;
    }
    if (peer->awg.enabled && peer->awg.s2 != 0 && len == WG_MSG_RESPONSE_BASE + peer->awg.s2 &&
        wg_get32_le(in + peer->awg.s2) == peer->awg.type_response) {
        return wg_handshake_consume_response(peer, in, len, now_ms) == 0 ? WG_RX_RESPONSE : WG_RX_ERROR;
    }

    /* initiation: consume_initiation validates the junk prefix itself, so the
     * type field must be read past that prefix here. */
    {
        size_t off = peer->awg.enabled ? peer->awg.s1 : 0;
        if (len == WG_MSG_INITIATION_BASE + off && wg_get32_le(in + off) == peer->awg.type_init) {
            return wg_handshake_consume_initiation(peer, peer->hs.local_index, in, len, now_ms, out, cap,
                                                   outlen) == 0
                       ? WG_RX_INITIATION
                       : WG_RX_ERROR;
        }
    }

    return WG_RX_ERROR;
}
