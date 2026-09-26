local ADDON_NAME, ns = ...
local RH = ns.RH

-- Enemy counting and target time-to-die.
--
-- 3.3.5 nameplates have no unit tokens, so enemies are counted from the
-- combat log: a unit counts while we (or our pets) have hit it, it has
-- hit us, or we've put a debuff on it, within the last ENEMY_TIMEOUT
-- seconds. Disease ticks keep diseased enemies counted.
--
-- Time-to-die fits a line through the target's health over the last
-- TTD_WINDOW seconds and extrapolates it to zero.
local Targets = RH:NewModule("Targets", "AceEvent-3.0")
ns.Targets = Targets

local GetTime, UnitGUID, UnitHealth, UnitIsDead = GetTime, UnitGUID, UnitHealth, UnitIsDead
local band = bit.band
local pairs, wipe, max, min = pairs, wipe, math.max, math.min

local ENEMY_TIMEOUT = 6
local TTD_WINDOW = 15
local TTD_SAMPLE_INTERVAL = 0.25
local TTD_MIN_SAMPLES = 3
local TTD_MIN_SPAN = 2
Targets.TTD_UNKNOWN = 3600 -- also the cap: "a long time"

-- Combat log unit flags (not all are defined as globals in 3.3.5).
local AFFILIATION_MINE = 0x00000001
local REACTION_FRIENDLY = 0x00000010

-- Subevents that mean two units are fighting each other.
local HOSTILE_EVENTS = {
    SWING_DAMAGE = true, SWING_MISSED = true,
    RANGE_DAMAGE = true, RANGE_MISSED = true,
    SPELL_DAMAGE = true, SPELL_MISSED = true,
    SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_MISSED = true,
    SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_APPLIED_DOSE = true,
}
local DEATH_EVENTS = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

local lastSeen = {} -- enemy GUID -> GetTime() of last activity

---------------------------------------------------------------------------
-- Enemy counting
---------------------------------------------------------------------------
-- 3.3.5 args: timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...
function Targets:OnCombatLog(_, _, subevent, srcGUID, _, srcFlags, dstGUID, _, dstFlags)
    if HOSTILE_EVENTS[subevent] then
        if srcFlags and band(srcFlags, AFFILIATION_MINE) > 0 then
            -- We hit something that isn't friendly.
            if dstFlags and band(dstFlags, REACTION_FRIENDLY) == 0 and dstGUID ~= self.playerGUID then
                lastSeen[dstGUID] = GetTime()
            end
        elseif dstGUID == self.playerGUID and srcFlags and band(srcFlags, REACTION_FRIENDLY) == 0 then
            -- Something hostile hit us.
            if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH"
                and subevent ~= "SPELL_AURA_APPLIED_DOSE" then
                lastSeen[srcGUID] = GetTime()
            end
        end
    elseif DEATH_EVENTS[subevent] and dstGUID then
        lastSeen[dstGUID] = nil
    end
end

-- Number of enemies seen recently, dropping ones that timed out.
function Targets:CountEnemies(now)
    local n = 0
    for guid, seen in pairs(lastSeen) do
        if now - seen > ENEMY_TIMEOUT then
            lastSeen[guid] = nil
        else
            n = n + 1
        end
    end
    return n
end

-- Whether `guid` is still counted as an enemy.
function Targets:IsActive(guid, now)
    local seen = lastSeen[guid]
    return seen ~= nil and now - seen <= ENEMY_TIMEOUT
end

-- The count the APL sees as active_enemies. `targetHostile` makes it at
-- least 1, since our target is an enemy even before anyone hits it.
function Targets:ActiveEnemies(now, aoeMode, targetHostile)
    if aoeMode == "single" then return 1 end
    local n = self:CountEnemies(now)
    if targetHostile and not lastSeen[UnitGUID("target") or ""] then n = n + 1 end
    n = max(n, 1)
    if aoeMode == "aoe" then return max(n, 3) end
    return n
end

---------------------------------------------------------------------------
-- Time to die
---------------------------------------------------------------------------
-- Samples are kept in parallel arrays, oldest first.
local sampleTime, sampleHealth = {}, {}
local sampleCount = 0
local ttdGUID

local function ResetSamples(guid)
    sampleCount = 0
    ttdGUID = guid
end

local function DropOldSamples(now)
    local drop = 0
    while drop < sampleCount and now - sampleTime[drop + 1] > TTD_WINDOW do drop = drop + 1 end
    if drop > 0 then
        for i = 1, sampleCount - drop do
            sampleTime[i], sampleHealth[i] = sampleTime[i + drop], sampleHealth[i + drop]
        end
        sampleCount = sampleCount - drop
    end
end

function Targets:SampleTarget(now)
    local guid = UnitGUID("target")
    if not guid or UnitIsDead("target") then
        ResetSamples(nil)
        return
    end
    if guid ~= ttdGUID then ResetSamples(guid) end
    if sampleCount > 0 and now - sampleTime[sampleCount] < TTD_SAMPLE_INTERVAL then return end
    DropOldSamples(now)
    sampleCount = sampleCount + 1
    sampleTime[sampleCount] = now
    sampleHealth[sampleCount] = UnitHealth("target")
end

-- Seconds until the target dies, or TTD_UNKNOWN when there's too little
-- data or its health isn't going down.
function Targets:TimeToDie(now)
    if sampleCount < TTD_MIN_SAMPLES or sampleTime[sampleCount] - sampleTime[1] < TTD_MIN_SPAN then
        return self.TTD_UNKNOWN
    end
    -- Least-squares slope of health over time (times relative to the first
    -- sample, for precision).
    local t0 = sampleTime[1]
    local sumT, sumH, sumTT, sumTH = 0, 0, 0, 0
    for i = 1, sampleCount do
        local t, h = sampleTime[i] - t0, sampleHealth[i]
        sumT, sumH = sumT + t, sumH + h
        sumTT, sumTH = sumTT + t * t, sumTH + t * h
    end
    local n = sampleCount
    local denominator = n * sumTT - sumT * sumT
    if denominator <= 0 then return self.TTD_UNKNOWN end
    local slope = (n * sumTH - sumT * sumH) / denominator
    if slope >= 0 then return self.TTD_UNKNOWN end
    local health = sampleHealth[sampleCount] + slope * (now - sampleTime[sampleCount])
    return min(self.TTD_UNKNOWN, max(0, health / -slope))
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Targets:OnCombatEnded()
    wipe(lastSeen)
end

function Targets:OnEnable()
    if not RH.classSupported then return end
    self.playerGUID = UnitGUID("player")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", function(_, inCombat)
        if not inCombat then Targets:OnCombatEnded() end
    end)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function() Targets:SampleTarget(GetTime()) end)
    RH:RegisterUpdater(function(_, now) Targets:SampleTarget(now) end, RH.UPDATE_ORDER.TARGETS, "target tracking")
end
