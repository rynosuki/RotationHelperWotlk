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
-- Methods shared by frames, textures and font strings.
local RegionMethods = {}

function RegionMethods:SetPoint(point, rel, relPoint, x, y)
    -- Normalize the short forms SetPoint("TOPLEFT", x, y) and SetPoint("CENTER").
    if type(rel) == "number" or rel == nil then
        rel, relPoint, x, y = self.parent, point, rel or 0, relPoint or 0
    end
    self.points[#self.points + 1] = { point, rel, relPoint, x, y }
end
function RegionMethods:GetPoint(i)
    local p = self.points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function RegionMethods:ClearAllPoints() self.points = {} end
function RegionMethods:SetAllPoints(rel) self.points = { { "ALL", rel or self.parent } } end
function RegionMethods:SetWidth(w) self.width = w end
function RegionMethods:SetHeight(h) self.height = h end
function RegionMethods:GetWidth() return self.width or 0 end
function RegionMethods:GetHeight() return self.height or 0 end
function RegionMethods:Show()
    self.shown = true
    if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function RegionMethods:Hide()
    self.shown = false
    if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function RegionMethods:IsShown() return self.shown end
function RegionMethods:IsVisible()
    local r = self
    while r do
        if not r.shown then return false end
        r = r.parent
    end
    return true
end
function RegionMethods:SetAlpha(a) self.alpha = a end
function RegionMethods:GetName() return self.name end
function RegionMethods:GetParent() return self.parent end

local TextureMethods = setmetatable({}, { __index = RegionMethods })
TextureMethods.__index = TextureMethods
function TextureMethods:SetTexture(t) self.texture = t end
function TextureMethods:GetTexture() return self.texture end
function TextureMethods:SetTexCoord(...) self.texCoord = { ... } end
function TextureMethods:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
function TextureMethods:SetDrawLayer(layer) self.layer = layer end
function TextureMethods:SetBlendMode() end

local FontStringMethods = setmetatable({}, { __index = RegionMethods })
FontStringMethods.__index = FontStringMethods
function FontStringMethods:SetText(t) self.text = t end
function FontStringMethods:GetText() return self.text end
function FontStringMethods:SetFont(...) self.font = { ... } end
function FontStringMethods:SetFontObject(f) self.fontObject = f end
function FontStringMethods:SetTextColor(...) self.textColor = { ... } end
function FontStringMethods:SetJustifyH(j) self.justifyH = j end
function FontStringMethods:SetJustifyV(j) self.justifyV = j end
function FontStringMethods:SetShadowOffset() end

local function NewFrameFactory(session)
    local FrameMethods = setmetatable({}, { __index = RegionMethods })
    FrameMethods.__index = FrameMethods

    function FrameMethods:CreateTexture(name, layer)
        return setmetatable({ name = name, parent = self, layer = layer, points = {}, shown = true }, TextureMethods)
    end
    function FrameMethods:CreateFontString(name, layer, template)
        return setmetatable({ name = name, parent = self, layer = layer, template = template,
            points = {}, shown = true }, FontStringMethods)
    end
    function FrameMethods:SetBackdrop(b) self.backdrop = b end
    function FrameMethods:SetBackdropColor(...) self.backdropColor = { ... } end
    function FrameMethods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    function FrameMethods:SetScale(s) self.scale = s end
    function FrameMethods:GetScale() return self.scale or 1 end
    function FrameMethods:EnableMouse(e) self.mouseEnabled = e and true or false end
    function FrameMethods:IsMouseEnabled() return self.mouseEnabled end
    function FrameMethods:SetMovable(m) self.movable = m end
    function FrameMethods:RegisterForDrag(...) self.dragButtons = { ... } end
    function FrameMethods:StartMoving() self.moving = true end
    function FrameMethods:StopMovingOrSizing() self.moving = false end
    function FrameMethods:SetFrameLevel(l) self.frameLevel = l end
    function FrameMethods:GetFrameLevel() return self.frameLevel or 1 end
    -- Cooldown frames
    function FrameMethods:SetCooldown(start, duration) self.cooldownStart, self.cooldownDuration = start, duration end

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
    function FrameMethods:SetClampedToScreen() end
    function FrameMethods:SetFrameStrata() end
    function FrameMethods:SetParent(p) self.parent = p end

    return function(frameType, name, parent, template)
        local f = setmetatable({
            frameType = frameType, name = name, parent = parent, template = template,
            events = {}, scripts = {}, points = {}, shown = true,
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

    -- WoW's bit library (Lua 5.1 has none).
    env.bit = {
        band = function(a, b)
            local result, bitValue = 0, 1
            while a > 0 and b > 0 do
                local ra, rb = a % 2, b % 2
                if ra == 1 and rb == 1 then result = result + bitValue end
                a, b, bitValue = (a - ra) / 2, (b - rb) / 2, bitValue * 2
            end
            return result
        end,
    }

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

    -- Spells: id -> { name, icon }. Tests may add more via session.spells.
    session.spells = {
        [51425] = { "Obliterate", "Interface\\Icons\\Spell_DeathKnight_ClassIcon" },
        [55268] = { "Frost Strike", "Interface\\Icons\\Spell_DeathKnight_EmpowerRuneBlade2" },
        [51411] = { "Howling Blast", "Interface\\Icons\\Spell_Frost_ArcticWinds" },
        [49909] = { "Icy Touch", "Interface\\Icons\\Spell_DeathKnight_IceTouch" },
        [49921] = { "Plague Strike", "Interface\\Icons\\Spell_DeathKnight_EmpowerRuneBlade" },
        [57623] = { "Horn of Winter", "Interface\\Icons\\INV_Misc_Horn_02" },
        [57330] = { "Horn of Winter", "Interface\\Icons\\INV_Misc_Horn_02" },
        [49930] = { "Blood Strike", "i" }, [50842] = { "Pestilence", "i" }, [49941] = { "Blood Boil", "i" },
        [49938] = { "Death and Decay", "i" }, [49895] = { "Death Coil", "i" }, [49924] = { "Death Strike", "i" },
        [45529] = { "Blood Tap", "i" }, [51271] = { "Unbreakable Armor", "i" },
        [47568] = { "Empower Rune Weapon", "i" }, [49796] = { "Deathchill", "i" },
        [42650] = { "Army of the Dead", "i" }, [46584] = { "Raise Dead", "i" }, [47528] = { "Mind Freeze", "i" },
        [55095] = { "Frost Fever", "i" }, [55078] = { "Blood Plague", "i" }, [51124] = { "Killing Machine", "i" },
        [59052] = { "Freezing Fog", "i" }, [48266] = { "Blood Presence", "i" }, [48263] = { "Frost Presence", "i" },
        [48265] = { "Unholy Presence", "i" }, [2825] = { "Bloodlust", "i" }, [32182] = { "Heroism", "i" },
        -- glyph spells
        [58647] = { "Glyph of Frost Strike", "i" }, [58671] = { "Glyph of Obliterate", "i" },
    }
    -- Like the real client, a lookup by name only finds spells in the spellbook.
    session.known = {}
    env.GetSpellInfo = function(idOrName)
        if type(idOrName) == "string" then
            if session.known[idOrName] then return idOrName, "", "i" end
            return nil
        end
        local s = session.spells[idOrName]
        if s then return s[1], "", s[2] end
    end

    -- Action bars: slot -> { type, id, subType, spellId }; bindings: command -> key.
    session.actions, session.bindings, session.macros = {}, {}, {}
    env.GetActionInfo = function(slot)
        local a = session.actions[slot]
        if a then return a[1], a[2], a[3], a[4] end
    end
    env.GetBindingKey = function(command) return session.bindings[command] end
    env.GetMacroSpell = function(id) return session.macros[id] end
    env.GetSpellName = function() return nil end

    -- Target and range: session.range[spellName] = 0 marks it out of range.
    session.hasTarget, session.range = false, {}
    session.target = { name = "Training Dummy", guid = "0xF130000001", health = 100, healthMax = 100,
        level = -1, canAttack = true, dead = false, classification = "worldboss" }
    env.UnitExists = function(unit) return unit == "target" and session.hasTarget end
    env.IsSpellInRange = function(name) return session.range[name] or 1 end
    env.UnitGUID = function(unit)
        if unit == "player" then return Mock.PLAYER_GUID end
        return unit == "target" and session.hasTarget and session.target.guid or nil
    end
    local baseUnitName = env.UnitName
    env.UnitName = function(unit)
        if unit == "target" then return session.hasTarget and session.target.name or nil end
        return baseUnitName(unit)
    end
    env.UnitCanAttack = function(_, unit) return unit == "target" and session.hasTarget and session.target.canAttack end
    env.UnitIsDead = function(unit) return unit == "target" and session.hasTarget and session.target.dead end
    env.UnitHealth = function(unit) return unit == "target" and session.target.health or 0 end
    env.UnitHealthMax = function(unit) return unit == "target" and session.target.healthMax or 0 end
    env.UnitLevel = function(unit) return unit == "target" and session.target.level or 80 end
    env.UnitClassification = function(unit) return unit == "target" and session.target.classification or "normal" end
    env.UnitCastingInfo = function() return nil end
    env.UnitChannelInfo = function() return nil end
    env.GetUnitSpeed = function() return session.speed or 0 end

    -- Power: runic power by default.
    session.power = { type = 6, current = 0, max = 130 }
    env.UnitPowerType = function() return session.power.type end
    env.UnitPower = function() return session.power.current end
    env.UnitPowerMax = function() return session.power.max end

    -- Runes: slots 1-2 blood, 3-4 unholy, 5-6 frost, all ready.
    -- Set session.runes[i].readyAt to make a rune recharge.
    session.runes = {}
    for i, t in ipairs({ 1, 1, 2, 2, 3, 3 }) do session.runes[i] = { type = t } end
    session.runeRegen = 10
    env.GetRuneType = function(i) return session.runes[i].type end
    env.GetRuneCooldown = function(i)
        local r = session.runes[i]
        if r.readyAt and r.readyAt > session.time then
            return r.readyAt - session.runeRegen, session.runeRegen, false
        end
        return 0, 0, true
    end

    -- Auras: session.auras.player / .target = list of
    -- { name, spellId, count, duration, expires, caster, harmful }
    session.auras = { player = {}, target = {} }
    env.UnitAura = function(unit, index, filter)
        local wantHarmful = filter and filter:find("HARMFUL") ~= nil
        local n = 0
        for _, a in ipairs(session.auras[unit] or {}) do
            if (a.harmful or false) == wantHarmful then
                n = n + 1
                if n == index then
                    return a.name, "", "icon", a.count or 0, nil, a.duration or 0, a.expires or 0,
                        a.caster or "player", nil, nil, a.spellId
                end
            end
        end
    end

    -- Cooldowns by spell name: session.cooldowns[name] = { start, duration }
    session.cooldowns = {}
    env.GetSpellCooldown = function(name)
        local c = session.cooldowns[name]
        if c then return c[1], c[2], 1 end
        return 0, 0, 1
    end

    -- Talents: session.talentTabs = { { name = "Frost", talents = { { "Name", rank }, ... } }, ... }
    session.talentTabs = {
        { name = "Blood", talents = { { "Butchery", 0 }, { "Subversion", 3 } } },
        { name = "Frost", talents = { { "Blood of the North", 3 }, { "Killing Machine", 5 }, { "Chill of the Grave", 2 } } },
        { name = "Unholy", talents = { { "Epidemic", 2 } } },
    }
    session.talentGroup = 1
    env.GetActiveTalentGroup = function() return session.talentGroup end
    env.GetNumTalentTabs = function() return #session.talentTabs end
    env.GetTalentTabInfo = function(tab)
        local t = session.talentTabs[tab]
        local points = 0
        for _, talent in ipairs(t.talents) do points = points + talent[2] end
        return t.name, "icon", points, "bg"
    end
    env.GetNumTalents = function(tab) return #session.talentTabs[tab].talents end
    env.GetTalentInfo = function(tab, i)
        local talent = session.talentTabs[tab].talents[i]
        return talent[1], "icon", 1, 1, talent[2], 5
    end

    -- Glyphs: session.glyphs[socket] = glyph spell ID
    session.glyphs = {}
    env.GetGlyphSocketInfo = function(socket)
        local id = session.glyphs[socket]
        return id ~= nil, 1, id, "icon"
    end

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

Mock.PLAYER_GUID = "0x0000000000000001"
-- Combat log unit flags: us (mine, friendly player), and a hostile NPC.
Mock.FLAGS_ME = 0x511
Mock.FLAGS_HOSTILE_NPC = 0xa48
Mock.FLAGS_FRIENDLY_NPC = 0xa18

-- Fires a combat log event with 3.3.5's argument layout.
function Mock:CombatLog(subevent, srcGUID, srcFlags, dstGUID, dstFlags)
    self:FireEvent("COMBAT_LOG_EVENT_UNFILTERED", self.time, subevent,
        srcGUID, "src", srcFlags, dstGUID, "dst", dstFlags, 49909, "Icy Touch", 16)
end

-- Adds an aura. unit is "player" or "target"; fields as in session.auras.
function Mock:AddAura(unit, aura)
    local list = self.auras[unit]
    list[#list + 1] = aura
end

-- Marks spells (by name) as in the spellbook and refreshes the Spec module.
function Mock:Learn(...)
    for i = 1, select("#", ...) do self.known[(select(i, ...))] = true end
    self:FireEvent("LEARNED_SPELL_IN_TAB")
end

-- Puts a spell on an action slot, optionally bound to a key.
function Mock:PlaceSpell(slot, spellId, command, key)
    self.actions[slot] = { "spell", slot, "spell", spellId }
    if command then self.bindings[command] = key end
    self:FireEvent("ACTIONBAR_SLOT_CHANGED", slot)
end

function Mock:ChatContains(pattern)
    for _, line in ipairs(self.chat) do
        if line:find(pattern) then return true end
    end
    return false
end

return Mock
