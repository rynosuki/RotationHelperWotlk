local ADDON_NAME, ns = ...

-- Druid data for 3.3.5a. Spell IDs are the highest rank; mana costs are
-- percentages of base mana (see Classes/Paladin.lua); cast times as in
-- Classes/Priest.lua.
--
-- Eclipse: a Starfire crit can start Solar Eclipse (Wrath +40% damage), a
-- Wrath crit Lunar Eclipse (Starfire +40% crit); each has a 30 second
-- internal cooldown. After one ends you keep casting its spell until the
-- other one procs, so the last one is remembered (last.lunar_eclipse).

-- Starlight Wrath: -0.1 seconds per rank on Wrath and Starfire.
local function StarlightWrath(base)
    return function(spec) return base - 0.1 * spec:TalentRank("starlight_wrath") end
end

ns.RegisterClass("DRUID", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1126, -- Mark of the Wild
    baseMana = 3496, -- level 80
    hasteProbe = "entangling_roots", -- a 1.5s cast no talent changes: its cast time in game gives the spell haste
    procs = { "lunar_eclipse", "solar_eclipse" },
    lastAuraGroup = { "lunar_eclipse", "solar_eclipse" },
    majorCooldowns = { "force_of_nature", "starfall" },
    reviewDebuffs = { balance = { "moonfire", "insect_swarm" } },

    -- For the simulator: mana with ~260 per second of regen (Replenishment,
    -- Moonkin Form mana on crits, Omen of Clarity), and Eclipse procs from crits (about
    -- 50% crit on Starfire with talents, 60% of Wrath crits).
    simPower = { type = "mana", max = 20000, start = 20000, regen = 260 },
    simProcs = {
        { aura = "solar_eclipse", duration = 15, icd = 30, on = { starfire = true },
          chance = function(spec) return spec:TalentRank("eclipse") > 0 and 0.5 or 0 end },
        { aura = "lunar_eclipse", duration = 15, icd = 30, on = { wrath = true },
          chance = function(spec) return spec:TalentRank("eclipse") > 0 and 0.25 or 0 end },
    },

    specs = { balance = true, feral_combat = false, restoration = false },

    abilities = {
        wrath = { id = 48461, mana = 11, castTime = 2, castTimeFn = StarlightWrath(2) },
        starfire = { id = 48465, mana = 16, castTime = 3.5, castTimeFn = StarlightWrath(3.5) },
        -- Nature's Splendor: +3 seconds on Moonfire, +2 on Insect Swarm.
        moonfire = { id = 48463, mana = 21,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "moonfire", 12 + 3 * spec:TalentRank("natures_splendor")) end },
        insect_swarm = { id = 48468, mana = 8,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "insect_swarm", 12 + 2 * spec:TalentRank("natures_splendor")) end },
        faerie_fire = { id = 770, mana = 8,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "faerie_fire", 300) end },
        -- Glyph of Starfall: -30 seconds.
        starfall = { id = 53201, mana = 35, cooldown = 90,
            cooldownFn = function(spec) return spec:HasGlyph("starfall") and 60 or 90 end },
        force_of_nature = { id = 33831, mana = 12, cooldown = 180 },
        hurricane = { id = 48467, mana = 81, channel = 10 },
        moonkin_form = { id = 24858, mana = 13,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "moonkin_form") end },
        entangling_roots = { id = 53308, mana = 7, castTime = 1.5 },
    },

    auras = {
        lunar_eclipse = { id = 48518 },
        solar_eclipse = { id = 48517 },
        moonfire = { id = 48463, debuff = true },
        insect_swarm = { id = 48468, debuff = true },
        -- Anyone's counts (a feral druid's too).
        faerie_fire = { ids = { 770, 16857 }, debuff = true, anySource = true },
        moonkin_form = { id = 24858 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
