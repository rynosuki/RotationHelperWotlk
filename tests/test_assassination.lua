-- Assassination Rogue: Mutilate (2 points), Envenom, Hunger for Blood and
-- its bleed, Cold Blood, Relentless Strikes energy.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Mutilate", "Garrote", "Envenom", "Hunger for Blood", "Cold Blood", "Slice and Dice", "Rupture",
    "Eviscerate", "Kick", "Sinister Strike", "Vanish" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Mutilate rogue in combat with a boss; `setUp` puts Slice and Dice and
-- Hunger for Blood up.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "ROGUE" })
    s.talentTabs = {
        { name = "Assassination", talents = { { "Mutilate", 1 }, { "Seal Fate", 5 }, { "Cold Blood", 1 },
            { "Hunger for Blood", 1 }, { "Focused Attacks", 3 }, { "Improved Slice and Dice", 2 }, { "Malice", 5 } } },
        { name = "Combat", talents = { { "Precision", 5 } } },
        { name = "Subtlety", talents = { { "Relentless Strikes", 5 }, { "Elusiveness", 2 } } },
    }
    if opts.overkill then table.insert(s.talentTabs[1].talents, { "Overkill", 1 }) end
    s.power = { type = 3, current = opts.energy or 100, max = 100 }
    s.combo = opts.combo or 0
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if opts.setUp then
        s:AddAura("player", { name = "Slice and Dice", spellId = 6774, duration = 30, expires = s.time + 20 })
        s:AddAura("player", { name = "Hunger For Blood", spellId = 63848, duration = 60, expires = s.time + 50 })
    end
    return s, RH
end

local function Queue(s, count)
    s:Tick(0.1)
    local out = {}
    for i, e in ipairs(s.env.RotationHelper.recommendations or {}) do
        if i > count then break end
        out[#out + 1] = e.wait < 0.05 and e.name or ("%s +%.1f"):format(e.name, e.wait)
    end
    return table.concat(out, ", ")
end

test("assassination: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(s.ns.Spec.key, "assassination", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Assassination (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("Mutilate builds 2 points; Envenom at 3+ by default and refreshes before expiry", function()
    local s = Fight({ setUp = true, combo = 2 })
    eq(Queue(s, 1), "mutilate", "2 points")
    s.ns.State:Reset()
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "mutilate", st.now)
    eq(st.comboPoints, 4, "4 points")
    s.combo = 3
    eq(Queue(s, 1), "envenom", "3 points by default")
    s.combo = 3
    s:AddAura("player", { name = "Envenom", spellId = 57993, duration = 1, expires = s.time + 0.4 })
    eq(Queue(s, 1), "envenom", "refresh before Envenom expires")
end)

test("assassination opener: Garrote from stealth when no bleed is active", function()
    local s = Fight({ combo = 0 })
    s:AddAura("player", { name = "Stealth", spellId = 1784, duration = 15, expires = s.time + 10 })
    eq(Queue(s, 1), "garrote", "stealth opener")
end)

test("Hunger for Blood needs a bleed: Rupture when there's none", function()
    local s = Fight({ combo = 4 })
    s:AddAura("player", { name = "Slice and Dice", spellId = 6774, duration = 30, expires = s.time + 20 })
    eq(Queue(s, 2), "rupture, hunger_for_blood +1.0", "no bleed: Rupture, then Hunger for Blood")
    s = Fight({ combo = 4 })
    s:AddAura("player", { name = "Slice and Dice", spellId = 6774, duration = 30, expires = s.time + 20 })
    s:AddAura("target", { name = "Deep Wounds", spellId = 43104, duration = 6, expires = s.time + 5, harmful = true,
        caster = "raid4" })
    eq(Queue(s, 2), "hunger_for_blood, envenom +1.0", "a warrior's Deep Wounds is enough")
end)

test("Relentless Strikes: finishers give energy back on average", function()
    local s = Fight({ setUp = true, combo = 5, energy = 50 })
    s.ns.State:Reset()
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "envenom", st.now)
    near(st.power, 50 - 35 + 25 * 0.2 * 5, "35 spent, 25 back on average at 5 points")
end)

test("Cold Blood before Envenom", function()
    local s = Fight({ setUp = true, combo = 5, cooldowns = true })
    eq(Queue(s, 2), "cold_blood, envenom", "cooldowns")
end)

test("simulator: Assassination", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.mutilate or 0) > 8, "Mutilate per minute " .. tostring(casts.mutilate))
    truthy((casts.envenom or 0) > 1.5, "Envenom per minute " .. tostring(casts.envenom))
    truthy((casts.hunger_for_blood or 0) >= 0.9, "Hunger for Blood per minute " .. tostring(casts.hunger_for_blood))
end)

---------------------------------------------------------------------------
-- Vanish for Overkill
---------------------------------------------------------------------------
test("Vanish with Overkill when energy is low (a big cooldown)", function()
    local s, RH = Fight({ setUp = true, combo = 2, energy = 30, overkill = true, cooldowns = true })
    s.cooldowns["Cold Blood"] = { s.time, 180 }
    eq(Queue(s, 1), "vanish", "30 energy: Vanish")
    near(s.ns.Abilities.CooldownDuration(RH.classData.abilities.vanish), 120, "Elusiveness 2/2")
    s = Fight({ setUp = true, combo = 2, energy = 80, overkill = true, cooldowns = true })
    falsy(Queue(s, 1) == "vanish", "plenty of energy: not now")
    s = Fight({ setUp = true, combo = 2, energy = 30, cooldowns = true })
    falsy(Queue(s, 3):find("vanish", 1, true), "no Overkill talent")
    s = Fight({ setUp = true, combo = 2, energy = 30, overkill = true })
    falsy(Queue(s, 3):find("vanish", 1, true), "cooldowns off")
end)

test("Overkill: 30% faster energy, in the game and in the prediction", function()
    local s, RH = Fight({ setUp = true, energy = 0, overkill = true })
    local base = s.ns.State:Reset().powerRegen
    s:AddAura("player", { name = "Overkill", spellId = 58427, duration = 20, expires = s.time + 20 })
    local st = s.ns.State:Reset()
    eq(st.regenBoost, 1.3, "boost read from the buff")
    near(s.ns.Resources.PowerAt(st, st.now + 2), base * 1.3 * 2, "2 seconds of Overkill")
    s = Fight({ setUp = true, energy = 0, overkill = true })
    s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, "vanish", v.now)
    eq(v.buffs.overkill ~= nil, true, "Vanish starts Overkill")
    near(v.regenBoostUntil, v.now + 20, "for 20 seconds")
end)

test("overlapping energy boosts multiply until the first one ends", function()
    local s = Fight({ energy = 0 })
    s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    local fx = s.ns.Abilities.Effects
    fx.BoostRegen(v, 2, v.now + 15)   -- Adrenaline Rush
    fx.BoostRegen(v, 1.3, v.now + 20) -- Overkill
    near(v.regenBoost, 2.6, "both")
    near(v.regenBoostUntil, v.now + 15, "until the shorter one ends")
end)
