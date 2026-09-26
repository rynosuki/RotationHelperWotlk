local ADDON_NAME, ns = ...
local RH = ns.RH

-- Fight review: measures each fight while it happens and keeps a summary.
--
-- A fight is one stretch in combat. Every update adds its duration to:
--   idle        the GCD was free, you weren't casting, and the main icon was
--               ready (real GCD end, not the latency-shifted one)
--   runes       rune pairs sitting full (summed over the pairs)
--   runicPower  runic power at the cap
--   debuffs     each review debuff up on the hostile target
--   cooldowns   each known major cooldown ready but unused
-- and each GCD ability you cast is compared with the first two icons shown
-- at that moment (off-GCD casts only count when they match).
--
-- Fights shorter than the minimum aren't kept; the last MAX_REVIEWS
-- summaries are saved per character (db.char.reviews, newest last).
local Review = RH:NewModule("Review", "AceEvent-3.0")
ns.Review = Review

local GetTime, UnitName = GetTime, UnitName
local min, max, floor = math.min, math.max, math.floor
local tinsert, tremove, sort, wipe = table.insert, table.remove, table.sort, wipe

local MAX_REVIEWS = 10
local EMPTY = {}
local MAX_SAMPLE_GAP = 0.5 -- longer gaps between updates aren't counted
local MAX_MISTAKES_KEPT = 50
local PAIRS = { { 1, 2 }, { 3, 4 }, { 5, 6 } }

local fight -- the fight being recorded, or nil

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
function Review:Start(now)
    fight = {
        start = now, lastSample = nil, targetTime = 0, idle = 0, runes = 0, runicPower = 0,
        debuffs = {}, cooldowns = {}, casts = 0, matches = 0, mistakes = {}, target = nil,
    }
end

local function TargetIsHostile(t)
    return t.exists and t.canAttack and not t.dead
end

-- One update's worth of measuring, from the real state.
function Review:Sample(s, recs)
    if not fight then return end
    local now = s.now
    local dt = fight.lastSample and (now - fight.lastSample) or 0
    fight.lastSample = now
    if dt <= 0 then return end
    dt = min(dt, MAX_SAMPLE_GAP)

    local classData = RH.classData
    if classData.usesRunes then
        for _, pair in ipairs(PAIRS) do
            local a, b = s.runes[pair[1]], s.runes[pair[2]]
            if a and b and a.readyAt <= now and b.readyAt <= now then fight.runes = fight.runes + dt end
        end
    end
    if s.powerType == "runic_power" and s.powerMax > 0 and s.power >= s.powerMax then
        fight.runicPower = fight.runicPower + dt
    end

    local t = s.target
    if not TargetIsHostile(t) then return end
    fight.targetTime = fight.targetTime + dt
    fight.target = fight.target or t.name

    local main = recs and recs[1]
    local gcdFree = now >= (s.realGcdEnd or s.gcdEnd) and (s.realCastRemains or s.castRemains) <= 0
    if main and gcdFree and main.wait <= 0.05 then fight.idle = fight.idle + dt end

    for _, key in ipairs(classData.reviewDebuffs or {}) do
        local rec = s.debuffs[key]
        if rec and rec.expires > now then fight.debuffs[key] = (fight.debuffs[key] or 0) + dt end
    end
    -- Unused cooldowns aren't counted on trash when cooldowns are for bosses only.
    local trashFight = RH.db.profile.toggles.cooldownsBossOnly and not s.bossFight
    for _, key in ipairs(trashFight and EMPTY or classData.majorCooldowns or EMPTY) do
        local cd = s.cooldowns[key]
        if ns.Spec.known[key] and (not cd or cd.readyAt <= now) then
            fight.cooldowns[key] = (fight.cooldowns[key] or 0) + dt
        end
    end
end

-- A spell we cast, compared with what the icons showed right then.
function Review:OnCast(key, now)
    local recs = RH.recommendations
    if not (fight and recs and recs[1]) then return end
    local ability = RH.classData.abilities[key]
    local matched = recs[1].name == key or (recs[2] and recs[2].name == key)
    if ability.offGcd and not matched then return end -- weaving an off-GCD ability isn't a mistake
    fight.casts = fight.casts + 1
    if matched then
        fight.matches = fight.matches + 1
    elseif #fight.mistakes < MAX_MISTAKES_KEPT then
        tinsert(fight.mistakes, { time = now - fight.start, cast = key, expected = recs[1].name,
            expectedReady = recs[1].wait <= 0.05 })
    end
end

---------------------------------------------------------------------------
-- Summaries
---------------------------------------------------------------------------
local function Percent(part, whole)
    if whole <= 0 then return nil end
    return floor(part / whole * 1000 + 0.5) / 10
end

local function PerMinute(seconds, duration)
    return floor(seconds / duration * 60 * 10 + 0.5) / 10
end

-- The three most telling mistakes: ones where the recommended ability was
-- ready right then come first, then earliest first.
local function TopMistakes(mistakes)
    sort(mistakes, function(a, b)
        if a.expectedReady ~= b.expectedReady then return a.expectedReady end
        return a.time < b.time
    end)
    local top = {}
    for i = 1, min(3, #mistakes) do top[i] = mistakes[i] end
    return top
end

function Review:Summarize(f, now)
    local duration = now - f.start
    local summary = {
        when = date and date("%H:%M") or "",
        target = f.target or "?",
        duration = floor(duration + 0.5),
        gcdUsage = Percent(f.targetTime - f.idle, f.targetTime),
        runeWaste = PerMinute(f.runes, duration),
        runicPowerCapped = PerMinute(f.runicPower, duration),
        debuffs = {},
        cooldowns = {},
        casts = f.casts,
        adherence = Percent(f.matches, f.casts),
        mistakes = TopMistakes(f.mistakes),
        mistakeCount = #f.mistakes,
    }
    for _, key in ipairs(RH.classData.reviewDebuffs or {}) do
        summary.debuffs[#summary.debuffs + 1] = { key = key, uptime = Percent(f.debuffs[key] or 0, f.targetTime) }
    end
    for _, key in ipairs(RH.classData.majorCooldowns or {}) do
        local unused = f.cooldowns[key]
        if unused and unused >= 1 then
            summary.cooldowns[#summary.cooldowns + 1] = { key = key, unused = floor(unused + 0.5) }
        end
    end
    return summary
end

function Review:Finish(now)
    local f = fight
    fight = nil
    local settings = RH.db.profile.review
    if not f or not settings.enabled or now - f.start < settings.minDuration then return nil end
    local summary = self:Summarize(f, now)
    local reviews = RH.db.char.reviews
    tinsert(reviews, summary)
    while #reviews > MAX_REVIEWS do tremove(reviews, 1) end
    if settings.autoShow and ns.ReviewWindow then ns.ReviewWindow:Show(#reviews) end
    return summary
end

function Review:IsRecording()
    return fight ~= nil
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Review:OnEnable()
    if not RH.classSupported then return end
    self:RegisterMessage("ROTATIONHELPER_COMBAT_CHANGED", function(_, inCombat)
        if inCombat then Review:Start(GetTime()) else Review:Finish(GetTime()) end
    end)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, spellName)
        if unit ~= "player" then return end
        local key = RH.classData.abilityByName[spellName]
        if key then Review:OnCast(key, GetTime()) end
    end)
    RH:RegisterUpdater(function() Review:Sample(ns.State.real, RH.recommendations) end,
        RH.UPDATE_ORDER.REVIEW, "fight review")
end
