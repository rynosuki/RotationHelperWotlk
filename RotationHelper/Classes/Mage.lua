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
    procs = { "hot_streak" },
    majorCooldowns = { "combustion", "mirror_image" },
    reviewDebuffs = { fire = { "living_bomb" } },

    -- For the simulator: mana with ~150 per second of regen (Replenishment,
    -- Master of Elements, Evocation, mana gems), and Hot Streak after two
    -- crits in a row: roughly 1 in 5 Fireballs at 3/3.
    simPower = { type = "mana", max = 20000, start = 20000, regen = 150 },
    simProcs = {
        { aura = "hot_streak", duration = 10,
          on = { fireball = true, scorch = true, fire_blast = true, living_bomb = true },
          chance = function(spec) return 0.2 * spec:TalentRank("hot_streak") / 3 end },
    },

    specs = { arcane = false, fire = true, frost = false },

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
    },

    auras = {
        hot_streak = { id = 48108 },
        living_bomb = { id = 55360, debuff = true },
        -- The 5% crit debuff; any mage's counts, and Winter's Chill or a
        -- warlock's Shadow Mastery do the same.
        improved_scorch = { ids = { 22959, 12579, 17800 }, debuff = true, anySource = true },
        molten_armor = { id = 43046 },
        combustion = { id = 11129 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
