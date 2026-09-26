local ADDON_NAME, ns = ...

-- Warrior data for 3.3.5a. Spell IDs are the highest rank.
--
-- Rage (`rage`, `rageCost`, `rageGain`): costs are checked like runic power,
-- but rage keeps coming in from white hits, so an ability short on rage
-- waits for the expected income (learned during the fight; `rageIncome`
-- per second until there's data). See Classes/DeathKnight.lua for the
-- other ability fields; `nextSwing` marks on-next-swing attacks (Heroic
-- Strike, Cleave), which aren't suggested again while one is queued.

-- Intensify Rage: -11% cooldown per rank on Bloodrage, Berserker Rage,
-- Recklessness and Death Wish.
local function IntensifyRage(base)
    return function(spec) return base * (1 - 0.11 * spec:TalentRank("intensify_rage")) end
end

ns.RegisterClass("WARRIOR", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 1715, -- Hamstring
    rageIncome = 12, -- rage per second in combat until the real income is known
    interrupt = "pummel",
    procs = { "bloodsurge", "taste_for_blood", "sudden_death" },
    majorCooldowns = { "death_wish", "recklessness", "bladestorm" },
    reviewDebuffs = { arms = { "rend" } },
    -- Stance expected before a pull, per spec (1 battle, 2 defensive, 3 berserker).
    prepullForm = {
        arms = { form = 1, label = "Battle Stance" },
        fury = { form = 3, label = "Berserker Stance" },
    },

    -- For the simulator: rage income of 15 per second, Berserker Stance, and
    -- Bloodsurge (Slam!) from Bloodthirst, Whirlwind and Heroic Strike hits.
    simPower = { type = "rage", max = 100, start = 20, regen = 15 },
    simForm = { arms = 1, fury = 3 },
    simSwing = { arms = 3.3, fury = 2.5 }, -- seconds between main-hand swings (a queued Heroic Strike lands on the next)
    simProcs = {
        { aura = "bloodsurge", duration = 5, on = { bloodthirst = true, whirlwind = true, heroic_strike = true },
          chance = function(spec) return ({ 0.07, 0.13, 0.20 })[spec:TalentRank("bloodsurge")] or 0 end },
        -- Arms: Taste for Blood from Rend ticks (at most one every 6 seconds),
        -- Sudden Death from melee hits.
        { aura = "taste_for_blood", duration = 9,
          perMinute = function(spec) return 3.3 * spec:TalentRank("taste_for_blood") end },
        { aura = "sudden_death", duration = 10,
          perMinute = function(spec) return spec:TalentRank("sudden_death") end },
    },

    specs = { arms = true, fury = true, protection = false },

    abilities = {
        bloodthirst = { id = 23881, rage = 20, cooldown = 4 },
        -- Glyph of Whirlwind: -2 seconds.
        whirlwind = { id = 1680, rage = 25, cooldown = 10, requiresForm = 3,
            cooldownFn = function(spec) return spec:HasGlyph("whirlwind") and 8 or 10 end },
        -- A 1.5s cast, instant with Bloodsurge (the rotation only uses it then).
        slam = { id = 47475, rage = 15, consumes = { "bloodsurge" } },
        -- Below 20% health, or any time with Sudden Death (the rotation checks);
        -- uses up to 30 extra rage for more damage.
        execute = { id = 47471, rage = 15, consumes = { "sudden_death" },
            apply = function(s, spec, fx) s.power = math.max(0, s.power - 30) end },
        -- On the next swing; Improved Heroic Strike: -1 rage per rank.
        heroic_strike = { id = 47450, offGcd = true, nextSwing = true,
            rageCost = function(spec) return 15 - spec:TalentRank("improved_heroic_strike") end },
        cleave = { id = 47520, rage = 20, offGcd = true, nextSwing = true },
        battle_shout = { id = 47436, rage = 10,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "battle_shout", 120) end },
        commanding_shout = { id = 47440, rage = 10,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "commanding_shout", 120) end },
        -- 20 rage (10 at once, 10 over 10 seconds).
        bloodrage = { id = 2687, cooldown = 60, cooldownFn = IntensifyRage(60), offGcd = true,
            rageGain = function(spec) return 20 end },
        -- Improved Berserker Rage: 10 rage per rank.
        berserker_rage = { id = 18499, cooldown = 30, cooldownFn = IntensifyRage(30), offGcd = true,
            rageGain = function(spec) return 10 * spec:TalentRank("improved_berserker_rage") end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "berserker_rage", 10) end },
        death_wish = { id = 12292, rage = 10, cooldown = 180, cooldownFn = IntensifyRage(180), offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "death_wish", 30) end },
        recklessness = { id = 1719, cooldown = 300, cooldownFn = IntensifyRage(300), offGcd = true, requiresForm = 3,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "recklessness", 12, 3) end },
        pummel = { id = 6552, rage = 10, cooldown = 10, offGcd = true, requiresForm = 3 },
        -- Only after a kill (usable when the game allows it).
        victory_rush = { id = 34428, reactive = true },

        -- Arms
        -- Improved Mortal Strike: -1 second at 3/3.
        mortal_strike = { id = 47486, rage = 30, cooldown = 6,
            cooldownFn = function(spec) return 6 - spec:TalentRank("improved_mortal_strike") / 3 end },
        -- Glyph of Rending: +6 seconds.
        rend = { id = 47465, rage = 10,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "rend", spec:HasGlyph("rending") and 21 or 15) end },
        -- Battle Stance; after the target dodges, or with Taste for Blood.
        -- Unrelenting Assault: -2 seconds cooldown per rank.
        overpower = { id = 7384, rage = 5, cooldown = 5, requiresForm = 1, reactive = true,
            usableWith = "taste_for_blood", consumes = { "taste_for_blood" },
            cooldownFn = function(spec) return 5 - 2 * spec:TalentRank("unrelenting_assault") end },
        -- 6 seconds of spinning: nothing else can be used meanwhile.
        -- Glyph of Bladestorm: -15 seconds.
        bladestorm = { id = 46924, rage = 25, cooldown = 90,
            cooldownFn = function(spec) return spec:HasGlyph("bladestorm") and 75 or 90 end,
            apply = function(s, spec, fx) s.gcdEnd = math.max(s.gcdEnd, s.now + 6) end },
        -- Glyph of Sweeping Strikes: no rage cost.
        sweeping_strikes = { id = 12328, cooldown = 30, offGcd = true,
            rageCost = function(spec) return spec:HasGlyph("sweeping_strikes") and 0 or 30 end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "sweeping_strikes", 10) end },
    },

    auras = {
        bloodsurge = { id = 46916 },          -- "Slam!": next Slam is instant
        taste_for_blood = { id = 60503 },     -- Overpower usable
        sudden_death = { id = 52437 },        -- Execute usable at any health
        sweeping_strikes = { id = 12328 },
        rend = { id = 47465, debuff = true },
        death_wish = { id = 12292 },
        recklessness = { id = 1719 },
        berserker_rage = { id = 18499 },
        battle_shout = { id = 47436 },
        commanding_shout = { id = 47440 },
        blessing_of_might = { ids = { 48932, 48934 } }, -- replaces Battle Shout
        bloodlust = { ids = { 2825, 32182 } },
    },
})
