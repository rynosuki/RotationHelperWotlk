-- Arcane Mage: Arcane Blast stacks (a debuff on you) raising its cost,
-- Missile Barrage, Presence of Mind, the mana threshold.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Arcane Blast", "Arcane Missiles", "Arcane Barrage", "Arcane Power", "Presence of Mind",
    "Mirror Image", "Evocation", "Molten Armor", "Counterspell", "Arcane Intellect", "Scorch", "Fireball" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "MAGE" })
    s.talentTabs = {
        { name = "Arcane", talents = { { "Missile Barrage", 5 }, { "Arcane Flows", 2 }, { "Arcane Power", 1 },
            { "Presence of Mind", 1 }, { "Arcane Empowerment", 3 } } },
        { name = "Fire", talents = { { "Improved Fireball", 2 } } },
        { name = "Frost", talents = {} },
    }
    s.power = { type = 0, current = opts.mana or 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Molten Armor", spellId = 43046, duration = 1800, expires = s.time + 1800 })
    if opts.stacks then
        s:AddAura("player", { name = "Arcane Blast", spellId = 36032, count = opts.stacks, duration = 6,
            expires = s.time + 5, harmful = true })
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

test("arcane: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(s.ns.Spec.key, "arcane", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Arcane (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("Arcane Blast stacks are read from the debuff on you, and raise its cost", function()
    local s, RH = Fight({ stacks = 3 })
    eq(Eval(s, "buff.arcane_blast.stack"), 3, "3 stacks (a harmful aura on the player)")
    local st = s.ns.State:Reset()
    near(s.ns.Abilities.PowerCost(RH.classData.abilities.arcane_blast, st), 0.07 * 3268 * (1 + 1.75 * 3), "cost")
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, "arcane_blast", v.now)
    eq(v.buffs.arcane_blast.stacks, 4, "a fourth stack")
    s.ns.Abilities.Apply(v, "arcane_blast", v.now + 2.5)
    eq(v.buffs.arcane_blast.stacks, 4, "four at most")
end)

test("above 35% mana: Arcane Blast; below: 4 stacks, then Arcane Missiles", function()
    local s = Fight({ stacks = 4 })
    eq(Queue(s, 2), "arcane_blast, arcane_blast +2.5", "full mana")
    s = Fight({ stacks = 4, mana = 6000 })
    eq(Queue(s, 2), "arcane_missiles, arcane_blast +5.0", "30% mana: spend the stacks (5s channel)")
    s = Fight({ mana = 6000 })
    eq(Queue(s, 4), "arcane_blast, arcane_blast +2.5, arcane_blast +5.0, arcane_blast +7.5", "build 4 first")
end)

test("Missile Barrage: fast free Arcane Missiles at 4 stacks", function()
    local s, RH = Fight({ stacks = 4 })
    s:AddAura("player", { name = "Missile Barrage", spellId = 44401, duration = 15, expires = s.time + 15 })
    eq(Queue(s, 2), "arcane_missiles, arcane_blast +2.5", "2.5s channel")
    eq(RH.recommendations[1].usesProc, "missile_barrage", "glows")
    local st = s.ns.State:Reset()
    eq(s.ns.Abilities.PowerCost(RH.classData.abilities.arcane_missiles, st), 0, "free")
    s = Fight({ stacks = 2 })
    s:AddAura("player", { name = "Missile Barrage", spellId = 44401, duration = 15, expires = s.time + 15 })
    eq(Queue(s, 1), "arcane_blast", "not before 4 stacks")
end)

test("cooldowns: Arcane Power, then Presence of Mind makes Arcane Blast instant", function()
    local s = Fight({ cooldowns = true })
    eq(Queue(s, 4), "arcane_power, presence_of_mind, mirror_image, arcane_blast +1.5", "cooldowns")
    s:AddAura("player", { name = "Presence of Mind", spellId = 12043, duration = 0, expires = 0 })
    eq(Eval(s, "action.arcane_blast.cast_time"), 0, "instant")
    s.speed = 7
    s.cooldowns["Arcane Power"] = { s.time, 120 }
    s.cooldowns["Mirror Image"] = { s.time, 180 }
    s.cooldowns["Presence of Mind"] = { s.time, 84 }
    eq(Queue(s, 1), "arcane_blast", "even while moving")
end)

test("moving: Arcane Barrage", function()
    local s = Fight({ stacks = 2 })
    s.speed = 7
    eq(Queue(s, 1), "arcane_barrage", "moving")
end)

test("simulator: Arcane burns and conserves mana", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy(summary.gcdUsage > 95, "time spent casting " .. summary.gcdUsage)
    truthy((casts.arcane_blast or 0) > 15, "Arcane Blast per minute " .. tostring(casts.arcane_blast))
    truthy((casts.arcane_missiles or 0) > 2, "Arcane Missiles per minute " .. tostring(casts.arcane_missiles))
end)
