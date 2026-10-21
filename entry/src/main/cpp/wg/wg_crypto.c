/*
 * wg_crypto.c - HMAC-BLAKE2s, the WireGuard KDF, RFC 8439 AEAD and thin
 * wrappers around the vendored Monocypher primitives.
 */
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "monocypher.h"
#include "wg_crypto.h"

/* ---- HMAC --------------------------------------------------------------- */

void wg_hmac_blake2s(uint8_t out[32], const void *key, size_t keylen,
                     const void *data, size_t datalen)
{
    uint8_t k[64];
    uint8_t ipad[64];
    uint8_t opad[64];
    uint8_t inner[32];
    wg_blake2s_ctx ctx;
    size_t i;

    memset(k, 0, sizeof(k));
    if (keylen > 64) {
        wg_blake2s(k, 32, key, keylen);
    } else if (keylen > 0) {
        memcpy(k, key, keylen);
    }

    for (i = 0; i < 64; i++) {
        ipad[i] = (uint8_t)(k[i] ^ 0x36);
        opad[i] = (uint8_t)(k[i] ^ 0x5c);
    }

    wg_blake2s_init(&ctx, 32);
    wg_blake2s_update(&ctx, ipad, sizeof(ipad));
    wg_blake2s_update(&ctx, data, datalen);
    wg_blake2s_final(&ctx, inner);

    wg_blake2s_init(&ctx, 32);
    wg_blake2s_update(&ctx, opad, sizeof(opad));
    wg_blake2s_update(&ctx, inner, sizeof(inner));
    wg_blake2s_final(&ctx, out);

    wg_memzero(k, sizeof(k));
    wg_memzero(ipad, sizeof(ipad));
    wg_memzero(opad, sizeof(opad));
    wg_memzero(inner, sizeof(inner));
}

void wg_kdf1(uint8_t t0[32], const uint8_t key[32], const void *input, size_t inlen)
{
    uint8_t prk[32];
    const uint8_t one = 0x01;

    wg_hmac_blake2s(prk, key, 32, input, inlen);
    wg_hmac_blake2s(t0, prk, 32, &one, 1);
    wg_memzero(prk, sizeof(prk));
}

void wg_kdf2(uint8_t t0[32], uint8_t t1[32], const uint8_t key[32], const void *input, size_t inlen)
{
    uint8_t prk[32];
    uint8_t buf[33];

    wg_hmac_blake2s(prk, key, 32, input, inlen);
    {
        const uint8_t one = 0x01;
        wg_hmac_blake2s(t0, prk, 32, &one, 1);
    }
    memcpy(buf, t0, 32);
    buf[32] = 0x02;
    wg_hmac_blake2s(t1, prk, 32, buf, sizeof(buf));
    wg_memzero(prk, sizeof(prk));
    wg_memzero(buf, sizeof(buf));
}

void wg_kdf3(uint8_t t0[32], uint8_t t1[32], uint8_t t2[32], const uint8_t key[32],
             const void *input, size_t inlen)
{
    uint8_t prk[32];
    uint8_t buf[33];

    wg_hmac_blake2s(prk, key, 32, input, inlen);
    {
        const uint8_t one = 0x01;
        wg_hmac_blake2s(t0, prk, 32, &one, 1);
    }
    memcpy(buf, t0, 32);
    buf[32] = 0x02;
    wg_hmac_blake2s(t1, prk, 32, buf, sizeof(buf));
    memcpy(buf, t1, 32);
    buf[32] = 0x03;
    wg_hmac_blake2s(t2, prk, 32, buf, sizeof(buf));
    wg_memzero(prk, sizeof(prk));
    wg_memzero(buf, sizeof(buf));
}

/* ---- X25519 ------------------------------------------------------------- */

void wg_x25519_public_key(uint8_t pub[32], const uint8_t priv[32])
{
    crypto_x25519_public_key(pub, priv);
}

void wg_x25519(uint8_t shared[32], const uint8_t priv[32], const uint8_t pub[32])
{
    crypto_x25519(shared, priv, pub);
}

/* ---- AEAD (RFC 8439 / XChaCha) ----------------------------------------- */

void wg_aead_encrypt(uint8_t *out, uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[12],
                     const void *ad, size_t adlen, const void *pt, size_t ptlen)
{
    uint8_t polykey[64];

    /* counter 0 block -> Poly1305 key */
    crypto_chacha20_ietf(polykey, NULL, sizeof(polykey), key, nonce, 0);
    crypto_chacha20_ietf(out, (const uint8_t *)pt, ptlen, key, nonce, 1);

    {
        crypto_poly1305_ctx pctx;
        static const uint8_t zeros[16] = {0};
        uint8_t lenbuf[16];
        uint64_t a = (uint64_t)adlen;
        uint64_t b = (uint64_t)ptlen;
        size_t i;

        for (i = 0; i < 8; i++) {
            lenbuf[i] = (uint8_t)(a >> (8 * i));
            lenbuf[8 + i] = (uint8_t)(b >> (8 * i));
        }
        crypto_poly1305_init(&pctx, polykey);
        if (adlen > 0) {
            crypto_poly1305_update(&pctx, (const uint8_t *)ad, adlen);
            if (adlen % 16 != 0) {
                crypto_poly1305_update(&pctx, zeros, 16 - (adlen % 16));
            }
        }
        if (ptlen > 0) {
            crypto_poly1305_update(&pctx, out, ptlen);
            if (ptlen % 16 != 0) {
                crypto_poly1305_update(&pctx, zeros, 16 - (ptlen % 16));
            }
        }
        crypto_poly1305_update(&pctx, lenbuf, sizeof(lenbuf));
        crypto_poly1305_final(&pctx, tag);
    }
    wg_memzero(polykey, sizeof(polykey));
}

int wg_aead_decrypt(uint8_t *out, const uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[12],
                    const void *ad, size_t adlen, const void *ct, size_t ctlen)
{
    uint8_t polykey[64];
    uint8_t realtag[16];
    crypto_poly1305_ctx pctx;
    static const uint8_t zeros[16] = {0};
    uint8_t lenbuf[16];
    uint64_t a = (uint64_t)adlen;
    uint64_t b = (uint64_t)ctlen;
    size_t i;

    crypto_chacha20_ietf(polykey, NULL, sizeof(polykey), key, nonce, 0);

    for (i = 0; i < 8; i++) {
        lenbuf[i] = (uint8_t)(a >> (8 * i));
        lenbuf[8 + i] = (uint8_t)(b >> (8 * i));
    }
    crypto_poly1305_init(&pctx, polykey);
    if (adlen > 0) {
        crypto_poly1305_update(&pctx, (const uint8_t *)ad, adlen);
        if (adlen % 16 != 0) {
            crypto_poly1305_update(&pctx, zeros, 16 - (adlen % 16));
        }
    }
    if (ctlen > 0) {
        crypto_poly1305_update(&pctx, (const uint8_t *)ct, ctlen);
        if (ctlen % 16 != 0) {
            crypto_poly1305_update(&pctx, zeros, 16 - (ctlen % 16));
        }
    }
    crypto_poly1305_update(&pctx, lenbuf, sizeof(lenbuf));
    crypto_poly1305_final(&pctx, realtag);
    wg_memzero(polykey, sizeof(polykey));

    if (wg_compare16(realtag, tag) != 0) {
        wg_memzero(realtag, sizeof(realtag));
        return -1;
    }
    crypto_chacha20_ietf(out, (const uint8_t *)ct, ctlen, key, nonce, 1);
    wg_memzero(realtag, sizeof(realtag));
    return 0;
}

void wg_xaead_encrypt(uint8_t *out, uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[24],
                      const void *ad, size_t adlen, const void *pt, size_t ptlen)
{
    crypto_aead_lock(out, tag, key, nonce, (const uint8_t *)ad, adlen,
                     (const uint8_t *)pt, ptlen);
}

int wg_xaead_decrypt(uint8_t *out, const uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[24],
                     const void *ad, size_t adlen, const void *ct, size_t ctlen)
{
    return crypto_aead_unlock(out, tag, key, nonce, (const uint8_t *)ad, adlen,
                              (const uint8_t *)ct, ctlen);
}

/* ---- misc --------------------------------------------------------------- */

int wg_compare16(const uint8_t *a, const uint8_t *b)
{
    return crypto_verify16(a, b) ? 1 : 0;
}

void wg_memzero(void *buf, size_t len)
{
    crypto_wipe(buf, len);
}

void wg_random_bytes(void *buf, size_t len)
{
    uint8_t *p = (uint8_t *)buf;
    size_t done = 0;
    int fd;

#if defined(__linux__) || defined(__OHOS__)
    fd = open("/dev/urandom", 0 /* O_RDONLY */);
    if (fd >= 0) {
        while (done < len) {
            ssize_t n = read(fd, p + done, len - done);
            if (n <= 0) {
                break;
            }
            done += (size_t)n;
        }
        close(fd);
    }
#endif
    if (done < len) {
        /* Fallback (should not happen on OHOS/Android): mix clock and address. */
        struct timespec ts;
        unsigned int seed;
        timespec_get(&ts, TIME_UTC);
        seed = (unsigned int)((uint64_t)ts.tv_nsec ^ ((uint64_t)ts.tv_sec << 8) ^ (uintptr_t)p);
        while (done < len) {
            seed = seed * 1103515245u + 12345u;
            p[done++] = (uint8_t)(seed >> 16);
        }
    }
}
