"""Compare the C responder's intermediate handshake state with the Python reference.

Builds the C harness with WG_DEBUG and diffs the hash/key it derives for the
initiation's encrypted static block against the values computed in Python.
"""
import io
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wgref

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "build", "wgtest_dbg.exe")

IPRIV = bytes(range(1, 33))
SPRIV = bytes(range(0x40, 0x60))
IPUB = wgref.x25519_pub(IPRIV)
SPUB = wgref.x25519_pub(SPRIV)

EPH_PRIV = bytes(range(0x80, 0xA0))
EPH_PUB = wgref.x25519_pub(EPH_PRIV)


def build():
    zig = r"C:\Users\simon\AppData\Local\Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe\zig-x86_64-windows-0.17.0\zig.exe"
    src = [os.path.join(ROOT, "tools", "wgtest.c")]
    for name in ("wg_proto.c", "wg_crypto.c", "wg_blake2s.c"):
        src.append(os.path.join(ROOT, "entry", "src", "main", "cpp", "wg", name))
    src.append(os.path.join(ROOT, "entry", "src", "main", "cpp", "wg", "third_party", "monocypher.c"))
    cmd = [zig, "cc", "-std=c11", "-O0", "-DWG_DEBUG",
           "-I", os.path.join(ROOT, "entry", "src", "main", "cpp", "wg"),
           "-I", os.path.join(ROOT, "entry", "src", "main", "cpp", "wg", "third_party"),
           "-o", BIN] + src
    subprocess.run(cmd, check=True)


def expected():
    """Responder-side state before decrypting the initiator's static key."""
    h = wgref.mix_hash(wgref.initial_hash(), SPUB)
    h = wgref.mix_hash(h, EPH_PUB)
    c = wgref.kdf1(wgref.initial_chain(), EPH_PUB)
    c, key = wgref.kdf2(c, wgref.x25519(SPRIV, EPH_PUB))
    return h, key


def main():
    build()

    p = subprocess.Popen([BIN, "-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, bufsize=1)
    p.stdin.write(f"SETUP {SPRIV.hex()} {IPUB.hex()} {(bytes(32)).hex()}\n")
    p.stdin.flush()
    assert p.stdout.readline().strip() == "OK"

    # Build an initiation by hand so the ephemeral key is known.
    eph_priv, eph_pub = EPH_PRIV, EPH_PUB
    h = wgref.initial_hash()
    ch = wgref.initial_chain()
    h = wgref.mix_hash(h, SPUB)
    ch = wgref.kdf1(ch, eph_pub)
    h = wgref.mix_hash(h, eph_pub)
    ch, key = wgref.kdf2(ch, wgref.x25519(eph_priv, SPUB))
    static_ct = wgref.seal(key, bytes(12), h, IPUB)
    h = wgref.mix_hash(h, static_ct)
    ch, key = wgref.kdf2(ch, wgref.x25519(IPRIV, SPUB))
    ts_ct = wgref.seal(key, bytes(12), h, wgref.tai64n(1700000000.0))
    h = wgref.mix_hash(h, ts_ct)
    body = (bytes.fromhex("01000000") + (0x11111111).to_bytes(4, "little") + eph_pub + static_ct
            + ts_ct)
    body += wgref.mac1_of(SPUB, body + bytes(32))
    body += bytes(16)
    assert len(body) == 148

    p.stdin.write(f"RESP {body.hex()} 0x22222222\n")
    p.stdin.flush()
    out = p.stdout.readline().strip()
    p.stdin.write("QUIT\n")
    p.stdin.flush()
    err = p.stderr.read()
    p.wait(timeout=5)

    want_h, want_key = expected()
    got = {}
    for line in err.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "dbg":
            got[parts[1]] = parts[2]

    print("C responded:", out[:40])
    ok = True
    for name, want in (("resp.static.hash", want_h), ("resp.static.key", want_key)):
        have = got.get(name, "")
        same = have == want.hex()
        ok = ok and same
        print(f"{'ok  ' if same else 'FAIL'} {name}\n     c: {have}\n     py:{want.hex()}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
