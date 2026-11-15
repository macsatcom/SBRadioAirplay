-- Plays the receiver's loopback PCM stream through SqueezePlay's stock player.
-- Adapted from Squeezebox Spotify Connect's SpotifyPlayback.lua (MIT).
local oo = require("loop.simple")
local Player = require("jive.slim.Player")
local decode = require("squeezeplay.decode")
local Stream = require("squeezeplay.stream")
local string, math = require("string"), require("math")

module(...)
oo.class(_M)

function init(self, applet)
    self.applet = applet
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
    if not self.playback then return false end
    local player = Player:getLocalPlayer()
    if not player or player.playback ~= self.playback then return false end
    player:volumeLocal(self.remoteVolume, true, true)
    local gain = self.remoteVolume == 0 and 0 or self.playback:_getGainFromVolume(self.remoteVolume)
    decode:audioGain(gain, gain)
    return true
end

-- AirPlay volume (0..1, linear in dB over -30..0, 0 = mute) -> the Radio
-- volume step whose firmware gain is closest to that dB level.
function setAirPlayVolume(self, airplay)
    if not airplay or airplay <= 0 then return self:setRemoteVolume(0) end
    local playback = self.playback
    if not playback then
        self.pendingAirPlay = airplay
        return false
    end
    local target = 65536 * 10 ^ ((math.min(airplay, 1) - 1) * 30 / 20)
    local best, bestDiff = 100, math.huge
    for step = 1, 100 do
        local gain = playback:_getGainFromVolume(step)
        local diff = gain and math.abs(gain - target)
        if diff and diff < bestDiff then best, bestDiff = step, diff end
    end
    return self:setRemoteVolume(best)
end

function stop(self)
    if self.playback then
        self.playback:stopInternal()
        self.playback = nil
    end
end
