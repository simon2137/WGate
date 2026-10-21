#!/usr/bin/env python3
"""Independent WireGuard/AmneziaWG reference used to cross-check the C core.

Implements the responder and initiator sides of the Noise IKpsk2 handshake and
the transport data messages exactly as wireguard-go does, using Python's
hashlib (BLAKE2s) plus `cryptography` for X25519 and ChaCha20-Poly1305.  No code
is shared with the C implementation, so agreement is meaningful.
"""
import hashlib
import hmac
import struct
import sys

from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey,
    X25519PublicKey,
)
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

CONSTRUCTION = b"Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"
IDENTIFIER = b"WireGuard v1 zx2c4 Jason@zx2c4.com"
LABEL_MAC1 = b"mac1----"
LABEL_COOKIE = b"cookie--"

INITIATION_SIZE = 148
RESPONSE_SIZE = 92
COOKIE_SIZE = 64
TRANSPORT_HEADER = 16
KEEPALIVE = 32
MAX_PACKET = 2048
REPLAY_WINDOW = 2048


def blake2s(data, outlen=32, key=b""):
    return hashlib.blake2s(data, digest_size=outlen, key=key).digest()


def hmac_blake2s(key, data):
    # WireGuard's noise HMAC is a real HMAC (RFC 2104) with BLAKE2s-256 as the
    # hash function, not keyed BLAKE2s.  hashlib.blake2s has block_size 64, so
    # the stdlib hmac module reproduces wireguard-go's hmac.New(blake2s.New256).
    return hmac.new(key, data, hashlib.blake2s).digest()


def initial_chain():
    return blake2s(CONSTRUCTION)


def initial_hash():
    return blake2s(initial_chain() + IDENTIFIER)


def mix_hash(h, data):
    return blake2s(h + data)


def kdf1(key, data):
    prk = hmac_blake2s(key, data)
    return hmac_blake2s(prk, b"\x01")


def kdf2(key, data):
    prk = hmac_blake2s(key, data)
    t0 = hmac_blake2s(prk, b"\x01")
    t1 = hmac_blake2s(prk, t0 + b"\x02")
    return t0, t1


def kdf3(key, data):
    prk = hmac_blake2s(key, data)
    t0 = hmac_blake2s(prk, b"\x01")
    t1 = hmac_blake2s(prk, t0 + b"\x02")
    t2 = hmac_blake2s(prk, t1 + b"\x03")
    return t0, t1, t2


def x25519_pub(priv):
    return X25519PrivateKey.from_private_bytes(priv).public_key().public_bytes_raw()


def x25519(priv, peer_pub):
    return X25519PrivateKey.from_private_bytes(priv).exchange(X25519PublicKey.from_public_bytes(peer_pub))


def seal(key, nonce, ad, plain):
    return ChaCha20Poly1305(key).encrypt(nonce, plain, ad)


def open_(key, nonce, ad, cipher):
    return ChaCha20Poly1305(key).decrypt(nonce, cipher, ad)


def label_mac1(pub):
    return blake2s(LABEL_MAC1 + pub)


def mac1_of(pub, msg):
    """mac1 covers the message without its trailing mac1+mac2 (bare message)."""
    return blake2s(msg[:-32], 16, label_mac1(pub))


def tai64n(now=None):
    import time

    if now is None:
        now = time.time()
    sec = int(now) + 0x400000000000000A
    nsec = int((now - int(now)) * 1e9)
    return struct.pack(">QI", sec, nsec)


def replay_ok(state, counter):
    if counter >= 0xFFFFFFFFFFFFE000:
        return False
    window = state["window"]
    if counter > state["last"]:
        return True
    if counter + REPLAY_WINDOW <= state["last"]:
        return False
    return (window >> (state["last"] - counter)) & 1 == 0


def replay_advance(state, counter):
    if counter > state["last"]:
        shift = counter - state["last"]
        state["window"] = ((state["window"] << shift) | 1) & ((1 << REPLAY_WINDOW) - 1)
        state["last"] = counter
    else:
        state["window"] |= 1 << (state["last"] - counter)


class Peer:
    def __init__(self, static_priv, peer_static, psk=b"\x00" * 32, awg=None):
        self.static_priv = static_priv
        self.static_pub = x25519_pub(static_priv)
        self.peer_static = peer_static
        self.psk = psk
        self.awg = awg or {}
        self.mac1_key = label_mac1(peer_static)
        self.session = None

    # -- roles ---------------------------------------------------------
    def create_initiation(self, local_index, now=None):
        a = self.awg
        eph_priv = X25519PrivateKey.generate().private_bytes_raw()
        eph_pub = x25519_pub(eph_priv)

        h = initial_hash()
        c = initial_chain()
        h = mix_hash(h, self.peer_static)
        c = kdf1(c, eph_pub)
        h = mix_hash(h, eph_pub)
        c, key = kdf2(c, x25519(eph_priv, self.peer_static))
        static_ct = seal(key, b"\x00" * 12, h, self.static_pub)
        h = mix_hash(h, static_ct)
        c, key = kdf2(c, x25519(self.static_priv, self.peer_static))
        ts_ct = seal(key, b"\x00" * 12, h, tai64n(now))
        h = mix_hash(h, ts_ct)

        body = struct.pack("<II", a.get("type_init", 1), local_index) + eph_pub + static_ct + ts_ct
        assert len(body) == INITIATION_SIZE - 32
        body += mac1_of(self.peer_static, body + b"\x00" * 32)
        body += b"\x00" * 16
        junk = a.get("s1", 0)
        self.hs = {"hash": h, "chain": c, "eph_priv": eph_priv, "eph_pub": eph_pub,
                   "index": local_index}
        return bytes([0x11] * junk) + body

    def consume_response(self, msg, now=None):
        a = self.awg
        junk = a.get("s2", 0)
        body = msg[junk:]
        assert len(body) == RESPONSE_SIZE, len(body)
        assert struct.unpack("<I", body[0:4])[0] == a.get("type_response", 2)
        peer_idx = struct.unpack("<I", body[8:12])[0]
        assert peer_idx == self.hs["index"], (peer_idx, self.hs["index"])
        eph = body[12:44]

        h = self.hs["hash"]
        c = self.hs["chain"]
        h = mix_hash(h, eph)
        c = kdf1(c, eph)
        c = kdf1(c, x25519(self.hs["eph_priv"], eph))
        c = kdf1(c, x25519(self.static_priv, eph))
        c, tau, key = kdf3(c, self.psk)
        h = mix_hash(h, tau)
        open_(key, b"\x00" * 12, h, body[44:60])
        h = mix_hash(h, body[44:60])

        send, recv = kdf2(c, b"")
        self.session = {"send": send, "recv": recv, "remote_index": peer_idx - 0,
                        "local_index": self.hs["index"], "last": 0, "window": 0,
                        "send_counter": 0, "created": now or 0}
        self.session["remote_index"] = struct.unpack("<I", body[4:8])[0]
        return self.session

    def consume_initiation(self, msg, local_index, now=None):
        a = self.awg
        junk = a.get("s1", 0)
        body = msg[junk:]
        assert len(body) == INITIATION_SIZE, len(body)
        assert struct.unpack("<I", body[0:4])[0] == a.get("type_init", 1), body[0:4]
        want = mac1_of(self.static_pub, body)
        assert want == body[116:132], ("mac1 mismatch", want.hex(), body[116:132].hex())
        sender = struct.unpack("<I", body[4:8])[0]
        eph = body[8:40]

        h = initial_hash()
        c = initial_chain()
        h = mix_hash(h, self.static_pub)
        h = mix_hash(h, eph)
        c = kdf1(c, eph)
        c, key = kdf2(c, x25519(self.static_priv, eph))
        remote_static = open_(key, b"\x00" * 12, h, body[40:88])
        assert remote_static == self.peer_static, "static mismatch"
        h = mix_hash(h, body[40:88])
        c, key = kdf2(c, x25519(self.static_priv, self.peer_static))
        open_(key, b"\x00" * 12, h, body[88:116])
        h = mix_hash(h, body[88:116])

        eph_priv = X25519PrivateKey.generate().private_bytes_raw()
        eph_pub = x25519_pub(eph_priv)
        h = mix_hash(h, eph_pub)
        c = kdf1(c, eph_pub)
        c = kdf1(c, x25519(eph_priv, eph))
        c = kdf1(c, x25519(eph_priv, remote_static))
        c, tau, key = kdf3(c, self.psk)
        h = mix_hash(h, tau)
        empty = seal(key, b"\x00" * 12, h, b"")
        h = mix_hash(h, empty)

        out_body = struct.pack("<II", a.get("type_response", 2), local_index) + struct.pack(
            "<I", sender) + eph_pub + empty
        assert len(out_body) == RESPONSE_SIZE - 32
        out_body += mac1_of(remote_static, out_body + b"\x00" * 32)
        out_body += b"\x00" * 16

        recv, send = kdf2(c, b"")
        self.session = {"send": send, "recv": recv, "remote_index": sender,
                        "local_index": local_index, "last": 0, "window": 0,
                        "send_counter": 0, "created": now or 0}
        junk_out = a.get("s2", 0)
        return bytes([0x22] * junk_out) + out_body

    # -- transport -----------------------------------------------------
    def encrypt(self, payload):
        s = self.session
        counter = s["send_counter"]
        s["send_counter"] += 1
        hdr = struct.pack("<IIQ", self.awg.get("type_transport", 4), s["remote_index"], counter)
        nonce = b"\x00" * 4 + struct.pack("<Q", counter)
        return hdr + seal(s["send"], nonce, b"", payload)

    def decrypt(self, packet, now=None):
        s = self.session
        mtype, recv_index, counter = struct.unpack("<IIQ", packet[0:16])
        assert mtype == self.awg.get("type_transport", 4), mtype
        assert recv_index == s["local_index"], (recv_index, s["local_index"])
        assert replay_ok(s, counter), "replay"
        nonce = b"\x00" * 4 + struct.pack("<Q", counter)
        pt = open_(s["recv"], nonce, b"", packet[16:])
        replay_advance(s, counter)
        return pt


def selftest():
    """Cross-check the Python reference against itself (both roles)."""
    a_priv = bytes(range(1, 33))
    b_priv = bytes(range(0x40, 0x60))
    b_pub = x25519_pub(b_priv)
    a_pub = x25519_pub(a_priv)
    a = Peer(a_priv, b_pub)
    b = Peer(b_priv, a_pub)
    init = a.create_initiation(0x11111111)
    resp = b.consume_initiation(init, 0x22222222)
    a.consume_response(resp)
    assert a.session["send"] == b.session["recv"]
    assert a.session["recv"] == b.session["send"]
    assert b.decrypt(a.encrypt(b"hello")) == b"hello"
    assert a.decrypt(b.encrypt(b"world")) == b"world"
    print("python reference self-test ok")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        selftest()
    else:
        print(__doc__)
