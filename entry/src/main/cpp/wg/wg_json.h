/*
 * wg_json.h - the tiny base64 and flat-JSON helpers used by the NAPI bridge.
 *
 * Everything here is deliberately dependency free: the NDK ships neither a
 * base64 codec nor a JSON parser, and the configuration that crosses the
 * bridge is produced by our own ArkTS code, so a strict reader over a flat
 * object is enough.  Kept in a header so the host test in tools/jsontest.cpp
 * exercises exactly the code that runs on the device.
 */
#ifndef WG_JSON_H
#define WG_JSON_H

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

static const char WG_B64_ALPHABET[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string wg_b64_encode(const uint8_t *in, size_t len)
{
    std::string out;
    size_t i = 0;

    out.reserve(((len + 2) / 3) * 4);
    while (i + 2 < len) {
        uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8) | in[i + 2];
        out.push_back(WG_B64_ALPHABET[(v >> 18) & 0x3f]);
        out.push_back(WG_B64_ALPHABET[(v >> 12) & 0x3f]);
        out.push_back(WG_B64_ALPHABET[(v >> 6) & 0x3f]);
        out.push_back(WG_B64_ALPHABET[v & 0x3f]);
        i += 3;
    }
    if (i < len) {
        uint32_t v = (uint32_t)in[i] << 16;
        int pad = 2;
        if (i + 1 < len) {
            v |= (uint32_t)in[i + 1] << 8;
            pad = 1;
        }
        out.push_back(WG_B64_ALPHABET[(v >> 18) & 0x3f]);
        out.push_back(WG_B64_ALPHABET[(v >> 12) & 0x3f]);
        out.push_back(pad == 1 ? WG_B64_ALPHABET[(v >> 6) & 0x3f] : '=');
        out.push_back('=');
    }
    return out;
}

static int wg_b64_value(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

/* Strict decoder: requires the result to be exactly 32 bytes. */
static bool wg_b64_decode32(const std::string &in, uint8_t out[32])
{
    size_t o = 0;
    uint32_t acc = 0;
    int bits = 0;

    for (size_t i = 0; i < in.size(); i++) {
        char c = in[i];
        int v;

        if (c == '=' || c == '\n' || c == '\r' || c == ' ') {
            continue;
        }
        v = wg_b64_value(c);
        if (v < 0) {
            return false;
        }
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (o >= 32) {
                return false;
            }
            out[o++] = (uint8_t)((acc >> bits) & 0xff);
        }
    }
    return o == 32;
}

/*
 * Reads the value of `key` out of a flat JSON object.  Strings are returned
 * without their quotes, everything else as its literal token, so callers can
 * feed numbers and booleans through the same path.
 */
static bool wg_json_raw(const std::string &json, const char *key, std::string *out)
{
    std::string needle = std::string("\"") + key + "\"";
    size_t pos = json.find(needle);

    if (pos == std::string::npos) {
        return false;
    }
    pos = json.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    pos++;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' || json[pos] == '\r')) {
        pos++;
    }
    if (pos >= json.size()) {
        return false;
    }
    if (json[pos] == '"') {
        size_t end = json.find('"', pos + 1);
        if (end == std::string::npos) {
            return false;
        }
        *out = json.substr(pos + 1, end - pos - 1);
        return true;
    }
    size_t end = pos;
    while (end < json.size() && json[end] != ',' && json[end] != '}' && json[end] != '\n') {
        end++;
    }
    *out = json.substr(pos, end - pos);
    return true;
}

static uint32_t wg_json_num(const std::string &json, const char *key, uint32_t fallback)
{
    std::string raw;

    if (!wg_json_raw(json, key, &raw) || raw.empty()) {
        return fallback;
    }
    return (uint32_t)strtoul(raw.c_str(), nullptr, 10);
}

static bool wg_json_bool(const std::string &json, const char *key, bool fallback)
{
    std::string raw;

    if (!wg_json_raw(json, key, &raw)) {
        return fallback;
    }
    return raw == "true" || raw == "1";
}

#endif /* WG_JSON_H */
