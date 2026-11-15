#!/usr/bin/env python3
"""Minimal mDNS browser: prints '<instance>\t<port>\t<txt;...>' for each _raop._tcp service found."""
import socket, struct, sys, time

SERVICE = "_raop._tcp.local"


def encode_name(name):
    out = b""
    for part in name.rstrip(".").split("."):
        out += bytes([len(part)]) + part.encode()
    return out + b"\0"


def read_name(data, off):
    labels, jumped, end = [], False, None
    while True:
        n = data[off]
        if n & 0xC0 == 0xC0:
            if not jumped:
                end = off + 2
            off = ((n & 0x3F) << 8) | data[off + 1]
            jumped = True
            continue
        if n == 0:
            off += 1
            break
        labels.append(data[off + 1:off + 1 + n].decode(errors="replace"))
        off += 1 + n
    return ".".join(labels), (end if jumped else off)


def parse(data):
    _, _, qd, an, ns, ar = struct.unpack("!6H", data[:12])
    off = 12
    for _ in range(qd):
        _, off = read_name(data, off)
        off += 4
    ptrs, srv, txt = set(), {}, {}
    for _ in range(an + ns + ar):
        name, off = read_name(data, off)
        rtype, _, _, rdlen = struct.unpack("!HHIH", data[off:off + 10])
        off += 10
        rdata = data[off:off + rdlen]
        if rtype == 12 and name.lower() == SERVICE:
            ptrs.add(read_name(data, off)[0])
        elif rtype == 33:
            srv[name] = struct.unpack("!H", rdata[4:6])[0]
        elif rtype == 16:
            items, i = [], 0
            while i < len(rdata):
                l = rdata[i]
                items.append(rdata[i + 1:i + 1 + l].decode(errors="replace"))
                i += 1 + l
            txt[name] = items
        off += rdlen
    return ptrs, srv, txt


def main():
    timeout = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
    s.settimeout(0.3)
    query = struct.pack("!6H", 0, 0, 1, 0, 0, 0) + encode_name(SERVICE) + struct.pack("!HH", 12, 0x8001)
    found, srv, txt = set(), {}, {}
    deadline = time.time() + timeout
    while time.time() < deadline:
        s.sendto(query, ("224.0.0.251", 5353))
        end = time.time() + 0.5
        while time.time() < end:
            try:
                data, _ = s.recvfrom(9000)
            except socket.timeout:
                break
            try:
                p, sr, t = parse(data)
            except Exception:
                continue
            found |= p
            srv.update(sr)
            txt.update(t)
        if found and all(f in srv for f in found):
            break
    for f in sorted(found):
        print(f"{f}\t{srv.get(f, '')}\t{';'.join(txt.get(f, []))}")
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
