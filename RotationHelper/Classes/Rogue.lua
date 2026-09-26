local ADDON_NAME, ns = ...

-- Rogue data for 3.3.5a. Spell IDs are the highest rank.
--
-- Energy (`energy`): costs are checked like rage, and energy comes back at
-- a known rate (energyRegen), twice as fast during Adrenaline Rush
-- (energyBoost). Combo points: builders add `comboGain`, finishers
-- (`finisher = true`) need at least one and use them all; their effects can
-- read how many from s.comboPointsSpent. The GCD is 1 second.

-- Improved Slice and Dice: +25% duration per rank; Glyph of Slice and Dice: +3 seconds.
local function SliceAndDice(s, spec, fx)
    local cp = s.comboPointsSpent or 1
    local duration = (6 + 3 * cp) * (1 + 0.25 * spec:TalentRank("improved_slice_and_dice"))
    if spec:HasGlyph("slice_and_dice") then duration = duration + 3 end
    fx.ApplyBuff(s, "slice_and_dice", duration)
end

ns.RegisterClass("ROGUE", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1752, -- Sinister Strike
    baseGcd = 1,
    -- 10 energy a second; Vitality +8/16/25%; Combat Potency adds roughly
    -- 0.35 a second per rank from off-hand hits.
    energyRegen = function(spec)
        local vitality = ({ 0.08, 0.16, 0.25 })[spec:TalentRank("vitality")] or 0
        return 10 * (1 + vitality) + 0.35 * spec:TalentRank("combat_potency")
    end,
    energyBoost = { aura = "adrenaline_rush", factor = 2 },
    interrupt = "kick",
    prepullImbues = true, -- the checklist wants poisons on
    majorCooldowns = { "adrenaline_rush", "killing_spree", "blade_flurry" },
    reviewDebuffs = { combat = { "rupture" } },

    -- For the simulator: 100 energy, starting full.
    simPower = { type = "energy", max = 100, start = 100 },

    specs = { assassination = false, combat = true, subtlety = false },

    abilities = {
        -- Improved Sinister Strike: -3 / -5 energy.
        sinister_strike = { id = 48638, comboGain = 1,
            energyCost = function(spec) return 45 - (({ 3, 5 })[spec:TalentRank("improved_sinister_strike")] or 0) end },
        slice_and_dice = { id = 6774, energy = 25, finisher = true, apply = SliceAndDice },
        -- Glyph of Rupture: +4 seconds.
        rupture = { id = 48672, energy = 25, finisher = true,
            apply = function(s, spec, fx)
                local duration = 6 + 2 * (s.comboPointsSpent or 1)
                if spec:HasGlyph("rupture") then duration = duration + 4 end
                fx.ApplyDebuff(s, "rupture", duration)
            end },
        eviscerate = { id = 48668, energy = 35, finisher = true },
        -- Five attacks over 2 seconds; nothing else meanwhile.
        killing_spree = { id = 51690, cooldown = 120,
            apply = function(s, spec, fx) s.gcdEnd = math.max(s.gcdEnd, s.now + 2) end },
        adrenaline_rush = { id = 13750, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx)
                fx.ApplyBuff(s, "adrenaline_rush", 15)
                s.regenBoost, s.regenBoostUntil = 2, s.now + 15
            end },
        blade_flurry = { id = 13877, energy = 25, cooldown = 120, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "blade_flurry", 15) end },
        kick = { id = 1766, energy = 25, cooldown = 10, offGcd = true },
    },

    auras = {
        slice_and_dice = { id = 6774 },
        adrenaline_rush = { id = 13750 },
        blade_flurry = { id = 13877 },
        rupture = { id = 48672, debuff = true },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
