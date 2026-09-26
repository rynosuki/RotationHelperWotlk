local ADDON_NAME, ns = ...
local RH = ns.RH

-- Learns what each ability hits for with the player's own gear, from the
-- combat log: damage per cast, per rune and per runic power, crit rate,
-- and damage per tick for the diseases. Kept per character
-- (db.char.damage) until reset. `/rh damage` prints it, and the simulator
-- uses it to estimate the damage of a rotation (Engine/Sim.lua).
--
-- Casts come from UNIT_SPELLCAST_SUCCEEDED; damage from our SPELL_DAMAGE,
-- SPELL_PERIODIC_DAMAGE, RANGE_DAMAGE and SWING_DAMAGE events, matched to
-- abilities by name (so both hands of Obliterate and Frost Strike, and
-- every enemy Howling Blast hits, count towards one cast) and to dots by
-- spell ID.
local DamageLog = RH:NewModule("DamageLog", "AceEvent-3.0")
ns.DamageLog = DamageLog

local UnitGUID = UnitGUID
local pairs, ipairs, floor, max, sort, wipe = pairs, ipairs, math.floor, math.max, table.sort, wipe
local date, time = date, time

DamageLog.MIN_CASTS = 5 -- fewer casts than this aren't used for estimates
DamageLog.MELEE = "melee"

local DAMAGE_EVENTS = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true }
local dotById = {} -- spell ID -> dot aura key

local function Record(key)
    local data = RH.db.char.damage
    local rec = data.abilities[key]
    if not rec then
        rec = { casts = 0, damage = 0, hits = 0, crits = 0 }
        data.abilities[key] = rec
    end
    return rec
end

local function AddHit(key, amount, critical)
    local rec = Record(key)
    rec.damage = rec.damage + amount
    rec.hits = rec.hits + 1
    if critical then rec.crits = rec.crits + 1 end
    local data = RH.db.char.damage
    data.total = data.total + amount
    data.since = data.since or (time and time())
end

-- 3.3.5 args: timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...
-- then for spell events: spellId, spellName, school, amount, overkill, school, resisted,
-- blocked, absorbed, critical; for swings: amount, overkill, school, resisted, blocked,
-- absorbed, critical.
function DamageLog:OnCombatLog(_, _, subevent, srcGUID, _, _, _, _, _, a1, a2, a3, a4, _, _, a7, _, _, a10)
    if srcGUID ~= self.playerGUID then return end
    if DAMAGE_EVENTS[subevent] then
        local key = dotById[a1] or RH.classData.abilityByName[a2 or ""]
        if key and a4 then AddHit(key, a4, a10 and true or false) end
    elseif subevent == "SWING_DAMAGE" and a1 then
        AddHit(DamageLog.MELEE, a1, a7 and true or false) -- a7: critical
    end
end

function DamageLog:OnSpellcastSucceeded(_, unit, spellName)
    if unit ~= "player" then return end
    local key = RH.classData.abilityByName[spellName or ""]
    if key then
        local rec = Record(key)
        rec.casts = rec.casts + 1
    end
end

function DamageLog:Reset()
    local data = RH.db.char.damage
    data.abilities = {}
    data.total = 0
    data.since = nil
end

---------------------------------------------------------------------------
-- Reading it back
---------------------------------------------------------------------------
local function RuneCount(ability)
    local n = 0
    for _, count in pairs(ability.runes or {}) do n = n + count end
    return n
end

-- Average damage per cast of an ability, or nil without enough data.
function DamageLog:PerCast(key)
    local rec = RH.db.char.damage.abilities[key]
    if not rec or rec.casts < self.MIN_CASTS then return nil end
    return rec.damage / rec.casts
end

-- Average damage per tick of a dot, or nil without enough data.
function DamageLog:PerTick(key)
    local rec = RH.db.char.damage.abilities[key]
    if not rec or rec.hits < self.MIN_CASTS then return nil end
    return rec.damage / rec.hits
end

-- 12345 -> "12,345"
local function Thousands(n)
    local s = tostring(floor(n + 0.5))
    local formatted
    repeat
        s, formatted = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until formatted == 0
    return s
end
DamageLog.Thousands = Thousands

local function DisplayName(key)
    local classData = RH.classData
    if key == DamageLog.MELEE then return "Melee" end
    local ability = classData.abilities[key]
    if ability and ability.name then return ability.name end
    local aura = classData.auras[key]
    local id = aura and (aura.id or (aura.ids and aura.ids[1]))
    return (id and GetSpellInfo(id)) or key
end

-- The report as text lines, most damage first.
function DamageLog:Report()
    local data = RH.db.char.damage
    local lines = {}
    if data.total <= 0 then
        lines[1] = "No damage recorded yet. Fight something (a training dummy works) and try again."
        return lines
    end
    local since = data.since and date and date("%Y-%m-%d", data.since)
    lines[1] = ("Your damage%s, %s in total:"):format(since and (" since " .. since) or "", Thousands(data.total))
    local keys = {}
    for key, rec in pairs(data.abilities) do
        if rec.damage > 0 then keys[#keys + 1] = key end
    end
    sort(keys, function(a, b) return data.abilities[a].damage > data.abilities[b].damage end)
    local classData = RH.classData
    for _, key in ipairs(keys) do
        local rec = data.abilities[key]
        local share = rec.damage / data.total * 100
        local crit = rec.hits > 0 and rec.crits / rec.hits * 100 or 0
        local ability = classData.abilities[key]
        local detail
        if classData.auras[key] and not ability then
            detail = ("%s per tick"):format(Thousands(rec.damage / max(1, rec.hits)))
        elseif key == DamageLog.MELEE then
            detail = ("%s per swing"):format(Thousands(rec.damage / max(1, rec.hits)))
        elseif rec.casts > 0 then
            local perCast = rec.damage / rec.casts
            detail = ("%d casts, %s per cast"):format(rec.casts, Thousands(perCast))
            local runes = ability and RuneCount(ability) or 0
            if runes > 0 then detail = detail .. (", %s per rune"):format(Thousands(perCast / runes)) end
            local rp = ability and ability.rp or 0
            if rp > 0 then detail = detail .. (", %s per runic power"):format(Thousands(perCast / rp)) end
        else
            detail = ("%d hits"):format(rec.hits)
        end
        lines[#lines + 1] = ("  %s: %s, %d%% crit, %.1f%% of your damage"):format(DisplayName(key), detail, crit, share)
    end
    return lines
end

function DamageLog:OnEnable()
    if not RH.classSupported then return end
    local data = RH.db.char.damage
    data.abilities = data.abilities or {}
    data.total = data.total or 0
    self.playerGUID = UnitGUID("player")
    wipe(dotById)
    for key, aura in pairs(RH.classData.auras) do
        if aura.debuff then
            for _, id in ipairs(aura.ids or { aura.id }) do dotById[id] = key end
        end
    end
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
end

-- /rh damage [reset]
function RH:PrintDamage(arg)
    if not self.classSupported then return end
    if arg == "reset" then
        DamageLog:Reset()
        self:Print("Damage log cleared.")
        return
    end
    for i, line in ipairs(DamageLog:Report()) do
        if i == 1 then self:Print(line) else print(line) end
    end
end
