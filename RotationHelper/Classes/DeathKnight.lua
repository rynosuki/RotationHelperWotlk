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
--   freeWith  aura key; while that buff is up the ability costs no runes
ns.RegisterClass("DEATHKNIGHT", {
    -- A spell with no cooldown and no rune cost; its cooldown is the GCD.
    gcdSpell = 49895, -- Death Coil
    usesRunes = true,

    specs = { blood = false, frost = true, unholy = false },

    abilities = {
        icy_touch = { id = 49909, runes = { frost = 1 }, rp = -10 },
        plague_strike = { id = 49921, runes = { unholy = 1 }, rp = -10 },
        obliterate = { id = 51425, runes = { frost = 1, unholy = 1 }, rp = -15 },
        frost_strike = { id = 55268, rp = 40,
            rpCost = function(spec) return spec:HasGlyph("frost_strike") and 32 or 40 end },
        howling_blast = { id = 51411, runes = { frost = 1, unholy = 1 }, rp = -15, cooldown = 8,
            freeWith = "freezing_fog" },
        blood_strike = { id = 49930, runes = { blood = 1 }, rp = -10 },
        pestilence = { id = 50842, runes = { blood = 1 }, rp = -10 },
        blood_boil = { id = 49941, runes = { blood = 1 }, rp = -10 },
        death_and_decay = { id = 49938, runes = { blood = 1, unholy = 1, frost = 1 }, rp = -15, cooldown = 30 },
        death_coil = { id = 49895, rp = 40 },
        death_strike = { id = 49924, runes = { frost = 1, unholy = 1 }, rp = -15 },
        horn_of_winter = { id = 57623, rp = -10, cooldown = 20 },
        blood_tap = { id = 45529, cooldown = 60, offGcd = true },
        unbreakable_armor = { id = 51271, runes = { frost = 1 }, rp = -10, cooldown = 60, offGcd = true },
        empower_rune_weapon = { id = 47568, rp = -25, cooldown = 300, offGcd = true },
        deathchill = { id = 49796, cooldown = 120, offGcd = true },
        army_of_the_dead = { id = 42650, runes = { blood = 1, unholy = 1, frost = 1 }, cooldown = 600 },
        raise_dead = { id = 46584, cooldown = 180 },
        mind_freeze = { id = 47528, rp = 20, cooldown = 10, offGcd = true },
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
    },
})
