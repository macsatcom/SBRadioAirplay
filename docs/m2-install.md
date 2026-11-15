# Milestone 2: install and test the AirPlay applet

The applet has been tested on a PC (Lua logic against faked SqueezePlay
modules) and the receiver on a real Radio, but **the applet itself has not yet
run inside SqueezePlay**. These steps do that. Everything is reversible: the
uninstall section removes all of it.

## Build

```sh
sh build/fetch-deps.sh
sh build/build-arm.sh all
sh build/package.sh all          # dist/AirPlay-<version>-baby.zip / -fab4.zip
sh tests/test_package.sh baby
```

## Install on a Radio over SSH

Use the `fab4` ZIP for a Touch. Root password is usually `1234`.

```sh
RADIO=192.168.1.35
scp -O dist/AirPlay-0.1.0-baby.zip root@$RADIO:/tmp/   # or: ssh … 'cat > /tmp/AirPlay.zip' < …
ssh root@$RADIO '
  mkdir -p /usr/share/jive/applets/AirPlay &&
  cd /usr/share/jive/applets/AirPlay &&
  unzip -o /tmp/AirPlay-0.1.0-baby.zip && chmod 755 airplay-receiver &&
  rm /tmp/AirPlay-0.1.0-baby.zip &&
  /etc/init.d/squeezeplay restart'
```

If the firmware has no `unzip`, unpack on the PC and copy the files with
`ssh root@$RADIO 'cat > /usr/share/jive/applets/AirPlay/<file>' < <file>`.

`/usr/share/jive/applets` is where Spotify Connect and StandaloneBase live on
this Radio. With Extended Storage it may be on the extended partition; that is
fine.

## What to check

| Check | Result |
|---|---|
| Home menu shows **AirPlay**; State: running | |
| `ps` shows `airplay-receiver`; `/tmp/airplay/state` says `stopped` | |
| iPhone lists "Squeezebox Radio-XX" | |
| Playing from the iPhone comes out of the Radio speaker | |
| Now Playing screen opens with title/artist/album | |
| iPhone volume slider changes Radio volume | |
| Pause → resume from iPhone resumes audio | |
| Skip track → new track plays, Now Playing updates | |
| Switch iPhone to another speaker → Radio stops, Now Playing released | |
| Start a Standalone Radio station while AirPlay plays → radio takes over | |
| Start AirPlay while Spotify plays → AirPlay takes over | |
| Operating Mode Disabled → speaker disappears from the iPhone | |
| `kill` the receiver → it is back within ~10 s | |

Useful while testing (read-only):

```sh
ssh root@$RADIO 'cat /tmp/airplay/state /tmp/airplay/stream; tail /tmp/airplay/receiver.log;
                 grep -i airplay /var/log/messages | tail'
```

## Uninstall

```sh
ssh root@$RADIO 'killall airplay-receiver; rm -rf /usr/share/jive/applets/AirPlay /tmp/airplay;
                 /etc/init.d/squeezeplay restart'
```

Settings are stored by SqueezePlay under
`/etc/squeezeplay/userpath/settings/AirPlay.lua`; remove it too for a clean slate.

## Known limitations (v1)

- No remote control from the Radio's buttons (play/pause/next go to the
  iPhone only via the iPhone).
- No cover art yet.
- Hand-over with Spotify Connect and Standalone Radio is direct, not through
  StandaloneBase's ownership protocol.
- Session setup takes about 0.8 s of CPU on the Radio (two RSA operations).
