"""AirPlayPlayback: drive SqueezePlay's stock player with the PCM decoder."""
import pytest

PRELUDE = r'''
calls = {}
function rec(...) table.insert(calls, {...}) end
playback = {
  stopInternal=function(self) rec('stopInternal') end,
  _streamConnect=function(self, host, port) rec('streamConnect', host, port) end,
  _getGainFromVolume=function(self, v) return v * 1000 end,
}
player = {playback=playback,
  volumeLocal=function(self, v, a, b) rec('volumeLocal', v, a, b) end,
  volume=function(self, v, send) rec('volume', v, send) end,
  incrementSequenceNumber=function(self) rec('incSeq') end}
localPlayer = player
package.loaded['jive.slim.Player'] = {
  getLocalPlayer=function() return localPlayer end,
  getCurrentPlayer=function() return localPlayer end}
package.loaded['squeezeplay.decode'] = {
  start=function(self, ...) rec('decodeStart', ...) end,
  audioGain=function(self, l, r) rec('audioGain', l, r) end}
package.loaded['squeezeplay.stream'] = {icyMetaInterval=function(self, n) rec('icy', n) end}
'''


@pytest.fixture
def pb(lua):
    lua(PRELUDE)
    lua("""ownership = {install=function(self, p) rec('own.install') end,
                        setActive=function(self, on) rec('own.active', on) end}""")
    mod = lua.load("AirPlayPlayback")
    inst = mod()
    inst.init(inst, None, lua.eval("ownership"))
    return inst


def calls(lua, name):
    out = []
    n = lua.eval("#calls")
    for i in range(1, n + 1):
        c = lua.eval(f"calls[{i}]")
        if c[1] == name:
            out.append([c[j] for j in range(2, len(c) + 1)])
    return out


def test_start_uses_pcm_decoder_and_loopback_stream(lua, pb):
    assert pb.start(pb, "127.0.0.1", 6069) is True
    assert len(calls(lua, "stopInternal")) == 1
    ds = calls(lua, "decodeStart")
    assert ds == [[ord('p'), 0, 0, 0, 0, 0, 0, ord('1'), ord('3'), ord('2'), ord('0')]]
    assert calls(lua, "streamConnect") == [["127.0.0.1", 6069]]
    pbk = lua.eval("playback")
    assert pbk.mode == "p"
    assert pbk.header == ("GET /stream HTTP/1.0\nHost: 127.0.0.1\n"
                          "Accept: audio/L16,*/*\nConnection: close\n\n")
    assert pbk.autostart == "1"
    assert calls(lua, "icy") == [[0]]
    assert pb.isActive(pb)


def test_start_without_player_fails(lua, pb):
    lua("localPlayer = nil")
    assert pb.start(pb, "127.0.0.1", 6069) is False
    assert calls(lua, "decodeStart") == []
    assert not pb.isActive(pb)


def test_volume_zero_mutes(lua, pb):
    pb.start(pb, "127.0.0.1", 6069)
    assert pb.setRemoteVolume(pb, 0) is True
    assert calls(lua, "volumeLocal") == [[0, True, True]]
    assert calls(lua, "audioGain") == [[0, 0]]


def test_volume_is_local_not_sent_to_server(lua, pb):
    # While AirPlay owns the player the server is kept out (AirPlayOwnership),
    # so volume is applied locally like Spotify Connect does.
    pb.start(pb, "127.0.0.1", 6069)
    assert pb.setRemoteVolume(pb, 50) is True
    assert calls(lua, "volumeLocal") == [[50, True, True]]
    assert calls(lua, "audioGain") == [[50000, 50000]]
    assert calls(lua, "volume") == []


def test_start_activates_ownership_and_stop_releases(lua, pb):
    pb.start(pb, "127.0.0.1", 6069)
    assert calls(lua, "own.install") and calls(lua, "own.active") == [[True]]
    pb.stop(pb)
    assert calls(lua, "own.active") == [[True], [False]]


def test_volume_clamped(lua, pb):
    pb.start(pb, "127.0.0.1", 6069)
    pb.setRemoteVolume(pb, 140)
    assert calls(lua, "volumeLocal")[-1][0] == 100


def test_volume_before_start_is_remembered_and_applied(lua, pb):
    assert pb.setRemoteVolume(pb, 30) is False
    pb.start(pb, "127.0.0.1", 6069)
    assert calls(lua, "volumeLocal") == [[30, True, True]]


def test_stop_once(lua, pb):
    pb.start(pb, "127.0.0.1", 6069)
    pb.stop(pb)
    pb.stop(pb)
    assert len(calls(lua, "stopInternal")) == 2  # one from start, one from stop
    assert not pb.isActive(pb)


CURVE = r'''
-- firmware-like curve: volume v (1..100) -> 65536 * 10^(-(100-v)*0.72/20)
playback._getGainFromVolume = function(self, v)
  return math.floor(65536 * 10 ^ (-(100 - v) * 0.72 / 20) + 0.5)
end
'''


@pytest.mark.parametrize("airplay,percent", [(1.0, 100), (0.5, 79), (0.0, 0), (0.1, 62), (0.001, 58)])
def test_airplay_volume_follows_decibels(lua, pb, airplay, percent):
    # AirPlay 0..1 is linear in dB over -30..0; 0 is mute
    lua(CURVE)
    pb.start(pb, "127.0.0.1", 6069)
    assert pb.setAirPlayVolume(pb, airplay) is True
    assert calls(lua, "volumeLocal")[-1][0] == percent


def set_status(lua, audioState=0, decodeFull=0):
    lua(f"package.loaded['squeezeplay.decode'].status = function() return {{audioState={audioState}, decodeFull={decodeFull}}} end")


def test_resumes_audio_after_output_underrun_when_buffered(lua, pb):
    # Stock Playback pauses output on underrun and waits for the server's
    # strm-u; without LMS nobody sends it, so we resume locally.
    lua("package.loaded['squeezeplay.decode'].resumeAudio = function() rec('resumeAudio') end")
    pb.start(pb, "127.0.0.1", 6069)
    lua("playback.sentOutputUnderrunEvent = true")
    set_status(lua, audioState=0, decodeFull=1000)
    pb.recover(pb)
    assert calls(lua, "resumeAudio") == []          # not enough buffered yet
    set_status(lua, audioState=0, decodeFull=50000)
    pb.recover(pb)
    pb.recover(pb)
    assert len(calls(lua, "resumeAudio")) == 1      # once per underrun
    lua("playback.sentOutputUnderrunEvent = false")
    set_status(lua, audioState=0, decodeFull=50000)
    pb.recover(pb)                                  # healthy: re-arm
    set_status(lua, audioState=2, decodeFull=50000) # audio underrun bit
    pb.recover(pb)
    assert len(calls(lua, "resumeAudio")) == 2


def test_recover_when_not_playing_does_nothing(lua, pb):
    lua("package.loaded['squeezeplay.decode'].resumeAudio = function() rec('resumeAudio') end")
    set_status(lua, audioState=2, decodeFull=50000)
    pb.recover(pb)
    assert calls(lua, "resumeAudio") == []
