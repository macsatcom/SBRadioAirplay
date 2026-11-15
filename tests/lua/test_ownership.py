"""AirPlayOwnership: while AirPlay plays, keep the server (Standalone Base or
LMS) from controlling or flooding the local player. Same rules Standalone
Radio applies while it owns the decoder."""
import pytest

PRELUDE = r'''
log = {}
local function rec(...) table.insert(log, table.concat({...}, ' ')) end
ticks = 1000
package.loaded['jive.ui.Framework'] = {getTicks=function() return ticks end}
slimproto = {send=function(self, packet, force) rec('send', packet.opcode or '?', packet.event or '') return 'sent' end}
playback = {slimproto=slimproto, sequenceNumber=10,
  _audg=function(self, data, isLocal) rec('audg', tostring(isLocal)) end,
  _strm=function(self, data) rec('strm', data.command) end,
  _cont=function(self) rec('cont') end,
  _aude=function(self) rec('aude') end}
player = {playback=playback, state={},
  getCurrentSequenceNumber=function(self) return self.playback.sequenceNumber end,
  getVolume=function() return 40 end,
  refreshLocallyMaintainedParameters=function(self)
    self.playback.sequenceNumber = self.playback.sequenceNumber + 1; rec('refresh') end,
  setPower=function(self, on) rec('power', tostring(on)) end}
jiveMain = {getSoftPowerState=function() return 'on' end}
'''


@pytest.fixture
def own(lua):
    lua(PRELUDE)
    mod = lua.load("AirPlayOwnership")
    o = mod.new(lua.eval("{onPowerOff=function() table.insert(log, 'onPowerOff') end}"))
    o.install(o, lua.eval("player"))
    return o


def ev(lua):
    out = [lua.eval(f"log[{i}]") for i in range(1, lua.eval("#log") + 1)]
    lua("log = {}")
    return out


def test_inactive_passes_everything_through(lua, own):
    lua("playback:_audg({}, false); playback:_strm({command='q'}); playback:_cont(); playback:_aude()")
    lua("slimproto:send({opcode='RESP'})")
    assert ev(lua) == ["audg false", "strm q", "cont", "aude", "send RESP "]


def test_active_ignores_server_volume_but_not_local(lua, own):
    own.setActive(own, True)
    lua("playback:_audg({}, false); playback:_audg({}, true)")
    assert ev(lua) == ["audg true"]


def test_active_ignores_server_stream_commands(lua, own):
    own.setActive(own, True)
    lua("playback:_strm({command='q'}); playback:_cont(); playback:_aude()")
    assert ev(lua) == []


def test_active_only_heartbeat_and_status_reach_server(lua, own):
    own.setActive(own, True)
    lua("slimproto:send({opcode='HELO'}); slimproto:send({opcode='STAT', event='STMt'})")
    lua("slimproto:send({opcode='RESP'}); slimproto:send({opcode='META'})")
    assert ev(lua) == ["send HELO ", "send STAT STMt"]


def test_active_coalesces_refresh_storm(lua, own):
    own.setActive(own, True)
    lua("player:refreshLocallyMaintainedParameters()")
    lua("ticks = 1500; player:refreshLocallyMaintainedParameters()")
    lua("ticks = 1900; player:refreshLocallyMaintainedParameters()")
    assert ev(lua) == ["refresh"]
    lua("ticks = 4000; player:refreshLocallyMaintainedParameters()")
    assert ev(lua) == ["refresh"]


def test_active_rebases_stale_sequence_number(lua, own):
    own.setActive(own, True)
    lua("player.state.seq_no = '500'; player:refreshLocallyMaintainedParameters()")
    assert lua.eval("playback.sequenceNumber") == 501


def test_inactive_refresh_unchanged(lua, own):
    lua("player:refreshLocallyMaintainedParameters(); player:refreshLocallyMaintainedParameters()")
    assert ev(lua) == ["refresh", "refresh"]


def test_power_off_while_active_stops_airplay(lua, own):
    own.setActive(own, True)
    lua("player:setPower(false)")
    assert ev(lua) == ["onPowerOff", "power false"]
    lua("player:setPower(true)")
    assert ev(lua) == ["power true"]


def test_install_twice_wraps_once(lua, own):
    own.install(own, lua.eval("player"))
    own.setActive(own, True)
    lua("playback:_audg({}, true)")
    assert ev(lua) == ["audg true"]


def test_release_restores_pass_through(lua, own):
    own.setActive(own, True)
    own.setActive(own, False)
    lua("playback:_audg({}, false); slimproto:send({opcode='RESP'})")
    assert ev(lua) == ["audg false", "send RESP "]
