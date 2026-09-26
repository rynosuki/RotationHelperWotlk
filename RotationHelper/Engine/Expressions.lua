local ADDON_NAME, ns = ...

-- Binds APL names to getters over the state. Every getter is
-- `function(state) -> number` and reads the state *as of state.now*, so the
-- runner can check a condition at a future time by moving state.now.
--
-- Supported names:
--   buff.KEY.up|down|react|remains|stack       (player buffs)
--   debuff.KEY.* / dot.KEY.*  (+ .ticking)     (our debuffs on the target)
--   cooldown.KEY.ready|up|remains|ready_for|duration
--   pull.active|remains, burst.active|remains
--   runic_power, runic_power.deficit|max|pct
--   runes.blood|unholy|frost|death|total        (ready runes; "rune" works too)
--   runes.TYPE.time_to_N                        (seconds until N of that type are ready)
--   gcd, gcd.remains, time, active_enemies, moving, pet.alive
--   target.health.pct, target.time_to_die
--   talent.KEY.enabled|rank, glyph.KEY.enabled
--   toggle.cooldowns
local Expressions = {}
ns.Expressions = Expressions

local huge, max = math.huge, math.max

local function B(value) return value and 1 or 0 end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------
local AURA_FIELDS = {
    up = function(rec, now) return B(rec and rec.expires > now) end,
    down = function(rec, now) return B(not (rec and rec.expires > now)) end,
    remains = function(rec, now)
        if not rec or rec.expires <= now then return 0 end
        return rec.expires == huge and 9999 or rec.expires - now
    end,
    stack = function(rec, now) return (rec and rec.expires > now) and rec.stacks or 0 end,
}
AURA_FIELDS.react = AURA_FIELDS.up
AURA_FIELDS.ticking = AURA_FIELDS.up

local function AuraGetter(parts, classData, listName)
    local key, field = parts[2], parts[3]
    local def = key and classData.auras[key]
    local wantDebuff = listName == "debuffs"
    if not def then return nil, "unknown aura '" .. tostring(key) .. "'" end
    if (def.debuff or false) ~= wantDebuff then
        return nil, ("'%s' is a %s; use %s.%s"):format(key, def.debuff and "debuff" or "buff",
            def.debuff and "dot" or "buff", key)
    end
    local fn = AURA_FIELDS[field or ""]
    if not fn or #parts > 3 then
        return nil, ("unknown field '%s' (use up, down, remains or stack)"):format(tostring(field))
    end
    return function(s) return fn(s[listName][key], s.now) end
end

---------------------------------------------------------------------------
-- Runes
---------------------------------------------------------------------------
local RUNE_TYPES = { blood = true, unholy = true, frost = true, death = true, total = true }

local function RunesReadyAt(s, runeType, at)
    local n = 0
    for i = 1, #s.runes do
        local rune = s.runes[i]
        if rune.readyAt <= at and (runeType == "total" or rune.type == runeType) then n = n + 1 end
    end
    return n
end

-- Seconds until `count` runes of the type are ready (huge if never).
local readyTimes = {}
local function TimeToRunes(s, runeType, count)
    local n = 0
    for i = 1, #s.runes do
        local rune = s.runes[i]
        if runeType == "total" or rune.type == runeType then
            n = n + 1
            readyTimes[n] = rune.readyAt
        end
    end
    if n < count then return huge end
    for i = n + 1, #readyTimes do readyTimes[i] = nil end
    table.sort(readyTimes)
    return max(0, readyTimes[count] - s.now)
end

local function RuneGetter(parts)
    local runeType = parts[2]
    if not RUNE_TYPES[runeType or ""] then
        return nil, "unknown rune type '" .. tostring(runeType) .. "' (use blood, unholy, frost, death or total)"
    end
    if #parts == 2 then
        return function(s) return RunesReadyAt(s, runeType, s.now) end
    end
    local count = #parts == 3 and tonumber((parts[3] or ""):match("^time_to_(%d)$"))
    if not count or count < 1 or count > 6 then
        return nil, "unknown rune field '" .. tostring(parts[3]) .. "' (use time_to_1 .. time_to_6)"
    end
    return function(s) return TimeToRunes(s, runeType, count) end
end

---------------------------------------------------------------------------
-- Everything else
---------------------------------------------------------------------------
-- Names with no parameters, e.g. "gcd.remains".
local SIMPLE = {
    runic_power = function(s) return s.power end,
    ["runic_power.deficit"] = function(s) return s.powerMax - s.power end,
    ["runic_power.max"] = function(s) return s.powerMax end,
    ["runic_power.pct"] = function(s) return s.powerMax > 0 and s.power / s.powerMax * 100 or 0 end,
    gcd = function(s) return s.gcdDuration end,
    ["gcd.remains"] = function(s) return max(0, s.gcdEnd - s.now) end,
    time = function(s) return s.combatStart and max(0, s.now - s.combatStart) or 0 end,
    active_enemies = function(s) return s.activeEnemies end,
    moving = function(s) return B(s.moving) end,
    ["pet.alive"] = function(s) return B(s.petAlive) end,
    -- Pull timer (DBM/BigWigs or /rh pull): active while counting down.
    -- Times are absolute, so conditions checked at a future moment see the
    -- countdown as it will be then.
    ["pull.active"] = function(s) return B(s.pullAt ~= nil) end,
    ["pull.remains"] = function(s) return s.pullAt and max(0, s.pullAt - s.now) or 0 end,
    -- Burst window: a notable damage buff is up (Engine/Burst.lua).
    ["burst.active"] = function(s) return B((s.burstUntil or 0) > s.now) end,
    ["burst.remains"] = function(s) return max(0, (s.burstUntil or 0) - s.now) end,
    ["target.health.pct"] = function(s) return s.target.healthPct end,
    ["health.pct"] = function(s) return s.healthPct or 100 end, -- yours
    -- 3600 when unknown or the target isn't losing health.
    ["target.time_to_die"] = function(s) return s.target.timeToDie end,
    ["toggle.cooldowns"] = function(s) return B(s.cooldownsEnabled) end,
    -- The CD toggle alone (no boss check): for short cooldowns used on trash too.
    ["toggle.short_cooldowns"] = function(s) return B(s.shortCooldownsEnabled ~= false) end,
    -- Consumables allowed right now (the POT toggle; bosses only by default).
    ["toggle.consumables"] = function(s) return B(s.consumablesAllowed ~= false) end,
    -- Enemies with all of the class's spreadable dots (diseases), the
    -- target included (Engine/Dots.lua).
    diseased_enemies = function(s) return ns.Dots.Diseased(s) end,
}

-- active_dot.KEY: enemies with that dot, the target included.
local function ActiveDotGetter(parts, classData)
    local key = parts[2]
    local aura = key and classData.auras[key]
    if #parts ~= 2 or not (aura and aura.debuff) then
        return nil, "use active_dot.NAME with a dot, e.g. active_dot.frost_fever"
    end
    return function(s)
        local n = 0
        if s.otherDots and (s.otherDotsUntil[key] or 0) > s.now then n = s.otherDots[key] or 0 end
        local rec = s.debuffs[key]
        if rec and rec.expires > s.now then n = n + 1 end
        return n
    end
end

local function CooldownGetter(parts, classData)
    local key, field = parts[2], parts[3]
    if not (key and classData.abilities[key]) then
        return nil, "unknown ability '" .. tostring(key) .. "'"
    end
    if #parts ~= 3 then return nil, "use cooldown." .. key .. ".ready or .remains" end
    if field == "ready" or field == "up" then
        return function(s)
            local cd = s.cooldowns[key]
            return B(not cd or cd.readyAt <= s.now)
        end
    elseif field == "remains" then
        return function(s)
            local cd = s.cooldowns[key]
            return cd and max(0, cd.readyAt - s.now) or 0
        end
    elseif field == "ready_for" then
        -- Seconds it has been ready (0 while on cooldown).
        return function(s)
            local since = s.readySince and s.readySince[key]
            return since and max(0, s.now - since) or 0
        end
    elseif field == "duration" then
        local base = classData.abilities[key].cooldown or 0
        return function(s)
            local cd = s.cooldowns[key]
            return cd and cd.duration or base
        end
    end
    return nil, "unknown cooldown field '" .. tostring(field) .. "' (use ready, remains, ready_for or duration)"
end

-- Talents and glyphs come from the Spec module, not the state; they can't
-- change mid-evaluation. Names aren't validated, as the talent list is
-- only known once the talent API has loaded.
local function TalentGetter(parts)
    local key, field = parts[2], parts[3]
    if #parts ~= 3 or (field ~= "enabled" and field ~= "rank") then
        return nil, "use talent.NAME.enabled or talent.NAME.rank"
    end
    local Spec = ns.Spec
    if field == "rank" then return function() return Spec:TalentRank(key) end end
    return function() return B(Spec:TalentRank(key) > 0) end
end

local function GlyphGetter(parts)
    if #parts ~= 3 or parts[3] ~= "enabled" then return nil, "use glyph.NAME.enabled" end
    local key, Spec = parts[2], ns.Spec
    return function() return B(Spec:HasGlyph(key)) end
end

local PREFIXES = {
    buff = function(parts, classData) return AuraGetter(parts, classData, "buffs") end,
    debuff = function(parts, classData) return AuraGetter(parts, classData, "debuffs") end,
    dot = function(parts, classData) return AuraGetter(parts, classData, "debuffs") end,
    cooldown = CooldownGetter,
    runes = RuneGetter,
    rune = RuneGetter,
    talent = TalentGetter,
    glyph = GlyphGetter,
    active_dot = ActiveDotGetter,
}

-- Returns resolve(name) -> getter, or nil + message.
function Expressions.CreateResolver(classData)
    return function(name)
        if SIMPLE[name] then return SIMPLE[name] end
        local parts = {}
        for part in name:gmatch("[^%.]+") do parts[#parts + 1] = part end
        local prefix = PREFIXES[parts[1]]
        if prefix then return prefix(parts, classData) end
        return nil, "unknown name '" .. name .. "'"
    end
end
