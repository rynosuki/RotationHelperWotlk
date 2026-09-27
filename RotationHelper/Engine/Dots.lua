local ADDON_NAME, ns = ...
local RH = ns.RH

-- Our dots on enemies other than the target, from the combat log: which
-- enemies carry which of the class's `spreadDots` (diseases, which
-- Pestilence spreads) and the spec's `trackDots` (Affliction: Corruption,
-- Unstable Affliction, Curse of Agony). The target itself is read exactly
-- from its auras.
--
-- trackDots = { SPEC = { "key", ..., hint = "LABEL" } }: with several
-- enemies, the status line shows "2/4 LABEL" for the first key (Death
-- Knights: "2/4 DIS", enemies with all diseases).
--
-- A dot counts from our SPELL_AURA_APPLIED / REFRESH (or any tick) until
-- SPELL_AURA_REMOVED, the enemy dying, or no tick for STALE seconds (when
-- the removal happened out of combat log range). Only enemies that
-- Engine/Targets.lua still counts are included.
--
-- The state gets, per dot key, the number of other enemies with it
-- (s.otherDots[key], valid until s.otherDotsUntil[key]) and the number
-- with all of them (s.otherDiseased until s.otherDiseasedUntil). Pestilence
-- in the prediction spreads them (Abilities.Effects.SpreadDots).
local Dots = RH:NewModule("Dots", "AceEvent-3.0")
ns.Dots = Dots

local GetTime, UnitGUID = GetTime, UnitGUID
local pairs, ipairs, wipe, huge = pairs, ipairs, wipe, math.huge

local STALE = 6 -- diseases tick every 3 seconds

local tracked = {}  -- enemy GUID -> { [dot key] = time last seen }
local keyById = {}  -- spell ID -> dot key
local keys = {}     -- the dot keys tracked for the current spec
local DISEASE_HINT = { label = "DIS" }
local builtFor = false -- the spec key the lists were built for

local APPLY_EVENTS = {
    SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true,
    SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_MISSED = true,
}
local DEATH_EVENTS = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

-- The spec's tracked dots, or nil.
local function SpecDots()
    local track = RH.classData.trackDots
    return track and ns.Spec.key and track[ns.Spec.key]
end

function Dots:BuildIds()
    builtFor = ns.Spec.key
    wipe(keyById)
    wipe(keys)
    local classData = RH.classData
    local added = {}
    local function Add(key)
        if added[key] then return end
        added[key] = true
        keys[#keys + 1] = key
        local aura = classData.auras[key]
        for _, id in ipairs(aura.ids or { aura.id }) do keyById[id] = key end
    end
    for _, key in ipairs(classData.spreadDots or {}) do Add(key) end
    local specDots = SpecDots()
    for _, key in ipairs(specDots or {}) do Add(key) end
    -- The status hint: all diseases, or the spec's first tracked dot.
    Dots.hint = nil
    if classData.spreadDots then
        Dots.hint = DISEASE_HINT
    elseif specDots and specDots.hint then
        Dots.hint = { label = specDots.hint, key = specDots[1] }
    end
end

-- 3.3.5 args: timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, ...
function Dots:OnCombatLog(_, _, subevent, srcGUID, _, _, dstGUID, _, _, spellId)
    if DEATH_EVENTS[subevent] then
        if dstGUID then tracked[dstGUID] = nil end
        return
    end
    if srcGUID ~= self.playerGUID or not dstGUID then return end
    if ns.Spec.key ~= builtFor then self:BuildIds() end
    local key = keyById[spellId or 0]
    if not key then return end
    if APPLY_EVENTS[subevent] then
        local rec = tracked[dstGUID]
        if not rec then
            rec = {}
            tracked[dstGUID] = rec
        end
        rec[key] = GetTime()
    elseif subevent == "SPELL_AURA_REMOVED" then
        local rec = tracked[dstGUID]
        if rec then rec[key] = nil end
    end
end

-- Fills the dot counts of state `s` (after the enemy count is known).
function Dots:Read(s, now)
    if ns.Spec.key ~= builtFor then self:BuildIds() end -- the spec is known (or changed)
    local spread = RH.classData.spreadDots
    local counts, untils = s.otherDots, s.otherDotsUntil
    s.otherDiseased, s.otherDiseasedUntil = 0, huge
    if #keys == 0 then return end
    for _, key in ipairs(keys) do
        counts[key], untils[key] = 0, huge
    end
    local targetGUID = UnitGUID("target")
    local Targets = ns.Targets
    for guid, rec in pairs(tracked) do
        if guid ~= targetGUID and Targets:IsActive(guid, now) then
            for _, key in ipairs(keys) do
                local seen = rec[key]
                if seen and now - seen <= STALE then counts[key] = counts[key] + 1 end
            end
            if spread then
                local all = true
                for _, key in ipairs(spread) do
                    local seen = rec[key]
                    if not (seen and now - seen <= STALE) then all = false end
                end
                if all then s.otherDiseased = s.otherDiseased + 1 end
            end
        end
    end
end

-- Enemies (the target included) with dot `key`, as the rotation sees it
-- at s.now (active_dot.KEY).
function Dots.Count(s, key)
    local n = 0
    if s.otherDots and (s.otherDotsUntil[key] or 0) > s.now then n = s.otherDots[key] or 0 end
    local rec = s.debuffs[key]
    if rec and rec.expires > s.now then n = n + 1 end
    return n
end

-- The number for the status hint ("2/4 DIS"), or nil without one.
function Dots.HintCount(s)
    local hint = Dots.hint
    if not hint then return nil end
    if hint.key then return Dots.Count(s, hint.key) end
    return Dots.Diseased(s)
end

-- Enemies (the target included) with every spreadable dot, as the
-- rotation sees it at s.now; and the enemy count, for the status hint.
function Dots.Diseased(s)
    local keys = RH.classData.spreadDots
    if not keys then return 0 end
    local n = (s.otherDiseasedUntil or 0) > s.now and s.otherDiseased or 0
    local target = s.target
    if target and target.exists and target.canAttack and not target.dead then
        local all = true
        for _, key in ipairs(keys) do
            local rec = s.debuffs[key]
            if not (rec and rec.expires > s.now) then all = false end
        end
        if all then n = n + 1 end
    end
    return n
end

function Dots:OnEnable()
    if not RH.classSupported then return end
    self.playerGUID = UnitGUID("player")
    self:BuildIds()
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", function(_, inCombat)
        if not inCombat then wipe(tracked) end
    end)
end
