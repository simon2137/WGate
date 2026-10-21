/*
 * wg_blake2s.c - BLAKE2s (RFC 7693) with keyed hashing and variable output
 * length, as required by the WireGuard handshake (32 byte hash, 16 byte macs).
 */
#include <string.h>

#include "wg_crypto.h"

static const uint32_t wg_b2s_iv[8] = {
    0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u, 0xA54FF53Au,
    0x510E527Fu, 0x9B05688Cu, 0x1F83D9ABu, 0x5BE0CD19u,
};

static const uint8_t wg_b2s_sigma[10][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
    {11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
    {7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
    {9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
    {2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
    {12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
    {13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
    {6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
    {10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
};

static uint32_t wg_rotr32(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

static uint32_t wg_load32_le(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void wg_store32_le(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v);
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

#define WG_G(a, b, c, d, x, y)                       \
    do {                                             \
        v[a] = v[a] + v[b] + (x);                    \
        v[d] = wg_rotr32(v[d] ^ v[a], 16);           \
        v[c] = v[c] + v[d];                          \
        v[b] = wg_rotr32(v[b] ^ v[c], 12);           \
        v[a] = v[a] + v[b] + (y);                    \
        v[d] = wg_rotr32(v[d] ^ v[a], 8);            \
        v[c] = v[c] + v[d];                          \
        v[b] = wg_rotr32(v[b] ^ v[c], 7);            \
    } while (0)

static void wg_b2s_compress(wg_blake2s_ctx *ctx, const uint8_t block[64], int last)
{
    uint32_t m[16];
    uint32_t v[16];
    int i;
    int r;

    for (i = 0; i < 16; i++) {
        m[i] = wg_load32_le(block + 4 * i);
    }
    for (i = 0; i < 8; i++) {
        v[i] = ctx->h[i];
        v[i + 8] = wg_b2s_iv[i];
    }
    v[12] ^= ctx->t[0];
    v[13] ^= ctx->t[1];
    if (last) {
        v[14] ^= 0xFFFFFFFFu;
    }

    for (r = 0; r < 10; r++) {
        const uint8_t *s = wg_b2s_sigma[r];
        WG_G(0, 4, 8, 12, m[s[0]], m[s[1]]);
        WG_G(1, 5, 9, 13, m[s[2]], m[s[3]]);
        WG_G(2, 6, 10, 14, m[s[4]], m[s[5]]);
        WG_G(3, 7, 11, 15, m[s[6]], m[s[7]]);
        WG_G(0, 5, 10, 15, m[s[8]], m[s[9]]);
        WG_G(1, 6, 11, 12, m[s[10]], m[s[11]]);
        WG_G(2, 7, 8, 13, m[s[12]], m[s[13]]);
        WG_G(3, 4, 9, 14, m[s[14]], m[s[15]]);
    }

    for (i = 0; i < 8; i++) {
        ctx->h[i] ^= v[i] ^ v[i + 8];
    }
}

static void wg_b2s_init_internal(wg_blake2s_ctx *ctx, size_t outlen,
                                 const void *key, size_t keylen)
{
    int i;

    memset(ctx, 0, sizeof(*ctx));
    for (i = 0; i < 8; i++) {
        ctx->h[i] = wg_b2s_iv[i];
    }
    /* parameter block: digest length | key length | fanout=1 | depth=1 */
    ctx->h[0] ^= 0x01010000u ^ ((uint32_t)keylen << 8) ^ (uint32_t)outlen;
    ctx->outlen = outlen;

    if (keylen > 0) {
        uint8_t block[64];
        memset(block, 0, sizeof(block));
        memcpy(block, key, keylen);
        memcpy(ctx->buf, block, 64);
        ctx->buflen = 64;
        wg_memzero(block, sizeof(block));
    }
}

void wg_blake2s_init(wg_blake2s_ctx *ctx, size_t outlen)
{
    wg_b2s_init_internal(ctx, outlen, NULL, 0);
}

void wg_blake2s_init_key(wg_blake2s_ctx *ctx, size_t outlen, const void *key, size_t keylen)
{
    if (keylen > 32) {
        keylen = 32;
    }
    wg_b2s_init_internal(ctx, outlen, key, keylen);
}

void wg_blake2s_update(wg_blake2s_ctx *ctx, const void *in, size_t inlen)
{
    const uint8_t *p = (const uint8_t *)in;

    while (inlen > 0) {
        if (ctx->buflen == 64) {
            ctx->t[0] += 64;
            if (ctx->t[0] < 64) {
                ctx->t[1]++;
            }
            wg_b2s_compress(ctx, ctx->buf, 0);
            ctx->buflen = 0;
        }
        size_t n = 64 - ctx->buflen;
        if (n > inlen) {
            n = inlen;
        }
        memcpy(ctx->buf + ctx->buflen, p, n);
        ctx->buflen += n;
        p += n;
        inlen -= n;
    }
}

void wg_blake2s_final(wg_blake2s_ctx *ctx, uint8_t *out)
{
    size_t i;

    ctx->t[0] += (uint32_t)ctx->buflen;
    if (ctx->t[0] < (uint32_t)ctx->buflen) {
        ctx->t[1]++;
    }
    memset(ctx->buf + ctx->buflen, 0, 64 - ctx->buflen);
    wg_b2s_compress(ctx, ctx->buf, 1);

    for (i = 0; i < ctx->outlen; i++) {
        out[i] = (uint8_t)(ctx->h[i / 4] >> (8 * (i % 4)));
    }
    wg_memzero(ctx, sizeof(*ctx));
}

void wg_blake2s(uint8_t *out, size_t outlen, const void *in, size_t inlen)
{
    wg_blake2s_ctx ctx;
    wg_blake2s_init(&ctx, outlen);
    wg_blake2s_update(&ctx, in, inlen);
    wg_blake2s_final(&ctx, out);
}

void wg_blake2s_keyed(uint8_t *out, size_t outlen, const void *key, size_t keylen,
                      const void *in, size_t inlen)
{
    wg_blake2s_ctx ctx;
    wg_blake2s_init_key(&ctx, outlen, key, keylen);
    wg_blake2s_update(&ctx, in, inlen);
    wg_blake2s_final(&ctx, out);
}

void wg_blake2s16_keyed(uint8_t out[16], const void *key, size_t keylen,
                        const void *in, size_t inlen)
{
    wg_blake2s_keyed(out, 16, key, keylen, in, inlen);
}
