local ADDON_NAME, ns = ...

-- Hunter data for 3.3.5a. Spell IDs are the highest rank; mana costs are
-- percentages of base mana (see Classes/Paladin.lua).
--
-- Auto Shot keeps firing on its own (Engine/AutoShot.lua). Steady Shot is a
-- cast (`avoidAutoClip`): when it would delay the next Auto Shot it waits
-- for it, and instants fill the gap. Ranged haste shortens Steady Shot, but
-- the GCD stays 1.5 seconds.

-- Glyph of Serpent Sting: +6 seconds.
local function SerpentSting(spec)
    return spec:HasGlyph("serpent_sting") and 21 or 15
end

ns.RegisterClass("HUNTER", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1130, -- Hunter's Mark
    baseMana = 5046, -- level 80
    baseGcd = 1.5,   -- not shortened by haste
    hasteProbe = "steady_shot", -- its cast time in game gives the ranged haste
    autoShot = true,
    interrupt = "silencing_shot",
    prepullPet = true, -- the checklist wants your pet out
    procs = { "lock_and_load" },
    majorCooldowns = { "rapid_fire", "readiness", "bestial_wrath" },
    reviewDebuffs = {
        beast_mastery = { "serpent_sting" },
        marksmanship = { "serpent_sting" },
        survival = { "serpent_sting", "black_arrow" },
    },
    -- The Beast Within (Bestial Wrath with the talent): half mana costs.
    costBuff = { aura = "the_beast_within", factor = 0.5 },

    -- For the simulator: mana with ~120 per second of regen (Aspect of the
    -- Viper when low, Replenishment, Hunting Party), Auto Shot every 2.4
    -- seconds.
    simPower = { type = "mana", max = 22000, start = 22000, regen = 120 },
    simAutoShot = 2.4,
    -- Lock and Load from Serpent Sting and Black Arrow ticks: about one a
    -- minute per rank (22 second internal cooldown), two charges.
    simProcs = {
        { aura = "lock_and_load", duration = 12, stacks = 2, icd = 22,
          perMinute = function(spec) return spec:TalentRank("lock_and_load") end },
    },

    specs = { beast_mastery = true, marksmanship = true, survival = true },

    abilities = {
        -- A 2 second cast (hasted); waits for the Auto Shot it would clip.
        steady_shot = { id = 49052, mana = 5, castTime = 2, avoidAutoClip = true },
        arcane_shot = { id = 49045, mana = 5, cooldown = 6 },
        -- Refreshes Serpent Sting.
        chimera_shot = { id = 53209, mana = 12, cooldown = 10,
            apply = function(s, spec, fx)
                if fx.DebuffUp(s, "serpent_sting") then fx.ApplyDebuff(s, "serpent_sting", SerpentSting(spec)) end
            end },
        -- Glyph of Aimed Shot: -2 seconds. Shares its cooldown with Multi-Shot.
        aimed_shot = { id = 49050, mana = 8, cooldown = 10, cooldownGroup = "aimed",
            cooldownFn = function(spec) return spec:HasGlyph("aimed_shot") and 8 or 10 end },
        multi_shot = { id = 49048, mana = 9, cooldown = 10, cooldownGroup = "aimed" },
        serpent_sting = { id = 49001, mana = 9,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "serpent_sting", SerpentSting(spec)) end },
        -- Below 20% health only (the rotation checks target.health.pct).
        kill_shot = { id = 61006, mana = 7, cooldown = 15 },
        hunters_mark = { id = 53338, mana = 2,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "hunters_mark", 300) end },
        silencing_shot = { id = 34490, mana = 6, cooldown = 20, offGcd = true },
        -- Rapid Killing: -1 minute per rank.
        rapid_fire = { id = 3045, mana = 3, cooldown = 300, offGcd = true,
            cooldownFn = function(spec) return 300 - 60 * spec:TalentRank("rapid_killing") end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "rapid_fire", 15) end },
        -- Finishes the cooldown of your other Hunter abilities (not trinkets,
        -- potions or racials).
        readiness = { id = 23989, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx)
                for key, cd in pairs(s.cooldowns) do
                    if key ~= "readiness" and not ns.SharedAbilities[key] and cd.readyAt > s.now then
                        cd.readyAt = s.now
                    end
                end
            end },
        -- Needs your pet. Catlike Reflexes: -10 seconds per rank.
        kill_command = { id = 34026, mana = 3, cooldown = 60, offGcd = true, requiresPet = true,
            cooldownFn = function(spec) return 60 - 10 * spec:TalentRank("catlike_reflexes") end },
        -- Beast Mastery: your pet goes berserk; with The Beast Within, you too.
        -- Longevity: -10% cooldown per rank.
        bestial_wrath = { id = 19574, mana = 10, cooldown = 120, offGcd = true, requiresPet = true,
            cooldownFn = function(spec) return 120 * (1 - 0.1 * spec:TalentRank("longevity")) end,
            apply = function(s, spec, fx)
                if spec:TalentRank("the_beast_within") > 0 then fx.ApplyBuff(s, "the_beast_within", 18) end
            end },
        -- Survival
        -- With Lock and Load: no cooldown and free (one of its two charges).
        explosive_shot = { id = 60053, cooldown = 6, ignoreCooldownWith = "lock_and_load",
            manaFn = function(spec, s, baseMana)
                local rec = s.buffs.lock_and_load
                return (rec and rec.expires > s.now) and 0 or 0.07 * baseMana
            end,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "explosive_shot", 2) end },
        black_arrow = { id = 63672, mana = 6, cooldown = 30,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "black_arrow", 15) end },
        aspect_of_the_dragonhawk = { id = 61847,
            apply = function(s, spec, fx)
                fx.RemoveBuff(s, "aspect_of_the_viper")
                fx.ApplyBuff(s, "aspect_of_the_dragonhawk")
            end },
        aspect_of_the_viper = { id = 34074,
            apply = function(s, spec, fx)
                fx.RemoveBuff(s, "aspect_of_the_dragonhawk")
                fx.ApplyBuff(s, "aspect_of_the_viper")
            end },
    },

    auras = {
        serpent_sting = { id = 49001, debuff = true },
        -- Anyone's Hunter's Mark counts.
        hunters_mark = { id = 53338, debuff = true, anySource = true },
        rapid_fire = { id = 3045 },
        lock_and_load = { id = 56453 },
        the_beast_within = { id = 34471 },
        explosive_shot = { id = 60053, debuff = true },
        black_arrow = { id = 63672, debuff = true },
        aspect_of_the_dragonhawk = { id = 61847 },
        aspect_of_the_viper = { id = 34074 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
