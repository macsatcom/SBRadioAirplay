"""Smoke tests: AirPlayMeta and AirPlayApplet load and run with faked Jive."""
import pytest

JIVE = r'''
log = {}
local function rec(...) table.insert(log, table.concat({...}, ' ')) end
jive = {ui={EVENT_WINDOW_POP=1}}
local function widget(kind)
  return function(...) local w = {kind=kind, items={}}
    w.addWidget=function(self, x) end
    w.addItem=function(self, item) table.insert(self.items, item); lastMenu = self end
    w.setText=function(self, item, t) item.text = t end
    w.addListener=function() end
    w.show=function(self) rec('show', kind); shown = self end
    w.hide=function() end
    return w end
end
package.loaded['jive.ui.Window'] = widget('window')
package.loaded['jive.ui.SimpleMenu'] = widget('menu')
timers = {}
package.loaded['jive.ui.Timer'] = function(ms, cb, once)
  local t = {ms=ms, cb=cb}; t.start=function() end; t.stop=function() end
  table.insert(timers, t); return t end
package.loaded['jive.utils.log'] = {logger=function() return {warn=function() end, info=function() end} end}
package.loaded['jive.System'] = {getMachine=function() return 'baby' end}
package.loaded['jive.AppletMeta'] = {}
package.loaded['jive.Applet'] = {}
package.loaded['jive.slim.Player'] = {getLocalPlayer=function() return nil end, getCurrentPlayer=function() return nil end}
package.loaded['squeezeplay.decode'] = {}
package.loaded['squeezeplay.stream'] = {}
package.loaded['jive.net.RequestHttp'] = nil
os = {execute=function(c) rec('exec', c); return 0 end}
appletManager = {
  loadApplet=function(self, n) rec('loadApplet', n) end,
  getAppletInstance=function(self, n) return n == 'AirPlay' and appletInstance or nil end,
  hasService=function() return false end}
menuItems = {}
jiveMain = {addItem=function(self, item) table.insert(menuItems, item) end}
'''


@pytest.fixture
def jive(lua):
    lua(JIVE)
    return lua


def test_meta_registers_and_defaults(jive):
    meta_mod = jive.load("AirPlayMeta")
    meta = jive.eval("{}")
    jive("_meta = ...", ) if False else None
    jive("""metaObj = setmetatable({menuItem=function(self, id, node, label, cb, w)
            return {id=id, node=node, label=label, cb=cb} end,
            storeSettings=function() end},
            {__index=package.loaded['applets.AirPlay.AirPlayMeta']})""")
    jive("metaObj:registerApplet()")
    assert jive.eval("menuItems[1].id") == "airplay" and jive.eval("menuItems[1].node") == "home"
    assert jive.eval("log[1]") == "loadApplet AirPlay"
    d = jive.eval("metaObj:defaultSettings()")
    assert d.serviceMode == "always_on" and d.deviceName == "Squeezebox Radio"
    up = jive.eval("metaObj:upgradeSettings({})")
    assert up.serviceMode == "always_on"


def test_touch_model_name(jive):
    jive("package.loaded['jive.System'] = {getMachine=function() return 'fab4' end}")
    jive.load("AirPlayMeta")
    jive("metaObj = setmetatable({}, {__index=package.loaded['applets.AirPlay.AirPlayMeta']})")
    assert jive.eval("metaObj:defaultSettings()").deviceName == "Squeezebox Touch"


def test_applet_init_starts_service_and_watcher(jive):
    jive.load("AirPlayApplet")
    jive("""appletInstance = setmetatable({_settings={serviceMode='always_on', deviceName='Squeezebox Radio'},
            storeSettings=function() end}, {__index=package.loaded['applets.AirPlay.AirPlayApplet']})""")
    jive("appletInstance:init()")
    cmds = [jive.eval(f"log[{i}]") for i in range(1, jive.eval("#log") + 1)]
    assert any("chmod 755 /usr/share/jive/applets/AirPlay/airplay-receiver" in c for c in cmds)
    assert any("--state-dir /tmp/airplay" in c for c in cmds)
    ms = sorted(jive.eval(f"timers[{i}].ms") for i in range(1, jive.eval("#timers") + 1))
    assert 250 in ms and 10000 in ms
    # watcher tick on a PC without /tmp/airplay must not raise
    t250 = [jive.eval(f"timers[{i}]") for i in range(1, jive.eval("#timers") + 1) if jive.eval(f"timers[{i}].ms") == 250][0]
    t250.cb()


def test_menu_builds(jive):
    jive.load("AirPlayMeta")
    jive.load("AirPlayApplet")
    jive("""appletInstance = setmetatable({_settings={serviceMode='manual', deviceName='Kitchen'},
            storeSettings=function() end}, {__index=package.loaded['applets.AirPlay.AirPlayApplet']})
            appletInstance:init()
            metaObj = setmetatable({menuItem=function(self, id, node, label, cb) return {cb=cb} end,
              storeSettings=function() end}, {__index=package.loaded['applets.AirPlay.AirPlayMeta']})
            metaObj:registerApplet()
            menuItems[1].cb()""")
    texts = [jive.eval(f"lastMenu.items[{i}].text") for i in range(1, jive.eval("#lastMenu.items") + 1)]
    assert texts[0] == "Operating Mode: Manual"
    assert "Start AirPlay" in texts and "Speaker name: Kitchen" in texts


def test_free_keeps_service_running(jive):
    jive.load("AirPlayApplet")
    jive("""appletInstance = setmetatable({_settings={serviceMode='always_on'}, storeSettings=function() end},
            {__index=package.loaded['applets.AirPlay.AirPlayApplet']}); appletInstance:init()
            shutdownCalled = false
            appletInstance.service.shutdown = function() shutdownCalled = true end""")
    assert jive.eval("appletInstance:free()") is False
    assert jive.eval("shutdownCalled") is False
