local ADDON_NAME, ns = ...

-- Reads power and (for Death Knights) runes.
--
-- state.runes[1..6] = { type = "blood"|"unholy"|"frost"|"death", base = slot type, readyAt = time }
-- state.runeRegen   = seconds for one rune to regenerate (10 base)
-- state.power, state.powerMax, state.powerType ("runic_power", "rage", ...)
-- state.powerTime   = when state.power was that much
-- state.powerRegen  = power per second expected from now on, or nil. For rage
--                     it's learned from the last seconds of combat (white
--                     hits and damage taken can't be predicted one by one).
-- Resources.PowerAt(state, t) = the power at time t.
local Resources = {}
ns.Resources = Resources

local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local GetRuneCooldown, GetRuneType = GetRuneCooldown, GetRuneType

local NUM_RUNES = 6
local BASE_RUNE_REGEN = 10

-- GetRuneType() values
Resources.RUNE_TYPES = { "blood", "unholy", "frost", "death" }

-- The type each rune slot has when it isn't a death rune.
Resources.SLOT_BASE = { "blood", "blood", "unholy", "unholy", "frost", "frost" }

local POWER_TYPES = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy", [6] = "runic_power" }

local min = math.min

-- The power at time `t`, with the expected regeneration.
function Resources.PowerAt(state, t)
    local regen = state.powerRegen
    if not regen or t <= state.powerTime then return state.power end
    return min(state.powerMax, state.power + regen * (t - state.powerTime))
end

---------------------------------------------------------------------------
-- Learning the rage income: gains per second over the last RATE_WINDOW
-- seconds of combat (one bucket per second, reused).
---------------------------------------------------------------------------
local RATE_WINDOW = 8
local buckets, bucketSecond = {}, {}
for i = 1, RATE_WINDOW do buckets[i], bucketSecond[i] = 0, -1 end
local lastPower, combatStart

function Resources.ResetIncome(now)
    for i = 1, RATE_WINDOW do buckets[i], bucketSecond[i] = 0, -1 end
    lastPower, combatStart = nil, now
end

local function TrackIncome(power, now)
    if lastPower and power > lastPower then
        local second = math.floor(now)
        local i = second % RATE_WINDOW + 1
        if bucketSecond[i] ~= second then buckets[i], bucketSecond[i] = 0, second end
        buckets[i] = buckets[i] + (power - lastPower)
    end
    lastPower = power
end

-- Power per second over the last seconds of combat, or nil with too little data.
function Resources.Income(now)
    if not combatStart then return nil end
    local span = min(RATE_WINDOW, now - combatStart)
    if span < 2 then return nil end
    local sum, oldest = 0, math.floor(now) - RATE_WINDOW
    for i = 1, RATE_WINDOW do
        if bucketSecond[i] > oldest then sum = sum + buckets[i] end
    end
    return sum / span
end

local function ReadRunes(state, now)
    local runes = state.runes
    local regen = BASE_RUNE_REGEN
    for i = 1, NUM_RUNES do
        local rune = runes[i]
        if not rune then
            rune = {}
            runes[i] = rune
        end
        local start, duration, ready = GetRuneCooldown(i)
        rune.type = Resources.RUNE_TYPES[GetRuneType(i)] or "unknown"
        rune.base = Resources.SLOT_BASE[i]
        if ready or not start or start == 0 then
            rune.readyAt = now
        else
            rune.readyAt = start + duration
        end
        -- Rune regen can be hasted (Improved Unholy Presence), so learn it
        -- from any recharging rune.
        if not ready and duration and duration > 0 then
            regen = duration
        end
    end
    state.runeRegen = regen
end

function Resources.Read(state, classData, now)
    local powerType = UnitPowerType("player")
    state.powerType = POWER_TYPES[powerType] or tostring(powerType)
    state.power = UnitPower("player", powerType)
    state.powerMax = UnitPowerMax("player", powerType)
    state.powerTime = now
    state.powerRegen = nil
    if state.powerType == "rage" then
        -- In combat: the learned income, or the class's guess until there's data.
        if state.inCombat then
            TrackIncome(state.power, now)
            state.powerRegen = Resources.Income(now) or classData.rageIncome
        else
            lastPower = nil
        end
    end
    if classData.usesRunes then
        ReadRunes(state, now)
    end
end

-- Number of runes of `runeType` ready at time `at` (death runes counted separately).
function Resources.RunesReady(state, runeType, at)
    local n = 0
    for i = 1, NUM_RUNES do
        local rune = state.runes[i]
        if rune and rune.type == runeType and rune.readyAt <= at then
            n = n + 1
        end
    end
    return n
end
