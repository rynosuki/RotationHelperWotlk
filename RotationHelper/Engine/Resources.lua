local ADDON_NAME, ns = ...

-- Reads power and (for Death Knights) runes.
--
-- state.runes[1..6] = { type = "blood"|"unholy"|"frost"|"death", base = slot type, readyAt = time }
-- state.runeRegen   = seconds for one rune to regenerate (10 base)
-- state.power, state.powerMax, state.powerType ("runic_power", "rage", ...)
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
