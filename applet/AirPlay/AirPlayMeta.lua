-- AirPlay applet registration and Home menu.
local oo = require("loop.simple")
local AppletMeta = require("jive.AppletMeta")
local Window = require("jive.ui.Window")
local SimpleMenu = require("jive.ui.SimpleMenu")
local Timer = require("jive.ui.Timer")
local ipairs, pcall, require = ipairs, pcall, require
local jiveMain = jiveMain
local appletManager = appletManager
local EVENT_WINDOW_POP = jive.ui.EVENT_WINDOW_POP

module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta) return 1, 1 end

local function modelName()
    local ok, System = pcall(require, "jive.System")
    if ok then
        local okMachine, machine = pcall(function() return System:getMachine() end)
        if okMachine and machine == "fab4" then return "Squeezebox Touch" end
    end
    return "Squeezebox Radio"
end

function defaultSettings(meta)
    return { serviceMode = "always_on", deviceName = modelName() }
end

function upgradeSettings(meta, settings)
    settings = settings or {}
    if settings.serviceMode == nil then settings.serviceMode = "always_on" end
    if settings.deviceName == nil then settings.deviceName = modelName() end
    return settings
end

local MODE_NAMES = { disabled = "Disabled", manual = "Manual", always_on = "Always On" }

local function showModes(meta, service)
    local window = Window("text_list", "Operating Mode")
    local menu = SimpleMenu("menu")
    window:addWidget(menu)
    for _, mode in ipairs({ "disabled", "manual", "always_on" }) do
        local selected = mode
        menu:addItem({ text = MODE_NAMES[selected] .. (service:getMode() == selected and " *" or ""),
            callback = function() service:setMode(selected); meta:storeSettings(); window:hide() end })
    end
    window:show()
end

local function showMenu(meta)
    local applet = appletManager:getAppletInstance("AirPlay")
    local service = applet and applet.service
    if not service then return end
    local window = Window("text_list", "AirPlay")
    local menu = SimpleMenu("menu")
    window:addWidget(menu)
    local modeItem = { text = "Operating Mode: " .. MODE_NAMES[service:getMode()],
        callback = function() showModes(meta, service) end }
    local stateItem = { text = "State: " .. service:getStatus() }
    menu:addItem(modeItem)
    menu:addItem(stateItem)
    if service:getMode() == "manual" then
        menu:addItem({ text = "Start AirPlay", callback = function() service:start() end })
        menu:addItem({ text = "Stop AirPlay", callback = function() service:stop(false) end })
    end
    if service:getMode() ~= "disabled" then
        menu:addItem({ text = "Restart AirPlay", callback = function() service:restart() end })
    end
    menu:addItem({ text = "Speaker name: " .. service:speakerName() })
    if service:getLastError() then menu:addItem({ text = "Last error: " .. service:getLastError() }) end
    local timer = Timer(2000, function()
        menu:setText(stateItem, "State: " .. service:getStatus())
        menu:setText(modeItem, "Operating Mode: " .. MODE_NAMES[service:getMode()])
    end)
    timer:start()
    window:addListener(EVENT_WINDOW_POP, function() timer:stop() end)
    window:show()
end

function registerApplet(meta)
    -- Background service: load at boot so the speaker is visible without
    -- opening the menu first.
    appletManager:loadApplet("AirPlay")
    jiveMain:addItem(meta:menuItem("airplay", "home", "AIRPLAY", function() showMenu(meta) end, 1))
end

function configureApplet(meta) end
