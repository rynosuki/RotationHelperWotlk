-- Frost Mage: Brain Freeze (instant free Frostfire Bolt), Fingers of Frost
-- (Deep Freeze, two charges), Water Elemental, Icy Veins and Cold Snap.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Frostbolt", "Frostfire Bolt", "Ice Lance", "Deep Freeze", "Icy Veins", "Cold Snap",
    "Summon Water Elemental", "Mirror Image", "Evocation", "Molten Armor", "Counterspell", "Arcane Intellect", "Scorch" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "MAGE" })
    s.talentTabs = {
        { name = "Arcane", talents = { { "Arcane Focus", 3 } } },
        { name = "Fire", talents = {} },
        { name = "Frost", talents = { { "Improved Frostbolt", 5 }, { "Fingers of Frost", 2 }, { "Brain Freeze", 3 },
            { "Deep Freeze", 1 }, { "Ice Floes", 3 }, { "Icy Veins", 1 }, { "Cold Snap", 1 }, { "Summon Water Elemental", 1 } } },
    }
    s.power = { type = 0, current = 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s.petAlive = opts.noPet ~= true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Molten Armor", spellId = 43046, duration = 1800, expires = s.time + 1800 })
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

test("frost mage: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "frost", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Frost (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("Frostbolt (2.5s with Improved Frostbolt); the Water Elemental first", function()
    local s = Fight()
    eq(Queue(s, 2), "frostbolt, frostbolt +2.5", "filler")
    s = Fight({ noPet = true })
    eq(Queue(s, 1), "summon_water_elemental", "no pet")
end)

test("Brain Freeze: instant, free Frostfire Bolt", function()
    local s, RH = Fight()
    s:AddAura("player", { name = "Fireball!", spellId = 57761, duration = 15, expires = s.time + 15 })
    eq(Queue(s, 2), "frostfire_bolt, frostbolt +1.5", "instant")
    eq(RH.recommendations[1].usesProc, "brain_freeze", "glows")
    local st = s.ns.State:Reset()
    eq(s.ns.Abilities.PowerCost(RH.classData.abilities.frostfire_bolt, st), 0, "free")
end)

test("Fingers of Frost: Deep Freeze, one of the two charges", function()
    local s, RH = Fight()
    falsy(Queue(s, 1) == "deep_freeze", "not frozen")
    s:AddAura("player", { name = "Fingers of Frost", spellId = 74396, count = 2, duration = 15, expires = s.time + 15 })
    eq(Queue(s, 1), "deep_freeze", "Fingers of Frost")
    s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, "deep_freeze", v.now)
    eq(v.buffs.fingers_of_frost.stacks, 1, "one charge left")
end)

test("cooldowns: Icy Veins, Cold Snap brings it back", function()
    local s, RH = Fight({ cooldowns = true })
    eq(Queue(s, 2), "icy_veins, mirror_image", "Icy Veins (off the GCD), Mirror Image")
    s.cooldowns["Icy Veins"] = { s.time, 144 }
    s.cooldowns["Mirror Image"] = { s.time, 180 }
    eq(Queue(s, 2), "cold_snap, icy_veins", "Cold Snap, then Icy Veins again")
    eq(s.ns.Abilities.CooldownDuration(RH.classData.abilities.icy_veins), 144, "Ice Floes 3/3")
end)

test("simulator: Frost with Brain Freeze and Fingers of Frost", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy(summary.gcdUsage > 95, "time spent casting " .. summary.gcdUsage)
    truthy((casts.frostbolt or 0) > 18, "Frostbolt per minute " .. tostring(casts.frostbolt))
    truthy((casts.frostfire_bolt or 0) > 0.5, "Frostfire Bolt per minute " .. tostring(casts.frostfire_bolt))
    truthy((casts.deep_freeze or 0) > 1, "Deep Freeze per minute " .. tostring(casts.deep_freeze))
end)
