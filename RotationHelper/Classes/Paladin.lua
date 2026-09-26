local ADDON_NAME, ns = ...

-- Paladin data for 3.3.5a. Spell IDs are the highest rank.
--
-- Mana costs (`mana`) are percentages of base mana, as in the tooltips; in
-- game the client's real cost is used (talents like Benediction included).
-- See Classes/DeathKnight.lua for the other ability fields.

-- Improved Judgements: -1 second per rank.
local function JudgementCooldown(spec)
    return 10 - spec:TalentRank("improved_judgements")
end

-- Sanctified Wrath: -30 seconds per rank.
local function AvengingWrathCooldown(spec)
    return 180 - 30 * spec:TalentRank("sanctified_wrath")
end

-- Glyph of Consecration: +2 seconds duration and cooldown.
local function ConsecrationCooldown(spec)
    return spec:HasGlyph("consecration") and 10 or 8
end

-- Glyph of Holy Wrath: -15 seconds.
local function HolyWrathCooldown(spec)
    return spec:HasGlyph("holy_wrath") and 15 or 30
end

ns.RegisterClass("PALADIN", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 19740, -- Blessing of Might
    baseMana = 4394,  -- level 80; mana costs are percentages of this
    -- Procs worth highlighting when the recommended ability spends them.
    procs = { "the_art_of_war" },
    majorCooldowns = { "avenging_wrath" },

    -- For the simulator: a raid-buffed mana bar with about 60 mana per second
    -- of passive regen (Replenishment, mp5), and The Art of War from melee
    -- crits: roughly 4 procs a minute per rank (Exorcism's cooldown caps its use).
    simPower = { type = "mana", max = 25000, start = 25000, regen = 60 },
    simProcs = {
        { aura = "the_art_of_war", duration = 15,
          perMinute = function(spec) return 4 * spec:TalentRank("the_art_of_war") end },
    },

    specs = { holy = false, protection = false, retribution = true },

    abilities = {
        crusader_strike = { id = 35395, mana = 5, cooldown = 4 },
        divine_storm = { id = 53385, mana = 12, cooldown = 10 },
        -- One ability for all three Judgements; which one is chosen in the
        -- options (General > Judgement). They share the cooldown.
        judgement = { id = 20271, mana = 5, cooldown = 10, cooldownFn = JudgementCooldown,
            variants = { light = 20271, wisdom = 53408, justice = 53407 }, variant = "light",
            -- Judgements of the Wise: 25% of base mana back (a third per rank).
            apply = function(s, spec, fx)
                local rank = spec:TalentRank("judgements_of_the_wise")
                if rank > 0 and s.powerType == "mana" then
                    s.power = math.min(s.powerMax, s.power + 0.25 * 4394 * rank / 3)
                end
            end },
        consecration = { id = 48819, mana = 22, cooldown = 8, cooldownFn = ConsecrationCooldown },
        -- A 1.5s cast, instant with The Art of War (the rotation only uses it then).
        exorcism = { id = 48801, mana = 8, cooldown = 15, consumes = { "the_art_of_war" } },
        -- Only on targets below 20% health (the rotation checks target.health.pct).
        hammer_of_wrath = { id = 48806, mana = 12, cooldown = 6 },
        -- Undead and demons only (target.type.undead / target.type.demon).
        holy_wrath = { id = 48817, mana = 20, cooldown = 30, cooldownFn = HolyWrathCooldown },
        avenging_wrath = { id = 31884, mana = 8, cooldown = 180, cooldownFn = AvengingWrathCooldown,
            offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "avenging_wrath", 20) end },
        -- Restores 25% of your mana over 15 seconds; the prediction adds it at once.
        divine_plea = { id = 54428, cooldown = 60,
            apply = function(s, spec, fx)
                fx.ApplyBuff(s, "divine_plea", 15)
                s.power = math.min(s.powerMax, s.power + s.powerMax * 0.25)
            end },
        -- Seals: Vengeance (Alliance) or Corruption (Horde), Command for many targets.
        seal_of_vengeance = { id = 31801, mana = 14,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "seal", 1800) end },
        seal_of_corruption = { id = 53736, mana = 14,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "seal", 1800) end },
        seal_of_command = { id = 20375, mana = 14,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "seal", 1800) end },
        seal_of_righteousness = { id = 21084, mana = 14,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "seal", 1800) end },
    },

    -- Buffs are read from the player, debuffs from the target.
    auras = {
        the_art_of_war = { ids = { 59578, 53489 } },
        avenging_wrath = { id = 31884 },
        divine_plea = { id = 54428 },
        -- Any seal (buff.seal.up): every seal below is part of it.
        seal = {},
        seal_of_vengeance = { id = 31801, partOf = "seal" },
        seal_of_corruption = { id = 53736, partOf = "seal" },
        seal_of_command = { id = 20375, partOf = "seal" },
        seal_of_righteousness = { id = 21084, partOf = "seal" },
        seal_of_light = { id = 20165, partOf = "seal" },
        seal_of_wisdom = { id = 20166, partOf = "seal" },
        seal_of_justice = { id = 20164, partOf = "seal" },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
