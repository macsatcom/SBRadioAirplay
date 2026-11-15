#!/usr/bin/env python3
"""Debug helper: resolve an mDNS RAOP instance fully (SRV target, A record).
usage: mdns_resolve.py '<instance name, e.g. 00042026931A@Squeezebox Radio-1A>'"""
import socket, struct, sys, time
sys.path.insert(0, __import__("os").path.dirname(__file__))
from mdns_browse import encode_name, read_name


def query(name, qtype, timeout=3):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0.5)
    # QU bit set (unicast response) and also listen for multicast replies
    q = struct.pack("!6H", 0, 0, 1, 0, 0, 0) + encode_name(name) + struct.pack("!HH", qtype, 0x8001)
    answers = []
    end = time.time() + timeout
    s.sendto(q, ("224.0.0.251", 5353))
    while time.time() < end:
        try:
            data, src = s.recvfrom(9000)
        except socket.timeout:
            s.sendto(q, ("224.0.0.251", 5353)); continue
        _, flags, qd, an, ns, ar = struct.unpack("!6H", data[:12])
        off = 12
        for _ in range(qd):
            _, off = read_name(data, off); off += 4
        for _ in range(an + ns + ar):
            rname, off = read_name(data, off)
            rtype, rclass, ttl, rdlen = struct.unpack("!HHIH", data[off:off + 10]); off += 10
            rdata = data[off:off + rdlen]
            if rtype == 1:
                val = socket.inet_ntoa(rdata)
            elif rtype == 28:
                val = socket.inet_ntop(socket.AF_INET6, rdata)
            elif rtype == 33:
                val = "%s:%d" % (read_name(data, off + 6)[0], struct.unpack("!H", rdata[4:6])[0])
            else:
                val = "type%d len%d" % (rtype, rdlen)
            answers.append((src[0], rname, rtype, ttl, val))
            off += rdlen
        if answers:
            break
    return answers


inst = sys.argv[1] + "._raop._tcp.local"
srv = query(inst, 33)
for a in srv: print("SRV ", a)
targets = {a[4].rsplit(":", 1)[0] for a in srv if a[2] == 33}
for t in targets:
    for a in query(t, 1): print("A   ", a)
    for a in query(t, 28): print("AAAA", a)
