# AirPlay for Squeezebox Radio / Touch

Play from an iPhone, iPad or Mac straight to a Logitech **Squeezebox Radio** or
**Squeezebox Touch**, with no music server running. The Radio appears as an
AirPlay speaker. Audio comes out of its own speaker, the iPhone's volume slider
controls the Radio, and the track shows on the Radio's Now Playing screen.

It is an applet for SqueezePlay (the Radio's own software), built to run next
to Sjoerd Brandsma's **Standalone Base**, **Standalone Radio** and
**Spotify Connect** applets.

> **Status: early (0.1.0).** Tested on one Squeezebox Radio (SqueezeOS 9.0.1)
> with Standalone Base as its only server: sound, volume, Now Playing,
> pause/resume, skip, stop, the AirPlay menu and crash recovery all work. The
> Squeezebox Touch build exists but is untested. See
> [Known limitations](#known-limitations).

---

## Contents

1. [What it does](#what-it-does)
2. [How it works](#how-it-works)
3. [Prerequisites](#prerequisites)
4. [Install](#install)
   - [Option A: SB Radio Applets plugin for Lyrion](#option-a-sb-radio-applets-plugin-for-lyrion-music-server)
   - [Option B: Manual install over SSH](#option-b-manual-install-over-ssh)
5. [Using it](#using-it)
6. [Uninstall](#uninstall)
7. [Troubleshooting](#troubleshooting)
8. [Known limitations](#known-limitations)
9. [Building from source](#building-from-source)
10. [Tests](#tests)
11. [Project layout](#project-layout)
12. [Credits and licences](#credits-and-licences)

---

## What it does

- Makes the Radio an **AirPlay 1** speaker. It shows up in the iPhone's
  Control Centre, in the Music app and in macOS sound output.
- Plays through the Radio's **built-in speaker or line out**, using
  SqueezePlay's own player.
- **Volume:** the iPhone slider maps onto the Radio's volume curve, and the
  Radio's knob keeps working.
- **Now Playing:** title, artist and album appear on the Radio's stock Now
  Playing screen, through Standalone Base's Now Playing API.
- **Pause, resume, skip and stop** from the iPhone.
- **Hand-over:** starting AirPlay stops Standalone Radio and Spotify Connect
  playback first, so they don't fight over the player.
- **Home menu "AirPlay"**: Operating Mode (Disabled / Manual / Always On),
  state, start/stop/restart, speaker name.
- **Background service:** the receiver starts at boot (Always On) and is
  restarted automatically if it stops.

**Not included (yet):** AirPlay 2 / multi-room, cover art, controlling the
iPhone from the Radio's buttons, password-protected speakers.

## How it works

```
iPhone / Mac ──AirPlay 1 (RTSP + RTP, AES, ALAC)──► airplay-receiver   (static ARM program)
                                                    │  decodes ALAC → 16-bit PCM
                                                    │  serves it on http://127.0.0.1:<port>/stream
                                                    │  writes small state files in /tmp/airplay
                                                    ▼
                                AirPlay applet (Lua, inside SqueezePlay)
                                  • reads /tmp/airplay every 250 ms
                                  • points SqueezePlay's player + PCM decoder at the stream
                                  • applies the iPhone volume
                                  • publishes Now Playing to Standalone Base
                                  • keeps the server off the player while AirPlay plays
                                                    ▼
                                    Radio speaker / headphone / line out
```

- **The receiver** is philippe44's [libraop](https://github.com/philippe44/libraop)
  receiver, with a small command-line front end, built as one static ARMv5/ARMv6
  program (about 680 KB). It uses wolfSSL instead of OpenSSL for the AirPlay
  RSA/AES handshake. The audio port listens on the loopback address only, so
  other devices on the network can't reach it.
- **The applet** never forks on its polling path; it only reads the files.
  While AirPlay plays it applies the same guards Standalone Radio uses, so that
  Standalone Base or a Lyrion server can't stop the stream, override the volume,
  or start a request storm. It also resumes the audio itself after a buffer
  underrun, which a real music server would normally do.

## Prerequisites

**Device**
- Squeezebox **Radio** (`baby`) or Squeezebox **Touch** (`fab4`; built but untested).
- Firmware/SqueezeOS **7.7.2 or newer** (tested on 9.0.1 r17084).
- Connected to your network, on the same network segment as your iPhone/Mac
  (AirPlay discovery uses mDNS/Bonjour).

**Software on the Radio**
- **[Standalone Base](https://github.com/ssbrandsma/SBStandaloneBase)**, installed
  first. It provides the local server the Radio runs on without Lyrion, and the
  Now Playing integration.
- About **1 MB free** applet storage. With Spotify Connect also installed,
  Standalone Base's **Extended Storage** is recommended.
- Optional: Standalone Radio, Spotify Connect. AirPlay cooperates with both.

**Senders**
- iPhone/iPad (iOS) or Mac (macOS) on the same network. Any app that can
  send audio to an AirPlay speaker (Music, Podcasts, Spotify, Safari, …).

**You do _not_ need** a Lyrion Music Server running 24/7. That's the point of
this project. Lyrion is only needed if you install through Option A.

## Install

### Option A: SB Radio Applets plugin for Lyrion Music Server

> **Planned.** The [SB Radio Applets](https://github.com/macsatcom/SBRadio) plugin
> currently offers Standalone Base, Standalone Radio and Spotify Connect.
> AirPlay will be added to its catalog. Until then, use
> [Option B](#option-b-manual-install-over-ssh).

The Radio's Applet Installer can only download over plain HTTP, and GitHub only
serves HTTPS. The SB Radio Applets plugin lets your Lyrion Music Server (LMS)
download the applets from GitHub, check their checksums, and offer them to the
Radio's Applet Installer over HTTP. LMS is only needed for the install. AirPlay
plays without it afterwards.

You need Lyrion Music Server 7.9 or newer with internet access, and the Radio
connected to that LMS while you install.

1. **Add the repository to LMS.** Open the LMS web interface
   (`http://<your-lms-address>:9000`) → **Settings → Manage Plugins** (Material
   skin: **Settings → Server → Plugins**). At the bottom, under
   **Additional Repositories**, paste:
   ```
   https://raw.githubusercontent.com/macsatcom/SBRadio/main/repo.xml
   ```
   Click **Apply**.
2. **Enable the plugin.** Tick **SB Radio Applets** (under *3rd party plugins*),
   click **Apply**, then **Restart LMS**. Wait one to two minutes while it
   downloads the applets.
3. **Connect the Radio to this LMS.** On the Radio: **Home → Settings →
   Advanced → Networking → Remote Libraries** (some firmware: **Choose Library**),
   then select your LMS.
4. **Install Standalone Base first.** On the Radio: **Settings → Advanced →
   Applet Installer → Standalone Base → Install**. The Radio restarts.
5. **Install AirPlay.** Open the **Applet Installer** again, select **AirPlay**,
   then **Install**. The Radio restarts.
6. **Switch the Radio back to Standalone Base** (Home → Choose Library) if
   you don't want it to depend on LMS from now on.

Updates appear in the Applet Installer the same way. Full plugin documentation,
troubleshooting and a plugin-free mirror alternative are in the
[SB Radio Applets README](https://github.com/macsatcom/SBRadio#readme).

### Option B: Manual install over SSH

This works today and needs no Lyrion server.

**1. Get the package** for your device, from a release or by
[building it yourself](#building-from-source):
- Radio: `dist/AirPlay-0.1.0-baby.zip`
- Touch: `dist/AirPlay-0.1.0-fab4.zip`

**2. Enable SSH on the Radio.** **Settings → Advanced → Remote Login → Enable
SSH**. The username is `root`; the password is usually `1234`.

**3. Copy and unpack** (replace the IP address with your Radio's). The Radio
has no `sftp`, so the ZIP is piped over `ssh`:
```sh
RADIO=192.168.1.35
ZIP=dist/AirPlay-0.1.0-baby.zip

ssh root@$RADIO 'cat > /tmp/AirPlay.zip' < "$ZIP"
ssh root@$RADIO '
  mkdir -p /usr/share/jive/applets/AirPlay &&
  cd /usr/share/jive/applets/AirPlay &&
  unzip -o -q /tmp/AirPlay.zip &&
  chmod 755 airplay-receiver &&
  rm /tmp/AirPlay.zip'
```
If `ssh` refuses the Radio's old host key, add
`-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa`.

**4. Restart SqueezePlay** (or power-cycle the Radio):
```sh
ssh root@$RADIO '/etc/init.d/squeezeplay restart'
```
The screen shows the startup animation for about 30 seconds. Occasionally the
Radio reboots fully instead; that's harmless.

**5. Check it.** **AirPlay** appears in the Home menu with *State: running*,
and your iPhone lists **Squeezebox Radio-XX** (XX = the last two characters of
the Radio's MAC address).

## Using it

1. On the iPhone, open **Control Centre → AirPlay** (or the AirPlay button in
   any app) and pick **Squeezebox Radio-XX**.
2. Play something. The Radio stops any radio or Spotify playback, shows Now
   Playing, and plays at the iPhone's volume.
3. Use the iPhone (or the Radio's knob) for volume, and the iPhone for
   pause/skip.
4. To stop, choose another output on the iPhone.

**Home → AirPlay** on the Radio:

| Item | What it does |
|---|---|
| Operating Mode | **Always On** (default): receiver runs from boot. **Manual**: Start/Stop items. **Disabled**: receiver off, speaker hidden. |
| State | running / stopped / error |
| Start / Stop / Restart AirPlay | Manual control |
| Speaker name | The name the iPhone shows |
| Last error | Shown only after a problem |

## Uninstall

```sh
ssh root@$RADIO 'killall airplay-receiver;
  rm -rf /usr/share/jive/applets/AirPlay /tmp/airplay;
  rm -f /etc/squeezeplay/userpath/settings/AirPlay.lua;
  /etc/init.d/squeezeplay restart'
```
If you installed via Option A, you can also use **Settings → Advanced → Applet
Installer → AirPlay → Remove**.

## Troubleshooting

**The iPhone doesn't list the speaker**
- Is AirPlay's Operating Mode **Always On**, with State **running**?
- Are the iPhone and Radio on the same network or VLAN (mDNS must pass)?
- Toggle the iPhone's Wi-Fi off and on to clear its speaker cache.
- On the Radio: `pidof airplay-receiver`, `cat /tmp/airplay/receiver.log`.

**It connects but there's no sound**
- Turn the Radio's knob up once; some earlier sessions may have stored a very
  low volume on the server.
- Check the state files while playing:
  ```sh
  ssh root@$RADIO 'cat /tmp/airplay/state /tmp/airplay/stream /tmp/airplay/volume'
  ```
  `state` should say `playing`, and `volume` should be between 0 and 1.

**It plays through Lyrion's AirConnect instead**
If your Lyrion server runs the AirConnect (AirPlay bridge) plugin, it also
picks up this speaker and creates a duplicate Lyrion player for it. Exclude
the Radio in AirConnect's settings.

**"Connecting to Standalone Base" keeps appearing**
That's a Standalone Base issue, unrelated to AirPlay; it also happens with the
AirPlay applet removed. It has been reported upstream.

**Detailed logs**
Create `/etc/squeezeplay/userpath/logconf.lua` with
```lua
return {category={["applet.AirPlay"]="DEBUG",["audio.decode"]="DEBUG"},appender={syslog="DEBUG"}}
```
restart SqueezePlay, reproduce, then read `/var/log/messages`. Delete the file
afterwards.

## Known limitations

- **AirPlay 1 only:** no AirPlay 2, multi-room or synchronised playback.
- **No cover art yet.**
- **No remote control from the Radio:** the Radio's play/pause/skip buttons
  don't control the iPhone (no DACP). Now Playing advertises no controls.
- **Hand-over** with Standalone Radio and Spotify Connect is direct, not via
  Standalone Base's ownership protocol. The AirPlay-over-Spotify hand-over is
  untested.
- **Connecting takes about a second** of CPU on the Radio, for two RSA-2048
  operations (384 ms each with ARM-optimised wolfSSL).
- **Restarting SqueezePlay sometimes reboots the Radio** (60-second hardware
  watchdog). Under investigation.
- **Lyrion-connected Radios** work, but the Lyrion server can still drive the
  same player. This project targets Radios without a server.
- **Squeezebox Touch** builds, but hasn't been tested on a device.

## Building from source

Building needs a Linux PC (tested on Ubuntu/Debian x86-64). The ARM
cross-compiler is downloaded by the build scripts; nothing is installed system-wide.

```sh
sh install-packages.sh            # apt packages: build-essential, cmake, autotools, qemu-user, …
sh build/fetch-deps.sh            # pinned libraop (+ patches), wolfSSL, Bootlin musl toolchain
sh build/build-host.sh            # PC build + unit tests (for testing on the PC)
sh build/build-arm.sh all         # static ARM receivers: build/out/baby, build/out/fab4
sh build/package.sh all           # dist/AirPlay-<version>-baby.zip / -fab4.zip
```

**Notes**
- **Toolchain:** Bootlin `armv5-eabi--musl--stable-2020.02-2` (GCC 8.4, musl),
  the same one Standalone Base uses.
- **Targets:** `baby` is built for `-march=armv5te -mfloat-abi=soft`; `fab4`
  for `-march=armv6`.
- **wolfSSL:** built static with SP math and ARM assembly
  (`-DWOLFSSL_ARM_ARCH=5` avoids ARMv6 instructions on the Radio).
- **libraop patches:** all changes live in `patches/` and are applied by
  `fetch-deps.sh`:
  - `0001`: reject non-ALAC and absurd frame sizes, which would otherwise crash
    the receiver or exhaust its memory.
  - `0002`: end the session cleanly when the sender disappears without
    TEARDOWN.
  - `0003`: serve audio on loopback by default.
- **Version:** set in `VERSION`.

## Tests

```sh
ctest --test-dir build/host                 # C unit tests (args, encoder, state files)
.venv/bin/python -m pytest -q tests/lua     # 94 Lua tests (lupa, Lua 5.1, faked SqueezePlay)
sh tests/test_host_smoke.sh                 # mDNS, resolvable .local host, RSA handshake, bad input, SIGTERM
sh tests/test_host_stream.sh                # real ALAC stream → captured audio checked (1 kHz tone)
sh tests/test_host_state.sh                 # state files + loopback-only audio
sh tests/test_arm_binary.sh baby|fab4       # static, soft-float, no missing 2.6 syscalls, runs under qemu
sh tests/test_package.sh baby|fab4          # ZIP layout, ARM binary, Lua compiles
sh tests/device_run.sh <ip> baby test       # stream test with the receiver on a real Radio (/tmp only)
```
The Lua tests need a virtualenv with `lupa`, `pytest` and `numpy`:
`uv venv .venv && uv pip install --python .venv/bin/python lupa pytest numpy`.

## Project layout

```
applet/AirPlay/           Lua applet (Meta, Applet, Service, Playback, Watcher, State,
                          Ownership, NowPlaying, strings.txt)
native/airplay-receiver/  receiver front end: main.c, args, PCM/WAV encoder, state files
patches/                  local changes to libraop
build/                    fetch, build (host/ARM/wolfSSL), package scripts, CMake toolchain
tests/                    C unit tests, Lua tests, host/device integration tests
docs/                     design specs, plans, device test results, install notes
```

## Credits and licences

- **Receiver:** [libraop](https://github.com/philippe44/libraop), with libmdns,
  dmap-parser and crosstools, by philippe44 (MIT).
- **TLS/crypto:** [wolfSSL](https://github.com/wolfSSL/wolfssl) (GPLv2), statically
  linked into `airplay-receiver`.
- **Model and reference:** Sjoerd Brandsma's
  [Spotify Connect](https://github.com/ssbrandsma/squeezebox-radio-spotify-connect)
  (MIT). AirPlay's Playback and Now Playing modules are adapted from it.
- **Ownership guards:** reimplemented after Standalone Radio's
  approach ([SBStandalone](https://github.com/ssbrandsma/SBStandalone)).
- **Platform:** [Standalone Base](https://github.com/ssbrandsma/SBStandaloneBase).
- **Install channel:** [SB Radio Applets](https://github.com/macsatcom/SBRadio)
  plugin for Lyrion Music Server.

The applet's own licence is still to be decided. Because the receiver binary
statically links wolfSSL, the binary as distributed is subject to the GPLv2.
