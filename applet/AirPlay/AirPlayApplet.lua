-- AirPlay applet: owns the receiver service, the playback adapter and the
-- 250 ms state watcher.
local oo = require("loop.simple")
local Applet = require("jive.Applet")
local Timer = require("jive.ui.Timer")
local Log = require("jive.utils.log")
local AirPlayService = require("applets.AirPlay.AirPlayService")
local AirPlayPlayback = require("applets.AirPlay.AirPlayPlayback")
local AirPlayNowPlaying = require("applets.AirPlay.AirPlayNowPlaying")
local AirPlayWatcher = require("applets.AirPlay.AirPlayWatcher")
local AirPlayOwnership = require("applets.AirPlay.AirPlayOwnership")
local pcall, os = pcall, os
local appletManager = appletManager

module(...)
oo.class(_M, Applet)

local log = Log.logger("applet.AirPlay")

function init(self)
    os.execute("chmod 755 " .. AirPlayService.BIN .. " 2>/dev/null")
    self._settings = self._settings or {}
    self.ownership = AirPlayOwnership.new({ onPowerOff = function() self.playback:stop() end })
    self.playback = AirPlayPlayback()
    self.playback:init(self, self.ownership)
    self.nowPlaying = AirPlayNowPlaying.new({ log = log })
    self.watcher = AirPlayWatcher.new({ playback = self.playback, nowPlaying = self.nowPlaying,
        appletManager = appletManager, log = log })
    self.service = AirPlayService()
    self.service:init(self)
    self._watchTimer = Timer(250, function()
        local ok, err = pcall(function() self.watcher:tick() end)
        if not ok then log:warn("AirPlay watcher: ", err) end
    end)
    self._watchTimer:start()
end

-- Background service: refuse to be freed so the speaker stays available
-- after the menu is closed.
function free(self)
    return false
end
