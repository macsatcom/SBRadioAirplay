"""AirPlayApplet watcher: state files -> playback, volume, Now Playing, hand-over."""
import pytest

PRELUDE = r'''
log = {}
local function rec(...) table.insert(log, table.concat({...}, ' ')) end
snapshot = {}
fakeState = {read=function(dir) rec('read', dir); return snapshot end}
playbackObj = {
  start=function(self, host, port) rec('start', host, port); return true end,
  stop=function(self) rec('stop') end,
  setRemoteVolume=function(self, p) rec('volume', p); return true end,
  setAirPlayVolume=function(self, v) rec('airplay', string.format('%.3f', v)); return true end,
  isActive=function() return true end}
nowPlayingObj = {
  activate=function(self, d, g) rec('np.activate', d.title or '-', g) end,
  update=function(self, d, g) rec('np.update', d.title or '-', g) end,
  release=function(self) rec('np.release') end,
  shutdown=function(self) end}
radioStopped, spotifyStopped = false, false
appletManager = {
  getAppletInstance=function(self, name)
    if name == 'StandaloneRadio' then
      return {streamPlayer={ownsPlayback=true, desiredStation='x',
        stop=function(sp) radioStopped = true end}}
    elseif name == 'SpotifyConnect' then
      return {playback={isActive=true, stop=function() spotifyStopped = true end, playback={}}}
    end
  end,
  hasService=function() return true end,
  callService=function(self, name) rec('service', name); return true end}
'''


@pytest.fixture
def app(lua):
    lua(PRELUDE)
    real = lua.load("AirPlayState")
    real.read = lua.eval("fakeState.read")
    mod = lua.load("AirPlayWatcher")
    return mod.new(lua.eval("{playback=playbackObj, nowPlaying=nowPlayingObj, appletManager=appletManager}"))


def set_snap(lua, **kw):
    lua("snapshot = {}")
    for k, v in kw.items():
        lua(f"snapshot[{k!r}] = {v!r}" if isinstance(v, str) else f"snapshot[{k!r}] = {v}")


def events(lua):
    out = [lua.eval(f"log[{i}]") for i in range(1, lua.eval("#log") + 1)]
    lua("log = {}")
    return [e for e in out if not e.startswith("read")]


def test_new_stream_hands_over_and_starts(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app)
    ev = events(lua)
    assert "start 127.0.0.1 6069" in ev
    assert lua.eval("radioStopped") and lua.eval("spotifyStopped")
    assert any(e.startswith("np.activate") for e in ev)
    assert "service goNowPlaying" in ev


def test_same_snapshot_does_nothing(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app); events(lua)
    app.tick(app)
    assert events(lua) == []


def test_resume_after_pause_restarts_without_navigation(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app); events(lua)
    set_snap(lua, gen=1, port=6069, state="flushed")
    app.tick(app); events(lua)
    set_snap(lua, gen=2, port=6070, state="playing")
    app.tick(app)
    ev = events(lua)
    assert "start 127.0.0.1 6070" in ev
    assert "service goNowPlaying" not in ev
    assert not any(e.startswith("np.activate") for e in ev)


def test_stop_releases(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app); events(lua)
    set_snap(lua, gen=1, port=6069, state="stopped")
    app.tick(app)
    assert events(lua) == ["stop", "np.release"]


def test_new_session_after_stop_navigates_again(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app)
    set_snap(lua, gen=1, port=6069, state="stopped")
    app.tick(app); events(lua)
    set_snap(lua, gen=2, port=6070, state="playing")
    app.tick(app)
    ev = events(lua)
    assert "service goNowPlaying" in ev and any(e.startswith("np.activate") for e in ev)


def test_volume(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing", volume=0.5)
    app.tick(app)
    assert "airplay 0.500" in events(lua)
    set_snap(lua, gen=1, port=6069, state="playing", volume=0.004)
    app.tick(app)
    assert events(lua) == ["airplay 0.004"]


def test_metadata_updates_now_playing(lua, app):
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app); events(lua)
    set_snap(lua, gen=1, port=6069, state="playing", title="Song", artist="Band", album="Rec")
    app.tick(app)
    assert events(lua) == ["np.update Song 1"]


def test_stream_while_stopped_state_is_ignored(lua, app):
    set_snap(lua, gen=1, port=6069, state="stopped")
    app.tick(app)
    assert events(lua) == []


def test_now_playing_error_does_not_block_audio(lua, app):
    lua("nowPlayingObj.activate = function() error('boom') end")
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app)
    assert "start 127.0.0.1 6069" in events(lua)


def test_missing_other_applets_is_fine(lua, app):
    lua("appletManager.getAppletInstance = function() return nil end")
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app)
    assert "start 127.0.0.1 6069" in events(lua)


def test_leftover_paused_session_at_startup_does_not_play(lua, app):
    # SqueezePlay restarted while an old receiver session was paused
    set_snap(lua, gen=3, port=6069, state="flushed")
    app.tick(app)
    assert events(lua) == []


def test_player_not_ready_retries_next_tick(lua, app):
    lua("playbackObj.start = function(self, h, p) table.insert(log, 'start-fail'); return false end")
    set_snap(lua, gen=1, port=6069, state="playing")
    app.tick(app)
    assert "start-fail" in events(lua)
    lua("playbackObj.start = function(self, h, p) table.insert(log, 'start ' .. h .. ' ' .. p); return true end")
    app.tick(app)
    assert "start 127.0.0.1 6069" in events(lua)


def test_volume_not_lost_when_start_fails(lua, app):
    lua("playbackObj.start = function() return false end")
    set_snap(lua, gen=1, port=6069, state="playing", volume=0.4)
    app.tick(app)
    assert "airplay 0.400" in events(lua)
