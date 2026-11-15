"""AirPlayNowPlaying: Standalone Base Now Playing API client (source 'airplay')."""
import pytest

PRELUDE = r'''
requests, timers = {}, {}
respond = nil   -- function(method, path, payload) -> status, body
request = function(method, path, payload, cb)
  table.insert(requests, {method=method, path=path, payload=payload})
  if respond then cb(respond(method, path, payload)) end
end
timerFactory = function(ms, cb, once)
  local t = {ms=ms, cb=cb, once=once}
  t.start = function(self) self.started = true end
  t.stop = function(self) self.started = false end
  table.insert(timers, t); return t
end
ok = function(method, path)
  if path == '/api/nowplaying/claim' then
    return 201, '{"success":true,"active":true,"session_id":"S1","generation":4}'
  end
  return 200, '{"success":true}'
end
package.loaded['json'] = {
  encode=function(v) return 'json' end,
  decode=function(s)
    local t = {}
    for k, v in string.gmatch(s, '"([%w_]+)":("?[^,}"]*"?)') do
      if v == 'true' then t[k] = true elseif v == 'false' then t[k] = false
      elseif tonumber(v) then t[k] = tonumber(v) else t[k] = v:gsub('"', '') end
    end
    return t
  end}
'''


@pytest.fixture
def np(lua):
    lua(PRELUDE)
    mod = lua.load("AirPlayNowPlaying")
    return mod.new(lua.eval("{request=request, timerFactory=timerFactory}"))


def reqs(lua):
    return [lua.eval(f"requests[{i}]") for i in range(1, lua.eval("#requests") + 1)]


def data(lua, **kw):
    t = lua.eval("{}")
    for k, v in kw.items():
        t[k] = v
    return t


def test_activate_claims_then_publishes(lua, np):
    lua("respond = ok")
    np.activate(np, data(lua, title="Song", artist="Band", album="Rec", playback_state="playing"), 1)
    r = reqs(lua)
    assert [x.path for x in r] == ["/api/nowplaying/claim", "/api/nowplaying/update"]
    claim = r[0].payload
    assert claim.source == "airplay" and claim.name == "AirPlay"
    caps = claim.capabilities
    assert all(caps[k] is False for k in ["play", "pause", "stop", "next", "previous", "seek", "volume"])
    up = r[1].payload
    assert up.session_id == "S1" and up.state == "playing" and up.live is False
    assert up.track.title == "Song" and up.track.artist == "Band" and up.track.album == "Rec"
    assert up.track.id.startswith("airplay:")


def test_track_id_stable_and_distinct(lua, np):
    mod = lua.eval("package.loaded['applets.AirPlay.AirPlayNowPlaying']")
    a = mod.trackId(data(lua, title="A", artist="B", album="C"))
    assert a == mod.trackId(data(lua, title="A", artist="B", album="C"))
    assert a != mod.trackId(data(lua, title="A2", artist="B", album="C"))


def test_activate_without_metadata_publishes_placeholder(lua, np):
    lua("respond = ok")
    np.activate(np, data(lua, playback_state="playing"), 1)
    up = reqs(lua)[1].payload
    assert up.track.title == "AirPlay" and up.track.id.startswith("airplay:")


def test_unchanged_update_sends_nothing(lua, np):
    lua("respond = ok")
    d = data(lua, title="Song", artist="Band", album="Rec", playback_state="playing")
    np.activate(np, d, 1)
    n = len(reqs(lua))
    assert np.update(np, data(lua, title="Song", artist="Band", album="Rec", playback_state="playing"), 1) is False
    assert len(reqs(lua)) == n
    assert np.update(np, data(lua, title="Next", artist="Band", album="Rec", playback_state="playing"), 1) is True
    assert reqs(lua)[-1].path == "/api/nowplaying/update"


def test_release(lua, np):
    lua("respond = ok")
    np.activate(np, data(lua, title="Song", playback_state="playing"), 1)
    np.release(np)
    assert reqs(lua)[-1].path == "/api/nowplaying/release"


def test_failure_schedules_retry_without_error(lua, np):
    lua("respond = function() return nil, nil, 'connection refused' end")
    np.activate(np, data(lua, title="Song", playback_state="playing"), 1)
    ts = [lua.eval(f"timers[{i}]") for i in range(1, lua.eval("#timers") + 1)]
    assert any(t.ms == 2000 and t.started for t in ts)
