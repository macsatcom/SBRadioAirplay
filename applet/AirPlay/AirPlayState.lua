-- Pure parsing of the receiver's state files (see airplay-receiver
-- --state-dir). No Jive dependencies so it can be tested on a PC.
local io, tonumber, string = io, tonumber, string

module(...)

local STATES = { playing = true, flushed = true, stopped = true }

local function slurp(open, path)
    local f = open(path, "r")
    if not f then return nil end
    local value = f:read("*a")
    f:close()
    return value
end

local function parseStream(raw)
    if not raw then return nil end
    local gen, port = string.match(raw, "^(%d+) (%d+)%s*$")
    gen, port = tonumber(gen), tonumber(port)
    if not gen or gen < 1 or not port or port < 1 or port > 65535 then return nil end
    return gen, port
end

local function parseVolume(raw)
    local v = tonumber(raw and string.match(raw, "^%s*(%S+)%s*$"))
    if not v then return nil end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

-- Snapshot of the state directory; any missing or malformed file reads as nil.
function read(dir, open)
    open = open or io.open
    local s = {}
    s.gen, s.port = parseStream(slurp(open, dir .. "/stream"))
    local state = slurp(open, dir .. "/state")
    state = state and string.match(state, "^(%a+)%s*$")
    s.state = STATES[state] and state or nil
    s.volume = parseVolume(slurp(open, dir .. "/volume"))
    local meta = slurp(open, dir .. "/metadata")
    if meta then
        local title, artist, album = string.match(meta, "^([^\n]*)\n?([^\n]*)\n?([^\n]*)")
        s.title, s.artist, s.album = title, artist or "", album or ""
    end
    return s
end

-- What changed between two snapshots (old may be nil on the first tick).
function diff(old, new)
    old = old or {}
    return {
        newStream = new.gen ~= nil and new.gen ~= old.gen,
        stopped = new.state == "stopped" and old.state ~= nil and old.state ~= "stopped",
        volumeChanged = new.volume ~= nil and new.volume ~= old.volume,
        metadataChanged = new.title ~= nil and (new.title ~= old.title
            or new.artist ~= old.artist or new.album ~= old.album),
    }
end
