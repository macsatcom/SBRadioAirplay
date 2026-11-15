#!/usr/bin/env python3
"""Check captured receiver audio: 44.1 kHz / 16-bit / stereo, >= min seconds,
1 kHz tone on both channels, no long dropout after audio starts.
usage: check_wav.py <file> [--raw] [--min-seconds N]
  --raw: file is headerless big-endian L16 (codec pcm); otherwise WAV."""
import argparse, struct, sys
import numpy as np

RATE = 44100


def load(path, raw):
    data = open(path, "rb").read()
    if raw:
        return np.frombuffer(data[: len(data) // 4 * 4], dtype=">i2").reshape(-1, 2)
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        sys.exit("FAIL not a WAV file")
    fmt, ch, rate = struct.unpack("<HHI", data[20:28])
    bits = struct.unpack("<H", data[34:36])[0]
    if (fmt, ch, rate, bits) != (1, 2, RATE, 16):
        sys.exit(f"FAIL format fmt={fmt} ch={ch} rate={rate} bits={bits}")
    body = data[44:]
    return np.frombuffer(body[: len(body) // 4 * 4], dtype="<i2").reshape(-1, 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--raw", action="store_true")
    ap.add_argument("--min-seconds", type=float, default=3.0)
    a = ap.parse_args()

    pcm = load(a.file, a.raw)
    nz = np.nonzero(np.any(pcm != 0, axis=1))[0]
    if len(nz) == 0:
        sys.exit("FAIL all silence")
    audio = pcm[nz[0] : nz[-1] + 1]
    secs = len(audio) / RATE
    if secs < a.min_seconds:
        sys.exit(f"FAIL only {secs:.2f} s of audio")

    silent = np.all(audio == 0, axis=1).astype(np.int8)
    longest, run = 0, 0
    # longest run of zero frames inside the audio
    edges = np.diff(np.concatenate(([0], silent, [0])))
    starts, ends = np.where(edges == 1)[0], np.where(edges == -1)[0]
    if len(starts):
        longest = int((ends - starts).max())
    if longest > 4410:
        sys.exit(f"FAIL dropout of {longest} frames")

    for c in range(2):
        x = audio[:, c].astype(np.float64)
        spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
        peak = np.argmax(spec[1:]) + 1
        freq = peak * RATE / len(x)
        if abs(freq - 1000) > 5:
            sys.exit(f"FAIL channel {c} peak at {freq:.1f} Hz")
    print(f"ok   {secs:.2f} s, 1 kHz on both channels, longest gap {longest} frames")


if __name__ == "__main__":
    main()
