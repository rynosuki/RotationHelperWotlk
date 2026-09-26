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

ns.RegisterClass("SHAMAN", {
    -- A spell with no cooldown; its cooldown is the GCD.
    gcdSpell = 324, -- Lightning Shield
    baseMana = 4396, -- level 80
    usesTotems = true,
    prepullImbues = true, -- the checklist wants weapon imbues on
    interrupt = "wind_shear",
    procs = { "maelstrom_weapon" },
    majorCooldowns = { "feral_spirit" },
    reviewDebuffs = { enhancement = { "flame_shock" } },

    -- For the simulator: mana with ~80 per second of regen (Shamanistic Rage,
    -- mp5, Replenishment), and Maelstrom Weapon stacks from melee hits:
    -- about 2.5 stacks a minute per rank.
    simPower = { type = "mana", max = 20000, start = 20000, regen = 80 },
    simProcs = {
        { aura = "maelstrom_weapon", duration = 30, maxStacks = 5,
          perMinute = function(spec) return 2.5 * spec:TalentRank("maelstrom_weapon") end },
    },

    specs = { elemental = false, enhancement = true, restoration = false },

    abilities = {
        stormstrike = { id = 17364, mana = 8, cooldown = 8 },
        lava_lash = { id = 60103, mana = 4, cooldown = 6 },
        -- The shocks share one cooldown.
        earth_shock = { id = 49231, mana = 18, cooldown = 6, cooldownFn = ShockCooldown, cooldownGroup = "shock" },
        flame_shock = { id = 49233, mana = 17, cooldown = 6, cooldownFn = ShockCooldown, cooldownGroup = "shock",
            apply = function(s, spec, fx) fx.ApplyDebuff(s, "flame_shock", 18) end },
        frost_shock = { id = 49236, mana = 18, cooldown = 6, cooldownFn = ShockCooldown, cooldownGroup = "shock" },
        -- 2.5s / 2s casts, instant with 5 Maelstrom Weapon stacks (the rotation
        -- only uses them then); they use the stacks up.
        lightning_bolt = { id = 49238, mana = 10, consumes = { "maelstrom_weapon" } },
        chain_lightning = { id = 49271, mana = 26, cooldown = 6, consumes = { "maelstrom_weapon" } },
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
    },

    auras = {
        maelstrom_weapon = { id = 53817 },
        lightning_shield = { id = 49281 },
        shamanistic_rage = { id = 30823 },
        flame_shock = { id = 49233, debuff = true },
        bloodlust = { ids = { 2825, 32182 } }, -- Bloodlust / Heroism
    },
})
