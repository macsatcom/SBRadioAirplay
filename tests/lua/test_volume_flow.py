"""End-to-end (watcher + real AirPlayPlayback): the iPhone's volume must be
applied when a session starts, also when the volume file is unchanged from
before (SqueezePlay restarted while the receiver kept running)."""

PRELUDE = r'''
calls = {}
function rec(...) table.insert(calls, {...}) end
playback = {stopInternal=function() end, _streamConnect=function() end,
  _getGainFromVolume=function(self, v) return math.floor(65536 * 10 ^ (-(100 - v) * 0.72 / 20) + 0.5) end}
player = {playback=playback, volume=function(self, v, send) rec('volume', v) end,
  incrementSequenceNumber=function() end}
package.loaded['jive.slim.Player'] = {getLocalPlayer=function() return player end,
  getCurrentPlayer=function() return player end}
package.loaded['squeezeplay.decode'] = {start=function() end, audioGain=function() end,
  status=function() return {audioState=0, decodeFull=0} end}
package.loaded['squeezeplay.stream'] = {icyMetaInterval=function() end}
snapshot = {}
'''


def test_volume_applied_at_session_start_when_unchanged(lua):
    lua(PRELUDE)
    st = lua.load("AirPlayState")
    st.read = lua.eval("function() return snapshot end")
    pb_mod = lua.load("AirPlayPlayback")
    pb = pb_mod()
    pb.init(pb, None, None)
    w = lua.load("AirPlayWatcher").new(lua.eval("{}"))
    w.playback = pb
    w.nowPlaying = lua.eval("{activate=function() end, update=function() end, release=function() end}")
    lua("snapshot = {state='stopped', volume=0.333}")
    w.tick(w)
    lua("snapshot = {gen=1, port=6062, state='playing', volume=0.333}")
    w.tick(w)
    vols = [lua.eval(f"calls[{i}][2]") for i in range(1, lua.eval("#calls") + 1)]
    assert vols and vols[-1] > 40, vols
