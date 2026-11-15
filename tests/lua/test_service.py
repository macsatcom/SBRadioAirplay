"""AirPlayService: background receiver lifecycle, owned via pid + /proc cmdline."""
import pytest

BIN = "/usr/share/jive/applets/AirPlay/airplay-receiver"

PRELUDE = r'''
commands, files, timers = {}, {}, {}
running_pid = nil  -- pid whose /proc cmdline is our binary
execute = function(cmd)
  table.insert(commands, cmd)
  if string.find(cmd, "echo $! >", 1, true) then
    running_pid = "4242"; files["/tmp/airplay/receiver.pid"] = "4242\n"
  end
  if string.find(cmd, "kill -TERM 4242", 1, true) then running_pid = nil end
  return 0
end
open = function(path)
  local v = files[path]
  if path == "/proc/4242/cmdline" and running_pid == "4242" then
    v = "/usr/share/jive/applets/AirPlay/airplay-receiver\0--name\0x\0"
  end
  if not v then return nil end
  return {read=function() return v end, close=function() end}
end
timer = function(ms, cb, once)
  local t = {ms=ms, cb=cb, once=once, started=false}
  t.start = function(self) self.started = true end
  t.stop = function(self) self.started = false end
  table.insert(timers, t); return t
end
applet = {_settings={serviceMode="manual", deviceName="Squeezebox Radio"},
          storeSettings=function() end}
'''


@pytest.fixture
def svc(lua):
    lua(PRELUDE)
    mod = lua.load("AirPlayService")
    inst = mod()
    deps = lua.eval("{execute=execute, open=open, timer=timer, model='Squeezebox Radio', mac='00:04:20:2a:b3:7f'}")
    inst.init(inst, lua.eval("applet"), deps)
    return inst


def cmds(lua):
    return [lua.eval(f"commands[{i}]") for i in range(1, lua.eval("#commands") + 1)]


def start_cmd(lua):
    c = [c for c in cmds(lua) if "echo $! >" in c]
    assert len(c) == 1, cmds(lua)
    return c[0]


def test_start_command(lua, svc):
    assert svc.start(svc) is True
    c = start_cmd(lua)
    assert "mkdir -p /tmp/airplay" in c
    assert ": > /tmp/airplay/receiver.log" in c
    assert f"exec '{BIN}' --name 'Squeezebox Radio-7F' --state-dir /tmp/airplay -d 1 >/dev/null 2>>/tmp/airplay/receiver.log" in c
    assert c.rstrip().endswith("& echo $! > /tmp/airplay/receiver.pid")
    assert svc.isRunning(svc)


def test_custom_name_is_shell_quoted(lua, svc):
    lua("""applet._settings.deviceName = 'Bob\\'s "Radio"; rm -rf /'""")
    svc.start(svc)
    assert """--name 'Bob'\\''s "Radio"; rm -rf /'""" in start_cmd(lua)


def test_stale_pid_is_not_running(lua, svc):
    lua("files['/tmp/airplay/receiver.pid'] = '999\\n'")
    assert not svc.isRunning(svc)
    lua("files['/tmp/airplay/receiver.pid'] = 'abc'")
    assert not svc.isRunning(svc)


def test_pid_of_other_program_is_not_running(lua, svc):
    lua("files['/tmp/airplay/receiver.pid'] = '77\\n'; files['/proc/77/cmdline'] = '/bin/sh\\0'")
    assert not svc.isRunning(svc)


def test_start_when_running_is_noop(lua, svc):
    svc.start(svc)
    svc.start(svc)
    start_cmd(lua)  # asserts exactly one


def test_disabled_refuses_start(lua, svc):
    svc.setMode(svc, "disabled")
    assert svc.start(svc) is False
    assert not [c for c in cmds(lua) if "echo $! >" in c]


def test_stop_kills_only_owned_pid(lua, svc):
    svc.start(svc)
    assert svc.stop(svc) is True
    kills = [c for c in cmds(lua) if "kill" in c]
    assert kills == ["kill -TERM 4242 2>/dev/null"]
    assert not svc.isRunning(svc)


def test_stop_with_stale_pid_kills_nothing(lua, svc):
    lua("files['/tmp/airplay/receiver.pid'] = '999\\n'")
    svc.stop(svc)
    assert not [c for c in cmds(lua) if "kill" in c]


def health(lua):
    ts = [lua.eval(f"timers[{i}]") for i in range(1, lua.eval("#timers") + 1)]
    h = [t for t in ts if t.ms == 10000]
    assert len(h) == 1
    return h[0]


def test_health_restarts_dead_receiver(lua, svc):
    svc.start(svc)
    lua("running_pid = nil")  # crashed
    assert svc.getStatus(svc) == "stopped"
    h = health(lua)
    assert h.started
    h.cb()
    assert len([c for c in cmds(lua) if "echo $! >" in c]) == 2
    assert svc.isRunning(svc)


def test_health_does_not_restart_after_user_stop(lua, svc):
    svc.start(svc)
    svc.stop(svc)
    health(lua).cb()
    assert len([c for c in cmds(lua) if "echo $! >" in c]) == 1


def test_always_on_mode_starts(lua, svc):
    svc.setMode(svc, "always_on")
    assert svc.isRunning(svc)
    assert lua.eval("applet._settings.serviceMode") == "always_on"


def test_disabled_mode_stops(lua, svc):
    svc.start(svc)
    svc.setMode(svc, "disabled")
    assert not svc.isRunning(svc)


def test_invalid_mode_rejected(lua, svc):
    assert svc.setMode(svc, "sometimes") is False
    assert svc.getMode(svc) == "manual"


def test_speaker_name_custom(lua, svc):
    lua("applet._settings.deviceName = 'Kitchen'")
    assert svc.speakerName(svc) == "Kitchen"


def test_speaker_name_without_mac(lua):
    lua(PRELUDE)
    mod = lua.load("AirPlayService")
    inst = mod()
    inst.init(inst, lua.eval("applet"), lua.eval("{execute=execute, open=open, timer=timer, model='Squeezebox Touch'}"))
    lua("applet._settings.deviceName = 'Squeezebox Touch'")
    assert inst.speakerName(inst) == "Squeezebox Touch"
