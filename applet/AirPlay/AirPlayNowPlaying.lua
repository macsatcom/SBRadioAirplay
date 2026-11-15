-- Standalone Base Now Playing API client for AirPlay.
-- Adapted from Squeezebox Spotify Connect's SpotifyStandaloneNowPlaying.lua (MIT):
-- source "airplay", hashed track ids, no artwork, no audio-quality fields.
local pcall, setmetatable, tonumber, tostring, type = pcall, setmetatable, tonumber, tostring, type
local string, math = require("string"), require("math")
local okHttp, RequestHttp = pcall(require, "jive.net.RequestHttp")
local okSocket, SocketHttp = pcall(require, "jive.net.SocketHttp")
local okTimer, Timer = pcall(require, "jive.ui.Timer")
local okLtn12, ltn12 = pcall(require, "ltn12")
local okJson, json = pcall(require, "json")
local jnt = jnt
module(...)

local Client = {}; Client.__index = Client
local HEARTBEAT_MS, REQUEST_TIMEOUT_MS, MAX_RESPONSE_BYTES = 45000, 15000, 16384
local RETRY_MS = { 2000, 5000, 10000, 30000 }
local VALID_STATE = { playing=true, paused=true, stopped=true, buffering=true, error=true }

local function capabilities()
    -- The sender owns control; no DACP remote control is implemented yet.
    return {play=false,pause=false,stop=false,next=false,previous=false,seek=false,volume=false}
end
local function text(v) return tostring(v or ""):gsub("^%s*(.-)%s*$", "%1") end
-- AirPlay has no track ids: derive a stable one from the metadata.
local function trackId(data)
    local key = text(data and data.title) .. "\n" .. text(data and data.artist) .. "\n" .. text(data and data.album)
    local h = 5381
    for i = 1, #key do h = (h * 33 + string.byte(key, i)) % 4294967296 end
    return string.format("airplay:%08x", h)
end

function new(options)
    options = options or {}
    return setmetatable({log=options.log, requestFn=options.request, timerFactory=options.timerFactory,
        isPlaybackOwner=options.isPlaybackOwner, host=options.host or "127.0.0.1", port=options.port or 9000,
        retryIndex=1, revision=0, publishedRevision=-1, requestSerial=0, activationGeneration=0}, Client)
end
function Client:_timer(delay, callback, once)
    if self.timerFactory then return self.timerFactory(delay, callback, once) end
    if okTimer then return Timer(delay, callback, once) end
end
function Client:_stopTimer(name)
    local t=self[name]; self[name]=nil; if t and t.stop then t:stop() end
end
function Client:_log(level, ...)
    if self.log and self.log[level] then self.log[level](self.log, "AirPlay NowPlayingAPI: ", ...) end
end
function Client:_nativeRequest(method, path, payload, callback)
    if not (okHttp and okSocket and okLtn12 and okJson) then callback(nil,nil,"HTTP/JSON unavailable"); return end
    local body = payload and json.encode(payload) or ""; local completed=false; local request
    local function finish(status,response,err) if completed then return end; completed=true; callback(status,response,err) end
    request = RequestHttp(function(response,err)
        local status=request:t_getResponseStatus(); if err then finish(status,nil,tostring(err))
        elseif response ~= nil then finish(status,response,nil) end
    end, method, path, {t_bodySource=method=="POST" and ltn12.source.string(body) or nil,
        headers={Host=self.host..":"..tostring(self.port),["Content-Type"]="application/json",
            ["Content-Length"]=tostring(#body),Accept="application/json",Connection="close"}})
    request.t_setResponseBody=function(instance,response)
        local status=instance:t_getResponseStatus()
        if type(response)=="string" and #response>MAX_RESPONSE_BYTES then finish(status,nil,"response too large")
        else finish(status,response or "",nil) end
    end
    local socket=SocketHttp(jnt,self.host,self.port,"AirPlayNowPlayingAPI"); self.http=socket
    local ok,err=pcall(function() socket:fetch(request) end); if not ok then finish(nil,nil,tostring(err)) end
end
function Client:_request(method,path,payload,callback)
    if self.requestFn then return self.requestFn(method,path,payload,callback) end
    self:_nativeRequest(method,path,payload,callback)
end
function Client:_send(kind,method,path,payload,handler)
    if self.inFlight then return false end
    self.requestSerial=self.requestSerial+1; local serial=self.requestSerial; self.inFlight={serial=serial,kind=kind}
    self:_stopTimer("requestTimer")
    self.requestTimer=self:_timer(REQUEST_TIMEOUT_MS,function()
        if not self.inFlight or self.inFlight.serial~=serial then return end
        self.inFlight=nil; if self.http and self.http.close then pcall(function() self.http:close("timeout") end) end
        self:_retry(kind.." timeout")
    end,true); if self.requestTimer then self.requestTimer:start() end
    self:_request(method,path,payload,function(status,body,err)
        if not self.inFlight or self.inFlight.serial~=serial then return end
        self.inFlight=nil; self:_stopTimer("requestTimer"); local decoded
        if body and body~="" and okJson then local ok,value=pcall(function() return json.decode(body) end)
            if ok and type(value)=="table" then decoded=value else err=err or "invalid JSON" end end
        handler(status,decoded,err)
    end); return true
end
function Client:_retry(reason)
    if self.shuttingDown or (not self.activeIntent and not self.releaseRequested) or self.retryTimer then return end
    local delay=RETRY_MS[self.retryIndex] or RETRY_MS[#RETRY_MS]
    if self.retryIndex<#RETRY_MS then self.retryIndex=self.retryIndex+1 end
    self:_log("warn",reason,"; retry in ",tostring(delay),"ms")
    self.retryTimer=self:_timer(delay,function() self.retryTimer=nil; self:_sync() end,true)
    if self.retryTimer then self.retryTimer:start() end
end
function Client:_snapshot()
    if not self.data then return nil end
    local d=self.data; local title=text(d.title)
    local track={id=trackId(d),title=title~="" and title or "AirPlay",artist=text(d.artist),album=text(d.album),artwork_url=""}
    return {state=VALID_STATE[self.desiredState] and self.desiredState or "buffering",live=false,
        position_ms=0,track=track}
end
function Client:_invalidate()
    self.sessionId=nil; self.sessionGeneration=nil; self.publishedRevision=-1; self:_stopTimer("heartbeatTimer")
end
function Client:_heartbeatTimer()
    if self.heartbeatTimer then return end
    self.heartbeatTimer=self:_timer(HEARTBEAT_MS,function()
        if self.sessionId and self.activeIntent and not self.inFlight then self:_heartbeat() end
    end); if self.heartbeatTimer then self.heartbeatTimer:start() end
end
function Client:_claim()
    self:_send("claim","POST","/api/nowplaying/claim",{source="airplay",name="AirPlay",capabilities=capabilities()},function(status,r,err)
        if status==201 and r and r.success==true and r.active==true and type(r.session_id)=="string" and tonumber(r.generation) then
            self.sessionId=r.session_id; self.sessionGeneration=tonumber(r.generation); self.retryIndex=1
            self:_heartbeatTimer(); self:_sync()
        else self:_retry("claim failed HTTP "..tostring(status or err or "unavailable")) end
    end)
end
function Client:_lost()
    self:_invalidate()
    if self.activeIntent and (not self.isPlaybackOwner or self.isPlaybackOwner()) then
        self:_send("status","GET","/api/nowplaying",nil,function(status,r,err)
            if status==200 and r and r.api_version==1 then
                if r.active==true then self.activeIntent=false else self:_sync() end
            else self:_retry("status probe failed HTTP "..tostring(status or err or "unavailable")) end
        end)
    else self.activeIntent=false; self.releaseRequested=false end
end
function Client:_update()
    local snapshot=self:_snapshot(); if not snapshot then return end
    local token,revision=self.sessionId,self.revision; snapshot.session_id=token
    self:_send("update","POST","/api/nowplaying/update",snapshot,function(status,r,err)
        if token~=self.sessionId then self:_sync(); return end
        if status==200 and r and r.success==true then self.retryIndex=1; self.publishedRevision=math.max(self.publishedRevision,revision); self:_sync()
        elseif status==409 then self:_lost() else self:_retry("update failed HTTP "..tostring(status or err or "unavailable")) end
    end)
end
function Client:_heartbeat()
    local token=self.sessionId
    self:_send("heartbeat","POST","/api/nowplaying/heartbeat",{session_id=token},function(status,r,err)
        if token~=self.sessionId then return end
        if status==200 and r and r.success==true then self.retryIndex=1; self:_sync() elseif status==409 then self:_lost()
        else self:_retry("heartbeat failed HTTP "..tostring(status or err or "unavailable")) end
    end)
end
function Client:_release()
    local token=self.sessionId
    if not token then self.releaseRequested=false; return end
    self:_send("release","POST","/api/nowplaying/release",{session_id=token},function(status,r,err)
        if token~=self.sessionId then return end
        if status==200 and r and r.success==true or status==409 then self.releaseRequested=false; self:_invalidate()
        else self:_retry("release failed HTTP "..tostring(status or err or "unavailable")) end
    end)
end
function Client:_sync()
    if self.inFlight then return end; self:_stopTimer("retryTimer")
    if not self.sessionId then if self.activeIntent then self:_claim() else self.releaseRequested=false end
    elseif self.publishedRevision<self.revision then self:_update()
    elseif self.releaseRequested then self:_release() end
end
function Client:activate(data,generation)
    generation=tonumber(generation) or self.activationGeneration+1
    if generation<self.activationGeneration then return end
    self.activationGeneration=generation; self.data=data or self.data; self.activeIntent=true; self.releaseRequested=false
    self.desiredState=(data and data.playback_state) or "buffering"; self.revision=self.revision+1; self:_sync()
end
function Client:update(data,generation)
    if generation and generation~=self.activationGeneration or not self.activeIntent then return false end
    local old=self.data or {}; self.data=data or {}
    self.desiredState=VALID_STATE[self.data.playback_state] and self.data.playback_state or self.desiredState or "buffering"
    local changed=text(old.title)~=text(self.data.title)
        or text(old.artist)~=text(self.data.artist) or text(old.album)~=text(self.data.album)
        or old.playback_state~=self.data.playback_state
    if changed then self.revision=self.revision+1; self:_sync() end; return changed
end
function Client:release()
    self.activeIntent=false; self.releaseRequested=true; self.desiredState="stopped"; self.revision=self.revision+1; self:_sync()
end
function Client:shutdown()
    self.shuttingDown=true; self.activeIntent=false; self.releaseRequested=true; self.desiredState="stopped"
    self.revision=self.revision+1; self:_stopTimer("retryTimer"); self:_stopTimer("heartbeatTimer"); self:_sync()
end
function Client:status() return {activeIntent=self.activeIntent==true,hasSession=self.sessionId~=nil,generation=self.sessionGeneration,revision=self.revision,state=self.desiredState} end
_M.trackId = trackId
function advertisedCapabilities() return capabilities() end
return _M
