#!/usr/bin/env python3
"""Send RTSP OPTIONS with an Apple-Challenge and verify the Apple-Response
signature against the well-known AirPort Express public key.
usage: rtsp_challenge.py <ip> <port>"""
import base64, os, socket, sys

# Public modulus of the AirPort Express key embedded in raop_server.c.
N = int(
    "e7d744f2a2e2788b6c1f55a08eb70544a8fa7945aa8be6c62ce5f51cbdd4dc6842fe3d1083dd2edec1bfd4252dc02e6f398bdf0e6148ea84855e2e442da6d62664f674a1f304929ade4f6893ef2df6e711a8c77a0d91c9d980822e50d12922afea40ea9f0e14c0f76938c5f3882fc0323dd9fe55155f51bb5921c201629fd73352d5e2efaabf9ba048d7b813a2b6767f6c3ccf1eb4ce673d037b0d2ea30c5fffeb06f8d08adde409571a9c689fef10728855dd8cfb9a8bef5c8943ef3b5faa15dde698beddf3599603eb3e6f61372bb628f6559f599a78bf500687aa7f4976c0562d412956f8989e18a6355bd81597825e0fc875343ec782117625cdbf98447b",
    16,
)
E = 65537


def main():
    ip, port = sys.argv[1], int(sys.argv[2])
    challenge = os.urandom(16)
    ch_b64 = base64.b64encode(challenge).decode().rstrip("=")
    req = (
        "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n"
        f"Apple-Challenge: {ch_b64}\r\n"
        "User-Agent: iTunes/12.0\r\n\r\n"
    )
    s = socket.create_connection((ip, port), timeout=5)
    s.sendall(req.encode())
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    s.close()
    head = data.decode(errors="replace")
    status = head.split("\r\n", 1)[0]
    if " 200 " not in status + " ":
        print(f"FAIL status: {status!r}")
        return 1
    resp = None
    for line in head.split("\r\n"):
        if line.lower().startswith("apple-response:"):
            resp = line.split(":", 1)[1].strip()
    if not resp:
        print("FAIL no Apple-Response")
        return 1
    sig = base64.b64decode(resp + "=" * (-len(resp) % 4))
    m = pow(int.from_bytes(sig, "big"), E, N).to_bytes(256, "big")
    # PKCS#1 v1.5 type 1: 00 01 ff.. 00 <challenge><ip><mac>
    if m[:2] != b"\x00\x01" or challenge not in m:
        print("FAIL signature does not contain challenge")
        return 1
    print("ok   Apple-Response verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
