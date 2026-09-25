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
local ipairs, pairs, sort = ipairs, pairs, table.sort

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

local function BuffUpAt(state, key, at)
    local rec = state.buffs[key]
    return rec ~= nil and rec.expires > at
end

-- Returns readyAt, limitedBy ("gcd", "cooldown", "runes"), or nil, reason.
function Abilities.ReadyAt(state, key)
    local ability = RH.classData.abilities[key]
    if not ability then return nil, "unknown ability" end
    if not ns.Spec.known[key] then return nil, "not in spellbook" end

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
