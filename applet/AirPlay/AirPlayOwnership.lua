-- While AirPlay plays, the local player must not be driven by the server it is
-- connected to (Standalone Base or an LMS): that server did not start this
-- stream. Modelled on the guards Standalone Radio installs while it owns the
-- decoder (SBStandalone StreamPlayer._installHooks), reimplemented here.
--
-- Rules while active:
--  * server volume (wire audg) ignored; local volume changes still apply
--  * server stream commands (strm/cont/aude) ignored
--  * only HELO and STAT reach the server (keeps the session alive)
--  * the stock stale-sequence refresh is rebased and coalesced (no storm)
--  * power off stops AirPlay
-- Inactive: everything passes straight through.
local setmetatable, pairs, tonumber, type = setmetatable, pairs, tonumber, type
local Framework = require("jive.ui.Framework")
local jiveMain = jiveMain

module(...)

local COALESCE_MS = 2000

local Ownership = {}
Ownership.__index = Ownership

-- options.onPowerOff(): called when the player is switched off while active
function new(options)
    return setmetatable({ options = options or {}, active = false, hooked = nil }, Ownership)
end

function Ownership:setActive(on)
    self.active = on and true or false
end

function Ownership:install(player)
    local playback = player and player.playback
    if not playback or self.hooked == playback then return end
    self.hooked = playback
    local own = self

    local audg = playback._audg
    if audg then
        playback._audg = function(instance, data, isLocal)
            if own.active and not isLocal then return end
            return audg(instance, data, isLocal)
        end
    end
    for _, name in pairs({ "_strm", "_cont", "_aude" }) do
        local original = playback[name]
        if original then
            playback[name] = function(instance, ...)
                if own.active then return end
                return original(instance, ...)
            end
        end
    end

    local slimproto = playback.slimproto
    if slimproto and slimproto.send then
        local send = slimproto.send
        slimproto.send = function(proto, packet, force)
            local opcode = type(packet) == "table" and packet.opcode or nil
            if own.active and opcode ~= "HELO" and opcode ~= "STAT" then return true end
            return send(proto, packet, force)
        end
    end

    local refresh = player.refreshLocallyMaintainedParameters
    if refresh then
        local last
        player.refreshLocallyMaintainedParameters = function(instance, ...)
            if not own.active then last = nil; return refresh(instance, ...) end
            -- The server can be far ahead after a SqueezePlay restart: adopt
            -- its sequence instead of firing rejected refreshes forever.
            local serverSeq = instance.state and tonumber(instance.state.seq_no)
            local seq = instance:getCurrentSequenceNumber()
            if serverSeq and serverSeq > seq and type(instance.playback.sequenceNumber) == "number" then
                instance.playback.sequenceNumber = serverSeq
            end
            local now = Framework:getTicks()
            local volume = instance:getVolume()
            local power = jiveMain and jiveMain:getSoftPowerState()
            if last and last.volume == volume and last.power == power
                and now >= last.at and now - last.at < COALESCE_MS then
                return
            end
            last = { volume = volume, power = power, at = now }
            return refresh(instance, ...)
        end
    end

    local setPower = player.setPower
    if setPower then
        player.setPower = function(instance, on, ...)
            if not on and own.active and own.options.onPowerOff then own.options.onPowerOff() end
            return setPower(instance, on, ...)
        end
    end
end
