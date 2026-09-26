-- Balance Druid: Eclipse (and the last one, remembered), DoTs, Starfall.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Wrath", "Starfire", "Moonfire", "Insect Swarm", "Faerie Fire", "Starfall", "Force of Nature",
    "Hurricane", "Moonkin Form", "Entangling Roots", "Mark of the Wild" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Moonkin in combat with a boss; `setUp` puts Faerie Fire, Insect Swarm and
-- Moonfire up and Starfall on cooldown.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "DRUID" })
    s.talentTabs = {
        { name = "Balance", talents = { { "Starlight Wrath", 5 }, { "Eclipse", 3 }, { "Nature's Splendor", 1 },
            { "Moonkin Form", 1 }, { "Starfall", 1 }, { "Force of Nature", 1 }, { "Improved Faerie Fire", 3 } } },
        { name = "Feral Combat", talents = {} },
        { name = "Restoration", talents = { { "Intensity", 3 } } },
    }
    s.power = { type = 0, current = 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Moonkin Form", spellId = 24858, duration = 0, expires = 0 })
    if opts.setUp then
        s:AddAura("target", { name = "Faerie Fire", spellId = 770, duration = 300, expires = s.time + 200, harmful = true })
        s:AddAura("target", { name = "Insect Swarm", spellId = 48468, duration = 14, expires = s.time + 12, harmful = true })
        s:AddAura("target", { name = "Moonfire", spellId = 48463, duration = 15, expires = s.time + 12, harmful = true })
        s.cooldowns["Starfall"] = { s.time, 90 }
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

local function Eclipse(s, which, remains)
    local name, id = "Eclipse (Lunar)", 48518
    if which == "solar" then name, id = "Eclipse (Solar)", 48517 end
    s:AddAura("player", { name = name, spellId = id, duration = 15, expires = s.time + remains })
end

test("druid: class data and the Balance rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "balance", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Balance (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Starfall, Faerie Fire, Insect Swarm, Moonfire", function()
    local s = Fight({ cooldowns = true })
    s.cooldowns["Force of Nature"] = { s.time, 180 }
    eq(Queue(s, 4), "starfall, faerie_fire +1.5, insect_swarm +3.0, moonfire +4.5", "opener")
end)

test("Eclipse: Starfire in Lunar, Wrath in Solar", function()
    local s = Fight({ setUp = true })
    Eclipse(s, "lunar", 10)
    eq(Queue(s, 1), "starfire", "Lunar")
    near(Eval(s, "action.starfire.cast_time"), 3.0, "Starlight Wrath 5/5")
    s = Fight({ setUp = true })
    Eclipse(s, "solar", 10)
    eq(Queue(s, 1), "wrath", "Solar")
end)

test("between eclipses: the spell of the last one", function()
    local s = Fight({ setUp = true })
    eq(Queue(s, 1), "wrath", "no Eclipse yet: Wrath (to proc Lunar)")
    Eclipse(s, "lunar", 2)
    Queue(s, 1)
    s.auras.player[#s.auras.player] = nil -- Lunar ran out
    eq(Eval(s, "last.lunar_eclipse"), 1, "last was Lunar")
    eq(Queue(s, 1), "starfire", "keep casting Starfire (to proc Solar)")
    Eclipse(s, "solar", 2)
    Queue(s, 1)
    s.auras.player[#s.auras.player] = nil
    eq(Eval(s, "last.solar_eclipse"), 1, "last was Solar")
    eq(Queue(s, 1), "wrath", "back to Wrath")
end)

test("someone else's Faerie Fire counts; Moonfire while moving", function()
    local s = Fight()
    s:AddAura("target", { name = "Faerie Fire (Feral)", spellId = 16857, duration = 300, expires = s.time + 200,
        harmful = true, caster = "raid3" })
    falsy(Queue(s, 3):find("faerie_fire", 1, true), "a feral's Faerie Fire")
    s = Fight({ setUp = true })
    s.speed = 7
    eq(Queue(s, 1), "moonfire", "moving")
end)

test("simulator: Balance cycles eclipses", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts, procs = {}, {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    for _, p in ipairs(summary.procs) do procs[p.aura] = p.gained end
    truthy(summary.gcdUsage > 95, "time spent casting " .. summary.gcdUsage)
    truthy((casts.starfire or 0) > 4 and (casts.wrath or 0) > 8, ("Starfire %s, Wrath %s per minute"):format(
        tostring(casts.starfire), tostring(casts.wrath)))
    truthy((procs.lunar_eclipse or 0) >= 2 and (procs.solar_eclipse or 0) >= 2, "both eclipses proc")
    for _, d in ipairs(summary.debuffs) do truthy(d.uptime > 85, d.key .. " uptime " .. d.uptime) end
end)
