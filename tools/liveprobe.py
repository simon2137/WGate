#!/usr/bin/env python3
"""liveprobe.py — talk to a real WireGuard server with the independent reference.

Same experiment as tools/liveprobe.c, but with the Python implementation and,
crucially, full visibility: every datagram that comes back is printed with its
length and type, and transport packets are decrypted, so a silent server and a
server that answers something unexpected look different.

    python tools/liveprobe.py <host> <port> <privateB64> <peerPublicB64> [--ping 114.114.114.114]
"""
import base64
import socket
import struct
import sys
import time

import wgref


def b64(text):
    return base64.b64decode(text)


def icmp_echo(src, dst, seq=1):
    payload = b"wgtunnel-harmony"
    icmp = struct.pack("!BBHHH", 8, 0, 0, 0x1234, seq) + payload
    csum = 0
    for i in range(0, len(icmp), 2):
        csum += (icmp[i] << 8) | (icmp[i + 1] if i + 1 < len(icmp) else 0)
    while csum >> 16:
        csum = (csum & 0xFFFF) + (csum >> 16)
    icmp = icmp[:2] + struct.pack("!H", ~csum & 0xFFFF) + icmp[4:]

    total = 20 + len(icmp)
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total, 0x4242, 0, 64, 1, 0,
                     socket.inet_aton(src), socket.inet_aton(dst))
    hsum = 0
    for i in range(0, 20, 2):
        hsum += (ip[i] << 8) | ip[i + 1]
    while hsum >> 16:
        hsum = (hsum & 0xFFFF) + (hsum >> 16)
    ip = ip[:10] + struct.pack("!H", ~hsum & 0xFFFF) + ip[12:]
    return ip + icmp


def describe(inner):
    if len(inner) < 20:
        return "short"
    ver = inner[0] >> 4
    if ver != 4:
        return f"ipv{ver}"
    proto = inner[9]
    src = ".".join(str(b) for b in inner[12:16])
    dst = ".".join(str(b) for b in inner[16:20])
    kind = {1: "icmp", 6: "tcp", 17: "udp"}.get(proto, str(proto))
    extra = ""
    if proto == 1 and len(inner) > 20:
        extra = f" icmp-type={inner[20]}"
    if proto == 17 and len(inner) > 28:
        extra = f" {struct.unpack('!H', inner[20:22])[0]}->{struct.unpack('!H', inner[22:24])[0]}"
    return f"{src} -> {dst} {kind}{extra}"


def udp_dns_query(src, dst, port=53):
    """A DNS A query for example.com, so a NATed tunnel answers something."""
    q = struct.pack("!HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)
    for label in (b"example", b"com"):
        q += bytes([len(label)]) + label
    q += b"\x00" + struct.pack("!HH", 1, 1)
    udp = struct.pack("!HHHH", 40000, port, 8 + len(q), 0) + q
    total = 20 + len(udp)
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total, 0x4243, 0, 64, 17, 0,
                     socket.inet_aton(src), socket.inet_aton(dst))
    hsum = 0
    for i in range(0, 20, 2):
        hsum += (ip[i] << 8) | ip[i + 1]
    while hsum >> 16:
        hsum = (hsum & 0xFFFF) + (hsum >> 16)
    ip = ip[:10] + struct.pack("!H", ~hsum & 0xFFFF) + ip[12:]
    return ip + udp


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    host, port = sys.argv[1], int(sys.argv[2])
    priv, peer_pub = b64(sys.argv[3]), b64(sys.argv[4])
    targets = ["114.114.114.114"]
    if "--ping" in sys.argv:
        targets = sys.argv[sys.argv.index("--ping") + 1].split(",")
    dns_target = None
    if "--dns" in sys.argv:
        dns_target = sys.argv[sys.argv.index("--dns") + 1]

    me = wgref.Peer(priv, peer_pub)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    server = (host, port)
    print(f"endpoint {host}:{port}")

    index = struct.unpack("<I", b"\x11\x22\x33\x44")[0]
    init = me.create_initiation(index)
    print(f"tx initiation {len(init)} bytes")
    sock.sendto(init, server)

    session = None
    deadline = time.time() + 10
    while time.time() < deadline and session is None:
        try:
            data, addr = sock.recvfrom(2048)
        except socket.timeout:
            continue
        mtype = struct.unpack("<I", data[:4])[0]
        print(f"rx {len(data)} bytes type={mtype} from {addr[0]}:{addr[1]}")
        if mtype == 2:
            session = me.consume_response(data)
    if session is None:
        print("NO RESPONSE to the handshake")
        return 1
    print("handshake ok")

    sent = []
    for target in targets:
        inner = icmp_echo("10.0.0.6", target)
        packet = me.encrypt(inner)
        sock.sendto(packet, server)
        sent.append(f"icmp->{target}")
        print(f"tx transport {len(packet)} bytes carrying {describe(inner)}")
    if dns_target is not None:
        inner = udp_dns_query("10.0.0.6", dns_target)
        packet = me.encrypt(inner)
        sock.sendto(packet, server)
        sent.append(f"dns->{dns_target}:53")
        print(f"tx transport {len(packet)} bytes carrying {describe(inner)}")

    replies = 0
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            data, addr = sock.recvfrom(2048)
        except socket.timeout:
            continue
        mtype = struct.unpack("<I", data[:4])[0]
        print(f"rx {len(data)} bytes type={mtype}")
        if mtype == 4:
            try:
                pt = me.decrypt(data)
            except Exception as exc:  # noqa: BLE001
                print(f"   decrypt failed: {exc}")
                continue
            if len(pt) == 0:
                print("   keepalive")
                continue
            print(f"   inner {len(pt)} bytes: {describe(pt)}")
            replies += 1
        if mtype == 3:
            print("   cookie reply")
    print(f"sent {len(sent)}, decrypted replies {replies}")
    return 0 if replies > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
