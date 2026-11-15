"""AirPlayState: parse /tmp/airplay state files; diff successive snapshots."""
import pytest


@pytest.fixture
def st(lua):
    lua("files = {}")
    lua("open = function(path) local v = files[path]; if not v then return nil end; "
        "return {read=function(self, fmt) return v end, close=function() end} end")
    return lua.load("AirPlayState")


def put(lua, name, content):
    lua(f"files['/tmp/airplay/{name}'] = {content!r}")


def read(lua, st):
    return st.read("/tmp/airplay", lua.eval("open"))


def test_valid_files_parse(lua, st):
    put(lua, "stream", "3 6069\n")
    put(lua, "state", "playing\n")
    put(lua, "volume", "0.500\n")
    put(lua, "metadata", "Song\nBand\nRecord\n")
    s = read(lua, st)
    assert (s.gen, s.port, s.state, s.volume) == (3, 6069, "playing", 0.5)
    assert (s.title, s.artist, s.album) == ("Song", "Band", "Record")


def test_missing_files_give_nils(lua, st):
    s = read(lua, st)
    assert s.gen is None and s.port is None and s.state is None and s.volume is None and s.title is None


def test_default_open_on_missing_dir_does_not_error(lua, st):
    s = st.read("/nonexistent/airplay-test-dir")
    assert s.gen is None


@pytest.mark.parametrize("bad", ["abc", "1", "1 99999999", "0 6000", "-1 6000", "1 6000 7", ""])
def test_garbage_stream_rejected(lua, st, bad):
    put(lua, "stream", bad)
    s = read(lua, st)
    assert s.gen is None and s.port is None


def test_unknown_state_rejected(lua, st):
    put(lua, "state", "dancing\n")
    assert read(lua, st).state is None


@pytest.mark.parametrize("raw,expected", [("1.000", 1.0), ("0", 0.0), ("1.7", 1.0), ("-0.2", 0.0), ("x", None), ("", None)])
def test_volume_clamped_or_rejected(lua, st, raw, expected):
    put(lua, "volume", raw)
    assert read(lua, st).volume == expected


def test_metadata_title_only(lua, st):
    put(lua, "metadata", "Only Title\n\n\n")
    s = read(lua, st)
    assert s.title == "Only Title" and s.artist == "" and s.album == ""


def snap(lua, **kw):
    t = lua.eval("{}")
    for k, v in kw.items():
        t[k] = v
    return t


def test_diff_first_snapshot_with_stream_is_new(lua, st):
    d = st.diff(None, snap(lua, gen=1, port=6000, state="playing"))
    assert d.newStream and not d.stopped


def test_diff_same_generation_not_new(lua, st):
    a = snap(lua, gen=1, port=6000, state="playing")
    b = snap(lua, gen=1, port=6000, state="playing")
    assert not st.diff(a, b).newStream


def test_diff_new_generation_is_new(lua, st):
    d = st.diff(snap(lua, gen=1, port=6000, state="flushed"), snap(lua, gen=2, port=6001, state="playing"))
    assert d.newStream


def test_diff_stop_detected_once(lua, st):
    a = snap(lua, gen=1, port=6000, state="playing")
    b = snap(lua, gen=1, port=6000, state="stopped")
    assert st.diff(a, b).stopped
    assert not st.diff(b, b).stopped


def test_diff_initial_stopped_is_not_a_stop(lua, st):
    assert not st.diff(None, snap(lua, state="stopped")).stopped


def test_diff_volume_and_metadata(lua, st):
    a = snap(lua, volume=0.5, title="A", artist="X", album="Y")
    b = snap(lua, volume=0.6, title="B", artist="X", album="Y")
    d = st.diff(a, b)
    assert d.volumeChanged and d.metadataChanged
    d = st.diff(b, b)
    assert not d.volumeChanged and not d.metadataChanged


def test_diff_volume_appearing_counts(lua, st):
    assert st.diff(snap(lua), snap(lua, volume=0.3)).volumeChanged
