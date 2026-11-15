"""AirPlayPlayback: drive SqueezePlay's stock player with the PCM decoder."""
import pytest

PRELUDE = r'''
calls = {}
local function rec(...) table.insert(calls, {...}) end
playback = {
  stopInternal=function(self) rec('stopInternal') end,
  _streamConnect=function(self, host, port) rec('streamConnect', host, port) end,
  _getGainFromVolume=function(self, v) return v * 1000 end,
}
player = {playback=playback,
  volumeLocal=function(self, v, a, b) rec('volumeLocal', v, a, b) end,
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
    mod = lua.load("AirPlayPlayback")
    inst = mod()
    inst.init(inst, None)
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


def test_volume_uses_firmware_curve(lua, pb):
    pb.start(pb, "127.0.0.1", 6069)
    assert pb.setRemoteVolume(pb, 50) is True
    assert calls(lua, "volumeLocal") == [[50, True, True]]
    assert calls(lua, "audioGain") == [[50000, 50000]]


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
