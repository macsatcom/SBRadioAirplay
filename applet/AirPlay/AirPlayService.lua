-- Lifecycle of the background airplay-receiver process.
-- Follows Squeezebox Spotify Connect's SpotifyService.lua (MIT): pid file plus
-- /proc/<pid>/cmdline ownership check, no forks on the polling path.
local oo = require("loop.simple")
local io, os, string, tostring, pcall, require, ipairs = io, os, string, tostring, pcall, require, ipairs

module(...)
oo.class(_M)

BIN = "/usr/share/jive/applets/AirPlay/airplay-receiver"
STATE_DIR = "/tmp/airplay"
PID = STATE_DIR .. "/receiver.pid"
LOG = STATE_DIR .. "/receiver.log"

local MODES = { disabled = true, manual = true, always_on = true }
local HEALTH_MS = 10000

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function defaultModel()
    local ok, System = pcall(require, "jive.System")
    if ok then
        local okMachine, machine = pcall(function() return System:getMachine() end)
        if okMachine and machine == "fab4" then return "Squeezebox Touch" end
    end
    return "Squeezebox Radio"
end

function init(self, applet, deps)
    deps = deps or {}
    self.applet = applet
    self.execute = deps.execute or os.execute
    self.open = deps.open or io.open
    self.timer = deps.timer or require("jive.ui.Timer")
    self.model = deps.model or defaultModel()
    self.mac = deps.mac
    self.desiredRunning = false
    self.lastError = nil
    self.healthTimer = self.timer(HEALTH_MS, function() self:_health() end)
    self.healthTimer:start()
    if self:getMode() == "always_on" then self:start() end
end

function _read(self, path)
    local f = self.open(path, "r")
    if not f then return nil end
    local value = f:read("*a")
    f:close()
    return value
end

function _mac(self)
    if self.mac then return self.mac end
    for _, iface in ipairs({ "eth1", "wlan0", "eth0" }) do
        local mac = self:_read("/sys/class/net/" .. iface .. "/address")
        if mac and #mac >= 2 then return (mac:gsub("%s", "")) end
    end
end

function speakerName(self)
    local settings = self.applet._settings or {}
    local name = settings.deviceName
    if name and name ~= "" and name ~= self.model then return name end
    local mac = self:_mac()
    if mac and #mac >= 2 then return self.model .. "-" .. mac:sub(-2):upper() end
    return self.model
end

function getMode(self)
    local mode = self.applet._settings and self.applet._settings.serviceMode
    return MODES[mode] and mode or "manual"
end

function setMode(self, mode)
    if not MODES[mode] then self.lastError = "Invalid operating mode"; return false end
    local settings = self.applet._settings or {}
    self.applet._settings = settings
    settings.serviceMode = mode
    if self.applet.storeSettings then pcall(function() self.applet:storeSettings() end) end
    if mode == "disabled" then self:stop(true)
    elseif mode == "always_on" then self:start() end
    return true
end

function _pid(self)
    local pid = self:_read(PID)
    pid = pid and pid:match("^%s*([1-9]%d*)%s*$")
    if not pid then return nil end
    local cmdline = self:_read("/proc/" .. pid .. "/cmdline")
    if not cmdline or cmdline:match("^([^%z]*)") ~= BIN then return nil end
    return pid
end

function isRunning(self)
    return self:_pid() ~= nil
end

function getStatus(self)
    if self:isRunning() then return "running" end
    return self.lastError and "error" or "stopped"
end

function getLastError(self) return self.lastError end

function start(self)
    if self:getMode() == "disabled" then
        self.lastError = "AirPlay is disabled"
        return false
    end
    self.desiredRunning = true
    if self:isRunning() then return true end
    -- drop a previous receiver's state so the watcher cannot act on it
    local cmd = "mkdir -p " .. STATE_DIR .. "; rm -f " .. STATE_DIR .. "/stream " .. STATE_DIR ..
        "/state; : > " .. LOG .. "; ( exec " .. q(BIN) ..
        " --name " .. q(self:speakerName()) .. " --state-dir " .. STATE_DIR ..
        " -d 1 >/dev/null 2>>" .. LOG .. " ) & echo $! > " .. PID
    if self.execute(cmd) ~= 0 then
        self.lastError = "Could not start the AirPlay receiver"
        return false
    end
    self.lastError = nil
    return true
end

function stop(self, force)
    if self:getMode() == "always_on" and not force then
        self.lastError = "Change Operating Mode to Manual before stopping"
        return false
    end
    self.desiredRunning = false
    local pid = self:_pid()
    if pid then self.execute("kill -TERM " .. pid .. " 2>/dev/null") end
    return true
end

function restart(self)
    self:stop(true)
    return self:start()
end

function _health(self)
    if self.desiredRunning and self:getMode() ~= "disabled" and not self:isRunning() then
        self.lastError = "AirPlay receiver stopped unexpectedly; restarting"
        self:start()
    end
end

function shutdown(self)
    if self.healthTimer then self.healthTimer:stop(); self.healthTimer = nil end
    self:stop(true)
end
