local ADDON_NAME, ns = ...

-- Mage data for 3.3.5a. Spell IDs are the highest rank; mana costs are
-- percentages of base mana (see Classes/Paladin.lua); cast times as in
-- Classes/Priest.lua. `instantWith` names a buff that makes a cast instant
-- (and is used up): Hot Streak for Pyroblast.

ns.RegisterClass("MAGE", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1459, -- Arcane Intellect
    baseMana = 3268, -- level 80
    hasteProbe = "scorch", -- a 1.5s cast no talent changes: its cast time in game gives the spell haste
    interrupt = "counterspell",
    procs = { "hot_streak", "missile_barrage", "brain_freeze", "fingers_of_frost" },
    majorCooldowns = { "combustion", "arcane_power", "icy_veins", "mirror_image" },
    hasPlayerDebuffs = true, -- Arcane Blast's stacks are a debuff on you
    reviewDebuffs = { fire = { "living_bomb" } },

    -- For the simulator: mana with ~150 per second of regen (Replenishment,
    -- Master of Elements, Evocation, mana gems), and Hot Streak after two
    -- crits in a row: roughly 1 in 5 Fireballs at 3/3.
    simPower = { type = "mana", max = 20000, start = 20000, regen = 150 },
    simProcs = {
        { aura = "hot_streak", duration = 10,
          on = { fireball = true, scorch = true, fire_blast = true, living_bomb = true },
          chance = function(spec) return 0.2 * spec:TalentRank("hot_streak") / 3 end },
        -- Missile Barrage: 8% per rank from Arcane Blast (40% at 5/5), half that from others.
        { aura = "missile_barrage", duration = 15, on = { arcane_blast = true },
          chance = function(spec) return 0.08 * spec:TalentRank("missile_barrage") end },
        { aura = "missile_barrage", duration = 15, on = { arcane_barrage = true, fireball = true },
          chance = function(spec) return 0.04 * spec:TalentRank("missile_barrage") end },
        -- Frost: Fingers of Frost (7/15% per chill, two charges) and Brain
        -- Freeze (5% per rank) from Frostbolt.
        { aura = "fingers_of_frost", duration = 15, stacks = 2, on = { frostbolt = true },
          chance = function(spec) return ({ 0.07, 0.15 })[spec:TalentRank("fingers_of_frost")] or 0 end },
        { aura = "brain_freeze", duration = 15, on = { frostbolt = true },
          chance = function(spec) return 0.05 * spec:TalentRank("brain_freeze") end },
    },

    specs = { arcane = true, fire = true, frost = true },

    abilities = {
        -- Improved Fireball: -0.1 seconds per rank.
        fireball = { id = 42833, mana = 19, castTime = 3.5,
            castTimeFn = function(spec) return 3.5 - 0.1 * spec:TalentRank("improved_fireball") end },
        -- A 5 second cast, instant with Hot Streak (the rotation only uses it then).
        pyroblast = { id = 42891, mana = 22, castTime = 5, instantWith = "hot_streak" },
        living_bomb = { id = 55360, mana = 22,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "living_bomb", 12) end },
        scorch = { id = 42859, mana = 8, castTime = 1.5,
            apply = function(s, spec, fx)
                if spec:TalentRank("improved_scorch") > 0 then fx.ApplyDebuff(s, "improved_scorch", 30) end
            end },
        fire_blast = { id = 42873, mana = 21, cooldown = 8 },
        flamestrike = { id = 42926, mana = 30, castTime = 2 },
        combustion = { id = 11129, cooldown = 120, offGcd = true },
        mirror_image = { id = 55342, mana = 10, cooldown = 180 },
        -- Mana back over 8 seconds (channel).
        evocation = { id = 12051, cooldown = 240, channel = 8,
            apply = function(s, spec, fx) s.power = math.min(s.powerMax, s.power + s.powerMax * 0.6) end },
        molten_armor = { id = 43046, mana = 28,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "molten_armor", 1800) end },
        counterspell = { id = 2139, mana = 9, cooldown = 24, offGcd = true },

        -- Arcane
        -- Each Arcane Blast stack (up to 4, 6 seconds) adds 175% to its cost.
        -- Presence of Mind makes it instant.
        arcane_blast = { id = 42897, mana = 7, castTime = 2.5, instantWith = "presence_of_mind",
            manaFn = function(spec, s, baseMana)
                local rec = s.buffs.arcane_blast
                local stacks = (rec and rec.expires > s.now) and rec.stacks or 0
                return 0.07 * baseMana * (1 + 1.75 * stacks)
            end,
            apply = function(s, spec, fx)
                local rec = s.buffs.arcane_blast
                local stacks = (rec and rec.expires > s.now) and rec.stacks or 0
                fx.ApplyBuff(s, "arcane_blast", 6, math.min(4, stacks + 1))
            end },
        -- A 5 second channel; with Missile Barrage 2.5 seconds and free. Uses
        -- up the Arcane Blast stacks.
        arcane_missiles = { id = 42846, mana = 31, channel = 5, consumes = { "missile_barrage", "arcane_blast" },
            castTimeFn = function(spec, s)
                local rec = s and s.buffs.missile_barrage
                return (rec and rec.expires > s.now) and 2.5 or 5
            end,
            manaFn = function(spec, s, baseMana)
                local rec = s.buffs.missile_barrage
                return (rec and rec.expires > s.now) and 0 or 0.31 * baseMana
            end },
        arcane_barrage = { id = 44781, mana = 18, cooldown = 3, consumes = { "arcane_blast" } },
        -- Arcane Flows: -15% cooldown per rank.
        arcane_power = { id = 12042, cooldown = 120, offGcd = true,
            cooldownFn = function(spec) return 120 * (1 - 0.15 * spec:TalentRank("arcane_flows")) end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "arcane_power", 15) end },
        presence_of_mind = { id = 12043, cooldown = 120, offGcd = true,
            cooldownFn = function(spec) return 120 * (1 - 0.15 * spec:TalentRank("arcane_flows")) end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "presence_of_mind") end },

        -- Frost
        -- Improved Frostbolt: -0.1 seconds per rank.
        -- Frost spells use a Fingers of Frost charge (their shatter crit).
        frostbolt = { id = 42842, mana = 11, castTime = 3, usesStack = "fingers_of_frost",
            castTimeFn = function(spec) return 3 - 0.1 * spec:TalentRank("improved_frostbolt") end },
        -- Instant and free with Brain Freeze (the rotation only uses it then).
        frostfire_bolt = { id = 47610, mana = 14, castTime = 3, instantWith = "brain_freeze",
            manaFn = function(spec, s, baseMana)
                local rec = s.buffs.brain_freeze
                return (rec and rec.expires > s.now) and 0 or 0.14 * baseMana
            end },
        ice_lance = { id = 42914, mana = 6, usesStack = "fingers_of_frost" },
        -- Only on a frozen target; Fingers of Frost counts (one charge used).
        deep_freeze = { id = 44572, mana = 9, cooldown = 30, reactive = true, usableWith = "fingers_of_frost",
            usesStack = "fingers_of_frost" },
        -- Ice Floes: -7/14/20% cooldown.
        icy_veins = { id = 12472, mana = 3, cooldown = 180, offGcd = true,
            cooldownFn = function(spec) return 180 * (1 - (({ 0.07, 0.14, 0.2 })[spec:TalentRank("ice_floes")] or 0)) end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "icy_veins", 20) end },
        -- Finishes the cooldown of your Frost spells.
        cold_snap = { id = 11958, cooldown = 480, offGcd = true,
            apply = function(s, spec, fx)
                for _, key in ipairs({ "icy_veins", "deep_freeze", "summon_water_elemental" }) do
                    local cd = s.cooldowns[key]
                    if cd and cd.readyAt > s.now then cd.readyAt = s.now end
                end
            end },
        summon_water_elemental = { id = 31687, mana = 16, cooldown = 180,
            apply = function(s, spec, fx) fx.SummonPet(s) end },
    },

    auras = {
        hot_streak = { id = 48108 },
        missile_barrage = { id = 44401 },
        arcane_blast = { id = 36032, onPlayer = true }, -- the stacking debuff on you
        arcane_power = { id = 12042 },
        fingers_of_frost = { id = 74396 },
        brain_freeze = { id = 57761 },
        icy_veins = { id = 12472 },
        presence_of_mind = { id = 12043 },
        living_bomb = { id = 55360, debuff = true },
        -- The 5% crit debuff; any mage's counts, and Winter's Chill or a
        -- warlock's Shadow Mastery do the same.
        improved_scorch = { ids = { 22959, 12579, 17800 }, debuff = true, anySource = true },
        molten_armor = { id = 43046 },
        combustion = { id = 11129 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
