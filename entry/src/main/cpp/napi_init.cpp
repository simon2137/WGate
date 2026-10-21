/*
 * NAPI bridge for the WireGuard/AmneziaWG core.
 *
 * The ArkTS side owns configuration, storage and the VPN extension lifecycle;
 * this module owns the crypto, the tunnel socket and the tun fd data path.
 *
 *   generateKeyPair()        -> {"private":"<b64>","public":"<b64>"}
 *   publicKeyFrom(b64)       -> "<b64>"
 *   open(configJson)         -> udp socket fd (>= 0) or a negative error code
 *   start(tunFd)             -> 0 on success
 *   stop()
 *   status()                 -> JSON snapshot for the UI
 *   logs()                   -> newest engine log lines, '\n' separated
 *   forceHandshake()
 *   probe(configJson)        -> JSON diagnostics: resolved addresses + handshake RTT
 *   version()
 *
 * The configuration JSON is flat because the NDK has no JSON parser:
 *   privateKey, mtu, peerCount,
 *   peer<N>PublicKey, peer<N>PresharedKey, peer<N>Host, peer<N>Port,
 *   peer<N>Keepalive, peer<N>AllowedIPs ("10.0.0.0/24, 0.0.0.0/0"),
 *   awg, h1..h4, jc, jmin, jmax, s1..s3
 */
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

#include "napi/native_api.h"

#include "wg/wg_crypto.h"
#include "wg/wg_engine.h"
#include "wg/wg_proto.h"

/* ---- small helpers ----------------------------------------------------- */

/* base64 and the flat-JSON reader live in a header so tools/jsontest.cpp can
 * test exactly the code that runs on the device. */
#include "wg/wg_json.h"

static std::string get_string_arg(napi_env env, napi_value value)
{
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok || len == 0) {
        return std::string();
    }
    /* the buffer needs room for the terminating NUL that N-API always writes */
    std::string buf(len + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, &buf[0], len + 1, &copied) != napi_ok) {
        return std::string();
    }
    buf.resize(copied);
    return buf;
}

static int32_t get_int_arg(napi_env env, napi_value value)
{
    int32_t v = 0;
    napi_get_value_int32(env, value, &v);
    return v;
}

static napi_value make_string(napi_env env, const std::string &s)
{
    napi_value out = nullptr;
    napi_create_string_utf8(env, s.c_str(), s.size(), &out);
    return out;
}

static napi_value make_int(napi_env env, int32_t v)
{
    napi_value out = nullptr;
    napi_create_int32(env, v, &out);
    return out;
}

/* ---- NAPI entry points ------------------------------------------------- */

static napi_value WgGenerateKeyPair(napi_env env, napi_callback_info info)
{
    uint8_t priv[32];
    uint8_t pub[32];
    std::string json;

    (void)info;
    wg_random_bytes(priv, sizeof(priv));
    /* clamp like wg(8) does: clear/set the X25519 bits before storing */
    priv[0] &= 248;
    priv[31] = (uint8_t)((priv[31] & 127) | 64);
    wg_x25519_public_key(pub, priv);

    json = "{\"private\":\"" + wg_b64_encode(priv, 32) + "\",\"public\":\"" + wg_b64_encode(pub, 32) + "\"}";
    wg_memzero(priv, sizeof(priv));
    return make_string(env, json);
}

static napi_value WgPublicKey(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    uint8_t priv[32];
    uint8_t pub[32];

    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return make_string(env, "");
    }
    if (!wg_b64_decode32(get_string_arg(env, argv[0]), priv)) {
        return make_string(env, "");
    }
    wg_x25519_public_key(pub, priv);
    wg_memzero(priv, sizeof(priv));
    return make_string(env, wg_b64_encode(pub, 32));
}

/* Parse "10.0.0.0/24, 0.0.0.0/0, ::/0" into the engine's AllowedIPs table. */
static uint32_t parse_allowed(const std::string &text, wg_allowed *out, uint32_t cap)
{
    uint32_t count = 0;
    size_t pos = 0;

    while (pos <= text.size() && count < cap) {
        size_t comma = text.find(',', pos);
        std::string item = text.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
        size_t begin = item.find_first_not_of(" \t");
        size_t end = item.find_last_not_of(" \t");
        if (begin == std::string::npos) {
            if (comma == std::string::npos) {
                break;
            }
            pos = comma + 1;
            continue;
        }
        item = item.substr(begin, end - begin + 1);

        size_t slash = item.find('/');
        std::string addr = slash == std::string::npos ? item : item.substr(0, slash);
        int bits = -1;
        if (slash != std::string::npos) {
            bits = atoi(item.c_str() + slash + 1);
        }
        uint8_t raw[16];
        wg_allowed entry;
        memset(&entry, 0, sizeof(entry));
        if (inet_pton(AF_INET, addr.c_str(), raw) == 1) {
            entry.family = 4;
            entry.bits = (uint8_t)(bits < 0 ? 32 : (bits > 32 ? 32 : bits));
            memcpy(entry.addr, raw, 4);
        } else if (inet_pton(AF_INET6, addr.c_str(), raw) == 1) {
            entry.family = 6;
            entry.bits = (uint8_t)(bits < 0 ? 128 : (bits > 128 ? 128 : bits));
            memcpy(entry.addr, raw, 16);
        } else {
            if (comma == std::string::npos) {
                break;
            }
            pos = comma + 1;
            continue;
        }
        out[count++] = entry;
        if (comma == std::string::npos) {
            break;
        }
        pos = comma + 1;
    }
    return count;
}

/**
 * Parses the flat configuration JSON into an engine config.
 * Returns 0 or the same negative codes `open()` reports.
 */
static int parse_engine_config(const std::string &json, wg_engine_config *cfg)
{
    uint8_t priv[32], psk[32];
    std::string priv_b64;
    uint32_t want;
    uint32_t i;

    memset(cfg, 0, sizeof(*cfg));
    if (!wg_json_raw(json, "privateKey", &priv_b64) || !wg_b64_decode32(priv_b64, priv)) {
        return -2;
    }
    memcpy(cfg->static_priv, priv, 32);
    wg_memzero(priv, sizeof(priv));

    cfg->mtu = (uint16_t)wg_json_num(json, "mtu", 1420);
    want = wg_json_num(json, "peerCount", 1);
    if (want == 0) {
        return -3;
    }
    if (want > WG_MAX_PEERS) {
        want = WG_MAX_PEERS;
    }
    cfg->peer_count = want;

    for (i = 0; i < want; i++) {
        char field[32];
        std::string peer_b64, host, allowed;
        uint16_t default_keepalive = (uint16_t)wg_json_num(json, "keepalive", 0);
        wg_peer_config *p = &cfg->peers[i];

        snprintf(field, sizeof(field), "peer%uPublicKey", (unsigned)(i + 1));
        if (!wg_json_raw(json, field, &peer_b64) || !wg_b64_decode32(peer_b64, p->public_key)) {
            return -4;
        }
        snprintf(field, sizeof(field), "peer%uPresharedKey", (unsigned)(i + 1));
        memset(psk, 0, sizeof(psk));
        if (wg_json_raw(json, field, &peer_b64) && !peer_b64.empty()) {
            if (!wg_b64_decode32(peer_b64, psk)) {
                return -5;
            }
        }
        memcpy(p->psk, psk, 32);
        wg_memzero(psk, sizeof(psk));
        snprintf(field, sizeof(field), "peer%uHost", (unsigned)(i + 1));
        if (!wg_json_raw(json, field, &host) || host.empty()) {
            return -6;
        }
        strncpy(p->host, host.c_str(), sizeof(p->host) - 1);
        snprintf(field, sizeof(field), "peer%uPort", (unsigned)(i + 1));
        p->port = (uint16_t)wg_json_num(json, field, 51820);
        snprintf(field, sizeof(field), "peer%uKeepalive", (unsigned)(i + 1));
        p->keepalive = (uint16_t)wg_json_num(json, field, default_keepalive);
        snprintf(field, sizeof(field), "peer%uAllowedIPs", (unsigned)(i + 1));
        if (wg_json_raw(json, field, &allowed) && !allowed.empty()) {
            p->allowed_count = parse_allowed(allowed, p->allowed, WG_MAX_ALLOWED);
        }
        if (p->allowed_count == 0) {
            /* no AllowedIPs means "everything", which is how wg-quick treats a
             * peer without any either */
            p->allowed[0].family = 4;
            p->allowed[0].bits = 0;
            p->allowed_count = 1;
        }
        if (p->port == 0) {
            return -7;
        }
    }

    cfg->awg.enabled = wg_json_bool(json, "awg", false) ? 1 : 0;
    if (cfg->awg.enabled) {
        cfg->awg.type_init = wg_json_num(json, "h1", 1);
        cfg->awg.type_response = wg_json_num(json, "h2", 2);
        cfg->awg.type_cookie = wg_json_num(json, "h3", 3);
        cfg->awg.type_transport = wg_json_num(json, "h4", 4);
        cfg->awg.jc = (uint16_t)wg_json_num(json, "jc", 0);
        cfg->awg.jmin = (uint16_t)wg_json_num(json, "jmin", 0);
        cfg->awg.jmax = (uint16_t)wg_json_num(json, "jmax", 0);
        cfg->awg.s1 = (uint16_t)wg_json_num(json, "s1", 0);
        cfg->awg.s2 = (uint16_t)wg_json_num(json, "s2", 0);
        cfg->awg.s3 = (uint16_t)wg_json_num(json, "s3", 0);
    }
    return 0;
}

static napi_value WgOpen(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    std::string json;
    wg_engine_config cfg;
    int code;

    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return make_int(env, -1);
    }
    json = get_string_arg(env, argv[0]);
    code = parse_engine_config(json, &cfg);
    if (code != 0) {
        wg_memzero(&cfg, sizeof(cfg));
        return make_int(env, code);
    }
    code = wg_engine_open(&cfg);
    wg_memzero(&cfg, sizeof(cfg));
    return make_int(env, code);
}

/* ---- endpoint diagnostics ---------------------------------------------- */

/* AmneziaWG sends at most this many junk datagrams before the initiation; the
 * engine keeps its own bound, but that macro is private to wg_engine.c. */
#define PROBE_MAX_JUNKS 8

/* Milliseconds on a monotonic-ish clock; only used for the probe RTT. */
static uint64_t probe_now_ms(void)
{
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
}

/* Formats a sockaddr the way the UI shows it: bare IPv4, bracketed IPv6. */
static void probe_format_addr(const struct sockaddr *sa, char *out, size_t cap)
{
    if (sa->sa_family == AF_INET6) {
        char tmp[64];
        const struct sockaddr_in6 *s6 = (const struct sockaddr_in6 *)sa;
        if (inet_ntop(AF_INET6, &s6->sin6_addr, tmp, sizeof(tmp)) != nullptr) {
            snprintf(out, cap, "[%s]", tmp);
            return;
        }
    } else if (sa->sa_family == AF_INET) {
        char tmp[32];
        const struct sockaddr_in *s4 = (const struct sockaddr_in *)sa;
        if (inet_ntop(AF_INET, &s4->sin_addr, tmp, sizeof(tmp)) != nullptr) {
            snprintf(out, cap, "%s", tmp);
            return;
        }
    }
    snprintf(out, cap, "?");
}

/*
 * Resolves the endpoint while the caller still can: once the VPN is up with a
 * default route, every DNS query from this process is routed into the tunnel
 * that has no session yet, so the engine's own getaddrinfo can never succeed.
 * Resolving before the tun device exists (or after the socket is protected)
 * breaks that circle. Returns "" when the name does not resolve.
 */
static napi_value WgResolve(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    struct addrinfo hints;
    struct addrinfo *res = NULL;
    char out[128];
    std::string host;

    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return make_string(env, "");
    }
    host = get_string_arg(env, argv[0]);
    if (host.empty()) {
        return make_string(env, "");
    }
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    if (getaddrinfo(host.c_str(), NULL, &hints, &res) != 0 || res == NULL) {
        return make_string(env, "");
    }
    probe_format_addr(res->ai_addr, out, sizeof(out));
    freeaddrinfo(res);
    return make_string(env, out);
}

static void probe_append_addr(std::string *out, const char *addr)
{
    if (!out->empty() && out->back() != '[') {
        out->append(",");
    }
    out->append("\"");
    out->append(addr);
    out->append("\"");
}

/**
 * Resolves the first peer's endpoint, performs one handshake attempt against it
 * and reports what happened.  This exists because the single most common
 * "the tunnel does not connect" cause is an endpoint hostname that resolves to
 * an address the server is not listening on; the engine cannot tell the user
 * that on its own, and neither can the UI without a resolver dump.
 */
static napi_value WgProbe(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    std::string json;
    std::string report;
    std::string addresses;
    wg_engine_config cfg;
    const wg_peer_config *pc;
    struct addrinfo hints;
    struct addrinfo *res = nullptr;
    struct addrinfo *it;
    char port_text[8];
    char line[512];
    char addr_text[80];
    int code;
    int gai;
    int fd = -1;
    int replied = 0;
    int handshook = 0;
    uint64_t rtt = 0;
    uint32_t idx;
    uint8_t *buf = nullptr;
    /* AmneziaWG sends up to `jc` junk datagrams before the initiation. */
    uint8_t junk_store[PROBE_MAX_JUNKS][WG_MAX_PACKET];
    uint8_t *junks[PROBE_MAX_JUNKS];
    size_t caps[PROBE_MAX_JUNKS];
    size_t outlen = 0;
    size_t i;
    wg_peer peer;

    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return make_string(env, "{\"error\":\"no configuration\"}");
    }
    json = get_string_arg(env, argv[0]);
    code = parse_engine_config(json, &cfg);
    if (code != 0) {
        snprintf(line, sizeof(line), "{\"error\":\"invalid configuration (%d)\"}", code);
        return make_string(env, line);
    }
    pc = &cfg.peers[0];

    /* 1. resolve ------------------------------------------------------- */
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    snprintf(port_text, sizeof(port_text), "%u", (unsigned)pc->port);
    gai = getaddrinfo(pc->host, port_text, &hints, &res);
    if (gai != 0 || res == nullptr) {
        snprintf(line, sizeof(line),
                 "{\"host\":\"%s\",\"port\":%u,\"addresses\":[],\"reply\":false,"
                 "\"handshake\":false,\"rttMs\":0,\"error\":\"resolve failed (%d: %s)\"}",
                 pc->host, (unsigned)pc->port, gai, gai_strerror(gai));
        wg_memzero(&cfg, sizeof(cfg));
        return make_string(env, line);
    }
    for (it = res; it != nullptr; it = it->ai_next) {
        probe_format_addr(it->ai_addr, addr_text, sizeof(addr_text));
        if (addresses.find(addr_text) == std::string::npos && addresses.size() < 200) {
            probe_append_addr(&addresses, addr_text);
        }
    }

    /* 2. one handshake attempt against the first address --------------- */
    fd = (int)socket(res->ai_family, SOCK_DGRAM, 0);
    if (fd >= 0) {
        wg_peer_init(&peer, cfg.static_priv, pc->public_key, pc->psk, &cfg.awg);
        idx = (uint32_t)(probe_now_ms() & 0xFFFFFFu) | 1u;
        peer.hs.local_index = idx;

        for (i = 0; i < PROBE_MAX_JUNKS; i++) {
            junks[i] = junk_store[i];
            caps[i] = WG_MAX_PACKET;
        }
        if (cfg.awg.enabled) {
            int njunk = wg_awg_junk_packets(&cfg.awg, junks, caps, PROBE_MAX_JUNKS);
            for (i = 0; i < (size_t)njunk; i++) {
                (void)sendto(fd, (const char *)junks[i], (int)caps[i], 0, res->ai_addr,
                             (socklen_t)res->ai_addrlen);
            }
        }
        buf = (uint8_t *)malloc(WG_MAX_PACKET);
        if (buf != nullptr &&
            wg_handshake_create_initiation(&peer, idx, buf, WG_MAX_PACKET, &outlen,
                                           probe_now_ms()) == 0) {
            uint64_t t0 = probe_now_ms();
            (void)sendto(fd, (const char *)buf, (int)outlen, 0, res->ai_addr,
                         (socklen_t)res->ai_addrlen);
            for (;;) {
                struct pollfd pfd;
                int ready;
                uint64_t spent = probe_now_ms() - t0;
                int wait_ms;

                if (spent >= 3000) {
                    break;
                }
                wait_ms = (int)(3000 - spent);
                pfd.fd = fd;
                pfd.events = POLLIN;
                pfd.revents = 0;
                ready = poll(&pfd, 1, wait_ms);
                if (ready <= 0) {
                    break;
                }
                {
                    uint8_t in[WG_MAX_PACKET];
                    int got = (int)recv(fd, (char *)in, sizeof(in), 0);
                    if (got <= 0) {
                        break;
                    }
                    replied = 1;
                    rtt = probe_now_ms() - t0;
                    if (wg_handshake_consume_response(&peer, in, (size_t)got,
                                                      probe_now_ms()) == 0) {
                        handshook = 1;
                        break;
                    }
                    /* a cookie reply is also a sign of life; keep waiting for
                     * the real response within the same budget */
                }
            }
        }
        free(buf);
        close(fd);
    }
    freeaddrinfo(res);

    /* 3. report -------------------------------------------------------- */
    snprintf(line, sizeof(line),
             "{\"host\":\"%s\",\"port\":%u,\"addresses\":[", pc->host, (unsigned)pc->port);
    report = line;
    report.append(addresses);
    snprintf(line, sizeof(line),
             "],\"reply\":%s,\"handshake\":%s,\"rttMs\":%llu,\"error\":\"%s\"}",
             replied ? "true" : "false", handshook ? "true" : "false",
             (unsigned long long)rtt,
             (replied || fd >= 0) ? "" : "socket failed");
    report.append(line);
    wg_memzero(&cfg, sizeof(cfg));
    wg_memzero(&peer, sizeof(peer));
    return make_string(env, report);
}

static napi_value WgStart(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    int32_t tun_fd;

    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return make_int(env, -1);
    }
    tun_fd = get_int_arg(env, argv[0]);
    if (tun_fd < 0) {
        return make_int(env, -2);
    }
    return make_int(env, wg_engine_start((int)tun_fd) == 0 ? 0 : -3);
}

static napi_value WgStop(napi_env env, napi_callback_info info)
{
    (void)info;
    wg_engine_stop();
    return make_int(env, 0);
}

static napi_value WgStatus(napi_env env, napi_callback_info info)
{
    wg_engine_info info_snap;
    char buf[512];
    const char *state = "idle";

    (void)info;
    wg_engine_info_snapshot(&info_snap);
    switch (info_snap.state) {
    case WG_STATE_CONNECTING: state = "connecting"; break;
    case WG_STATE_UP: state = "up"; break;
    case WG_STATE_RETRY: state = "retry"; break;
    case WG_STATE_ERROR: state = "error"; break;
    case WG_STATE_STOPPED: state = "stopped"; break;
    case WG_STATE_IDLE:
    default: state = "idle"; break;
    }
    snprintf(buf, sizeof(buf),
             "{\"state\":\"%s\",\"udpFd\":%d,\"rxBytes\":%llu,\"txBytes\":%llu,\"rxPackets\":%llu,"
             "\"txPackets\":%llu,\"handshakes\":%u,\"handshakeMs\":%llu,\"queueDrops\":%u,"
             "\"socketGen\":%u,\"peersUp\":%u,\"lastErrno\":%d}",
             state, info_snap.udp_fd, (unsigned long long)info_snap.rx_bytes,
             (unsigned long long)info_snap.tx_bytes, (unsigned long long)info_snap.rx_packets,
             (unsigned long long)info_snap.tx_packets, info_snap.handshakes,
             (unsigned long long)info_snap.handshake_ms, info_snap.queue_drops, info_snap.socket_gen,
             info_snap.peers_up, info_snap.last_errno);
    return make_string(env, buf);
}

static napi_value WgLogs(napi_env env, napi_callback_info info)
{
    char buf[4096];

    (void)info;
    wg_engine_logs(buf, sizeof(buf), 60);
    return make_string(env, buf);
}

static napi_value WgForceHandshake(napi_env env, napi_callback_info info)
{
    (void)info;
    wg_engine_force_handshake();
    return make_int(env, 0);
}

static napi_value WgClearLogs(napi_env env, napi_callback_info info)
{
    (void)info;
    wg_engine_clear_logs();
    return make_int(env, 0);
}

static napi_value WgVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    return make_string(env, "1.0.0");
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"version", nullptr, WgVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generateKeyPair", nullptr, WgGenerateKeyPair, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"publicKeyFrom", nullptr, WgPublicKey, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"open", nullptr, WgOpen, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, WgStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, WgStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, WgStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"logs", nullptr, WgLogs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearLogs", nullptr, WgClearLogs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"forceHandshake", nullptr, WgForceHandshake, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probe", nullptr, WgProbe, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"resolve", nullptr, WgResolve, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module wgcoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "wgcore",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterWgCoreModule(void)
{
    napi_module_register(&wgcoreModule);
}
