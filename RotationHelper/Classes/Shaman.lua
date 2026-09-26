local ADDON_NAME, ns = ...

-- Shaman data for 3.3.5a. Spell IDs are the highest rank; mana costs are
-- percentages of base mana (see Classes/Paladin.lua). Other fields:
--   cooldownGroup  abilities that share one cooldown (the shocks)
--   totem          the totem's element (fire, earth, water, air); with
--   totemDuration  how long it stays, for the prediction

-- Reverberation: -0.2 seconds per rank on the shocks.
local function ShockCooldown(spec)
    return 6 - 0.2 * spec:TalentRank("reverberation")
end

-- Lightning Bolt / Chain Lightning: instant with 5 Maelstrom Weapon stacks,
-- else the base cast minus Lightning Mastery (-0.1 seconds per rank).
local function MaelstromCast(spec, s, base)
    local rec = s and s.buffs.maelstrom_weapon
    if rec and rec.expires > s.now and rec.stacks >= 5 then return 0 end
    return base - 0.1 * spec:TalentRank("lightning_mastery")
end

ns.RegisterClass("SHAMAN", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 324, -- Lightning Shield
    baseMana = 4396, -- level 80
    usesTotems = true,
    hasteProbe = "lesser_healing_wave", -- a 1.5s cast no talent changes: its cast time in game gives the spell haste
    prepullImbues = true, -- the checklist wants weapon imbues on
    interrupt = "wind_shear",
    procs = { "maelstrom_weapon" },
    majorCooldowns = { "feral_spirit", "elemental_mastery", "fire_elemental_totem" },
    reviewDebuffs = { elemental = { "flame_shock" }, enhancement = { "flame_shock" } },

    -- For the simulator: mana regen per spec (Enhancement: Shamanistic Rage,
    -- mp5, Replenishment; Elemental: also Water Shield and Elemental Focus),
    -- and Maelstrom Weapon stacks from melee hits: about 2.5 stacks a minute
    -- per rank.
    simPower = {
        elemental = { type = "mana", max = 22000, start = 22000, regen = 220 },
        enhancement = { type = "mana", max = 20000, start = 20000, regen = 80 },
    },
    simProcs = {
        { aura = "maelstrom_weapon", duration = 30, maxStacks = 5,
          perMinute = function(spec) return 2.5 * spec:TalentRank("maelstrom_weapon") end },
    },

    specs = { elemental = true, enhancement = true, restoration = false },

    abilities = {
        stormstrike = { id = 17364, mana = 8, cooldown = 8 },
        lava_lash = { id = 60103, mana = 4, cooldown = 6 },
        -- The shocks share one cooldown.
        earth_shock = { id = 49231, mana = 18, cooldown = 6, cooldownFn = ShockCooldown, cooldownGroup = "shock" },
        flame_shock = { id = 49233, mana = 17, cooldown = 6, cooldownFn = ShockCooldown, cooldownGroup = "shock",
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "flame_shock", 18) end },
        frost_shock = { id = 49236, mana = 18, cooldown = 6, cooldownFn = ShockCooldown, cooldownGroup = "shock" },
        -- 2.5s / 2s casts (Lightning Mastery: -0.1 seconds per rank); instant with
        -- 5 Maelstrom Weapon stacks, which they use up.
        lightning_bolt = { id = 49238, mana = 10, castTime = 2.5, consumes = { "maelstrom_weapon" },
            castTimeFn = function(spec, s) return MaelstromCast(spec, s, 2.5) end },
        chain_lightning = { id = 49271, mana = 26, cooldown = 6, castTime = 2, consumes = { "maelstrom_weapon" },
            castTimeFn = function(spec, s) return MaelstromCast(spec, s, 2) end },
        -- Needs a fire totem (totem.fire.up). Improved Fire Nova: -2 seconds per rank.
        fire_nova = { id = 61657, mana = 22, cooldown = 10,
            cooldownFn = function(spec) return 10 - 2 * spec:TalentRank("improved_fire_nova") end },
        magma_totem = { id = 58734, mana = 27, totem = "fire", totemDuration = 20 },
        searing_totem = { id = 58704, mana = 7, totem = "fire", totemDuration = 60 },
        lightning_shield = { id = 49281,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "lightning_shield", 600, 3) end },
        feral_spirit = { id = 51533, mana = 12, cooldown = 180 },
        -- For 15 seconds every melee hit restores 30% of your attack power as
        -- mana; the prediction adds a rough half of your mana bar at once.
        shamanistic_rage = { id = 30823, cooldown = 60, offGcd = true,
            apply = function(s, spec, fx)
                fx.ApplyBuff(s, "shamanistic_rage", 15)
                s.power = math.min(s.powerMax, s.power + s.powerMax * 0.5)
            end },
        wind_shear = { id = 57994, mana = 9, cooldown = 6, offGcd = true },
        lesser_healing_wave = { id = 49276, mana = 15, castTime = 1.5 },

        -- Elemental
        -- Always crits on a target with your Flame Shock (the rotation checks it lasts the cast).
        lava_burst = { id = 60043, mana = 10, castTime = 2, cooldown = 8 },
        -- Restores 8% of your mana.
        thunderstorm = { id = 59159, cooldown = 45,
            apply = function(s, spec, fx) s.power = math.min(s.powerMax, s.power + s.powerMax * 0.08) end },
        elemental_mastery = { id = 16166, cooldown = 180, offGcd = true,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "elemental_mastery", 15) end },
        totem_of_wrath = { id = 57722, mana = 5, totem = "fire", totemDuration = 300 },
        fire_elemental_totem = { id = 2894, mana = 23, cooldown = 600, totem = "fire", totemDuration = 120 },
        water_shield = { id = 57960,
            apply = function(s, spec, fx) fx.ApplyBuff(s, "water_shield", 600, 3) end },
    },

    auras = {
        maelstrom_weapon = { id = 53817 },
        lightning_shield = { id = 49281 },
        water_shield = { id = 57960 },
        elemental_mastery = { id = 16166 },
        shamanistic_rage = { id = 30823 },
        flame_shock = { id = 49233, debuff = true },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
