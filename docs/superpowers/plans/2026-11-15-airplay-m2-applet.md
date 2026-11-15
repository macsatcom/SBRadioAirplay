# AirPlay Applet (Milestone 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Installable `AirPlay` applet that runs `airplay-receiver` in the background and plays AirPlay audio through SqueezePlay, with volume and Now Playing.

**Architecture:** Receiver writes small atomic state files in `/tmp/airplay`; a 250 ms Jive timer reads them with `io.open`, drives SqueezePlay's PCM decoder against the receiver's loopback HTTP stream, the device volume, and Standalone Base Now Playing. Lua modules are split so all logic except Jive glue is host-testable with lupa (Lua 5.1).

**Tech Stack:** C (receiver), Lua 5.1 (Jive applet), Python + lupa + uv venv (`.venv`) for Lua tests, shell for integration/packaging.

**Spec:** `docs/superpowers/specs/2026-11-15-airplay-m2-applet-design.md`

## Global Constraints

- Lua 5.1, Jive module style (`module(...)`, `oo.class`), no forks in the 250 ms watcher (only `io.open`/`read`).
- PCM decoder call: `decode:start(string.byte('p'), 0, 0, 0, 0, 0, 0, string.byte('1'), string.byte('3'), string.byte('2'), string.byte('0'))` (16-bit, 44.1 kHz, stereo, big-endian; 11 arguments as in firmware Playback.lua).
- Paths: applet `/usr/share/jive/applets/AirPlay/`, state dir `/tmp/airplay`, pid `/tmp/airplay/receiver.pid`, log `/tmp/airplay/receiver.log`.
- State files written via `<name>.tmp` + `rename()`; formats: `stream` = `<gen> <port>\n`, `state` = `playing|flushed|stopped\n`, `volume` = `%.3f\n` (0..1), `metadata` = `title\nartist\nalbum\n`.
- HTTP audio server binds 127.0.0.1 unless `--http-lan`.
- Default settings: `{serviceMode="always_on", deviceName=<model>}`; speaker name `<model>-XX` (last MAC byte) when deviceName equals the model name.
- Now Playing: Standalone Base `127.0.0.1:9000`, source `airplay`, name `AirPlay`, all capabilities false.
- Lua tests: `.venv/bin/python -m pytest tests/lua` (pytest added to venv).

## Review Focus

- iPhone pauses, then resumes (FLUSH then a new RECORD on the same session): playback must restart, not stay silent (Task 1 integration generation check, Task 6 watcher test).
- Receiver crashes or is killed while the applet runs: applet must notice within 10 s and restart it; stale pid file must not make it think it's running (Task 4).
- Speaker name with quotes/spaces (`Bob's "Radio"`): must reach the receiver intact, no shell injection (Task 4).
- State files partially written / missing / garbage: parser must ignore them, never throw inside the timer (Task 2).
- Standalone Base not installed or down: audio must still play (Task 5/6).

---

### Task 1: Receiver state files and loopback HTTP

**Files:**
- Create: `native/airplay-receiver/state_files.c`, `native/airplay-receiver/state_files.h`, `tests/unit/test_state_files.c`, `patches/0003-libraop-http-loopback.patch`, `tests/test_host_state.sh`
- Modify: `native/airplay-receiver/main.c`, `args.c/.h` (`--state-dir`, `--http-lan`), `tests/unit/test_args.c`, `CMakeLists.txt`, `tests/test_host_stream.sh`, `tests/test_host_smoke.sh` (pass `--http-lan` where capture is from another host or by LAN IP)

**Interfaces:**
- Produces:
  ```c
  int sf_init(const char *dir);                 /* mkdir -p; removes stale files; 0 ok */
  int sf_write(const char *dir, const char *name, const char *content); /* atomic; 0 ok */
  ```
  `ar_args_t` gains `char state_dir[128]` (default "" = disabled) and `bool http_lan` (default false).
  libraop global `extern bool raopst_http_loopback;` (patch 0003; true = bind HTTP to 127.0.0.1).
  STREAM url printed as `http://127.0.0.1:<port>/stream` when loopback, else LAN IP.

- [ ] Step 1: failing `test_state_files.c`: `sf_init` creates nested dir and removes existing `stream`; `sf_write` result readable with exact content; no `.tmp` left; write into missing dir returns -1. Failing `test_args.c` cases for `--state-dir /x` and `--http-lan`.
- [ ] Step 2: run ctest → FAIL. Step 3: implement. Step 4: ctest → PASS.
- [ ] Step 5: patch 0003 + main wiring (STREAM → gen++ and `stream`+`state playing`; PLAY → `state playing`; FLUSH → `state flushed`; STOP → `state stopped`; VOLUME → `volume`; METADATA → `metadata`; startup → `state stopped`).
- [ ] Step 6: `tests/test_host_state.sh` (RED first): receiver with `--state-dir $WORK/state --http-lan`, ALAC send → `stream` gen 1 + port, `state` playing, `volume` exists; sender killed → `state` stopped; second send → gen 2. Also: without `--http-lan`, `curl` to LAN-IP:port is refused and 127.0.0.1:port works.
- [ ] Step 7: all host tests + commit `feat: receiver state files, loopback HTTP by default`.

### Task 2: AirPlayState (pure Lua)

**Files:** Create `applet/AirPlay/AirPlayState.lua`, `tests/lua/conftest.py`, `tests/lua/test_state.py`

**Interfaces:**
- Produces: `AirPlayState.read(dir, open)` → snapshot `{gen=number|nil, port=number|nil, state="playing"|"flushed"|"stopped"|nil, volume=number 0..1|nil, title,artist,album=string|nil}`; `open` defaults to `io.open` (injectable). `AirPlayState.diff(old, new)` → `{newStream=bool, stopped=bool, volumeChanged=bool, metadataChanged=bool}` (old may be nil).
- [ ] Tests: valid files parse; missing dir → all nil, no error; garbage `stream` ("abc", "1", "1 99999999") → gen/port nil; volume clamps to 0..1 and rejects non-numbers; metadata with only title; diff: gen 1→2 newStream, same gen no; state playing→stopped stopped=true; first snapshot with gen → newStream. RED → implement → GREEN → commit.

### Task 3: AirPlayPlayback

**Files:** Create `applet/AirPlay/AirPlayPlayback.lua`, `tests/lua/test_playback.py`

**Interfaces:** `AirPlayPlayback()` instance with `init(applet)`, `start(host, port)` → bool, `stop()`, `setRemoteVolume(percent)` → bool, `isActive()`. Consumes Jive `jive.slim.Player`, `squeezeplay.decode`, `squeezeplay.stream` (mocked in tests).
- [ ] Tests: start calls `stopInternal`, sets `header` to `GET /stream HTTP/1.0\nHost: 127.0.0.1\n…Connection: close\n\n`, mode `'p'`, `decode:start` with exactly the 11 Global-Constraints args, `_streamConnect("127.0.0.1", port)`; no player → false; setRemoteVolume(0) → `audioGain(0,0)`, (50) → `volumeLocal(50,true,true)` + gain from `_getGainFromVolume(50)`; stop calls `stopInternal` once and isActive false. RED → implement → GREEN → commit.

### Task 4: AirPlayService

**Files:** Create `applet/AirPlay/AirPlayService.lua`, `tests/lua/test_service.py`

**Interfaces:** `AirPlayService()` with `init(applet, deps)` (deps: `execute`, `open`, `timer` injectable; default `os.execute`, `io.open`, `jive.ui.Timer`), `getMode()/setMode(m)`, `start()`, `stop(force)`, `isRunning()`, `getStatus()` ("stopped"|"starting"|"running"|"error"), `speakerName()`, `shutdown()`.
- [ ] Tests: start builds one command: `mkdir -p /tmp/airplay; : > log; ( exec '<bin>' --name '<name>' --state-dir /tmp/airplay -d 1 >/dev/null 2>>log ) & echo $! > pid` with single-quote escaping (`Bob's "Radio"` → `'Bob'\''s "Radio"'`); isRunning true only if pid file numeric AND `/proc/<pid>/cmdline` starts with the binary path; stale pid → false; health timer (10 s) restarts when desired and not running; disabled mode refuses start; stop sends `kill -TERM` only to the owned pid; always_on start at init. RED → implement → GREEN → commit.

### Task 5: AirPlayNowPlaying

**Files:** Create `applet/AirPlay/AirPlayNowPlaying.lua`, `tests/lua/test_nowplaying.py`

**Interfaces:** same public API as Spotify's client: `new(options)`, `activate(data, gen)`, `update(data, gen)`, `release()`, `shutdown()`; data = `{title, artist, album, playback_state}`; `options.request(method, path, payload, cb)` injectable.
- [ ] Tests (fake request): activate → POST `/api/nowplaying/claim` with `source="airplay"`, `name="AirPlay"`, all capabilities false; then update with `track.id` `airplay:` + stable hash, `live=false`, title/artist/album; same metadata twice → one update; release → `/release`; request error → retry timer scheduled, no exception. Port by adapting Spotify's module (MIT/GPL? check licence header of Spotify repo; record ruling). RED → implement → GREEN → commit.

### Task 6: Applet, Meta, watcher wiring

**Files:** Create `applet/AirPlay/AirPlayApplet.lua`, `applet/AirPlay/AirPlayMeta.lua`, `applet/AirPlay/strings.txt`, `tests/lua/test_applet.py`

**Interfaces:** Watcher `AirPlayApplet:_tick()` (called by 250 ms Timer): reads `AirPlayState.read("/tmp/airplay")`, diffs with last, then: newStream & state playing → hand-over (Radio `streamPlayer:stop()`+clear `desiredStation`; Spotify `playback:stop()` via `appletManager:getAppletInstance`) then `playback:start("127.0.0.1", port)`, Now Playing activate, native `goNowPlaying` once per new session (gen from stopped→stream); volumeChanged → `setRemoteVolume(floor(v*100+0.5))`; metadataChanged → Now Playing update; stopped → `playback:stop()`, Now Playing release.
- [ ] Tests with mocked modules: tick with gen1 playing → start called with port; same tick again → no second start; gen2 (resume after pause) → start again but goNowPlaying not again; state stopped → stop + release; volume 0.5 → setRemoteVolume(50); garbage files → no error; Now Playing failure doesn't block start. RED → implement → GREEN → commit.

### Task 7: Packaging and verification

**Files:** Create `build/package.sh`, `tests/test_package.sh`, `docs/m2-install.md`

- [ ] `build/package.sh [baby|fab4]` → `dist/AirPlay-<ver>-<target>.zip` with `AirPlay/` contents at root (Lua, strings.txt, `airplay-receiver`), version from `VERSION` (create `0.1.0`).
- [ ] `tests/test_package.sh`: zip lists exactly expected files; binary inside is the ARM one (`file`); every Lua file compiles with lupa (`loadstring`).
- [ ] Rebuild ARM; M1 binary tests; device stream test with `--http-lan` path (device_run passes `--http-lan`).
- [ ] `docs/m2-install.md`: manual install over SSH (copy to `/usr/share/jive/applets/AirPlay`, restart jive), uninstall, what to check.
- [ ] Commit `feat: AirPlay applet package`.
