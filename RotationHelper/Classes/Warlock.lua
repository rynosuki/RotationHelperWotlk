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

-- Backdraft: after Conflagrate, the next 3 Destruction spells cast 10% faster
-- per rank, with a GCD 10% shorter per rank. Used by the cast time and GCD
-- (gcdFn) of Immolate, Incinerate and Chaos Bolt.
local function Backdraft(spec, s, base)
    local rec = s and s.buffs.backdraft
    if rec and rec.expires > s.now then return base * (1 - 0.1 * spec:TalentRank("backdraft")) end
    return base
end

local function BackdraftGcd(spec, s, gcd) return Backdraft(spec, s, gcd) end

local function UseBackdraft(s, spec, fx)
    fx.ConsumeStack(s, "backdraft")
end

ns.RegisterClass("WARLOCK", {
    -- Dots counted on other enemies (active_dot.X, "2/4 CORR" on the status line).
    trackDots = { affliction = { "corruption", "unstable_affliction", "curse_of_agony", hint = "CORR" } },
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 687, -- Demon Skin
    baseMana = 3856, -- level 80
    hasteProbe = "searing_pain", -- a 1.5s cast no talent changes: its cast time in game gives the spell haste
    procs = { "decimation", "molten_core" },
    majorCooldowns = { "metamorphosis" },
    prepullPet = true, -- the checklist wants your demon out
    reviewDebuffs = {
        affliction = { "haunt", "unstable_affliction", "corruption", "curse_of_agony" },
        destruction = { "immolate" },
        demonology = { "corruption", "immolate" },
    },

    -- For the simulator: mana with ~120 per second of regen (Replenishment,
    -- Glyph of Life Tap); Life Tap in the rotation adds more.
    simPower = { type = "mana", max = 20000, start = 20000, regen = 120 },
    -- Demonology: Molten Core (three charges) from Corruption ticks, about
    -- one a minute per rank.
    simProcs = {
        { aura = "molten_core", duration = 15, stacks = 3,
          perMinute = function(spec) return spec:TalentRank("molten_core") end },
    },

    specs = { affliction = true, demonology = true, destruction = true },

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
        -- the filler. Cut after a tick when a DoT or Haunt is due.
        drain_soul = { id = 47855, mana = 14, channel = 15, ticks = 5, apply = EverlastingAffliction },
        seed_of_corruption = { id = 47836, mana = 34, castTime = 2 },
        searing_pain = { id = 47815, mana = 8, castTime = 1.5 },
        -- Health into mana (roughly 10% of your mana bar with talents and gear).
        life_tap = { id = 57946,
            apply = function(s, spec, fx) s.power = math.min(s.powerMax, s.power + s.powerMax * 0.1) end },
        fel_armor = { id = 47893, mana = 28,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "fel_armor", 1800) end },

        -- Destruction (Bane: -0.1 seconds per rank on Immolate and Chaos Bolt)
        immolate = { id = 47811, mana = 17, castTime = 2,
            castTimeFn = function(spec, s) return Backdraft(spec, s, 2 - 0.1 * spec:TalentRank("bane")) end,
            gcdFn = BackdraftGcd,
            apply = function(s, spec, fx)
                UseBackdraft(s, spec, fx)
                fx.ApplyDebuff(s, "immolate", 15)
            end },
        -- Needs Immolate on the target; uses it up unless glyphed. Starts Backdraft.
        conflagrate = { id = 17962, mana = 16, cooldown = 10,
            apply = function(s, spec, fx)
                if not spec:HasGlyph("conflagrate") then
                    local rec = s.debuffs.immolate
                    if rec then rec.expires = s.now end
                end
                if spec:TalentRank("backdraft") > 0 then fx.ApplyBuff(s, "backdraft", 15, 3) end
            end },
        -- Glyph of Chaos Bolt: -2 seconds cooldown.
        chaos_bolt = { id = 59172, mana = 7, castTime = 2.5, cooldown = 12,
            cooldownFn = function(spec) return spec:HasGlyph("chaos_bolt") and 10 or 12 end,
            castTimeFn = function(spec, s) return Backdraft(spec, s, 2.5 - 0.1 * spec:TalentRank("bane")) end,
            gcdFn = BackdraftGcd,
            apply = UseBackdraft },
        -- Emberstorm: -0.05 seconds per rank; Molten Core: -10% per rank (and
        -- one of its charges used).
        incinerate = { id = 47838, mana = 14, castTime = 2.5, usesStack = "molten_core",
            castTimeFn = function(spec, s)
                local base = Backdraft(spec, s, 2.5 - 0.05 * spec:TalentRank("emberstorm"))
                local rec = s and s.buffs.molten_core
                if rec and rec.expires > s.now then base = base * (1 - 0.1 * spec:TalentRank("molten_core")) end
                return base
            end,
            gcdFn = BackdraftGcd,
            apply = UseBackdraft },
        -- Demonology
        -- Nemesis: -10% cooldown per rank.
        metamorphosis = { id = 47241, cooldown = 180,
            cooldownFn = function(spec) return 180 * (1 - 0.1 * spec:TalentRank("nemesis")) end,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "metamorphosis", 30) end },
        -- Only in Metamorphosis (the rotation checks).
        immolation_aura = { id = 50589, mana = 64, cooldown = 30 },
        -- A 6 second cast (Bane: -0.4 per rank); Decimation (target below 35%)
        -- makes it 40% faster and free of a soul shard.
        soul_fire = { id = 47825, mana = 9, castTime = 6,
            castTimeFn = function(spec, s)
                local base = 6 - 0.4 * spec:TalentRank("bane")
                local rec = s and s.buffs.decimation
                if rec and rec.expires > s.now then base = base * 0.6 end
                return base
            end },
        -- Needs your demon.
        demonic_empowerment = { id = 47193, mana = 6, cooldown = 60, offGcd = true, requiresPet = true },
        -- A minute long; only worth it on targets that live that long.
        curse_of_doom = { id = 47867, mana = 15, cooldown = 60,
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "curse_of_doom", 60) end },
    },

    auras = {
        haunt = { id = 59164, debuff = true },
        corruption = { id = 47813, debuff = true },
        unstable_affliction = { id = 47843, debuff = true },
        curse_of_agony = { id = 47864, debuff = true },
        -- Anyone's (or a Moonkin's Earth and Moon, or an Unholy DK's Ebon Plague) counts.
        curse_of_the_elements = { ids = { 47865, 60433, 51735 }, debuff = true, anySource = true },
        fel_armor = { id = 47893 },
        immolate = { id = 47811, debuff = true },
        curse_of_doom = { id = 47867, debuff = true },
        backdraft = { id = 54277 },
        metamorphosis = { id = 47241 },
        decimation = { id = 63167 },
        molten_core = { id = 71165 },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
