/*
 * wg_crypto.h - cryptographic primitives used by the WireGuard/AmneziaWG core.
 *
 * All functions are C11, stateless and allocation free.  x25519, ChaCha20 and
 * Poly1305 come from the vendored Monocypher 4.0.2; BLAKE2s (which Monocypher
 * does not provide) and the HMAC/KDF glue are implemented here.
 */
#ifndef WG_CRYPTO_H
#define WG_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WG_KEY_LEN 32
#define WG_TAG_LEN 16
#define WG_MAC_LEN 16

/* ---- BLAKE2s ------------------------------------------------------------ */

typedef struct {
    uint32_t h[8];
    uint32_t t[2];
    uint8_t buf[64];
    size_t buflen;
    size_t outlen;
} wg_blake2s_ctx;

void wg_blake2s_init(wg_blake2s_ctx *ctx, size_t outlen);
/* Keyed variants: keylen must be <= 32 (WG uses 16 and 32 byte keys). */
void wg_blake2s_init_key(wg_blake2s_ctx *ctx, size_t outlen, const void *key, size_t keylen);
void wg_blake2s_update(wg_blake2s_ctx *ctx, const void *in, size_t inlen);
void wg_blake2s_final(wg_blake2s_ctx *ctx, uint8_t *out);

void wg_blake2s(uint8_t *out, size_t outlen, const void *in, size_t inlen);
void wg_blake2s_keyed(uint8_t *out, size_t outlen, const void *key, size_t keylen,
                      const void *in, size_t inlen);

/* Streaming keyed helper: used for the TAI64N timestamp mac (28 bytes). */
void wg_blake2s16_keyed(uint8_t out[16], const void *key, size_t keylen,
                        const void *in, size_t inlen);

/* ---- HMAC / KDF --------------------------------------------------------- */

void wg_hmac_blake2s(uint8_t out[32], const void *key, size_t keylen,
                     const void *data, size_t datalen);

/* WireGuard KDF_n over HMAC-BLAKE2s.  t0/t1/t2 are 32 byte outputs. */
void wg_kdf1(uint8_t t0[32], const uint8_t key[32], const void *input, size_t inlen);
void wg_kdf2(uint8_t t0[32], uint8_t t1[32], const uint8_t key[32], const void *input, size_t inlen);
void wg_kdf3(uint8_t t0[32], uint8_t t1[32], uint8_t t2[32], const uint8_t key[32],
             const void *input, size_t inlen);

/* ---- X25519 ------------------------------------------------------------- */

void wg_x25519_public_key(uint8_t pub[32], const uint8_t priv[32]);
void wg_x25519(uint8_t shared[32], const uint8_t priv[32], const uint8_t pub[32]);

/* ---- AEAD --------------------------------------------------------------- */

/* RFC 8439 ChaCha20-Poly1305 (12 byte nonce).
 * encrypt: out receives ptlen ciphertext bytes, tag receives the 16 byte tag.
 * decrypt: returns 0 on success, -1 on authentication failure (out untouched). */
void wg_aead_encrypt(uint8_t *out, uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[12],
                     const void *ad, size_t adlen, const void *pt, size_t ptlen);
int wg_aead_decrypt(uint8_t *out, const uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[12],
                    const void *ad, size_t adlen, const void *ct, size_t ctlen);

/* XChaCha20-Poly1305 (24 byte nonce), used for cookie replies. */
void wg_xaead_encrypt(uint8_t *out, uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[24],
                      const void *ad, size_t adlen, const void *pt, size_t ptlen);
int wg_xaead_decrypt(uint8_t *out, const uint8_t tag[16], const uint8_t key[32], const uint8_t nonce[24],
                     const void *ad, size_t adlen, const void *ct, size_t ctlen);

/* ---- misc --------------------------------------------------------------- */

void wg_random_bytes(void *buf, size_t len);
/* Constant time comparison, returns 0 when equal. */
int wg_compare16(const uint8_t *a, const uint8_t *b);
/* memzero that will not be optimised away. */
void wg_memzero(void *buf, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* WG_CRYPTO_H */
