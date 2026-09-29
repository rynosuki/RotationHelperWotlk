local ADDON_NAME, ns = ...

-- Rogue data for 3.3.5a. Spell IDs are the highest rank.
--
-- Energy (`energy`): costs are checked like rage, and energy comes back at
-- a known rate (energyRegen), twice as fast during Adrenaline Rush
-- (energyBoosts; Overkill: 30% faster). Combo points: builders add `comboGain`, finishers
-- (`finisher = true`) need at least one and use them all; their effects can
-- read how many from s.comboPointsSpent. The GCD is 1 second.

-- Relentless Strikes: finishers have a 4% chance per rank per combo point to
-- restore 25 energy; the prediction adds the average.
local function RelentlessStrikes(s, spec)
    local rank = spec:TalentRank("relentless_strikes")
    if rank > 0 then
        s.power = math.min(s.powerMax, s.power + 25 * 0.04 * rank * (s.comboPointsSpent or 0))
    end
end

-- Improved Slice and Dice: +25% duration per rank; Glyph of Slice and Dice: +3 seconds.
local function SliceAndDice(s, spec, fx)
    RelentlessStrikes(s, spec)
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
    -- 0.35 a second per rank from off-hand hits, Focused Attacks roughly 0.4
    -- per rank from crits.
    energyRegen = function(spec)
        local vitality = ({ 0.08, 0.16, 0.25 })[spec:TalentRank("vitality")] or 0
        return 10 * (1 + vitality) + 0.35 * spec:TalentRank("combat_potency")
            + 0.4 * spec:TalentRank("focused_attacks")
    end,
    energyBoosts = {
        { aura = "adrenaline_rush", factor = 2 },
        -- Overkill (Assassination): while stealthed and for 20 seconds after.
        { aura = "overkill", factor = 1.3 },
    },
    interrupt = "kick",
    prepullImbues = true, -- the checklist wants poisons on
    majorCooldowns = { "adrenaline_rush", "killing_spree", "blade_flurry", "cold_blood", "shadow_dance" },
    reviewDebuffs = { assassination = { "rupture" }, combat = { "rupture" }, subtlety = { "rupture", "hemorrhage" } },

    -- For the simulator: 100 energy, starting full; Honor Among Thieves gives
    -- a combo point from the group's crits, at most one per second (about 20
    -- a minute at 3/3 in a raid).
    simPower = { type = "energy", max = 100, start = 100 },
    simProcs = {
        { aura = "honor_among_thieves", comboPoints = 1,
          perMinute = function(spec) return 20 * spec:TalentRank("honor_among_thieves") / 3 end },
    },

    specs = { assassination = true, combat = true, subtlety = true },

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
                RelentlessStrikes(s, spec)
            end },
        eviscerate = { id = 48668, energy = 35, finisher = true, apply = RelentlessStrikes },
        -- Five attacks over 2 seconds; nothing else meanwhile.
        killing_spree = { id = 51690, cooldown = 120,
            apply = function(s, spec, fx) s.gcdEnd = math.max(s.gcdEnd, s.now + 2) end },
        adrenaline_rush = { id = 13750, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx)
                fx.ApplyBuff(s, "adrenaline_rush", 15)
                fx.BoostRegen(s, 2, s.now + 15)
            end },
        blade_flurry = { id = 13877, energy = 25, cooldown = 120, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "blade_flurry", 15) end },
        kick = { id = 1766, energy = 25, cooldown = 10, offGcd = true },

        -- Assassination
        -- Garrote is the stealth opener when no bleed is present; 1 combo point and a bleed debuff.
        garrote = { id = 48676, comboGain = 1, energyCost = function(spec) return 45 end,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "garrote", 18) end },
        -- Two combo points (more with Seal Fate crits, not predicted).
        -- Glyph of Mutilate: -5 energy.
        mutilate = { id = 48666, comboGain = 2,
            energyCost = function(spec) return spec:HasGlyph("mutilate") and 55 or 60 end },
        envenom = { id = 57993, energy = 35, finisher = true, consumes = { "cold_blood" },
            apply = function(s, spec, fx)
                fx.ApplyBuff(s, "envenom", 1 + (s.comboPointsSpent or 1))
                RelentlessStrikes(s, spec)
            end },
        -- Needs a bleed on the target (anyone's): the rotation checks it.
        hunger_for_blood = { id = 51662, energy = 15,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "hunger_for_blood", 60) end },
        cold_blood = { id = 14177, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "cold_blood") end },
        -- With Overkill: 30% faster energy for 20 seconds after (a DPS cooldown
        -- for Assassination). Elusiveness: -30 seconds cooldown per rank.
        vanish = { id = 26889, cooldown = 180, offGcd = true,
            cooldownFn = function(spec) return 180 - 30 * spec:TalentRank("elusiveness") end,
            apply = function(s, spec, fx)
                if spec:TalentRank("overkill") > 0 then
                    fx.ApplyBuff(s, "overkill", 20)
                    fx.BoostRegen(s, 1.3, s.now + 20)
                end
            end },

        -- Subtlety (Slaughter from the Shadows: -4 energy per rank on Backstab
        -- and Ambush, -1 on Hemorrhage)
        hemorrhage = { id = 48660, comboGain = 1,
            energyCost = function(spec) return 35 - spec:TalentRank("slaughter_from_the_shadows") end,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "hemorrhage", 15, 10) end },
        -- From behind the target.
        backstab = { id = 48657, comboGain = 1,
            energyCost = function(spec) return 60 - 4 * spec:TalentRank("slaughter_from_the_shadows") end },
        -- From behind, only in stealth or during Shadow Dance.
        ambush = { id = 48691, comboGain = 1, reactive = true, usableWith = "shadow_dance",
            energyCost = function(spec) return 60 - 4 * spec:TalentRank("slaughter_from_the_shadows") end },
        premeditation = { id = 14183, comboGain = 2, cooldown = 20, offGcd = true, reactive = true,
            usableWith = "shadow_dance" },
        -- Glyph of Shadow Dance: +2 seconds.
        shadow_dance = { id = 51713, cooldown = 60, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "shadow_dance", spec:HasGlyph("shadow_dance") and 8 or 6) end },
    },

    auras = {
        slice_and_dice = { id = 6774 },
        adrenaline_rush = { id = 13750 },
        blade_flurry = { id = 13877 },
        rupture = { id = 48672, debuff = true },
        hunger_for_blood = { id = 63848 },
        overkill = { id = 58427 },
        stealth = { id = 1784 },
        shadow_dance = { id = 51713 },
        hemorrhage = { id = 48660, debuff = true },
        envenom = { id = 57993 },
        cold_blood = { id = 14177 },
        deadly_poison = { id = 57970, debuff = true },
        garrote = { id = 48676, debuff = true },
        -- Any bleed on the target, anyone's (for Hunger for Blood): Deep Wounds,
        -- Rend, Garrote, Rake, Rip, Lacerate.
        bleed = { ids = { 43104, 47465, 48676, 48574, 49800, 48568 }, debuff = true, anySource = true },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
