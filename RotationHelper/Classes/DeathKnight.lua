local ADDON_NAME, ns = ...

-- Death Knight data for 3.3.5a. Spell IDs are the highest rank; aura and
-- cooldown lookups go through these IDs (or their localized names).
--
-- Ability fields:
--   id        spell ID (highest rank)
--   runes     rune cost by type: blood / unholy / frost
--   rp        runic power cost (negative = generates)
--   cooldown  base cooldown in seconds (0 = none)
--   offGcd    true if the ability does not trigger the GCD
--   rpCost    function(spec) -> runic power cost, when it depends on talents/glyphs
--   rpGain    function(spec) -> extra runic power generated
--   freeWith  aura key; while that buff is up the ability costs no runes (and uses it up)
--   consumes  buff keys the ability uses up
--   convert   { runes = { base = true }, talents = { ... } }: spent runes of those
--             base types become death runes if any listed talent is at rank 3
--   apply     function(state, spec, Effects): the ability's other effects, for prediction
--   requiresPet  true if it needs a living pet (Ghoul Frenzy)
--   reactive  true if only usable when the game says so (Rune Strike after a dodge or parry)

local EPIDEMIC_PER_RANK = 3 -- seconds added to disease duration
local DISEASE_DURATION = 15

local function DiseaseDuration(spec)
    return DISEASE_DURATION + EPIDEMIC_PER_RANK * spec:TalentRank("epidemic")
end

-- Chill of the Grave: +2.5 runic power per rank on Icy Touch, Howling Blast, Obliterate.
local function ChillOfTheGrave(spec)
    return 2.5 * spec:TalentRank("chill_of_the_grave")
end

-- Dirge: +2.5 runic power per rank on Death Strike, Obliterate, Plague Strike, Scourge Strike.
local function Dirge(spec)
    return 2.5 * spec:TalentRank("dirge")
end

local BLOOD_TO_DEATH = { runes = { blood = true }, talents = { "blood_of_the_north", "reaping" } }
local FROST_UNHOLY_TO_DEATH = { runes = { frost = true, unholy = true }, talents = { "death_rune_mastery" } }

ns.RegisterClass("DEATHKNIGHT", {
    -- A spell with no cooldown and no rune cost; its cooldown is the GCD.
    gcdSpell = 49895, -- Death Coil
    usesRunes = true,
    interrupt = "mind_freeze", -- shown by the interrupt icon
    -- Procs worth highlighting when the recommended ability spends them.
    procs = { "killing_machine", "freezing_fog" },
    -- For the fight review: cooldowns whose unused time is reported, and
    -- debuffs whose uptime on the target is measured.
    majorCooldowns = { "unbreakable_armor", "empower_rune_weapon", "summon_gargoyle", "deathchill",
        "dancing_rune_weapon", "hysteria" },
    reviewDebuffs = { "frost_fever", "blood_plague" },
    -- Diseases Pestilence spreads; tracked on other enemies (Engine/Dots.lua).
    spreadDots = { "frost_fever", "blood_plague" },

    -- Random procs for the simulator (Engine/Sim.lua). Either `on` (a chance
    -- when one of those abilities is used) or `perMinute` (random times).
    simProcs = {
        -- Rime: Obliterate has a 5% chance per rank to make the next Howling
        -- Blast free and reset its cooldown.
        { aura = "freezing_fog", duration = 15, on = { obliterate = true },
          chance = function(spec) return 0.05 * spec:TalentRank("rime") end,
          resetCooldown = "howling_blast" },
        -- Killing Machine: 1 proc per minute per rank from melee attacks.
        { aura = "killing_machine", duration = 30,
          perMinute = function(spec) return spec:TalentRank("killing_machine") end },
    },

    specs = { blood = true, frost = true, unholy = true },

    abilities = {
        icy_touch = { id = 49909, runes = { frost = 1 }, rp = -10, rpGain = ChillOfTheGrave,
            consumes = { "killing_machine", "deathchill" },
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "frost_fever", DiseaseDuration(spec)) end },
        plague_strike = { id = 49921, runes = { unholy = 1 }, rp = -10, rpGain = Dirge,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "blood_plague", DiseaseDuration(spec)) end },
        obliterate = { id = 51425, runes = { frost = 1, unholy = 1 }, rp = -15,
            rpGain = function(spec) return ChillOfTheGrave(spec) + Dirge(spec) end,
            consumes = { "deathchill" }, convert = FROST_UNHOLY_TO_DEATH },
        scourge_strike = { id = 55271, runes = { frost = 1, unholy = 1 }, rp = -15, rpGain = Dirge },
        frost_strike = { id = 55268, rp = 40,
            rpCost = function(spec) return spec:HasGlyph("frost_strike") and 32 or 40 end,
            consumes = { "killing_machine", "deathchill" } },
        howling_blast = { id = 51411, runes = { frost = 1, unholy = 1 }, rp = -15, cooldown = 8,
            rpGain = ChillOfTheGrave, freeWith = "freezing_fog",
            consumes = { "killing_machine", "deathchill" },
            apply = function(s, spec, fx)
                if spec:HasGlyph("howling_blast") then
                    fx.ApplyDebuff(s, "frost_fever", DiseaseDuration(spec))
                end
            end },
        blood_strike = { id = 49930, runes = { blood = 1 }, rp = -10, convert = BLOOD_TO_DEATH,
            -- Desolation: +5% damage for 20s.
            apply = function(s, spec, fx)
                if spec:TalentRank("desolation") > 0 then fx.ApplyBuff(s, "desolation", 20) end
            end },
        pestilence = { id = 50842, runes = { blood = 1 }, rp = -10, convert = BLOOD_TO_DEATH,
            -- Spreads the target's diseases to the other enemies; with Glyph
            -- of Disease it also refreshes them on the target.
            apply = function(s, spec, fx)
                fx.SpreadDots(s, DiseaseDuration(spec))
                if spec:HasGlyph("disease") then
                    for _, key in ipairs({ "frost_fever", "blood_plague" }) do
                        if fx.DebuffUp(s, key) then fx.ApplyDebuff(s, key, DiseaseDuration(spec)) end
                    end
                end
            end },
        blood_boil = { id = 49941, runes = { blood = 1 }, rp = -10,
            convert = { runes = { blood = true }, talents = { "reaping" } } },
        death_and_decay = { id = 49938, runes = { blood = 1, unholy = 1, frost = 1 }, rp = -15, cooldown = 30 },
        death_coil = { id = 49895, rp = 40 },
        death_strike = { id = 49924, runes = { frost = 1, unholy = 1 }, rp = -15, rpGain = Dirge,
            convert = FROST_UNHOLY_TO_DEATH },
        horn_of_winter = { id = 57623, rp = -10, cooldown = 20,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "horn_of_winter", 120) end },
        blood_tap = { id = 45529, cooldown = 60, offGcd = true,
            apply = function(s, spec, fx) fx.BloodTap(s) end },
        unbreakable_armor = { id = 51271, runes = { frost = 1 }, rp = -10, cooldown = 60, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "unbreakable_armor", 20) end },
        empower_rune_weapon = { id = 47568, rp = -25, cooldown = 300, offGcd = true,
            apply = function(s, spec, fx) fx.ActivateAllRunes(s) end },
        deathchill = { id = 49796, cooldown = 120, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "deathchill", 30) end },
        army_of_the_dead = { id = 42650, runes = { blood = 1, unholy = 1, frost = 1 }, cooldown = 600 },
        raise_dead = { id = 46584, cooldown = 180,
            apply = function(s, spec, fx) fx.SummonPet(s) end },
        mind_freeze = { id = 47528, rp = 20, cooldown = 10, offGcd = true },

        -- Unholy
        ghoul_frenzy = { id = 63560, runes = { unholy = 1 }, rp = -10, cooldown = 10, requiresPet = true },
        summon_gargoyle = { id = 49206, rp = 60, cooldown = 180 },
        bone_shield = { id = 49222, runes = { unholy = 1 }, rp = -10, cooldown = 60,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "bone_shield", 300) end },

        -- Blood
        heart_strike = { id = 55262, runes = { blood = 1 }, rp = -10 },
        -- Hits with the next swing, only after a dodge or parry (tanking).
        rune_strike = { id = 56815, rp = 20, offGcd = true, reactive = true },
        dancing_rune_weapon = { id = 49028, rp = 60, cooldown = 90 },
        hysteria = { id = 49016, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "hysteria", 30) end },
        rune_tap = { id = 48982, runes = { blood = 1 }, cooldown = 60, offGcd = true },
        vampiric_blood = { id = 55233, runes = { blood = 1 }, cooldown = 60, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "vampiric_blood", 10) end },
    },

    -- Buffs are read from the player, debuffs from the target. Debuffs only
    -- count when we applied them, unless anySource is set.
    auras = {
        frost_fever = { id = 55095, debuff = true },
        blood_plague = { id = 55078, debuff = true },
        killing_machine = { id = 51124 },
        freezing_fog = { id = 59052 }, -- Rime proc: free Howling Blast
        unbreakable_armor = { id = 51271 },
        deathchill = { id = 49796 },
        horn_of_winter = { ids = { 57623, 57330 } },
        blood_presence = { id = 48266 },
        frost_presence = { id = 48263 },
        unholy_presence = { id = 48265 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
        desolation = { id = 66803 },           -- from Blood Strike, Unholy talent
        bone_shield = { id = 49222 },
        hysteria = { id = 49016 },
        vampiric_blood = { id = 55233 },
    },
})
