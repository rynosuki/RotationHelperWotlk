local ADDON_NAME, ns = ...

-- Priest data for 3.3.5a. Spell IDs are the highest rank; mana costs are
-- percentages of base mana (see Classes/Paladin.lua).
--
-- Casts (`castTime`) and channels (`channel`) are in base seconds; spell
-- haste shortens them, measured from Mind Blast's cast time (hasteProbe).

ns.RegisterClass("PRIEST", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1243, -- Power Word: Fortitude
    baseMana = 3863, -- level 80
    hasteProbe = "mind_blast", -- a 1.5s cast: its cast time in game gives the spell haste
    interrupt = "silence",
    majorCooldowns = { "shadowfiend" },
    reviewDebuffs = { shadow = { "vampiric_touch", "devouring_plague", "shadow_word_pain" } },

    -- For the simulator: mana with ~180 per second of regen (Replenishment
    -- from Vampiric Touch, spirit, Shadowfiend).
    simPower = { type = "mana", max = 22000, start = 22000, regen = 180 },

    specs = { discipline = false, holy = false, shadow = true },

    abilities = {
        vampiric_touch = { id = 48160, mana = 16, castTime = 1.5,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "vampiric_touch", 15) end },
        shadow_word_pain = { id = 48125, mana = 22,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "shadow_word_pain", 18) end },
        devouring_plague = { id = 48300, mana = 25,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "devouring_plague", 24) end },
        -- Improved Mind Blast: -0.5 seconds cooldown per rank.
        mind_blast = { id = 48127, mana = 17, castTime = 1.5, cooldown = 8,
            cooldownFn = function(spec) return 8 - 0.5 * spec:TalentRank("improved_mind_blast") end },
        -- Pain and Suffering: Mind Flay refreshes Shadow Word: Pain (100% at 3/3).
        -- Cut after any of its 3 ticks when something above it is ready.
        mind_flay = { id = 48156, mana = 9, channel = 3, ticks = 3,
            apply = function(s, spec, fx)
                if spec:TalentRank("pain_and_suffering") >= 3 and fx.DebuffUp(s, "shadow_word_pain") then
                    fx.ApplyDebuff(s, "shadow_word_pain", 18)
                end
            end },
        mind_sear = { id = 53023, mana = 28, channel = 5 },
        shadow_word_death = { id = 48158, mana = 12, cooldown = 12 },
        shadowfiend = { id = 34433, cooldown = 300 },
        -- 6 seconds of damage reduction and 36% of your mana back.
        dispersion = { id = 47585, cooldown = 120, channel = 6,
            apply = function(s, spec, fx) s.power = math.min(s.powerMax, s.power + s.powerMax * 0.36) end },
        shadowform = { id = 15473,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "shadowform") end },
        inner_fire = { id = 48168,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "inner_fire", 1800) end },
        vampiric_embrace = { id = 15286,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "vampiric_embrace", 1800) end },
        silence = { id = 15487, cooldown = 45, offGcd = true },
    },

    auras = {
        vampiric_touch = { id = 48160, debuff = true },
        shadow_word_pain = { id = 48125, debuff = true },
        devouring_plague = { id = 48300, debuff = true },
        shadowform = { id = 15473 },
        inner_fire = { id = 48168 },
        vampiric_embrace = { id = 15286 },
        shadow_weaving = { id = 15258 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
