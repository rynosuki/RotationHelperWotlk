local ADDON_NAME, ns = ...
local RH = ns.RH

-- A snapshot of the real game state. The recommendation engine reads from
-- here; milestone 6 adds a virtual copy that can be moved forward in time.
local State = RH:NewModule("State", "AceEvent-3.0")
ns.State = State

local GetTime, UnitExists, UnitGUID, UnitName, UnitCanAttack, UnitIsDead =
    GetTime, UnitExists, UnitGUID, UnitName, UnitCanAttack, UnitIsDead
local UnitHealth, UnitHealthMax, UnitLevel, UnitClassification =
    UnitHealth, UnitHealthMax, UnitLevel, UnitClassification
local UnitCastingInfo, UnitChannelInfo, GetUnitSpeed = UnitCastingInfo, UnitChannelInfo, GetUnitSpeed

State.real = {
    now = 0,
    runes = {},
    buffs = {},
    debuffs = {},
    cooldowns = {},
    target = {},
    variables = {}, -- APL variables, reset for every evaluation
    lastCast = {},  -- ability key -> GetTime() of our last successful cast
}

-- Until enemy counting exists (milestone 7), the AoE toggle decides.
local ENEMIES_BY_AOE_MODE = { auto = 1, single = 1, aoe = 3 }

local function ReadTarget(t)
    t.exists = UnitExists("target") and true or false
    if not t.exists then
        t.guid, t.name, t.canAttack, t.dead = nil, nil, false, false
        t.health, t.healthMax, t.healthPct, t.level, t.classification = 0, 0, 0, 0, nil
        return
    end
    t.guid = UnitGUID("target")
    t.name = UnitName("target")
    t.canAttack = UnitCanAttack("player", "target") and true or false
    t.dead = UnitIsDead("target") and true or false
    t.health = UnitHealth("target")
    t.healthMax = UnitHealthMax("target")
    t.healthPct = t.healthMax > 0 and (t.health / t.healthMax * 100) or 0
    t.level = UnitLevel("target") -- -1 for bosses ("??")
    t.classification = UnitClassification("target")
end

local function ReadCast(s, now)
    local name, _, _, _, _, endTime = UnitCastingInfo("player")
    if not name then
        name, _, _, _, _, endTime = UnitChannelInfo("player")
    end
    s.castName = name
    s.castRemains = name and endTime and (endTime / 1000 - now) or 0
    if s.castRemains < 0 then s.castRemains = 0 end
end

-- Reads everything from the game. Order matters: cooldowns use the rune
-- regen time and presence buffs read before them.
function State:Reset(now)
    local s = self.real
    local classData = RH.classData
    now = now or GetTime()
    s.now = now
    s.inCombat = RH.inCombat or false
    s.combatStart = RH.combatStart
    s.moving = GetUnitSpeed and GetUnitSpeed("player") > 0 or false
    local toggles = RH.db.profile.toggles
    s.cooldownsEnabled = toggles.cooldowns
    s.activeEnemies = ENEMIES_BY_AOE_MODE[toggles.aoeMode] or 1

    ns.Resources.Read(s, classData, now)
    ns.Auras.Read(s, classData)
    ns.Cooldowns.Read(s, classData, now)
    ReadTarget(s.target)
    ReadCast(s, now)
    return s
end

---------------------------------------------------------------------------
-- Events that change the state trigger a prompt refresh.
---------------------------------------------------------------------------
function State:OnUnitEvent(_, unit)
    if unit == "player" or unit == "target" then
        RH:Invalidate()
    end
end

-- 3.3.5 passes (unit, spellName, spellRank, ...) with no spell ID.
function State:OnSpellcastSucceeded(_, unit, spellName)
    if unit ~= "player" then return end
    local key = RH.classData.abilityByName[spellName]
    if key then self.real.lastCast[key] = GetTime() end
    RH:Invalidate()
end

function State:OnEnable()
    if not RH.classSupported then return end
    local invalidate = function() RH:Invalidate() end
    self:RegisterEvent("UNIT_AURA", "OnUnitEvent")
    self:RegisterEvent("UNIT_RUNIC_POWER", "OnUnitEvent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("RUNE_POWER_UPDATE", invalidate)
    self:RegisterEvent("RUNE_TYPE_UPDATE", invalidate)
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", invalidate)
end
