-- Turns state-file snapshots into actions: start/stop playback, volume,
-- Now Playing and hand-over from Standalone Radio / Spotify Connect.
-- Called every 250 ms; only io.open reads, never forks.
local pcall, setmetatable, math = pcall, setmetatable, require("math")
local AirPlayState = require("applets.AirPlay.AirPlayState")

module(...)

STATE_DIR = "/tmp/airplay"
local LOOPBACK = "127.0.0.1"

local Watcher = {}
Watcher.__index = Watcher

-- options: playback, nowPlaying, appletManager, log (optional)
function new(options)
    return setmetatable({ playback = options.playback, nowPlaying = options.nowPlaying,
        appletManager = options.appletManager, log = options.log,
        last = nil, session = 0, active = false }, Watcher)
end

function Watcher:_warn(...)
    if self.log and self.log.warn then self.log:warn(...) end
end

local function instance(manager, name)
    if not manager or not manager.getAppletInstance then return nil end
    local ok, applet = pcall(function() return manager:getAppletInstance(name) end)
    return ok and applet or nil
end

-- Both share the single SqueezePlay decoder; stop them before taking it.
function Watcher:_handOver()
    local radio = instance(self.appletManager, "StandaloneRadio")
    local sp = radio and radio.streamPlayer
    if sp and (sp.ownsPlayback or sp.desiredStation or sp.pendingStation or sp.reconnectTimer) then
        pcall(function() sp:stop() end)
        sp.desiredStation = nil
    end
    local spotify = instance(self.appletManager, "SpotifyConnect")
    local spb = spotify and spotify.playback
    if spb and spb.playback and spb.stop then pcall(function() spb:stop() end) end
end

function Watcher:_metadata(s)
    return { title = s.title, artist = s.artist, album = s.album, playback_state = "playing" }
end

function Watcher:_goNowPlaying()
    local m = self.appletManager
    if m and m.hasService and m:hasService("goNowPlaying") then
        pcall(function() m:callService("goNowPlaying") end)
    end
end

function Watcher:tick()
    local s = AirPlayState.read(STATE_DIR)
    local firstTick = self.last == nil
    local d = AirPlayState.diff(self.last, s)
    self.last = s

    -- At startup only a session that is actually playing counts; leftovers
    -- (paused session, receiver being restarted) must not grab the decoder.
    local wantStream = d.newStream and s.state ~= "stopped" and (not firstTick or s.state == "playing")
    -- Retry a start that failed (e.g. local player not ready yet at boot).
    if not wantStream and self.pendingGen and self.pendingGen == s.gen and s.state == "playing" then
        wantStream = true
    end
    if s.state == "stopped" then self.pendingGen = nil end

    if wantStream then
        local firstOfSession = not self.active
        self:_handOver()
        if self.playback:start(LOOPBACK, s.port) then
            self.pendingGen = nil
            self.active = true
            if firstOfSession then
                self.session = self.session + 1
                local ok, err = pcall(function() self.nowPlaying:activate(self:_metadata(s), self.session) end)
                if not ok then self:_warn("Now Playing activate failed: ", err) end
                self:_goNowPlaying()
            end
        else
            self.pendingGen = s.gen
        end
    end

    if d.volumeChanged then
        self.playback:setAirPlayVolume(s.volume)
    end

    if d.metadataChanged and self.active and not d.newStream then
        local ok, err = pcall(function() self.nowPlaying:update(self:_metadata(s), self.session) end)
        if not ok then self:_warn("Now Playing update failed: ", err) end
    end

    if self.active and self.playback.recover then self.playback:recover() end

    if d.stopped and self.active then
        self.active = false
        self.playback:stop()
        pcall(function() self.nowPlaying:release() end)
    end
end
