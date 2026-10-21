"""A tiny WireGuard / AmneziaWG responder used to exercise the app on a device.

It speaks the plain WireGuard handshake (optionally with the AmneziaWG junk
prefix and message type substitution), decrypts transport packets and answers
ICMP echo requests with a real echo reply.  Any other inner packet is counted
but dropped.

The generated wg-quick file routes 10.99.0.0/16 into the tunnel, so

    ping -c 3 10.99.99.99

from the device goes through the VPN and is answered here.
"""
import argparse
import os
import socket
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wgref


def b64(raw):
    return __import__("base64").b64encode(raw).decode()


def checksum(data):
    if len(data) % 2:
        data += b"\x00"
    total = 0
    for i in range(0, len(data), 2):
        total += (data[i] << 8) | data[i + 1]
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def icmp_reply(pkt):
    """Turn an IPv4 ICMP echo request into its reply (or return None)."""
    if len(pkt) < 28 or (pkt[0] >> 4) != 4:
        return None
    ihl = (pkt[0] & 0x0F) * 4
    if pkt[9] != 1 or len(pkt) < ihl + 8:
        return None
    if pkt[ihl] != 8:
        return None
    body = bytearray(pkt)
    body[12:16], body[16:20] = pkt[16:20], pkt[12:16]
    body[8] = 64                      # ttl
    body[10:12] = b"\x00\x00"
    body[ihl] = 0                     # echo reply
    body[ihl + 2:ihl + 4] = b"\x00\x00"
    ck = checksum(bytes(body[ihl:]))
    body[ihl + 2:ihl + 4] = struct.pack("!H", ck)
    ck = checksum(bytes(body[0:ihl]))
    body[10:12] = struct.pack("!H", ck)
    return bytes(body)


def describe(pkt):
    if len(pkt) < 20 or (pkt[0] >> 4) != 4:
        return f"{len(pkt)} bytes"
    ihl = (pkt[0] & 0x0F) * 4
    src = ".".join(str(b) for b in pkt[12:16])
    dst = ".".join(str(b) for b in pkt[16:20])
    proto = pkt[9]
    kind = {1: "icmp", 6: "tcp", 17: "udp"}.get(proto, str(proto))
    extra = ""
    if proto == 1 and len(pkt) > ihl:
        extra = f" type={pkt[ihl]}"
    return f"{kind} {src} -> {dst}{extra} ({len(pkt)} bytes)"


def client_config(args, client_priv, client_pub, server_pub, port):
    return "\n".join([
        "[Interface]",
        f"PrivateKey = {b64(client_priv)}",
        f"Address = {args.address}",
        f"DNS = {args.dns}",
        "",
        "[Peer]",
        f"PublicKey = {b64(server_pub)}",
        f"PresharedKey = {args.psk}",
        f"Endpoint = {args.endpoint}:{port}",
        f"AllowedIPs = {args.allowed}",
        f"PersistentKeepalive = {args.keepalive}",
        "",
    ])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=51820)
    ap.add_argument("--endpoint", default="10.0.2.2", help="address the device dials")
    ap.add_argument("--address", default="10.66.0.2/32")
    ap.add_argument("--dns", default="1.1.1.1")
    ap.add_argument("--allowed", default="10.99.0.0/16")
    ap.add_argument("--keepalive", type=int, default=15)
    ap.add_argument("--psk", default="")
    ap.add_argument("--awg", action="store_true", help="use AmneziaWG 1.5 obfuscation")
    ap.add_argument("--jc", type=int, default=3)
    ap.add_argument("--jmin", type=int, default=40)
    ap.add_argument("--jmax", type=int, default=90)
    ap.add_argument("--s1", type=int, default=12)
    ap.add_argument("--s2", type=int, default=8)
    ap.add_argument("--h1", type=int, default=77)
    ap.add_argument("--h2", type=int, default=88)
    ap.add_argument("--h3", type=int, default=99)
    ap.add_argument("--h4", type=int, default=111)
    ap.add_argument("--out", default=os.path.join("build", "wg-tunnel.conf"))
    args = ap.parse_args()

    from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
    server_priv = X25519PrivateKey.generate().private_bytes_raw()
    server_pub = wgref.x25519_pub(server_priv)
    client_priv = X25519PrivateKey.generate().private_bytes_raw()
    client_pub = wgref.x25519_pub(client_priv)

    psk = bytes.fromhex(args.psk) if len(args.psk) == 64 else b"\x00" * 32
    awg = {}
    if args.awg:
        awg = {"type_init": args.h1, "type_response": args.h2, "type_cookie": args.h3,
               "type_transport": args.h4, "jc": args.jc, "jmin": args.jmin,
               "jmax": args.jmax, "s1": args.s1, "s2": args.s2}

    peer = wgref.Peer(server_priv, client_pub, psk, awg)
    type_init = args.h1 if args.awg else 1
    type_transport = args.h4 if args.awg else 4
    s1 = args.s1 if args.awg else 0

    text = client_config(args, client_priv, client_pub, server_pub, args.port)
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(text)
    print(f"server public key : {b64(server_pub)}")
    print(f"client config     : {args.out}")
    print(f"awg               : {'on' if args.awg else 'off'}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", args.port))
    print(f"listening         : udp 0.0.0.0:{args.port}")

    index = 0x1234_5678
    handshakes = 0
    packets = 0
    last_log = time.time()
    while True:
        try:
            data, addr = sock.recvfrom(4096)
        except KeyboardInterrupt:
            break
        if len(data) < 12:
            continue
        mtype = struct.unpack("<I", data[s1:s1 + 4])[0] if len(data) >= s1 + 4 else 0
        try:
            if mtype == type_init:
                resp = peer.consume_initiation(data, index)
                sock.sendto(resp, addr)
                handshakes += 1
                print(f"handshake from {addr[0]}:{addr[1]} (#{handshakes})")
                continue
            if mtype == type_transport:
                if peer.session is None:
                    continue
                inner = peer.decrypt(data)
                if len(inner) == 0:
                    print(f"keepalive from {addr[0]}:{addr[1]}")
                    continue
                packets += 1
                reply = icmp_reply(inner)
                print(f"packet #{packets}: {describe(inner)}"
                      f"{' -> replied' if reply else ' -> dropped'}")
                if reply is not None:
                    sock.sendto(peer.encrypt(reply), addr)
                continue
            print(f"unexpected message type {mtype} from {addr[0]}:{addr[1]}")
        except Exception as exc:                       # noqa: BLE001
            print(f"error: {exc!r}")
        if time.time() - last_log > 30:
            last_log = time.time()
            print(f"--- handshakes {handshakes}, packets {packets}")


if __name__ == "__main__":
    main()
