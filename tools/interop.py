#!/usr/bin/env python3
"""Interop driver: the C core (build/wgtest.exe) against the Python reference.

Both directions are exercised, plain WireGuard and the AmneziaWG framing.

    python tools/interop.py            # all cases
    python tools/interop.py plain      # only the plain case
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wgref

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BIN = os.path.join(ROOT, "build", "wgtest.exe")

AWG = {"type_init": 77, "type_response": 88, "type_cookie": 99, "type_transport": 111,
       "jc": 3, "jmin": 40, "jmax": 90, "s1": 12, "s2": 8}

IPRIV = bytes(range(1, 33))
SPRIV = bytes(range(0x40, 0x60))
IPUB = wgref.x25519_pub(IPRIV)
SPUB = wgref.x25519_pub(SPRIV)
PSK = bytes(32)


class C:
    def __init__(self):
        self.p = subprocess.Popen([BIN, "-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True, bufsize=1)

    def cmd(self, line, prefix):
        self.p.stdin.write(line + "\n")
        self.p.stdin.flush()
        out = self.p.stdout.readline().strip()
        if not out.startswith(prefix):
            raise AssertionError(f"C returned {out!r} for {line[:40]!r}")
        return out[len(prefix):].strip()

    def setup(self, self_priv, peer_pub, psk, awg):
        args = f"{self_priv.hex()} {peer_pub.hex()} {psk.hex()}"
        if awg:
            args += (f" {awg['jc']} {awg['jmin']} {awg['jmax']} {awg['s1']} {awg['s2']}")
        assert self.cmd("SETUP " + args, "OK") == ""

    def close(self):
        try:
            self.p.stdin.write("QUIT\n")
            self.p.stdin.flush()
        except Exception:
            pass
        self.p.wait(timeout=5)


def case_c_initiator(name, awg):
    c = C()
    c.setup(IPRIV, SPUB, PSK, awg)
    init = bytes.fromhex(c.cmd("INIT", "INIT"))
    expected_len = wgref.INITIATION_SIZE + (awg["s1"] if awg else 0)
    assert len(init) == expected_len, (len(init), expected_len)

    resp_peer = wgref.Peer(SPRIV, IPUB, PSK, awg)
    resp = resp_peer.consume_initiation(init, 0x22222222)
    expected = wgref.RESPONSE_SIZE + (awg["s2"] if awg else 0)
    assert len(resp) == expected, (len(resp), expected)

    assert c.cmd("DONE " + resp.hex(), "DONE") == ""
    sess = c.cmd("SESS", "SESS").split()
    c_send, c_recv = bytes.fromhex(sess[0]), bytes.fromhex(sess[1])
    assert c_send == resp_peer.session["recv"], "initiator send key != responder recv key"
    assert c_recv == resp_peer.session["send"], "initiator recv key != responder send key"

    payload = bytes(range(200))
    pkt = bytes.fromhex(c.cmd("ENC " + payload.hex(), "ENC"))
    assert resp_peer.decrypt(pkt) == payload, "responder failed to decrypt C transport"

    back = resp_peer.encrypt(b"python->c payload")
    out = bytes.fromhex(c.cmd("DEC " + back.hex(), "DEC"))
    assert out == b"python->c payload", out

    c.close()
    print(f"  ok  C initiator -> python responder [{name}]")


def case_py_initiator(name, awg):
    c = C()
    c.setup(SPRIV, IPUB, PSK, awg)
    init_peer = wgref.Peer(IPRIV, SPUB, PSK, awg)
    init = init_peer.create_initiation(0x11111111)
    resp = bytes.fromhex(c.cmd(f"RESP {init.hex()} 0x22222222", "RESP"))
    expected = wgref.RESPONSE_SIZE + (awg["s2"] if awg else 0)
    assert len(resp) == expected, (len(resp), expected)

    init_peer.consume_response(resp)
    sess = c.cmd("SESS", "SESS").split()
    c_send, c_recv = bytes.fromhex(sess[0]), bytes.fromhex(sess[1])
    # C is the responder: its send key is the python initiator's recv key
    assert c_send == init_peer.session["recv"], "responder send key mismatch"
    assert c_recv == init_peer.session["send"], "responder recv key mismatch"

    payload = b"python initiator payload"
    pkt = init_peer.encrypt(payload)
    out = bytes.fromhex(c.cmd("DEC " + pkt.hex(), "DEC"))
    assert out == payload, out

    back = bytes.fromhex(c.cmd("ENC " + payload.hex(), "ENC"))
    assert init_peer.decrypt(back) == payload

    c.close()
    print(f"  ok  python initiator -> C responder [{name}]")


def main():
    if not os.path.exists(BIN):
        raise SystemExit(f"missing {BIN}; build it first")
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("all", "plain"):
        print("plain wireguard framing")
        case_c_initiator("plain", None)
        case_py_initiator("plain", None)
    if which in ("all", "awg"):
        print("amneziawg framing")
        case_c_initiator("awg", AWG)
        case_py_initiator("awg", AWG)
    print("interop ok")


if __name__ == "__main__":
    main()
