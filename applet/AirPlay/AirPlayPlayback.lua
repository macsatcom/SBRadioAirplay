-- Plays the receiver's loopback PCM stream through SqueezePlay's stock player.
-- Adapted from Squeezebox Spotify Connect's SpotifyPlayback.lua (MIT).
local oo = require("loop.simple")
local Player = require("jive.slim.Player")
local decode = require("squeezeplay.decode")
local Stream = require("squeezeplay.stream")
local string, math = require("string"), require("math")
local pcall, type, tonumber, tostring = pcall, type, tonumber, tostring
local okLog, Log = pcall(require, "jive.utils.log")
local log = okLog and Log.logger("applet.AirPlay") or nil
local function info(...) if log then log:info(...) end end

module(...)
oo.class(_M)

-- ownership: AirPlayOwnership instance (keeps the server off the player)
function init(self, applet, ownership)
    self.applet = applet
    self.ownership = ownership
    self.playback = nil
    self.remoteVolume = nil
end

function isActive(self)
    return self.playback ~= nil
end

function start(self, host, port)
    local player = Player:getLocalPlayer() or Player:getCurrentPlayer()
    local playback = player and player.playback
    if not playback then return false end
    self.playback = playback
    if self.ownership then
        self.ownership:install(player)
        self.ownership:setActive(true)
    end
    playback:stopInternal()
    if player.incrementSequenceNumber then player:incrementSequenceNumber() end
    playback.flags = 0
    playback.mode = 'p'
    playback.header = "GET /stream HTTP/1.0\n" ..
        "Host: " .. host .. "\n" ..
        "Accept: audio/L16,*/*\n" ..
        "Connection: close\n\n"
    playback.autostart = '1'
    playback.threshold = 0
    playback.decodeThreshold = 2048
    playback.sentResume = false
    playback.sentResumeDecoder = false
    playback.sentDecoderUnderrunEvent = false
    playback.sentDecoderFullEvent = false
    playback.sentOutputUnderrunEvent = false
    playback.sentAudioUnderrunEvent = false
    playback.isLooping = false
    playback.ignoreStream = false
    Stream:icyMetaInterval(0)
    -- 'p' = PCM; params: 16-bit ('1'), 44.1 kHz ('3'), stereo ('2'),
    -- big-endian ('0'), matching the receiver's audio/L16 output.
    decode:start(string.byte('p'), 0, 0, 0, 0, 0, 0,
        string.byte('1'), string.byte('3'), string.byte('2'), string.byte('0'))
    playback:_streamConnect(host, port)
    if self.pendingAirPlay then
        local v = self.pendingAirPlay
        self.pendingAirPlay = nil
        self:setAirPlayVolume(v)
    elseif self.remoteVolume then
        self:setRemoteVolume(self.remoteVolume)
    end
    return true
end

-- percent 0..100. Before start the value is remembered and applied on start.
function setRemoteVolume(self, percent)
    self.remoteVolume = math.max(0, math.min(100, math.floor(percent)))
    if not self.playback then info("AirPlay volume ", self.remoteVolume, " deferred: not playing"); return false end
    local player = Player:getLocalPlayer()
    if not player or player.playback ~= self.playback then
        info("AirPlay volume ", self.remoteVolume, " not applied: local player changed")
        return false
    end
    info("AirPlay volume ", self.remoteVolume, " applied")
    -- Same path as the volume knob: sets the gain and stores the value on the
    -- server. The server's stored volume is what SqueezePlay's periodic
    -- refresh re-applies, so it must be ours. (AirPlayOwnership prevents the
    -- refresh storm this used to cause.)
    player:volume(self.remoteVolume, true)
    return true
end

local DB_GAIN = { 65536, 58409, 52057, 46396, 41350, 36854, 32846, 29274, 26090, 23253,
    20724, 18471, 16462, 14672, 13076, 11654, 10387, 9257, 8250, 7353, 6554, 5841, 5206,
    4640, 4135, 3685, 3285, 2927, 2609, 2325, 2072 }

-- AirPlay volume (0..1, linear in dB over -30..0, 0 = mute) -> the Radio
-- volume step whose firmware gain is closest to that dB level.
function setAirPlayVolume(self, airplay)
    info("AirPlay volume level ", tostring(airplay))
    if not airplay or airplay <= 0 then return self:setRemoteVolume(0) end
    local playback = self.playback
    if not playback then
        self.pendingAirPlay = airplay
        return false
    end
    -- 65536 * 10^(-dB/20) for 0..30 dB. Precomputed: SqueezePlay's Lua on the
    -- Radio does not evaluate fractional powers (10 ^ x gave ~0, i.e. volume 1).
    local dB = math.floor((1 - math.min(airplay, 1)) * 30 + 0.5)
    local target = DB_GAIN[dB + 1]
    local best, bestDiff = 100, math.huge
    for step = 1, 100 do
        local gain = playback:_getGainFromVolume(step)
        local diff = gain and math.abs(gain - target)
        if diff and diff < bestDiff then best, bestDiff = step, diff end
    end
    info("AirPlay volume ", dB, " dB below max -> step ", best)
    return self:setRemoteVolume(best)
end

-- Stock Playback pauses audio after an output underrun and waits for the
-- server to send strm-u. Without an LMS nobody does, so resume locally once
-- enough data is buffered (as Standalone Radio does). Call periodically.
local DECODE_UNDERRUN_BIT = 2  -- bit 1 of audioState

function recover(self)
    local playback = self.playback
    if not playback then self.underrunRecovered = false; return end
    local ok, status = pcall(function() return decode:status() end)
    if not ok or type(status) ~= "table" then return end
    local audioUnderrun = math.floor((tonumber(status.audioState) or 0) / DECODE_UNDERRUN_BIT) % 2 == 1
    if not audioUnderrun and not playback.sentOutputUnderrunEvent then
        self.underrunRecovered = false
        return
    end
    local threshold = tonumber(playback.decodeThreshold) or 2048
    if not self.underrunRecovered and (tonumber(status.decodeFull) or 0) > threshold then
        decode:resumeAudio()
        self.underrunRecovered = true
    end
end

function stop(self)
    if self.playback then
        self.playback:stopInternal()
        self.playback = nil
    end
    if self.ownership then self.ownership:setActive(false) end
end
