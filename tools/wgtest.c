/*
 * wgtest.c - host-side harness for the portable WireGuard/AmneziaWG core.
 *
 * Build (host):
 *   zig cc -std=c11 -O1 -I entry/src/main/cpp/wg -o build/wgtest.exe \
 *       tools/wgtest.c entry/src/main/cpp/wg/wg_proto.c \
 *       entry/src/main/cpp/wg/wg_crypto.c entry/src/main/cpp/wg/wg_blake2s.c \
 *       entry/src/main/cpp/wg/third_party/monocypher.c
 *
 * Modes:
 *   wgtest selftest
 *       primitive vectors + an in-process initiator/responder handshake
 *   wgtest -            interactive line protocol for interop tests:
 *       SETUP <self_priv> <peer_pub> <psk> [jc jmin jmax s1 s2]+
 *       INIT                     -> INIT <datagram-hex>
 *       RESP <init-hex> <index>  -> RESP <datagram-hex>
 *       DONE <resp-hex>          -> DONE
 *       ENC <payload-hex>        -> ENC <datagram-hex>
 *       DEC <datagram-hex>       -> DEC <payload-hex>
 *       SESS                     -> SESS <send_key> <recv_key>
 *       KEY <priv>               -> KEY <pub>
 *       QUIT
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "wg_crypto.h"
#include "wg_proto.h"

/* ---- helpers ----------------------------------------------------------- */

static int hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static size_t hex2bin(const char *hex, uint8_t *out, size_t cap)
{
    size_t n = 0;
    while (hex[0] && hex[1]) {
        int hi = hexval((unsigned char)hex[0]);
        int lo = hexval((unsigned char)hex[1]);
        if (hi < 0 || lo < 0 || n >= cap) {
            break;
        }
        out[n++] = (uint8_t)((hi << 4) | lo);
        hex += 2;
    }
    return n;
}

static void bin2hex(const uint8_t *bin, size_t len, char *out)
{
    static const char digits[] = "0123456789abcdef";
    size_t i;
    for (i = 0; i < len; i++) {
        out[i * 2] = digits[bin[i] >> 4];
        out[i * 2 + 1] = digits[bin[i] & 15];
    }
    out[len * 2] = 0;
}

static int fails;
static int checks;

static void expect(int cond, const char *what)
{
    checks++;
    if (!cond) {
        fails++;
        printf("FAIL %s\n", what);
    }
}

static void expect_hex(const uint8_t *got, size_t len, const char *want, const char *what)
{
    char buf[512];
    bin2hex(got, len, buf);
    checks++;
    if (strcmp(buf, want) != 0) {
        fails++;
        printf("FAIL %s\n  got  %s\n  want %s\n", what, buf, want);
    }
}

/* ---- primitives -------------------------------------------------------- */

static void test_blake2s(void)
{
    uint8_t d[32];
    uint8_t key[32];
    uint8_t out[16];
    size_t i;

    wg_blake2s(d, 32, "abc", 3);
    expect_hex(d, 32, "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982",
               "blake2s256(abc)");

    /* BLAKE2s-256 of the empty string */
    wg_blake2s(d, 32, "", 0);
    expect_hex(d, 32, "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9",
               "blake2s256(empty)");

    /* keyed 128-bit output: zero key, empty input */
    memset(key, 0, sizeof(key));
    wg_blake2s_keyed(out, 16, key, 32, "", 0);
    expect_hex(out, 16, "4b1fb082a728a87c3b6c6aa87b877441", "blake2s128 keyed zero-key empty");

    /* streaming split input must match one-shot */
    {
        uint8_t a[32], b[32];
        wg_blake2s_ctx ctx;
        wg_blake2s(a, 32, "The quick brown fox jumps over the lazy dog", 43);
        wg_blake2s_init(&ctx, 32);
        for (i = 0; i < 43; i += 7) {
            size_t n = 43 - i < 7 ? 43 - i : 7;
            wg_blake2s_update(&ctx, "The quick brown fox jumps over the lazy dog" + i, n);
        }
        wg_blake2s_final(&ctx, b);
        expect(memcmp(a, b, 32) == 0, "blake2s streaming == one-shot");
    }
}

static void test_aead_rfc8439(void)
{
    /* RFC 8439 2.8.2 */
    uint8_t key[32];
    uint8_t nonce[12];
    uint8_t aad[12];
    uint8_t pt[114];
    uint8_t ct[114];
    uint8_t tag[16];
    uint8_t back[114];
    uint8_t backtag[16];
    static const uint8_t ct_want[16] = {0x1a, 0xe1, 0x0b, 0x59, 0x4f, 0x09, 0xe2, 0x6a,
                                        0x7e, 0x90, 0x2e, 0xcb, 0xd0, 0x60, 0x06, 0x91};
    static const uint8_t tag_want[16] = {0xc6, 0xdd, 0xa6, 0x92, 0x88, 0x12, 0x41, 0x1b,
                                         0x2b, 0x5b, 0x2c, 0x63, 0x7b, 0x2a, 0x1a, 0x2b};
    const char *ptext = "Ladies and Gentlemen of the class of '99: If I could offer you "
                        "only one tip for the future, sunscreen would be it.";

    hex2bin("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f", key, 32);
    hex2bin("070000004041424344454647", nonce, 12);
    hex2bin("50515253c0c1c2c3c4c5c6c7", aad, 12);
    memcpy(pt, ptext, 114);

    wg_aead_encrypt(ct, tag, key, nonce, aad, 12, pt, 114);
    expect_hex(ct, 16, "d31a8d34648e60db7b86afbc53ef7ec2", "rfc8439 ciphertext[0:16]");
    expect_hex(tag, 16, "1ae10b594f09e26a7e902ecbd0600691", "rfc8439 tag");

    expect(wg_aead_decrypt(back, tag, key, nonce, aad, 12, ct, 114) == 0, "rfc8439 decrypt");
    expect(memcmp(back, pt, 114) == 0, "rfc8439 plaintext round trip");

    /* tampered tag must fail */
    tag[0] ^= 1;
    expect(wg_aead_decrypt(back, tag, key, nonce, aad, 12, ct, 114) != 0, "rfc8439 bad tag rejected");
    (void)ct_want;
    (void)tag_want;
}

static void test_x25519(void)
{
    /* RFC 7748 6.1: Alice priv/pub, Bob pub, shared secret */
    uint8_t apriv[32], apub[32], bpub[32], ss[32];
    hex2bin("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", apriv, 32);
    hex2bin("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", bpub, 32);

    wg_x25519_public_key(apub, apriv);
    expect_hex(apub, 32, "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", "rfc7748 alice pub");
    wg_x25519(ss, apriv, bpub);
    expect_hex(ss, 32, "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", "rfc7748 shared");
}

/* ---- in-process handshake ---------------------------------------------- */

static uint64_t g_now = 1700000000000ULL;

static void test_handshake_plain(void)
{
    static uint8_t ipriv[32], spub[32], spriv[32], psk[32];
    static wg_peer init, resp;
    static uint8_t msg[WG_MAX_PACKET];
    static uint8_t respmsg[WG_MAX_PACKET];
    static uint8_t payload[64];
    static uint8_t packet[WG_MAX_PACKET];
    static uint8_t plain[WG_MAX_PACKET];
    size_t len = 0, rlen = 0, plen = 0;
    size_t i;

    memset(psk, 0, sizeof(psk));
    for (i = 0; i < 32; i++) {
        ipriv[i] = (uint8_t)(i + 1);
        spriv[i] = (uint8_t)(0x40 + i);
    }
    wg_x25519_public_key(spub, spriv);
    {
        uint8_t ipub[32];
        wg_x25519_public_key(ipub, ipriv);
        wg_peer_init(&init, ipriv, spub, psk, NULL);
        wg_peer_init(&resp, spriv, ipub, psk, NULL);
    }

    expect(wg_handshake_create_initiation(&init, 0x11111111u, msg, sizeof(msg), &len, g_now) == 0,
           "create initiation");
    expect(len == WG_MSG_INITIATION_BASE, "initiation is 148 bytes");

    /* responder must be told the index it hands to the new session */
    resp.hs.local_index = 0x22222222u;
    expect(wg_handshake_consume(&resp, msg, len, g_now, respmsg, sizeof(respmsg), &rlen) == WG_RX_INITIATION,
           "responder consumes initiation");
    expect(rlen == WG_MSG_RESPONSE_BASE, "response is 92 bytes");

    expect(wg_handshake_consume(&init, respmsg, rlen, g_now, plain, sizeof(plain), &plen) == WG_RX_RESPONSE,
           "initiator consumes response");
    expect(wg_peer_has_session(&init) && wg_peer_has_session(&resp), "both sides have a session");
    expect(memcmp(init.curr.send_key, resp.curr.recv_key, 32) == 0, "initiator send == responder recv");
    expect(memcmp(init.curr.recv_key, resp.curr.send_key, 32) == 0, "initiator recv == responder send");

    /* transport data initiator -> responder */
    memset(payload, 0xab, sizeof(payload));
    expect(wg_transport_encrypt(&init, payload, sizeof(payload), packet, sizeof(packet), &len, g_now) == 0,
           "encrypt transport");
    expect(len == WG_MSG_TRANSPORT_HEADER + 64 + 16, "transport length");
    expect(wg_handshake_consume(&resp, packet, len, g_now, plain, sizeof(plain), &plen) == WG_RX_TRANSPORT,
           "responder decrypts transport");
    expect(plen == 64 && memcmp(plain, payload, 64) == 0, "transport payload matches");

    /* replay of the same counter must be rejected */
    expect(wg_handshake_consume(&resp, packet, len, g_now, plain, sizeof(plain), &plen) == WG_RX_ERROR,
           "replayed transport rejected");

    /* responder -> initiator */
    expect(wg_transport_encrypt(&resp, payload, 8, packet, sizeof(packet), &len, g_now) == 0, "responder encrypt");
    expect(wg_handshake_consume(&init, packet, len, g_now, plain, sizeof(plain), &plen) == WG_RX_TRANSPORT,
           "initiator decrypts transport");
    expect(plen == 8 && memcmp(plain, payload, 8) == 0, "reverse payload matches");

    /* keepalive: empty payload */
    expect(wg_transport_encrypt(&init, payload, 0, packet, sizeof(packet), &len, g_now) == 0, "encrypt keepalive");
    expect(len == WG_MSG_KEEPALIVE, "keepalive is 32 bytes");
    expect(wg_handshake_consume(&resp, packet, len, g_now, plain, sizeof(plain), &plen) == WG_RX_KEEPALIVE,
           "keepalive classified");
}

static void test_handshake_awg(void)
{
    static uint8_t ipriv[32], spub[32], spriv[32], psk[32];
    static wg_awg_params awg;
    static wg_peer init, resp;
    static uint8_t msg[WG_MAX_PACKET], respmsg[WG_MAX_PACKET], plain[WG_MAX_PACKET];
    size_t len = 0, rlen = 0, plen = 0;
    size_t i;

    memset(psk, 0, sizeof(psk));
    for (i = 0; i < 32; i++) {
        ipriv[i] = (uint8_t)(0x80 + i);
        spriv[i] = (uint8_t)(0x20 + i);
    }
    wg_x25519_public_key(spub, spriv);
    memset(&awg, 0, sizeof(awg));
    awg.enabled = 1;
    awg.type_init = 77;
    awg.type_response = 88;
    awg.type_cookie = 99;
    awg.type_transport = 111;
    awg.jc = 3;
    awg.jmin = 40;
    awg.jmax = 90;
    awg.s1 = 12;
    awg.s2 = 8;
    {
        uint8_t ipub[32];
        wg_x25519_public_key(ipub, ipriv);
        wg_peer_init(&init, ipriv, spub, psk, &awg);
        wg_peer_init(&resp, spriv, ipub, psk, &awg);
    }

    expect(wg_handshake_create_initiation(&init, 0x33333333u, msg, sizeof(msg), &len, g_now) == 0,
           "awg create initiation");
    expect(len == WG_MSG_INITIATION_BASE + 12, "awg initiation has s1 junk prefix");

    resp.hs.local_index = 0x44444444u;
    expect(wg_handshake_consume(&resp, msg, len, g_now, respmsg, sizeof(respmsg), &rlen) == WG_RX_INITIATION,
           "awg responder consumes initiation");
    expect(rlen == WG_MSG_RESPONSE_BASE + 8, "awg response has s2 junk prefix");

    expect(wg_handshake_consume(&init, respmsg, rlen, g_now, plain, sizeof(plain), &plen) == WG_RX_RESPONSE,
           "awg initiator consumes response");
    expect(memcmp(init.curr.send_key, resp.curr.recv_key, 32) == 0, "awg keys agree");

    /* junk datagrams */
    {
        static uint8_t j0[WG_MAX_PACKET], j1[WG_MAX_PACKET], j2[WG_MAX_PACKET];
        uint8_t *junks[3] = {j0, j1, j2};
        size_t caps[3] = {sizeof(j0), sizeof(j1), sizeof(j2)};
        int n = wg_awg_junk_packets(&awg, junks, caps, 3);
        expect(n == 3, "three junk packets");
    }
}

/* ---- interactive mode -------------------------------------------------- */

static wg_peer g_peer;
static uint8_t g_self_priv[32];
static uint8_t g_peer_pub[32];
static uint8_t g_psk[32];
static wg_awg_params g_awg;

static void cmd_setup(char *args)
{
    char *tok;
    int field = 0;

    memset(&g_awg, 0, sizeof(g_awg));
    g_awg.type_init = 1;
    g_awg.type_response = 2;
    g_awg.type_cookie = 3;
    g_awg.type_transport = 4;

    tok = strtok(args, " \t");
    while (tok != NULL) {
        switch (field) {
        case 0: hex2bin(tok, g_self_priv, 32); break;
        case 1: hex2bin(tok, g_peer_pub, 32); break;
        case 2: hex2bin(tok, g_psk, 32); break;
        case 3:
            g_awg.enabled = 1;
            g_awg.jc = (uint32_t)strtoul(tok, NULL, 10);
            break;
        case 4: g_awg.jmin = (size_t)strtoul(tok, NULL, 10); break;
        case 5: g_awg.jmax = (size_t)strtoul(tok, NULL, 10); break;
        case 6: g_awg.s1 = (size_t)strtoul(tok, NULL, 10); break;
        case 7:
            g_awg.s2 = (size_t)strtoul(tok, NULL, 10);
            g_awg.type_init = 77;
            g_awg.type_response = 88;
            g_awg.type_cookie = 99;
            g_awg.type_transport = 111;
            break;
        default: break;
        }
        field++;
        tok = strtok(NULL, " \t");
    }
    wg_peer_init(&g_peer, g_self_priv, g_peer_pub, g_psk, g_awg.enabled ? &g_awg : NULL);
    g_peer.hs.local_index = 0x1234abcd;
    printf("OK\n");
    fflush(stdout);
}

int main(int argc, char **argv)
{
    static uint8_t buf[WG_MAX_PACKET * 2];
    static uint8_t out[WG_MAX_PACKET];
    static char line[16384];
    static char hex[WG_MAX_PACKET * 4];

    if (argc > 1 && strcmp(argv[1], "selftest") == 0) {
        test_blake2s();
        test_aead_rfc8439();
        test_x25519();
        test_handshake_plain();
        test_handshake_awg();
        printf("%d checks, %d failures\n", checks, fails);
        return fails == 0 ? 0 : 1;
    }

    while (fgets(line, sizeof(line), stdin) != NULL) {
        char *cmd, *args;
        size_t n;

        n = strlen(line);
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
            line[--n] = 0;
        }
        cmd = line;
        args = strchr(line, ' ');
        if (args != NULL) {
            *args++ = 0;
        } else {
            args = line + strlen(line);
        }

        if (strcmp(cmd, "SETUP") == 0) {
            cmd_setup(args);
        } else if (strcmp(cmd, "KEY") == 0) {
            uint8_t priv[32], pub[32];
            hex2bin(args, priv, 32);
            wg_x25519_public_key(pub, priv);
            bin2hex(pub, 32, hex);
            printf("KEY %s\n", hex);
            fflush(stdout);
        } else if (strcmp(cmd, "INIT") == 0) {
            size_t len = 0;
            if (wg_handshake_create_initiation(&g_peer, g_peer.hs.local_index, out, sizeof(out), &len,
                                               g_now) != 0) {
                printf("ERR init\n");
            } else {
                bin2hex(out, len, hex);
                printf("INIT %s\n", hex);
            }
            fflush(stdout);
        } else if (strcmp(cmd, "RESP") == 0) {
            char *hexin = args;
            char *idx;
            size_t len, olen = 0;
            uint32_t local_index;

            idx = strchr(hexin, ' ');
            if (idx != NULL) {
                *idx++ = 0;
                local_index = (uint32_t)strtoul(idx, NULL, 10);
            } else {
                local_index = 0x22222222u;
            }
            len = hex2bin(hexin, buf, sizeof(buf));
            if (wg_handshake_consume_initiation(&g_peer, local_index, buf, len, g_now, out, sizeof(out),
                                                &olen) != 0) {
                printf("ERR resp\n");
            } else {
                bin2hex(out, olen, hex);
                printf("RESP %s\n", hex);
            }
            fflush(stdout);
        } else if (strcmp(cmd, "DONE") == 0) {
            size_t len = hex2bin(args, buf, sizeof(buf));
            if (wg_handshake_consume_response(&g_peer, buf, len, g_now) != 0) {
                printf("ERR done\n");
            } else {
                printf("DONE\n");
            }
            fflush(stdout);
        } else if (strcmp(cmd, "ENC") == 0) {
            size_t len = args[0] ? hex2bin(args, buf, sizeof(buf)) : 0;
            size_t olen = 0;
            if (wg_transport_encrypt(&g_peer, buf, len, out, sizeof(out), &olen, g_now) != 0) {
                printf("ERR enc\n");
            } else {
                bin2hex(out, olen, hex);
                printf("ENC %s\n", hex);
            }
            fflush(stdout);
        } else if (strcmp(cmd, "DEC") == 0) {
            size_t len = hex2bin(args, buf, sizeof(buf));
            size_t plen = 0;
            if (wg_handshake_consume(&g_peer, buf, len, g_now, out, sizeof(out), &plen) == WG_RX_ERROR) {
                printf("ERR dec\n");
            } else {
                bin2hex(out, plen, hex);
                printf("DEC %s\n", hex);
            }
            fflush(stdout);
        } else if (strcmp(cmd, "SESS") == 0) {
            char a[65], b[65];
            bin2hex(g_peer.curr.send_key, 32, a);
            bin2hex(g_peer.curr.recv_key, 32, b);
            printf("SESS %s %s\n", a, b);
            fflush(stdout);
        } else if (strcmp(cmd, "QUIT") == 0) {
            break;
        } else {
            printf("ERR unknown\n");
            fflush(stdout);
        }
    }
    return 0;
}
