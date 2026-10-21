/*
 * Host test for the configuration bridge (entry/src/main/cpp/wg/wg_json.h).
 *
 * The device path cannot be exercised without hardware, so the parsing of the
 * JSON that ArkTS hands to open() is tested here against the exact shape
 * WgTunnel.toJson() produces.
 */
#include <cstdio>
#include <cstring>
#include <string>

#include "wg_json.h"

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond, name)                                              \
    do {                                                               \
        g_checks++;                                                    \
        if (!(cond)) {                                                 \
            g_failures++;                                              \
            std::printf("  FAIL %s\n", name);                          \
        } else {                                                       \
            std::printf("  ok   %s\n", name);                          \
        }                                                              \
    } while (0)

static std::string sample_config()
{
    /* same field set and formatting as WgTunnel.toJson() */
    return "{\"privateKey\":\"OLK4uZ1nQ3A0m1nO0d7x9pW1c2v3b4n5m6q7r8s9t0U=\","
           "\"publicKey\":\"hJ8d1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7A8B9C0=\","
           "\"peerPublicKey\":\"xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\","
           "\"presharedKey\":\"\","
           "\"host\":\"vpn.example.net\","
           "\"port\":51820,"
           "\"keepalive\":25,"
           "\"mtu\":1420,"
           "\"awg\":true,"
           "\"jc\":4,\"jmin\":40,\"jmax\":90,\"s1\":15,\"s2\":0,\"s3\":0,"
           "\"h1\":1234567,\"h2\":2345678,\"h3\":3456789,\"h4\":4567890}";
}

int main(void)
{
    std::printf("jsontest\n");

    /* ---- base64 ---- */
    const char *peer = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
    uint8_t decoded[32];
    CHECK(wg_b64_decode32(std::string(peer), decoded), "decode a 44 char key");
    CHECK(wg_b64_encode(decoded, 32) == peer, "re-encode round trips");
    CHECK(!wg_b64_decode32(std::string("short"), decoded), "reject a short key");
    CHECK(!wg_b64_decode32(std::string("!!!!"), decoded), "reject invalid characters");

    uint8_t blob[32];
    for (int i = 0; i < 32; i++) {
        blob[i] = (uint8_t)(i * 7 + 3);
    }
    uint8_t again[32];
    CHECK(wg_b64_decode32(wg_b64_encode(blob, 32), again) && std::memcmp(blob, again, 32) == 0,
          "encode/decode 32 arbitrary bytes");

    /* ---- flat JSON ---- */
    std::string cfg = sample_config();
    std::string raw;

    CHECK(wg_json_raw(cfg, "host", &raw) && raw == "vpn.example.net", "read a string value");
    CHECK(wg_json_num(cfg, "port", 0) == 51820, "read a number");
    CHECK(wg_json_num(cfg, "keepalive", 0) == 25, "read keepalive");
    CHECK(wg_json_num(cfg, "mtu", 0) == 1420, "read mtu");
    CHECK(wg_json_bool(cfg, "awg", false), "read a true boolean");
    CHECK(wg_json_num(cfg, "jc", 0) == 4, "read jc");
    CHECK(wg_json_num(cfg, "jmin", 0) == 40, "read jmin");
    CHECK(wg_json_num(cfg, "jmax", 0) == 90, "read jmax");
    CHECK(wg_json_num(cfg, "s1", 0) == 15, "read s1");
    CHECK(wg_json_num(cfg, "s2", 0) == 0, "read a zero value");
    CHECK(wg_json_num(cfg, "h1", 0) == 1234567 && wg_json_num(cfg, "h4", 0) == 4567890,
          "read the four header types");
    CHECK(wg_json_raw(cfg, "presharedKey", &raw) && raw.empty(), "read an empty string");
    CHECK(!wg_json_raw(cfg, "absentKey", &raw), "missing key is reported missing");
    CHECK(wg_json_num(cfg, "absentKey", 7) == 7, "missing number falls back");

    /* keys must be read as whole tokens: "publicKey" must not match "privateKey" */
    std::string pub;
    CHECK(wg_json_raw(cfg, "publicKey", &pub) && pub == "hJ8d1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z7A8B9C0=",
          "publicKey does not collide with privateKey");

    /* the private key survives a decode/encode trip through the bridge */
    std::string priv_b64;
    uint8_t priv[32];
    CHECK(wg_json_raw(cfg, "privateKey", &priv_b64) && wg_b64_decode32(priv_b64, priv),
          "private key decodes to 32 bytes");

    /* the peer key that the native code has to derive a public key from */
    std::string peer_b64;
    uint8_t peer_raw[32];
    CHECK(wg_json_raw(cfg, "peerPublicKey", &peer_b64) && wg_b64_decode32(peer_b64, peer_raw),
          "peer public key decodes to 32 bytes");

    /* ---- multi peer hand-off: peerCount plus peer<N><Field> keys ---- */
    std::string multi =
        "{\"privateKey\":\"OLK4uZ1nQ3A0m1nO0d7x9pW1c2v3b4n5m6q7r8s9t0U=\",\"mtu\":1420,"
        "\"peerCount\":2,\"awg\":true,\"jc\":3,\"jmin\":40,\"jmax\":90,\"s1\":12,\"s2\":8,\"s3\":0,"
        "\"h1\":77,\"h2\":88,\"h3\":99,\"h4\":111,"
        "\"peer1PublicKey\":\"FBLhjeDZg0yJl3DpUmBF6oPI9HzVPUgwzWs6Q/E4yyo=\","
        "\"peer1PresharedKey\":\"\",\"peer1Host\":\"10.0.2.2\",\"peer1Port\":51820,"
        "\"peer1Keepalive\":15,\"peer1AllowedIPs\":\"10.99.0.0/16\","
        "\"peer2PublicKey\":\"NxSJ/tFa2JtBvm3L3eFM2LOh8LioK3pHCES4QxPqAVo=\","
        "\"peer2PresharedKey\":\"c2VjcmV0c2hhcmVka2V5MTIzNDU2Nzg5MDEyMzQ1Ng==\","
        "\"peer2Host\":\"10.0.2.2\",\"peer2Port\":51821,"
        "\"peer2Keepalive\":25,\"peer2AllowedIPs\":\"192.168.50.0/24\"}";
    CHECK(wg_json_num(multi, "peerCount", 0) == 2, "read peerCount");
    CHECK(wg_json_raw(multi, "peer1PublicKey", &raw) && raw == "FBLhjeDZg0yJl3DpUmBF6oPI9HzVPUgwzWs6Q/E4yyo=",
          "read peer1PublicKey");
    CHECK(wg_json_num(multi, "peer1Port", 0) == 51820, "read peer1Port");
    CHECK(wg_json_raw(multi, "peer1AllowedIPs", &raw) && raw == "10.99.0.0/16", "read peer1AllowedIPs");
    CHECK(wg_json_raw(multi, "peer2AllowedIPs", &raw) && raw == "192.168.50.0/24",
          "read peer2AllowedIPs");
    CHECK(wg_json_num(multi, "peer2Keepalive", 0) == 25, "read peer2Keepalive");
    /* peer1* must not be confused with peer1PresharedKey or peer2* */
    CHECK(wg_json_raw(multi, "peer2Host", &raw) && raw == "10.0.2.2", "read peer2Host");
    CHECK(!wg_json_raw(multi, "peer3PublicKey", &raw), "a third peer is absent");

    /* ---- JSON produced with no whitespace vs. pretty printed ---- */
    std::string pretty = "{\n  \"host\": \"a.example.org\",\n  \"port\": 1234\n}";
    CHECK(wg_json_raw(pretty, "host", &raw) && raw == "a.example.org", "read a pretty printed string");
    CHECK(wg_json_num(pretty, "port", 0) == 1234, "read a pretty printed number");

    /* an IPv4 literal must not be mistaken for a separator */
    std::string ip = "{\"host\":\"10.0.0.7\",\"port\":51820}";
    CHECK(wg_json_raw(ip, "host", &raw) && raw == "10.0.0.7", "read an address literal");

    std::printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
