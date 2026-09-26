local ADDON_NAME, ns = ...
local RH = ns.RH

-- Pre-pull checklist: out of combat with a boss or elite targeted, lists
-- what's missing (flask, food, Horn of Winter, the right presence, a
-- ghoul for Unholy). Sets RH.checklist to a list of labels, or nil.
local PrePull = RH:NewModule("PrePull")
ns.PrePull = PrePull

local UnitAura = UnitAura

local missing = {} -- reused result list

-- Buff names (enUS; Whitemane is English) that satisfy a check.
local function HasBuffNamed(prefix)
    for i = 1, 40 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then return false end
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local BOSS_CLASSIFICATIONS = { worldboss = true, elite = true, rareelite = true }

PrePull.PRESENCES = {
    blood = { aura = "blood_presence", label = "Blood Presence" },
    frost = { aura = "frost_presence", label = "Frost Presence" },
    unholy = { aura = "unholy_presence", label = "Unholy Presence" },
}
local PRESENCES = PrePull.PRESENCES

local function Up(s, key)
    local rec = s.buffs[key]
    return rec ~= nil and rec.expires > s.now
end

function PrePull:Check(s, settings)
    for i = #missing, 1, -1 do missing[i] = nil end
    if not settings.enabled or s.inCombat then return nil end
    local t = s.target
    if not (t.exists and t.canAttack and not t.dead) then return nil end
    if not (t.level == -1 or BOSS_CLASSIFICATIONS[t.classification or ""]) then return nil end

    if not (HasBuffNamed("Flask of") or HasBuffNamed("Elixir of")) then missing[#missing + 1] = "Flask" end
    if not HasBuffNamed("Well Fed") then missing[#missing + 1] = "Food" end

    if RH.classData.auras.horn_of_winter and not Up(s, "horn_of_winter") and not HasBuffNamed("Strength of Earth") then
        missing[#missing + 1] = "Horn of Winter"
    end
    local wanted = PRESENCES[settings.presence[ns.Spec.key or ""] or "any"]
    if wanted and not Up(s, wanted.aura) then missing[#missing + 1] = wanted.label end
    if ns.Spec.key == "unholy" and not s.petAlive then missing[#missing + 1] = "Ghoul" end
    -- Stance or form the spec wants (Fury: Berserker Stance).
    local form = RH.classData.prepullForm and RH.classData.prepullForm[ns.Spec.key or ""]
    if form and s.form ~= form.form then missing[#missing + 1] = form.label end

    return #missing > 0 and missing or nil
end

function PrePull:OnEnable()
    if not RH.classSupported then return end
    RH:RegisterUpdater(function()
        RH.checklist = PrePull:Check(ns.State.real, RH.db.profile.prepull)
    end, RH.UPDATE_ORDER.PREPULL, "pre-pull checklist", function() RH.checklist = nil end)
end
