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

-- Cat energy costs. Ferocity: -1 per rank on Mangle, Rake and Shred;
-- Improved Mangle: -2 per rank on Mangle; Shredding Attacks: -9 per rank on Shred.
local function CatCost(base, extra)
    return function(spec)
        local cost = base - spec:TalentRank("ferocity")
        if extra then cost = cost - extra(spec) end
        return cost
    end
end

ns.RegisterClass("DRUID", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1126, -- Mark of the Wild
    baseMana = 3496, -- level 80
    hasteProbe = "entangling_roots", -- a 1.5s cast no talent changes: its cast time in game gives the spell haste
    procs = { "lunar_eclipse", "solar_eclipse", "clearcasting" },
    -- Cat Form: 10 energy a second, a 1 second GCD; Omen of Clarity makes the
    -- next ability free, Berserk halves energy costs.
    energyRegen = function(spec) return 10 end,
    baseGcd = { feral_combat = 1 },
    freeCostAura = "clearcasting",
    costBuff = { aura = "berserk", factor = 0.5 },
    lastAuraGroup = { "lunar_eclipse", "solar_eclipse" },
    majorCooldowns = { "force_of_nature", "starfall", "berserk" },
    reviewDebuffs = { balance = { "moonfire", "insect_swarm" }, feral_combat = { "rip", "rake", "mangle" } },

    -- For the simulator: mana with ~260 per second of regen (Replenishment,
    -- Moonkin Form mana on crits, Omen of Clarity), and Eclipse procs from crits (about
    -- 50% crit on Starfire with talents, 60% of Wrath crits).
    simPower = {
        balance = { type = "mana", max = 20000, start = 20000, regen = 260 },
        feral_combat = { type = "energy", max = 100, start = 100 },
    },
    simProcs = {
        { aura = "solar_eclipse", duration = 15, icd = 30, on = { starfire = true },
          chance = function(spec) return spec:TalentRank("eclipse") > 0 and 0.5 or 0 end },
        { aura = "lunar_eclipse", duration = 15, icd = 30, on = { wrath = true },
          chance = function(spec) return spec:TalentRank("eclipse") > 0 and 0.25 or 0 end },
        -- Omen of Clarity: about 3.5 procs a minute in Cat Form.
        { aura = "clearcasting", duration = 15,
          perMinute = function(spec) return spec:TalentRank("omen_of_clarity") > 0 and 3.5 or 0 end },
    },

    specs = { balance = true, feral_combat = true, restoration = false },

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
        hurricane = { id = 48467, mana = 81, channel = 10, ticks = 10 },
        moonkin_form = { id = 24858, mana = 13,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "moonkin_form") end },
        entangling_roots = { id = 53308, mana = 7, castTime = 1.5 },

        -- Feral (cat)
        cat_form = { id = 768, mana = 35,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "cat_form") end },
        mangle_cat = { id = 48566, comboGain = 1,
            energyCost = CatCost(45, function(spec) return 2 * spec:TalentRank("improved_mangle") end),
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "mangle", 60) end },
        shred = { id = 48572, comboGain = 1,
            energyCost = CatCost(60, function(spec) return 9 * spec:TalentRank("shredding_attacks") end) },
        rake = { id = 48574, comboGain = 1, energyCost = CatCost(40),
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "rake", 9) end },
        -- Glyph of Rip: +4 seconds.
        rip = { id = 49800, energy = 30, finisher = true,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "rip", spec:HasGlyph("rip") and 16 or 12) end },
        savage_roar = { id = 52610, energy = 25, finisher = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "savage_roar", 9 + 5 * (s.comboPointsSpent or 1)) end },
        -- Uses up to 30 more energy for more damage.
        ferocious_bite = { id = 48577, energy = 35, finisher = true,
            apply = function(s, spec, fx) s.power = math.max(0, s.power - 30) end },
        -- King of the Jungle: 20 energy per rank.
        tigers_fury = { id = 50213, cooldown = 30, offGcd = true,
            energyGain = function(spec) return 20 * spec:TalentRank("king_of_the_jungle") end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "tigers_fury", 6) end },
        berserk = { id = 50334, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "berserk", 15) end },
        faerie_fire_feral = { id = 16857, cooldown = 6,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "faerie_fire", 300) end },
    },

    auras = {
        lunar_eclipse = { id = 48518 },
        solar_eclipse = { id = 48517 },
        moonfire = { id = 48463, debuff = true },
        insect_swarm = { id = 48468, debuff = true },
        -- Anyone's counts (a feral druid's too).
        faerie_fire = { ids = { 770, 16857 }, debuff = true, anySource = true },
        moonkin_form = { id = 24858 },
        cat_form = { id = 768 },
        clearcasting = { id = 16870 },
        savage_roar = { id = 52610 },
        tigers_fury = { id = 50213 },
        berserk = { id = 50334 },
        rip = { id = 49800, debuff = true },
        rake = { id = 48574, debuff = true },
        -- The bleed damage debuff: anyone's Mangle or a warrior's Trauma counts.
        mangle = { ids = { 48566, 48564, 46857 }, debuff = true, anySource = true },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
