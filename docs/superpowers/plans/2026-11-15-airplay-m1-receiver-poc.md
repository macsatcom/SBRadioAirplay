# AirPlay 1 Receiver PoC (Milestone 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A static `airplay-receiver` binary that an iPhone/Mac sees as an AirPlay 1 speaker and that serves the decoded audio as PCM/WAV on a loopback HTTP port, built for host, `baby` and `fab4`.

**Architecture:** Thin C CLI (`native/airplay-receiver/main.c`) around philippe44's `libraop` receiver (`raop_server.c`, `raop_streamer.c`, `alac.c`), `libmdns` (mdnssvc + mdnssd), `dmap-parser`, `crosstools`. OpenSSL calls are satisfied by wolfSSL's OpenSSL compatibility layer. libcodecs' `encoder.c` is replaced by our own PCM/WAV-only implementation of the same `encoder.h`. One CMake project builds both host and ARM (via toolchain file).

**Tech Stack:** C99, CMake ≥ 3.16, wolfSSL 5.x (static), Bootlin `armv5-eabi--musl--stable-2020.02-2`, qemu-user, Python 3 for tests.

**Spec:** `docs/superpowers/specs/2026-11-15-airplay-m1-receiver-poc-design.md`

## Global Constraints

- Target ARM binaries: static, no `PT_INTERP`, no dynamic section, EABI5 soft-float.
- `baby` flags: `-Os -marm -march=armv5te -mtune=arm926ej-s -mfloat-abi=soft -ffunction-sections -fdata-sections`
- `fab4` flags: `-Os -marm -march=armv6 -mtune=arm1136jf-s -mfloat-abi=soft -ffunction-sections -fdata-sections`
- Toolchain: `https://toolchains.bootlin.com/downloads/releases/toolchains/armv5-eabi/tarballs/armv5-eabi--musl--stable-2020.02-2.tar.bz2`, compiler `arm-buildroot-linux-musleabi-gcc`, unpacked to `build/toolchains/`.
- Kernel: Linux 2.6.26. If the link pulls in `epoll_create1`, `eventfd`, `accept4` or `SOCK_CLOEXEC` sockets, link Spotify Connect's `native/linux26-compat/linux26-compat.c` with `-Wl,--wrap=epoll_create1,--wrap=eventfd,--wrap=socket,--wrap=accept4`.
- No OpenSSL, no Rust, no dynamic `dlopen` of crypto (`SSL_STATIC_LIB` defined).
- Audio out: 16-bit signed LE, 44100 Hz, 2 channels.
- Pinned upstream revisions: libraop `c14088da44df37f58ef7a45b8ce8a3cbc051c5e4` (with recursive submodules at that commit), Spotify Connect `main` HEAD at fetch time recorded in `third_party/VERSIONS`.
- Third-party sources are never edited in place; changes live in `patches/*.patch`, applied by the fetch script.
- Nothing is written outside `/tmp` on the device during tests.

## Review Focus

- iPhone disconnects mid-stream, then reconnects: receiver must keep advertising and accept the new session (Task 4 reconnect test).
- HTTP client (later SqueezePlay) connects after audio already started, or disconnects and reconnects: must not crash or block the RTP thread (Task 4 late/re-connect test).
- SIGTERM / SIGINT while streaming: clean exit within 2 s, mDNS goodbye sent (Task 3 signal test).
- Host with several interfaces / no default route: `--ip` override must work; without it pick the first non-loopback IPv4 (Task 3 arg test).
- Second responder on UDP 5353 (librespot running): receiver must still start (Task 6 device checklist item).

---

### Task 1: Dependency fetch, pinning and patch mechanism

**Files:**
- Create: `build/fetch-deps.sh`, `third_party/VERSIONS`, `patches/README.md`, `.gitignore`
- Test: `tests/test_fetch.sh`

**Interfaces:**
- Produces: `third_party/libraop/` (recursive submodules), `third_party/wolfssl/` (tag `v5.7.2-stable`), `third_party/linux26-compat/linux26-compat.c`, `build/toolchains/armv5-eabi--musl--stable-2020.02-2/`. `.gitignore` excludes `third_party/*/` sources and `build/toolchains`, `build/out`, `build/work`.

- [ ] **Step 1: Write `tests/test_fetch.sh`** asserting after a fetch: `third_party/libraop/src/raop_server.c`, `third_party/libraop/libmdns/mdnssvc/mdnsd.c`, `third_party/libraop/libmdns/mdnssd/mdnssd.c`, `third_party/libraop/dmap-parser/dmap_parser.c`, `third_party/wolfssl/configure.ac`, `third_party/linux26-compat/linux26-compat.c` exist; `git -C third_party/libraop rev-parse HEAD` equals the pinned hash; `build/toolchains/.../bin/arm-buildroot-linux-musleabi-gcc --version` succeeds; re-running the fetch is a no-op (exit 0, no re-download).
- [ ] **Step 2: Run it, expect FAIL** (`sh tests/test_fetch.sh` → missing files).
- [ ] **Step 3: Implement `build/fetch-deps.sh`**: idempotent, checks each target before downloading, applies `patches/*.patch` with `git apply --check` first, writes resolved hashes to `third_party/VERSIONS`.
- [ ] **Step 4: Run test, expect PASS** (run twice).
- [ ] **Step 5: Commit** `feat: pinned dependency fetch for libraop, wolfSSL, toolchain`

### Task 2: PCM/WAV encoder replacing libcodecs encoder

**Files:**
- Create: `native/airplay-receiver/encoder_pcm.c`
- Test: `tests/unit/test_encoder.c`, `CMakeLists.txt` (initial, host only, with `ctest`)

**Interfaces:**
- Consumes: `third_party/libraop/libcodecs/addons/encoder.h` (unchanged).
- Produces: the full `encoder.h` API: `encoder_create(char* codec, uint32_t sample_rate, uint8_t channels, uint8_t sample_size, size_t max_frames, size_t *icy_interval)`, `encoder_mimetype`, `encoder_open`, `encoder_close`, `encoder_delete`, `encoder_encode`, `encoder_space`.

- [ ] **Step 1: Write failing tests:**
  - `encoder_create("pcm",44100,2,2,0,&i)` non-NULL; mimetype `"audio/L16;rate=44100;channels=2"`; `encoder_encode` of 352 frames returns 1408 bytes, **big-endian** samples (L16 is network order).
  - `encoder_create("wav",...)`: mimetype `"audio/wav"`; first `encoder_encode` after `encoder_open` returns 44-byte RIFF header (`"RIFF"`, `"WAVE"`, fmt PCM=1, 2 ch, 44100, 16 bit, data size `0xFFFFFFFF`) followed by little-endian samples; after `encoder_close`+`encoder_open` the header is emitted again.
  - `encoder_create("mp3",...)` and `("flc",...)` return NULL.
- [ ] **Step 2: Run `ctest --test-dir build/host -R encoder`, expect FAIL.**
- [ ] **Step 3: Implement** with a single growable output buffer owned by the encoder; `icy_interval` set to 0.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat: PCM/WAV encoder for raop_streamer`

### Task 3: Host build of `airplay-receiver` with wolfSSL

**Files:**
- Create: `native/airplay-receiver/main.c`, `native/airplay-receiver/args.c`, `native/airplay-receiver/args.h`, `build/build-wolfssl.sh`, `build/build-host.sh`
- Modify: `CMakeLists.txt`
- Patch (if needed): `patches/0001-libraop-wolfssl-compat.patch`
- Test: `tests/unit/test_args.c`, `tests/test_host_smoke.sh`

**Interfaces:**
- Consumes: Task 1 sources, Task 2 encoder.
- Produces: `build/out/host/airplay-receiver` and
  ```c
  typedef struct {
      char name[64];          /* --name, default "Squeezebox" */
      struct in_addr ip;      /* --ip, default first non-loopback IPv4 */
      char codec[8];          /* --codec pcm|wav, default "pcm" */
      unsigned short port_base, port_range; /* --ports 6000:100 */
      int log_level;          /* -d 0..5, default 2 */
  } ar_args_t;
  int ar_parse_args(int argc, char **argv, ar_args_t *out); /* 0 ok, -1 usage error */
  ```
  Stdout event lines (one per event, consumed by later milestones; exact format):
  `STREAM port=<hport> url=http://127.0.0.1:<hport>/stream`, `PLAY`, `PAUSE`, `FLUSH`, `STOP`, `VOLUME <0.000-1.000>`, `METADATA title=<..>\tartist=<..>\talbum=<..>`, `ARTWORK <bytes>`, `READY name=<name>`.

- [ ] **Step 1: Write failing `test_args.c`**: defaults as above; `--name "Kitchen Radio" --codec wav --ports 7000:10 -d 4` parsed; `--codec mp3` → -1; `--ports 7000` → -1; `--ip 192.168.1.5` parsed.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement `ar_parse_args`.** Run, expect PASS.
- [ ] **Step 4: `build/build-wolfssl.sh host|baby|fab4`** builds static wolfSSL into `build/work/<target>/wolfssl-prefix` with `--enable-static --disable-shared --enable-opensslextra --enable-opensslall --enable-keygen --disable-examples --disable-crypttests --enable-aescbc --disable-asm` plus `CFLAGS=-DWC_RSA_NO_PADDING -DWOLFSSL_KEY_GEN`. Verify: `nm libwolfssl.a | grep -E 'wolfSSL_RSA_private_(en|de)crypt|wolfSSL_AES_cbc_encrypt|wolfSSL_PEM_read_bio_RSAPrivateKey'` lists all four.
- [ ] **Step 5: Implement `main.c`**: `mdnsd_start(ip,false)`, `mdnsd_set_hostname`, read MAC of the chosen interface (fallback: derive from IP), `raopsr_create(ip, svr, name, "SqueezeboxRadio", mac, codec, true, true, false, "1000:0", NULL, cb, NULL, port_base, port_range, 0)` (`http_length` 0 = no Content-Length; check `latencies` format against `raop_server.c` before relying on `"1000:0"`), print `READY`, block on `sigwait(SIGINT,SIGTERM)`, then `raopsr_delete` + `mdnsd_stop`. Callback prints the event lines above; volume is already 0..1 from raop_server.
- [ ] **Step 6: Wire CMake**: compile libraop `src/raop_server.c src/raop_streamer.c src/alac.c src/aes.c` (+ whatever else the link demands; not `raop_client.c`, `cliraop.c`, `pairing.cpp`, `bplist.cpp`), libmdns `mdnssvc/mdns.c mdnssvc/mdnsd.c mdnssd/mdnssd.c`, `dmap-parser/dmap_parser.c`, `crosstools/src/*.c`; defines `-DNDEBUG -D_GNU_SOURCE -DSSL_STATIC_LIB -DOPENSSL_EXTRA`; include wolfSSL `wolfssl/openssl` compat headers as `openssl/`. Fix incompatibilities with a patch in `patches/`, never in-place.
- [ ] **Step 7: Write `tests/test_host_smoke.sh`**: start binary with `--name SmokeTest --ip 127.0.0.1`; within 5 s stdout has `READY name=SmokeTest`; `avahi-browse -rtp _raop._tcp` (skip with notice if absent) or a Python mDNS query on 5353 finds `*@SmokeTest._raop._tcp`; RTSP `OPTIONS * RTSP/1.0` with `Apple-Challenge` to the advertised port returns `200` and an `Apple-Response` header (proves RSA path via wolfSSL); SIGTERM → exit 0 within 2 s.
- [ ] **Step 8: Run `build/build-host.sh && sh tests/test_host_smoke.sh`, expect PASS.**
- [ ] **Step 9: Commit** `feat: host airplay-receiver on libraop + wolfSSL`

### Task 4: Real-stream verification on host

**Files:**
- Create: `tests/raop_send.sh`, `tests/fixtures/sine1k-5s.wav` (generated by `tests/make_fixture.py`), `tests/check_wav.py`
- Test: `tests/test_host_stream.sh`

**Interfaces:**
- Consumes: Task 3 binary; libraop's own `raop_play` sender built for host from the same pinned tree (`tests/raop_send.sh` builds it once into `build/work/host/raop_play`, linking wolfSSL too, or system OpenSSL if that's quicker for a test-only tool).

- [ ] **Step 1: Write `tests/check_wav.py <file>`**: asserts 44.1 kHz/16-bit/stereo (raw PCM read as big-endian L16 if `--raw`), ≥ 3 s of audio, dominant FFT peak 1000 Hz ± 5 Hz on both channels, no run of > 4410 zero samples after first non-zero.
- [ ] **Step 2: Write `tests/test_host_stream.sh`**: start receiver (`--codec wav --ip 127.0.0.1`), send fixture with `raop_play -e 127.0.0.1 tests/fixtures/sine1k-5s.wav` (raw PCM fed per its usage), wait for `STREAM` line, `curl` the URL into `build/work/capture.wav` for 6 s, run `check_wav.py`. Then: second send after first finishes → second `STREAM` line and second capture also passes (reconnect). Then: start `curl` 2 s late and kill/restart `curl` mid-stream → receiver still alive and second capture non-empty.
- [ ] **Step 3: Run, expect PASS** (fix via patches if not).
- [ ] **Step 4: Manual check with a real iPhone/Mac on the LAN** (record in `docs/m1-device-test.md` under "Host"): speaker visible, play music, `curl … | ffplay -f s16be -ar 44100 -ac 2 -` sounds right; volume slider produces `VOLUME` lines; track change produces `METADATA`.
- [ ] **Step 5: Commit** `test: end-to-end RAOP stream capture on host`

### Task 5: Static ARM builds for baby and fab4

**Files:**
- Create: `build/toolchain-arm.cmake`, `build/build-arm.sh`, `tests/test_arm_binary.sh`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `build/out/baby/airplay-receiver`, `build/out/fab4/airplay-receiver`, `build/out/native-targets.json` (`{"hardware":["baby","fab4"],"target":"arm-buildroot-linux-musleabi","floatAbi":"soft"}`).

- [ ] **Step 1: Write `tests/test_arm_binary.sh <target>`**: `file` says `ELF 32-bit LSB executable, ARM, EABI5` and `statically linked`; `readelf -l` has no `INTERP`; `readelf -d` prints "There is no dynamic section"; `readelf -A` shows `Tag_ABI_VFP_args` absent or not `VFP registers`; `qemu-arm -cpu arm926 <bin> --help` exits 0 (baby) / `-cpu arm1136` (fab4); `nm`/`strings` show no `epoll_create1`/`accept4`/`eventfd` symbol unless wrapped (`__wrap_` present).
- [ ] **Step 2: Run, expect FAIL** (no binary).
- [ ] **Step 3: Implement `build-arm.sh [baby|fab4|all]`** (wolfSSL via `build-wolfssl.sh <target>`, then CMake with toolchain file + per-target flags from Global Constraints, `-static -no-pie`, strip). Add linux26 shim only if Step 1's symbol check requires it.
- [ ] **Step 4: Run `build/build-arm.sh all && sh tests/test_arm_binary.sh baby && sh tests/test_arm_binary.sh fab4`, expect PASS.** Record binary sizes.
- [ ] **Step 5: qemu stream test**: run `tests/test_host_stream.sh` with `RECEIVER="qemu-arm -cpu arm926 build/out/baby/airplay-receiver"`, expect PASS.
- [ ] **Step 6: Commit** `feat: static ARMv5/ARMv6 musl builds`

### Task 6: On-device test procedure and results

**Files:**
- Create: `docs/m1-device-test.md`, `tests/device_run.sh`

**Interfaces:**
- Consumes: Task 5 binaries.

- [ ] **Step 1: Write `tests/device_run.sh <host> <baby|fab4>`**: `scp` binary to `/tmp/airplay-receiver`, `ssh root@<host> 'chmod 755 /tmp/airplay-receiver && /tmp/airplay-receiver --name "SB AirPlay Test" --codec wav -d 3'` in foreground; companion command prints `ssh … 'wget -q -O - http://127.0.0.1:<port>/stream' > capture.wav` and `ssh … 'grep VmRSS /proc/$(pidof airplay-receiver)/status; top -b -n1 | grep airplay'`. Note: device busybox may lack `pidof`/`wget` flags; script falls back to `ps | grep` and `nc`.
- [ ] **Step 2: Write `docs/m1-device-test.md` checklist** per device (Radio, Touch): starts without error on 2.6.26; iPhone lists speaker; 30 s capture passes `check_wav.py` with real music replaced by Apple's built-in test tone or the `raop_play` fixture from the host; RSS (kB); CPU % while streaming; works with Spotify Connect running (5353 coexistence) — both start orders; SIGTERM exit clean.
- [ ] **Step 3: User runs the checklist on Radio and Touch; results filled in.** (Human step; implementer prepares and waits.)
- [ ] **Step 4: Commit** `docs: M1 device test procedure and results`
