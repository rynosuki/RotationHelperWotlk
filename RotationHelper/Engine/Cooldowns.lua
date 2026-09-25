local ADDON_NAME, ns = ...

-- Reads the GCD and ability cooldowns.
--
-- state.gcdRemains, state.gcdDuration
-- state.cooldowns[key] = { readyAt = time, duration = seconds }
--   for every ability in the class data with a cooldown.
local Cooldowns = {}
ns.Cooldowns = Cooldowns

local GetSpellCooldown = GetSpellCooldown
local abs, pairs = math.abs, pairs

local BASE_GCD = 1.5
local MAX_GCD = 1.5

-- On 3.3.5, GetSpellCooldown on a rune ability reports the rune recharge
-- when its runes are down. That isn't the ability's own cooldown, so ignore
-- cooldowns matching the current rune regen time on rune abilities.
local function IsRuneCooldown(ability, duration, state)
    return ability.runes ~= nil and state.runeRegen ~= nil and abs(duration - state.runeRegen) < 0.05
end

function Cooldowns.Read(state, classData, now)
    local start, duration = GetSpellCooldown(classData.gcdSpellName)
    if start and start > 0 and duration and duration > 0 and duration <= MAX_GCD then
        state.gcdRemains = start + duration - now
        state.gcdDuration = duration
    else
        state.gcdRemains = 0
        state.gcdDuration = state.buffs.unholy_presence and 1.0 or BASE_GCD
    end
    if state.gcdRemains < 0 then state.gcdRemains = 0 end

    local list = state.cooldowns
    for key, ability in pairs(classData.abilities) do
        if ability.cooldown and ability.cooldown > 0 then
            local rec = list[key]
            if not rec then
                rec = {}
                list[key] = rec
            end
            local s, d = GetSpellCooldown(ability.name)
            if s and s > 0 and d and d > MAX_GCD and not IsRuneCooldown(ability, d, state) then
                rec.readyAt = s + d
                rec.duration = d
            else
                rec.readyAt = now
                rec.duration = ability.cooldown
            end
        end
    end
end

function Cooldowns.Remains(rec, now)
    if not rec then return 0 end
    local r = rec.readyAt - now
    return r > 0 and r or 0
end
