-- Minimal WoW 3.3.5a API mock for running the addon offline under Lua 5.1.
-- Each call to Mock.NewSession() builds an isolated global environment, so
-- tests can load the addon several times (e.g. as different classes).

local Mock = {}

local ADDON_DIR = "RotationHelper"

-- Load order for the offline harness. AceGUI/AceConfig are UI-only and are
-- only syntax-checked (see run.lua), so they are not loaded here.
local LIB_FILES = {
    "Libs/LibStub/LibStub.lua",
    "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
    "Libs/AceAddon-3.0/AceAddon-3.0.lua",
    "Libs/AceEvent-3.0/AceEvent-3.0.lua",
    "Libs/AceConsole-3.0/AceConsole-3.0.lua",
    "Libs/AceTimer-3.0/AceTimer-3.0.lua",
    "Libs/AceDB-3.0/AceDB-3.0.lua",
}

-- Addon files come from the TOC, so the harness can't drift from the game.
local function ReadToc(root)
    local files, meta = {}, {}
    for line in io.lines(root .. "/" .. ADDON_DIR .. "/" .. ADDON_DIR .. ".toc") do
        line = line:gsub("\r", "")
        local key, value = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
        if key then
            meta[key] = value
        elseif line:match("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files, meta
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function NewFrameFactory(session)
    local FrameMethods = {}
    FrameMethods.__index = FrameMethods

    function FrameMethods:RegisterEvent(e) self.events[e] = true end
    function FrameMethods:UnregisterEvent(e) self.events[e] = nil end
    function FrameMethods:UnregisterAllEvents() self.events = {} end
    function FrameMethods:IsEventRegistered(e) return self.events[e] or false end
    function FrameMethods:SetScript(name, fn) self.scripts[name] = fn end
    function FrameMethods:GetScript(name) return self.scripts[name] end
    function FrameMethods:HookScript(name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end
    function FrameMethods:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function FrameMethods:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function FrameMethods:IsShown() return self.shown end
    function FrameMethods:IsVisible() return self.shown end
    function FrameMethods:GetName() return self.name end
    -- Layout/visual methods are no-ops for now.
    for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight",
        "SetParent", "SetScale", "SetAlpha", "SetMovable", "EnableMouse", "RegisterForDrag",
        "SetClampedToScreen", "SetFrameStrata", "SetFrameLevel", "SetAllPoints" }) do
        FrameMethods[m] = function() end
    end

    return function(frameType, name, parent)
        local f = setmetatable({
            frameType = frameType, name = name, parent = parent,
            events = {}, scripts = {}, shown = true,
        }, FrameMethods)
        session.frames[#session.frames + 1] = f
        if name then session.env[name] = f end
        return f
    end
end

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------
function Mock.NewSession(opts)
    opts = opts or {}
    local root = opts.root or "."
    local session = { frames = {}, chat = {}, time = 1000, class = opts.class or "DEATHKNIGHT" }

    local env = {}
    setmetatable(env, { __index = _G }) -- standard Lua library
    env._G = env
    session.env = env

    -- WoW's global string/table aliases
    env.strfind, env.strsub, env.strmatch, env.gsub = string.find, string.sub, string.match, string.gsub
    env.strlower, env.strupper, env.strlen, env.strrep = string.lower, string.upper, string.len, string.rep
    env.strbyte, env.strchar, env.format, env.gmatch = string.byte, string.char, string.format, string.gmatch
    env.strtrim = function(s, chars)
        chars = chars and ("[" .. chars .. "]") or "%s"
        return (s:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
    end
    env.strsplit = function(sep, s, limit)
        local out, pos, n = {}, 1, 0
        while true do
            n = n + 1
            if limit and n >= limit then out[#out + 1] = s:sub(pos); break end
            local a, b = s:find(sep, pos, true)
            if not a then out[#out + 1] = s:sub(pos); break end
            out[#out + 1] = s:sub(pos, a - 1)
            pos = b + 1
        end
        return unpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.tinsert, env.tremove, env.tconcat, env.sort = table.insert, table.remove, table.concat, table.sort
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.table = setmetatable({ wipe = env.wipe }, { __index = table })
    env.floor, env.ceil, env.abs, env.max, env.min = math.floor, math.ceil, math.abs, math.max, math.min
    env.mod = math.fmod

    env.geterrorhandler = function() return function(err) error(err, 0) end end
    env.seterrorhandler = function() end
    env.debugstack = function() return debug.traceback() end
    env.issecurevariable = function() return true end
    env.hooksecurefunc = function(tbl, name, fn)
        if type(tbl) == "string" then tbl, name, fn = env, tbl, name end
        local old = tbl[name]
        tbl[name] = function(...) local r = { old(...) }; fn(...); return unpack(r) end
    end

    -- Chat output
    local function capture(msg) session.chat[#session.chat + 1] = tostring(msg) end
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        capture(table.concat(parts, " "))
    end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) capture(msg) end }
    env.SlashCmdList = {}
    env.hash_SlashCmdList = {}

    -- Game state
    env.GetTime = function() return session.time end
    env.GetLocale = function() return "enUS" end
    env.GetRealmName = function() return "Whitemane" end
    env.UnitName = function() return "Tester" end
    env.UnitClass = function() return session.class:sub(1, 1) .. session.class:sub(2):lower(), session.class end
    env.UnitRace = function() return "Human", "Human" end
    env.UnitFactionGroup = function() return "Alliance", "Alliance" end
    env.IsLoggedIn = function() return session.loggedIn end
    env.InCombatLockdown = function() return session.inCombat or false end
    env.GetCurrentRegion = nil

    local _, tocMeta = ReadToc(root)
    env.GetAddOnMetadata = function(addon, field)
        if addon == ADDON_DIR then return tocMeta[field] end
    end
    env.GetAddOnInfo = function(addon) return addon, addon, "", true, true end
    env.IsAddOnLoaded = function(addon) return addon == ADDON_DIR end

    env.CreateFrame = NewFrameFactory(session)
    env.UIParent = env.CreateFrame("Frame", "UIParent")

    session.toc = tocMeta
    return setmetatable(session, { __index = Mock })
end

function Mock:LoadFile(path, ...)
    local chunk, err = loadfile(path)
    if not chunk then error(err, 0) end
    setfenv(chunk, self.env)
    return chunk(...)
end

-- Loads libraries, then the addon's TOC files with the (name, namespace)
-- varargs the client passes, then fires ADDON_LOADED + PLAYER_LOGIN.
function Mock:LoadAddon()
    local root = "."
    for _, f in ipairs(LIB_FILES) do
        self:LoadFile(root .. "/" .. ADDON_DIR .. "/" .. f)
    end
    self.ns = {}
    local files = ReadToc(root)
    for _, f in ipairs(files) do
        self:LoadFile(root .. "/" .. ADDON_DIR .. "/" .. f, ADDON_DIR, self.ns)
    end
    self:FireEvent("ADDON_LOADED", ADDON_DIR)
    self.loggedIn = true
    self:FireEvent("PLAYER_LOGIN")
    self:FireEvent("PLAYER_ENTERING_WORLD")
    return self.env.RotationHelper
end

function Mock:FireEvent(event, ...)
    for _, f in ipairs(self.frames) do
        if f.events[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end

-- Advances time and runs every visible frame's OnUpdate once.
function Mock:Tick(dt)
    self.time = self.time + dt
    for _, f in ipairs(self.frames) do
        if f.shown and f.scripts.OnUpdate then
            f.scripts.OnUpdate(f, dt)
        end
    end
end

function Mock:Slash(cmd, msg)
    local handler = self.env.SlashCmdList[cmd]
    assert(handler, "no slash handler " .. cmd)
    handler(msg or "")
end

function Mock:ClearChat() self.chat = {} end

function Mock:ChatContains(pattern)
    for _, line in ipairs(self.chat) do
        if line:find(pattern) then return true end
    end
    return false
end

return Mock
