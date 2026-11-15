# Milestone 1 design: AirPlay 1 receiver proof of concept

Parent proposal: `airplay-proposal.md`.

## Intent

Find out, as cheaply as possible, whether an AirPlay 1 (RAOP) receiver can run
on a Squeezebox Radio/Touch: a static ARMv5 binary, started by hand over SSH,
that an iPhone/Mac sees as a speaker and that produces correct audio.
Everything else in the proposal (applet, SqueezePlay playback, ownership,
Now Playing) is later milestones and only worth doing if this works.

## Goals

- One static binary `airplay-receiver` for `baby` (Radio) and `fab4` (Touch),
  built reproducibly on this Linux host.
- Advertises `_raop._tcp` via mDNS under a name given on the command line.
- Accepts an AirPlay 1 stream (RSA key exchange, AES, ALAC) and exposes the
  decoded audio on a loopback HTTP port as 16-bit / 44.1 kHz / stereo PCM
  (WAV header optional, for easy checking).
- Logs volume, play/pause/stop and metadata events to stderr (used later).
- Runs under `qemu-arm -cpu arm926` on the host; then on the real device.

## Non-goals (for M1)

- No applet, Lua, supervisor, SqueezePlay integration, Now Playing, ownership.
- No AirPlay 2, no multi-room sync, no password/pairing.
- No changes to Standalone Base or Spotify Connect.

## Anti-goals

- A dynamically linked or glibc-dependent binary (won't run on the Radio).
- Pulling in OpenSSL or Rust: big, and Rust/Tokio already failed on the
  2.6.26 kernel in SBQobuzConnect.
- Writing anything outside a temp dir on the device during testing.

## Constraints

- Target: ARMv5TE soft-float (baby), ARMv6 soft-float (fab4), Linux 2.6.26.
- Toolchain: Bootlin `armv5-eabi--musl--stable-2020.02-2` (GCC 8.4), the one
  SBHttpsProxy / SBStandaloneBase use and have validated on hardware.
  Fetched into `build/toolchains/` like `SBHttpsProxy/arm/fetch-dependencies.sh`.
- Kernel shim: link `linux26-compat.c` from Spotify Connect
  (`--wrap=epoll_create1,eventfd,socket,accept4`) if any of those are used.
- Licences: libraop, libmdns, libcodecs, dmap-parser are MIT; wolfSSL is GPLv2
  (fine for a GPL-compatible distribution; same lib SBHttpsProxy ships).

## Approaches considered

- **A. philippe44's libraop receiver (`raop_server.c` + `raop_streamer.c`) —
  chosen.** Small portable C, MIT, includes mDNS responder (libmdns), ALAC
  decoder, DMAP metadata parser, and already serves the decoded stream over
  its own HTTP server with selectable codec (`pcm`, `wav`, `mp3`, ...). The
  only heavy dependency is OpenSSL, used for just 15 calls (RSA private
  decrypt/encrypt, PEM key load, AES-CBC decrypt): replaced by wolfSSL's
  OpenSSL compatibility layer.
- B. squeezelite-esp32 `components/raop`: same lineage with mbedTLS, but tied
  to FreeRTOS/ESP-IDF; porting back to Linux is more work than A.
- C. shairport-sync classic mode: most complete, most dependencies; not worth
  it for a feasibility test.

## Design

```
iPhone ──RAOP──► airplay-receiver (static ARM)
                   ├─ libmdns: advertises _raop._tcp
                   ├─ raop_server: RTSP, RSA/AES via wolfSSL
                   ├─ raop_streamer: RTP, ALAC decode, timing
                   └─ built-in HTTP :<port> → PCM/WAV
test: curl http://127.0.0.1:<port>/... > out.wav   (on device or host)
```

Repository layout (this folder becomes the project repo):

- `third_party/` — pinned sources: libraop (+ submodules libmdns, libcodecs
  addons/encoder, dmap-parser, crosstools), wolfSSL, linux26-compat.c.
  Pinned by commit; local changes kept as patches.
- `native/airplay-receiver/main.c` — our small CLI: parse
  `--name --port --codec`, start mDNS + `raopsr_create`, print events,
  exit cleanly on SIGTERM. Modelled on how AirConnect's `airupnp` uses the
  library, minus UPnP.
- `build/fetch-deps.sh` — downloads toolchain + sources at pinned versions.
- `build/build-host.sh` — native x86 build to test against a real iPhone/Mac
  on this LAN before touching ARM.
- `build/build-arm.sh [baby|fab4|all]` — static wolfSSL, then the receiver;
  verifies with `file`/`readelf` (static, no interpreter, soft-float) and a
  `qemu-arm -cpu arm926 ... --help` smoke run.
- `docs/m1-device-test.md` — exact SSH steps and what to record (RSS, CPU %,
  audio correct, discovery on iPhone).

Encoder: build libcodecs' `encoder.c` with only PCM/WAV enabled (no shine,
FLAC, etc.) to keep the binary small.

## Done when

1. Host build: iPhone sees the speaker, plays, and `curl` captures a WAV that
   sounds correct.
2. ARM build: static, passes the qemu smoke test.
3. On a Radio over SSH: speaker appears on iPhone, captured WAV is correct,
   RSS and CPU recorded. (Requires the user's device.)

## Left to the builder

- Exact wolfSSL configure flags (needs `--enable-opensslextra`, RSA, AES-CBC,
  OAEP); trim the rest.
- Whether libmdns needs the linux26 shim or small patches for 2.6.26.
- HTTP URL path and option names of the CLI.

## Open risks

- mDNS port 5353 coexistence with librespot's responder if Spotify Connect
  is running at the same time (test both orders on the device).
- libraop's `drift`/`latencies` settings vs. SqueezePlay buffering: only
  matters from milestone 2.
