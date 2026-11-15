# Milestone 1: device test procedure and results

Goal: prove that `airplay-receiver` runs on the real hardware and that an
iPhone/Mac can play to it. Nothing is installed on the device: the binary is
copied to `/tmp` and is gone after a reboot.

## Before you start

On this PC:

```sh
sh build/fetch-deps.sh
sh build/build-host.sh        # host binary + raop_play test sender
sh build/build-arm.sh all     # build/out/baby and build/out/fab4
```

On the device: SSH enabled (*Settings → Advanced → Remote Login*), root
password usually `1234`. If SSH complains about algorithms, override
`SSH_OPTS` (see `tests/device_run.sh`).

## A. Host (this PC) with a real iPhone/Mac

1. `build/out/host/airplay-receiver --name "PC AirPlay Test" -d 3`  (raw PCM: a listener that joins late still decodes it; with `--codec wav` the header is only sent to the first listener)
2. On the iPhone: Control Centre → AirPlay → pick "PC AirPlay Test", play music.
3. Copy the `url=` from the `STREAM` line, then listen:
   `curl -s <url> | ffplay -nodisp -f s16be -ar 44100 -ac 2 -`
4. Move the volume slider, skip a track, pause, stop.

| Check | Result |
|---|---|
| Speaker visible on iPhone | |
| Music sounds right | |
| `VOLUME` lines on slider move | |
| `METADATA` line on track change | |
| `STOP` when playback stopped / iPhone switches speaker | |

## B. Automated stream test on the device

Runs the receiver on the device and the sender, mDNS lookup and capture on
this PC (exercises ARM ALAC + AES decode, reconnect, late HTTP client,
sender vanishing):

```sh
sh tests/device_run.sh <radio-ip> baby test
sh tests/device_run.sh <touch-ip> fab4 test
```

Expected: last line `ok   stream test passed`.

## C. iPhone → device

```sh
sh tests/device_run.sh <device-ip> baby run     # terminal 1, stays in foreground
sh tests/device_run.sh <device-ip> baby measure # terminal 2, while music plays
```

Within 10 s of pressing play on the iPhone, capture from this PC with the URL
from the `STREAM` line: `curl -s -m 30 <url> -o capture.wav`, then listen to it.
(`run` uses `--codec wav`; the receiver replays its first ~12 s to the first
listener, header included. Later listeners get headerless PCM.)

Repeat with Spotify Connect running, starting it both before and after the
receiver (mDNS port 5353 sharing on kernel 2.6.26, which has no
`SO_REUSEPORT`).

## Results

| Check | Radio (baby) | Touch (fab4) |
|---|---|---|
| Kernel (`uname -r`) | 2.6.26.8-rt16 (SqueezeOS 9.0.1 r17084) | |
| Binary starts, `READY` line | yes | |
| B. automated stream test | passed | |
| Speaker visible on iPhone | | |
| Captured audio sounds right | | |
| RSS while streaming (kB) | 5328 (152 idle) | |
| CPU % while streaming | ~20 % steady (RTP/decode ~15 %, HTTP ~5 %); idle ~0 % | |
| Spotify Connect started first: both visible | | |
| Receiver started first: both visible | | |
| Ctrl-C / SIGTERM exits cleanly | | |

Notes:

- Radio, 2026-11-15: free memory 8–9 MB with Spotify Connect running, so memory
  is not a constraint. librespot idles at 0 % CPU.
- Session setup costs about 4 s of CPU in the RTSP thread: the RSA-2048
  private-key operations (Apple-Challenge and AES key) in wolfSSL built
  without ARM assembly. The connection takes about 1.4 s, and the system sits
  near 100 % during that burst. Fixed: wolfSSL now uses SP math with ARM
  assembly (`-DWOLFSSL_ARM_ARCH=5`, no UMAAL), at 384 ms per RSA operation
  instead of 1413 ms (`tests/time_challenge.sh`).
- Whole system was 83 % busy while streaming with an HTTP listener, which
  includes SSH and curl serving overhead from the test itself. Two of six
  earlier runs had audible gaps (16 ms and 96 ms); these overlapped with
  measurement scripts running on the device.
