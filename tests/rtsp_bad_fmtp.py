#!/usr/bin/env python3
"""Send ANNOUNCE + SETUP with an absurd ALAC frame size (unencrypted) and
expect SETUP to be refused. usage: rtsp_bad_fmtp.py <ip> <port> [frames]"""
import socket, sys


def request(s, method, cseq, headers="", body=""):
    msg = f"{method} rtsp://x/1 RTSP/1.0\r\nCSeq: {cseq}\r\n{headers}"
    if body:
        msg += f"Content-Type: application/sdp\r\nContent-Length: {len(body)}\r\n"
    s.sendall((msg + "\r\n" + body).encode())
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = s.recv(4096)
        if not chunk:
            return ""
        data += chunk
    return data.decode(errors="replace").split("\r\n", 1)[0]


def main():
    ip, port = sys.argv[1], int(sys.argv[2])
    frames = sys.argv[3] if len(sys.argv) > 3 else "2000000000"
    sdp = (
        "v=0\r\no=iTunes 1 0 IN IP4 127.0.0.1\r\ns=iTunes\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\n"
        "m=audio 0 RTP/AVP 96\r\na=rtpmap:96 AppleLossless\r\n"
        f"a=fmtp:96 {frames} 0 16 40 10 14 2 255 0 0 44100\r\n"
    )
    s = socket.create_connection((ip, port), timeout=5)
    st = request(s, "ANNOUNCE", 1, body=sdp)
    if " 200 " not in st + " ":
        print(f"FAIL ANNOUNCE: {st!r}")
        return 1
    st = request(s, "SETUP", 2, "Transport: RTP/AVP/UDP;unicast;mode=record;control_port=6001;timing_port=6002\r\n")
    s.close()
    if " 200 " in st + " ":
        print(f"FAIL SETUP accepted frame size {frames}")
        return 1
    print(f"ok   frame size {frames} refused ({st})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
