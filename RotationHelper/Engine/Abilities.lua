local ADDON_NAME, ns = ...

-- Works out when an ability can next be used, given a state snapshot.
--
-- Abilities.ReadyAt(state, key) returns the absolute time the ability is
-- usable, or nil plus a reason if it can't be used at all with the current
-- resources. The time accounts for:
--   - the GCD (off-GCD abilities ignore it) and any cast in progress
--   - the ability's cooldown
--   - rune costs; death runes can pay for any rune type
--   - runic power (it doesn't regenerate, so too little means "never")
local Abilities = {}
ns.Abilities = Abilities

local RH = ns.RH
local Utils = ns.Utils
local ipairs, pairs, sort, min, max = ipairs, pairs, table.sort, math.min, math.max

local NUM_RUNES = 6

-- Scratch tables, reused to avoid garbage on every evaluation.
local readyCount = { blood = 0, unholy = 0, frost = 0, death = 0 }
local candidateTimes = {}

local function RunesSatisfied(state, cost, at)
    readyCount.blood, readyCount.unholy, readyCount.frost, readyCount.death = 0, 0, 0, 0
    for i = 1, NUM_RUNES do
        local rune = state.runes[i]
        if rune.readyAt <= at and readyCount[rune.type] then
            readyCount[rune.type] = readyCount[rune.type] + 1
        end
    end
    local missing = 0
    for runeType, needed in pairs(cost) do
        local have = readyCount[runeType]
        if have < needed then missing = missing + needed - have end
    end
    return missing <= readyCount.death
end

-- Earliest time >= `from` when the rune cost can be paid, or nil if the
-- runes that exist can never pay it.
function Abilities.RunesReadyAt(state, cost, from)
    local n = 1
    candidateTimes[1] = from
    for i = 1, NUM_RUNES do
        local readyAt = state.runes[i].readyAt
        if readyAt > from then
            n = n + 1
            candidateTimes[n] = readyAt
        end
    end
    for i = n + 1, #candidateTimes do candidateTimes[i] = nil end
    sort(candidateTimes)
    for i = 1, n do
        if RunesSatisfied(state, cost, candidateTimes[i]) then return candidateTimes[i] end
    end
    return nil
end

function Abilities.RunicPowerCost(ability)
    if ability.rpCost then return ability.rpCost(ns.Spec) end
    return ability.rp and ability.rp > 0 and ability.rp or 0
end

function Abilities.RunicPowerGain(ability)
    local gain = ability.rp and ability.rp < 0 and -ability.rp or 0
    if ability.rpGain then gain = gain + ability.rpGain(ns.Spec) end
    return gain
end

local function BuffUpAt(state, key, at)
    local rec = state.buffs[key]
    return rec ~= nil and rec.expires > at
end

-- Returns readyAt, limitedBy ("gcd", "cooldown", "runes"), or nil, reason.
function Abilities.ReadyAt(state, key)
    local ability = RH.classData.abilities[key]
    if not ability then return nil, "unknown ability" end
    if not ns.Spec.known[key] then return nil, "not in spellbook" end
    if ability.requiresPet and not state.petAlive then return nil, "no pet" end

    local t, limitedBy = state.now, nil
    local castEnd = state.now + (state.castRemains or 0)
    if castEnd > t then t, limitedBy = castEnd, "cast" end
    if not ability.offGcd and state.gcdEnd > t then t, limitedBy = state.gcdEnd, "gcd" end

    local cd = state.cooldowns[key]
    if cd and cd.readyAt > t then t, limitedBy = cd.readyAt, "cooldown" end

    local rpCost = Abilities.RunicPowerCost(ability)
    if rpCost > 0 and state.power < rpCost then
        return nil, "runic power"
    end

    if ability.runes and not (ability.freeWith and BuffUpAt(state, ability.freeWith, t)) then
        local runesAt = Abilities.RunesReadyAt(state, ability.runes, t)
        if not runesAt then return nil, "runes" end
        if runesAt > t then t, limitedBy = runesAt, "runes" end
    end
    return t, limitedBy
end

-- If using `key` at time `t` spends one of the class's notable procs
-- (classData.procs, e.g. Killing Machine), returns that aura key and when
-- it expires.
function Abilities.ProcUsed(state, key, t)
    local procs = RH.classData.procs
    if not procs then return nil end
    for _, proc in ipairs(procs) do
        local expires = Abilities.SpendsProc(state, key, proc, t)
        if expires then return proc, expires end
    end
    return nil
end

-- If using `key` at time `t` spends aura `proc` (it's up and the ability
-- consumes it or is free with it), returns when the proc expires.
-- An ability can spend several at once (Howling Blast: Rime and Killing Machine).
function Abilities.SpendsProc(state, key, proc, t)
    local rec = state.buffs[proc]
    if not (rec and rec.expires > t) then return nil end
    local ability = RH.classData.abilities[key]
    if ability.freeWith == proc then return rec.expires end
    if ability.consumes then
        for _, consumed in ipairs(ability.consumes) do
            if consumed == proc then return rec.expires end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Simulation: what using an ability does to a (virtual) state.
---------------------------------------------------------------------------
-- Helpers for class handlers: ability.apply(state, spec, Effects).
-- Durations count from state.now.
local Effects = {}
Abilities.Effects = Effects

local function SetAura(list, key, now, duration, stacks)
    local rec = list[key]
    if not rec then
        rec = Utils.Acquire()
        list[key] = rec
    end
    rec.duration = duration
    rec.stacks = stacks or 1
    rec.expires = duration and (now + duration) or math.huge
end

function Effects.ApplyBuff(s, key, duration, stacks)
    SetAura(s.buffs, key, s.now, duration, stacks)
end

function Effects.ApplyDebuff(s, key, duration, stacks)
    SetAura(s.debuffs, key, s.now, duration, stacks)
end

function Effects.RemoveBuff(s, key)
    local rec = s.buffs[key]
    if rec then
        Utils.Release(rec)
        s.buffs[key] = nil
    end
end

function Effects.SummonPet(s)
    s.petAlive = true
end

function Effects.DebuffUp(s, key)
    local rec = s.debuffs[key]
    return rec ~= nil and rec.expires > s.now
end

-- Empower Rune Weapon: every rune is ready immediately.
function Effects.ActivateAllRunes(s)
    for i = 1, NUM_RUNES do
        if s.runes[i].readyAt > s.now then s.runes[i].readyAt = s.now end
    end
end

-- Blood Tap: a blood rune becomes a ready death rune. Prefers one that's
-- recharging, so a ready blood rune isn't wasted.
function Effects.BloodTap(s)
    local pick
    for i = 1, NUM_RUNES do
        local rune = s.runes[i]
        if rune.base == "blood" and rune.type == "blood" then
            if not pick or rune.readyAt > s.runes[pick].readyAt then pick = i end
        end
    end
    if pick then
        s.runes[pick].type = "death"
        s.runes[pick].readyAt = min(s.runes[pick].readyAt, s.now)
    end
end

-- Whether spending a rune of base `base` turns it into a death rune, e.g.
-- Blood of the North for Blood Strike. ability.convert = { runes = { blood = true },
-- talents = { "blood_of_the_north" } }: any listed talent at rank 3.
local function Converts(ability, base)
    local convert = ability.convert
    if not (convert and convert.runes[base]) then return false end
    for _, talent in ipairs(convert.talents) do
        if ns.Spec:TalentRank(talent) >= 3 then return true end
    end
    return false
end

local function SpendRune(s, i, ability)
    local rune = s.runes[i]
    rune.readyAt = s.now + s.runeRegen
    -- A spent death rune goes back to its slot's type, unless converted again.
    rune.type = Converts(ability, rune.base) and "death" or rune.base
end

-- Deterministic order: every type takes its own runes before death runes.
local RUNE_ORDER = { "blood", "unholy", "frost" }

local function FindReadyRune(s, runeType)
    for i = 1, NUM_RUNES do
        local rune = s.runes[i]
        if rune.type == runeType and rune.readyAt <= s.now then return i end
    end
end

local function SpendRunes(s, ability)
    for _, runeType in ipairs(RUNE_ORDER) do
        for _ = 1, ability.runes[runeType] or 0 do
            local i = FindReadyRune(s, runeType) or FindReadyRune(s, "death")
            if i then SpendRune(s, i, ability) end
        end
    end
end

-- Moves `s` to time `t` and applies using ability `key` there: GCD,
-- cooldown, runes, runic power, consumed procs, and the ability's own
-- effects (ability.apply). Procs that might happen (Killing Machine,
-- Rime) are random and not predicted.
function Abilities.Apply(s, key, t)
    local ability = RH.classData.abilities[key]
    s.now = t
    s.castRemains = 0
    if not ability.offGcd then s.gcdEnd = t + s.gcdDuration end

    local cd = s.cooldowns[key]
    if cd then
        -- A potion can't be used again in the same combat.
        cd.readyAt = ability.oncePerCombat and math.huge or t + (cd.duration or ability.cooldown)
        if s.readySince then s.readySince[key] = nil end
    end

    local free = ability.freeWith and BuffUpAt(s, ability.freeWith, t)
    if ability.runes and not free then SpendRunes(s, ability) end
    if free then Effects.RemoveBuff(s, ability.freeWith) end

    s.power = max(0, min(s.powerMax, s.power - Abilities.RunicPowerCost(ability) + Abilities.RunicPowerGain(ability)))

    if ability.consumes then
        for _, aura in ipairs(ability.consumes) do Effects.RemoveBuff(s, aura) end
    end
    if ability.apply then ability.apply(s, ns.Spec, Effects) end
    s.lastCast[key] = t
end
