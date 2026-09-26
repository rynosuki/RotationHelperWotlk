local ADDON_NAME, ns = ...

-- Warlock data for 3.3.5a. Spell IDs are the highest rank; mana costs are
-- percentages of base mana (see Classes/Paladin.lua); cast times as in
-- Classes/Priest.lua.

-- Everlasting Affliction: Shadow Bolt, Haunt and Drain Soul refresh
-- Corruption (always at 5/5).
local function EverlastingAffliction(s, spec, fx)
    if spec:TalentRank("everlasting_affliction") >= 5 and fx.DebuffUp(s, "corruption") then
        fx.ApplyDebuff(s, "corruption", 18)
    end
end

ns.RegisterClass("WARLOCK", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 687, -- Demon Skin
    baseMana = 3856, -- level 80
    hasteProbe = "searing_pain", -- a 1.5s cast no talent changes: its cast time in game gives the spell haste
    majorCooldowns = {},
    reviewDebuffs = { affliction = { "haunt", "unstable_affliction", "corruption", "curse_of_agony" } },

    -- For the simulator: mana with ~120 per second of regen (Replenishment,
    -- Glyph of Life Tap); Life Tap in the rotation adds more.
    simPower = { type = "mana", max = 20000, start = 20000, regen = 120 },

    specs = { affliction = true, demonology = false, destruction = false },

    abilities = {
        -- Affliction
        haunt = { id = 59164, mana = 12, castTime = 1.5, cooldown = 8,
            apply = function(s, spec, fx)
                fx.ApplyDebuff(s, "haunt", 12)
                EverlastingAffliction(s, spec, fx)
            end },
        corruption = { id = 47813, mana = 14,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "corruption", 18) end },
        unstable_affliction = { id = 47843, mana = 15, castTime = 1.5,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "unstable_affliction", 15) end },
        -- Glyph of Curse of Agony: +4 seconds.
        curse_of_agony = { id = 47864, mana = 10,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "curse_of_agony", spec:HasGlyph("curse_of_agony") and 28 or 24) end },
        curse_of_the_elements = { id = 47865, mana = 10,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "curse_of_the_elements", 300) end },
        -- Bane: -0.1 seconds per rank.
        shadow_bolt = { id = 47809, mana = 17, castTime = 3,
            castTimeFn = function(spec) return 3 - 0.1 * spec:TalentRank("bane") end,
            apply = EverlastingAffliction },
        -- A 15 second channel ticking every 3 seconds; below 25% health it's
        -- the filler. Treated one tick at a time so DoTs still get refreshed.
        drain_soul = { id = 47855, mana = 14, channel = 3, apply = EverlastingAffliction },
        seed_of_corruption = { id = 47836, mana = 34, castTime = 2 },
        searing_pain = { id = 47815, mana = 8, castTime = 1.5 },
        -- Health into mana (roughly 10% of your mana bar with talents and gear).
        life_tap = { id = 57946,
            apply = function(s, spec, fx) s.power = math.min(s.powerMax, s.power + s.powerMax * 0.1) end },
        fel_armor = { id = 47893, mana = 28,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "fel_armor", 1800) end },
    },

    auras = {
        haunt = { id = 59164, debuff = true },
        corruption = { id = 47813, debuff = true },
        unstable_affliction = { id = 47843, debuff = true },
        curse_of_agony = { id = 47864, debuff = true },
        -- Anyone's (or a Moonkin's Earth and Moon, or an Unholy DK's Ebon Plague) counts.
        curse_of_the_elements = { ids = { 47865, 60433, 51735 }, debuff = true, anySource = true },
        fel_armor = { id = 47893 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
