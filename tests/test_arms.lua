-- Arms Warrior: Rend upkeep, Overpower with Taste for Blood, Sudden Death,
-- Bladestorm, stances.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Mortal Strike", "Rend", "Overpower", "Bladestorm", "Sweeping Strikes", "Slam", "Execute",
    "Heroic Strike", "Cleave", "Battle Shout", "Bloodrage", "Berserker Rage", "Hamstring", "Pummel" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A deep Arms warrior in Battle Stance, in combat with a boss, Battle Shout up.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "WARRIOR" })
    s.talentTabs = {
        { name = "Arms", talents = { { "Improved Heroic Strike", 3 }, { "Taste for Blood", 3 }, { "Sudden Death", 3 },
            { "Improved Mortal Strike", 3 }, { "Unrelenting Assault", 2 }, { "Bladestorm", 1 }, { "Mortal Strike", 1 } } },
        { name = "Fury", talents = { { "Improved Berserker Rage", 2 } } },
        { name = "Protection", talents = {} },
    }
    s.power = { type = 1, current = opts.rage or 50, max = 100 }
    s.form = 1
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Battle Shout", spellId = 47436, duration = 120, expires = s.time + 120 })
    if opts.rend then
        s:AddAura("target", { name = "Rend", spellId = 47465, duration = 15, expires = s.time + 12, harmful = true })
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

test("arms: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "arms", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Arms (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("Rend first, then Mortal Strike and Slam", function()
    local s = Fight()
    eq(Queue(s, 3), "rend, mortal_strike +1.5, slam +3.0", "opener")
    s = Fight({ rend = true })
    eq(Queue(s, 2), "mortal_strike, slam +1.5", "Rend up")
end)

test("Overpower with Taste for Blood (or after a dodge), in Battle Stance only", function()
    local s, RH = Fight({ rend = true })
    falsy(Queue(s, 1) == "overpower", "no proc")
    s:AddAura("player", { name = "Taste for Blood", spellId = 60503, duration = 9, expires = s.time + 9 })
    eq(Queue(s, 1), "overpower", "Taste for Blood")
    eq(RH.recommendations[1].usesProc, "taste_for_blood", "spends the proc")
    s.form = 3
    falsy(Queue(s, 1) == "overpower", "Berserker Stance")
    s.form = 1
    s.auras.player = {}
    s:AddAura("player", { name = "Battle Shout", spellId = 47436, duration = 120, expires = s.time + 120 })
    s.usable["Overpower"] = true
    eq(Queue(s, 1), "overpower", "after a dodge")
end)

test("Execute with Sudden Death at any health", function()
    local s = Fight({ rend = true })
    s.cooldowns["Mortal Strike"] = { s.time, 5 }
    falsy(Queue(s, 1) == "execute", "no proc, full health")
    s:AddAura("player", { name = "Sudden Death", spellId = 52437, duration = 10, expires = s.time + 10 })
    eq(Queue(s, 1), "execute", "Sudden Death")
end)

test("Bladestorm locks you in for 6 seconds", function()
    local s, RH = Fight({ rend = true, rage = 80, cooldowns = true })
    s.cooldowns["Mortal Strike"] = { s.time, 5 }
    local queue = Queue(s, 3)
    truthy(queue:find("bladestorm", 1, true), "Bladestorm: " .. queue)
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "bladestorm", st.now)
    near(st.gcdEnd, st.now + 6, "nothing else for 6 seconds")
end)

test("Sweeping Strikes and Cleave on several targets", function()
    local s, RH = Fight({ rend = true, rage = 90 }) -- 60 left after Sweeping Strikes
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Queue(s, 2), "sweeping_strikes, cleave", "AoE")
end)

test("stances: Pummel needs Berserker Stance; the checklist wants Battle Stance", function()
    local s, RH = Fight()
    local st = s.ns.State:Reset()
    local t, reason = s.ns.Abilities.ReadyAt(st, "pummel")
    eq(reason, "wrong stance", "Pummel in Battle Stance")
    s:FireEvent("PLAYER_REGEN_ENABLED")
    s.form = 3
    s:Tick(0.1)
    truthy(RH.checklist and table.concat(RH.checklist, ", "):find("Battle Stance", 1, true), "checklist")
end)

test("review and simulator: Rend uptime for Arms (not for Fury)", function()
    local s, RH = Fight()
    eq(table.concat(RH:ReviewDebuffs(), ","), "rend", "Arms")
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.mortal_strike or 0) > 8, "Mortal Strike per minute " .. tostring(casts.mortal_strike))
    truthy((casts.overpower or 0) > 3, "Overpower per minute " .. tostring(casts.overpower))
    truthy((casts.slam or 0) > 8, "Slam per minute " .. tostring(casts.slam))
    truthy(summary.debuffs[1] and summary.debuffs[1].uptime > 85, "Rend uptime " .. tostring(summary.debuffs[1] and summary.debuffs[1].uptime))
    s.talentTabs[2].talents[1][2] = 60 -- now Fury
    s:FireEvent("PLAYER_TALENT_UPDATE")
    eq(#RH:ReviewDebuffs(), 0, "Fury: no Rend")
end)
