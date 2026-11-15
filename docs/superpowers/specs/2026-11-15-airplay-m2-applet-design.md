# Milestone 2 design: AirPlay applet playing through SqueezePlay

Parent: `airplay-proposal.md`, M1 spec `2026-11-15-airplay-m1-receiver-poc-design.md`.
Status: written while the user was away; every call below is the implementer's
and is listed in "Calls made without the user" for review.

## Intent

Make the Radio/Touch show up as an AirPlay speaker with no SSH: an installable
applet starts `airplay-receiver` in the background, and when an iPhone plays to
it the audio comes out of the Radio's own speaker through SqueezePlay, with
volume following the iPhone and title/artist/album on the stock Now Playing
screen via Standalone Base. Model everything on Spotify Connect, which already
solved the same problems on the same firmware.

## Goals

- Applet `AirPlay` (Home menu item) with Operating Mode Disabled / Manual /
  Always On (default Always On), Start/Stop, State, Speaker name.
- Background receiver lifecycle owned by the applet, restarted if it dies.
- On stream start: stop Standalone Radio and Spotify Connect playback, then play
  the receiver's loopback stream with SqueezePlay's PCM decoder.
- AirPlay volume → device volume (same API Spotify uses).
- Title/artist/album → Standalone Base Now Playing API; native Now Playing
  screen opened once per new session.
- Pause/resume/skip from the iPhone work (they arrive as FLUSH + new RECORD).
- Packaged ZIP with the same layout as Spotify Connect (Lua + binary at archive
  root, `chmod 755` at init, nothing written outside the applet's own paths).

## Non-goals

- Controlling the iPhone from the Radio's buttons (needs DACP; capabilities are
  advertised as false, exactly like Spotify).
- Artwork display (receiver logs `ARTWORK <bytes>` only; artwork needs a file
  path + Standalone Base image URL — M3).
- Full StandaloneBase ownership protocol (`OwnershipBinding`); v1 does the
  same explicit hand-over Spotify did before that existed.
- Multi-room, AirPlay 2, password.
- Installing on the user's device (left to the user).

## Anti-goals

- Writing to flash continuously (state files go to RAM: `/tmp`).
- Unbounded files or memory (state is a few small files rewritten in place,
  not an ever-growing event log).
- Exposing the audio stream on the LAN in production.
- Blocking or slowing the Jive UI: no forks in the 250 ms watcher.

## Approaches considered

1. **Receiver writes small state files; applet polls them (chosen).** Same
   pattern as Spotify's `metadata.json`/`stream.ready` files read every 250 ms
   with plain `io.open` (no forks). Bounded, crash-tolerant, testable on host.
2. Applet reads the receiver's stdout event lines from a log file. Simple, but
   the file grows without bound in RAM, and Lua must track offsets.
3. Local socket/IPC from the receiver into Jive. Most responsive, but needs
   Jive socket plumbing for a 250 ms-latency use case; overkill.

## Design

```
iPhone ─RAOP─► airplay-receiver --state-dir /tmp/airplay (HTTP on 127.0.0.1)
                 writes atomically: stream  (generation + port)
                                    state   (playing|flushed|stopped)
                                    volume  (0.000-1.000)
                                    metadata (title\nartist\nalbum)
AirPlay applet (Jive, 250 ms Timer, io.open only)
  new stream generation → stop Radio/Spotify, AirPlayPlayback:start(127.0.0.1, port)
                           → decode:start('p', …, '1','3','2','0') + _streamConnect
  volume change          → player:volumeLocal + decode:audioGain
  metadata change        → Now Playing client (source "airplay")
  state stopped          → AirPlayPlayback:stop, release Now Playing
```

### Receiver changes (C)

- `--state-dir <dir>`: on each event, write the corresponding file via
  `<file>.tmp` + `rename()`. `stream` contains `<generation> <port>`, where the
  generation increments on every STREAM event so the applet can detect
  re-RECORD after pause/skip. Stdout event lines are unchanged.
- `--http-lan`: bind the HTTP audio server to the LAN IP (tests only). Default
  binds it to 127.0.0.1 (new libraop patch `0003`), closing the M1 ruling.

### Applet (Lua), files under `applet/AirPlay/`

- `AirPlayMeta.lua` — registers Home menu item, loads applet at boot, settings
  defaults/upgrade.
- `AirPlayApplet.lua` — watcher, menu, wiring.
- `AirPlayService.lua` — start/stop/health of the receiver; pid ownership via
  `/proc/<pid>/cmdline` like Spotify.
- `AirPlayPlayback.lua` — Spotify's `SpotifyPlayback` adapted to PCM.
- `AirPlayState.lua` — pure parsing of the state files into a snapshot and a
  diff (what changed since last tick). No Jive dependencies → unit-testable.
- `AirPlayNowPlaying.lua` — Spotify's Standalone Base client, source
  `airplay`, track id `airplay:<hash of title|artist|album>`.
- `strings.txt`.

Paths: binary `/usr/share/jive/applets/AirPlay/airplay-receiver`; state dir
`/tmp/airplay`; pid file `/tmp/airplay/receiver.pid`; log
`/tmp/airplay/receiver.log` (stderr only, truncated at each start).

Speaker name default: `Squeezebox Radio-XX` / `Squeezebox Touch-XX` (last MAC
byte), same as Spotify's `defaultName()`.

## Done when

1. Host: unit tests (C state writer, Lua state/diff/playback/service/now
   playing) pass; host integration test drives a real stream and the state
   files show stream/volume/metadata/stopped correctly.
2. ARM builds still pass M1 binary checks; device stream test still passes
   with `--http-lan`.
3. Package ZIP builds with the right layout and passes a layout test.
4. On the Radio (user): install the ZIP, iPhone plays through the speaker.

## Calls made without the user

- Default mode Always On (no account needed; idle receiver uses ~0 % CPU and
  ~150 kB RAM).
- State files in `/tmp` (RAM), not userpath (flash).
- HTTP audio server on loopback by default (M1 had it on the LAN).
- v1 hand-over: stop Standalone Radio and Spotify Connect playback directly,
  not via StandaloneBase OwnershipBinding.
- No artwork in v1.
- Binary runs from the applet directory after `chmod 755`; not copied to a
  runtime dir like Spotify does.
