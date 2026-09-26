-- Combat Rogue: energy regeneration (and Adrenaline Rush), combo points,
-- finishers, Slice and Dice upkeep, the 1 second GCD.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Sinister Strike", "Slice and Dice", "Rupture", "Eviscerate", "Killing Spree", "Adrenaline Rush",
    "Blade Flurry", "Kick" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Combat rogue in combat with a boss, `energy` and `combo` points.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "ROGUE" })
    s.talentTabs = {
        { name = "Assassination", talents = { { "Malice", 5 } } },
        { name = "Combat", talents = { { "Improved Sinister Strike", 2 }, { "Vitality", 3 }, { "Combat Potency", 5 },
            { "Killing Spree", 1 }, { "Adrenaline Rush", 1 }, { "Blade Flurry", 1 }, { "Improved Slice and Dice", 2 } } },
        { name = "Subtlety", talents = { { "Relentless Strikes", 5 } } },
    }
    s.power = { type = 3, current = opts.energy or 100, max = 100 }
    s.combo = opts.combo or 0
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if opts.snd then
        s:AddAura("player", { name = "Slice and Dice", spellId = 6774, duration = 30, expires = s.time + opts.snd })
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

local function Eval(s, text, offset)
    local resolve = s.ns.Expressions.CreateResolver(s.env.RotationHelper.classData)
    local fn, message = s.ns.APL.Compiler.CompileExpression(text, resolve)
    if not fn then error("compile failed: " .. message, 2) end
    local st = s.ns.State:Reset()
    st.now = st.now + (offset or 0)
    return fn(st)
end

test("rogue: class data and the Combat rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "combat", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Combat (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("energy: regeneration with Vitality and Combat Potency, 1 second GCD", function()
    local s = Fight({ energy = 20 })
    local st = s.ns.State:Reset()
    near(st.powerRegen, 10 * 1.25 + 0.35 * 5, "14.25 per second")
    eq(st.gcdDuration, 1, "GCD")
    near(Eval(s, "energy", 2), 20 + 2 * 14.25, "energy in 2 seconds")
    eq(Eval(s, "energy.deficit"), 80, "deficit")
end)

test("combo points: builders add them, finishers need and use them", function()
    local s = Fight()
    eq(Queue(s, 2), "sinister_strike, slice_and_dice +1.0", "opener: a point, then Slice and Dice")
    s.combo = 3
    eq(Eval(s, "combo_points"), 3, "combo_points")
    s.ns.State:Reset()
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "slice_and_dice", st.now)
    eq(st.comboPoints, 0, "all used")
    near(st.buffs.slice_and_dice.expires - st.now, (6 + 3 * 3) * 1.5, "15s at 3 points, +50% Improved Slice and Dice")
    s.combo = 0
    local t, reason = s.ns.Abilities.ReadyAt(s.ns.State:Reset(), "eviscerate")
    eq(reason, "combo points", "no points: no finisher")
end)

test("at 5 points: Rupture, then Eviscerate; Slice and Dice first when it's running low", function()
    local s = Fight({ combo = 5, snd = 18 })
    eq(Queue(s, 1), "rupture", "Rupture")
    s:AddAura("target", { name = "Rupture", spellId = 48672, duration = 16, expires = s.time + 12, harmful = true })
    eq(Queue(s, 1), "eviscerate", "Rupture up: Eviscerate")
    s = Fight({ combo = 5, snd = 4 })
    eq(Queue(s, 1), "slice_and_dice", "Slice and Dice has 4s left")
end)

test("short on energy: the icon waits for it", function()
    local s, RH = Fight({ combo = 2, energy = 5, snd = 18 })
    eq(Queue(s, 1), "sinister_strike +2.5", "35 energy short at 14.25 per second")
    eq(RH.recommendations[1].limitedBy, "energy", "waits on energy")
end)

test("Adrenaline Rush doubles energy regeneration", function()
    local s = Fight({ energy = 0, snd = 18 })
    s:AddAura("player", { name = "Adrenaline Rush", spellId = 13750, duration = 15, expires = s.time + 15 })
    near(Eval(s, "energy", 2), 2 * 14.25 * 2, "twice as fast")
    near(Eval(s, "energy", 20), 100, "capped at 100")
    local st = s.ns.State:Reset()
    near(s.ns.Resources.TimeFor(st, 57) - st.powerTime, 2, "57 energy in 2 seconds")
end)

test("cooldowns and Killing Spree", function()
    local s = Fight({ cooldowns = true, energy = 30, snd = 18, combo = 2 })
    eq(Queue(s, 3), "adrenaline_rush, blade_flurry, killing_spree", "Adrenaline Rush and Blade Flurry off the GCD, then Killing Spree")
end)

test("simulator: Combat keeps Slice and Dice up", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.sinister_strike or 0) > 15, "Sinister Strike per minute " .. tostring(casts.sinister_strike))
    -- Energy-limited: about 4 finishers a minute from 20 Sinister Strikes.
    local finishers = (casts.slice_and_dice or 0) + (casts.rupture or 0) + (casts.eviscerate or 0)
    truthy(finishers > 3.5, "finishers per minute " .. finishers)
    truthy((casts.slice_and_dice or 0) >= 1.5, "Slice and Dice per minute " .. tostring(casts.slice_and_dice))
    truthy(summary.debuffs[1] and summary.debuffs[1].uptime > 40, "Rupture uptime " .. tostring(summary.debuffs[1] and summary.debuffs[1].uptime))
end)
