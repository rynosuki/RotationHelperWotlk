-- Elemental Shaman: Flame Shock + Lava Burst, Lightning Mastery cast times,
-- Totem of Wrath, Thunderstorm for mana.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Lava Burst", "Lightning Bolt", "Chain Lightning", "Flame Shock", "Earth Shock", "Frost Shock",
    "Thunderstorm", "Elemental Mastery", "Totem of Wrath", "Fire Elemental Totem", "Water Shield", "Wind Shear",
    "Lesser Healing Wave", "Lightning Shield" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- An Elemental shaman in combat with a boss, Water Shield up; `setUp` puts
-- Flame Shock on the target (`fs` seconds left) and Totem of Wrath down.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "SHAMAN" })
    s.talentTabs = {
        { name = "Elemental", talents = { { "Lightning Mastery", 5 }, { "Elemental Mastery", 1 }, { "Thunderstorm", 1 },
            { "Totem of Wrath", 1 }, { "Lava Flows", 3 }, { "Reverberation", 5 } } },
        { name = "Enhancement", talents = { { "Ancestral Knowledge", 5 } } },
        { name = "Restoration", talents = {} },
    }
    s.power = { type = 0, current = opts.mana or 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Water Shield", spellId = 57960, count = 3, duration = 600, expires = s.time + 600 })
    if opts.setUp then
        s:AddAura("target", { name = "Flame Shock", spellId = 49233, duration = 18, expires = s.time + (opts.fs or 12), harmful = true })
        s.totems[1] = { "Totem of Wrath IV", s.time - 10, 300 }
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

local function Eval(s, text)
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local fn, message = s.ns.APL.Compiler.CompileExpression(text, resolve)
    if not fn then error("compile failed: " .. message, 2) end
    return fn(s.ns.State:Reset())
end

test("elemental: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "elemental", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Elemental (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Totem of Wrath, Flame Shock, Lava Burst, Lightning Bolt", function()
    local s = Fight()
    eq(Queue(s, 4), "totem_of_wrath, flame_shock +1.5, lava_burst +3.0, lightning_bolt +5.0", "opener")
    near(Eval(s, "action.lightning_bolt.cast_time"), 2.0, "Lightning Mastery 5/5")
end)

test("Lava Burst only while Flame Shock lasts the cast", function()
    local s = Fight({ setUp = true, fs = 10 })
    eq(Queue(s, 1), "lava_burst", "10s left")
    s = Fight({ setUp = true, fs = 1.5 })
    falsy(Queue(s, 1) == "lava_burst", "1.5s left: it would land after")
end)

test("Chain Lightning on 2+ targets; Earth Shock while moving", function()
    local s, RH = Fight({ setUp = true })
    s.cooldowns["Lava Burst"] = { s.time, 8 }
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Queue(s, 1), "chain_lightning", "AoE")
    RH.db.profile.toggles.aoeMode = "single"
    s.speed = 7
    eq(Queue(s, 1), "earth_shock", "moving")
end)

test("Thunderstorm for mana; cooldowns", function()
    local s = Fight({ setUp = true, mana = 14000 })
    eq(Queue(s, 1), "thunderstorm", "70% mana")
    s = Fight({ setUp = true, cooldowns = true })
    eq(Queue(s, 2), "elemental_mastery, fire_elemental_totem", "Elemental Mastery (off the GCD), Fire Elemental")
end)

test("simulator: Elemental", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy(summary.gcdUsage > 95, "time spent casting " .. summary.gcdUsage)
    truthy((casts.lava_burst or 0) > 5, "Lava Burst per minute " .. tostring(casts.lava_burst))
    truthy((casts.lightning_bolt or 0) > 15, "Lightning Bolt per minute " .. tostring(casts.lightning_bolt))
    truthy(summary.debuffs[1] and summary.debuffs[1].uptime > 85, "Flame Shock uptime")
end)
