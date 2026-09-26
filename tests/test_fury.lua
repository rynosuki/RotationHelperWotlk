-- Fury Warrior: rage with expected income, on-next-swing attacks, Bloodsurge.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Bloodthirst", "Whirlwind", "Slam", "Execute", "Heroic Strike", "Cleave", "Battle Shout",
    "Bloodrage", "Berserker Rage", "Death Wish", "Recklessness", "Pummel", "Hamstring" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Titan's Grip Fury warrior in Berserker Stance, in combat with a boss,
-- Battle Shout up.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "WARRIOR" })
    s.talentTabs = {
        { name = "Arms", talents = { { "Improved Heroic Strike", 3 }, { "Deflection", 2 } } },
        { name = "Fury", talents = { { "Bloodsurge", 3 }, { "Intensify Rage", 3 }, { "Improved Berserker Rage", 2 },
            { "Death Wish", 1 }, { "Bloodthirst", 1 }, { "Titan's Grip", 1 } } },
        { name = "Protection", talents = { { "Shield Specialization", 2 } } },
    }
    s.power = { type = 1, current = opts.rage or 40, max = 100 }
    s.form = 3
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    if not opts.outOfCombat then s:FireEvent("PLAYER_REGEN_DISABLED") end
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if not opts.noShout then
        s:AddAura("player", { name = "Battle Shout", spellId = 47436, duration = 120, expires = s.time + 120 })
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

test("warrior: class data and the Fury rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "fury", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Fury (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("priority: Bloodthirst, then Whirlwind", function()
    local s = Fight()
    eq(Queue(s, 2), "bloodthirst, whirlwind +1.5", "40 rage")
end)

test("rage: short on rage means waiting for the expected income", function()
    local s, RH = Fight({ rage = 5 })
    eq(Queue(s, 1), "bloodthirst +1.3", "15 rage short at 12 per second")
    eq(RH.recommendations[1].limitedBy, "rage", "waits on rage")
    near(Eval(s, "rage", 1), 17, "rage in a second")
    eq(Eval(s, "rage.deficit"), 95, "deficit")
end)

test("rage: the income is learned from the fight", function()
    local s = Fight({ rage = 0 })
    eq(s.ns.State:Reset().powerRegen, 12, "the class's guess at first")
    for _ = 1, 10 do
        s.power.current = s.power.current + 10 -- a white hit every half second
        s:Tick(0.5)
    end
    near(s.ns.State:Reset().powerRegen, 20, "20 rage per second", 3)
    -- Out of combat nothing comes in.
    s:FireEvent("PLAYER_REGEN_ENABLED")
    eq(s.ns.State:Reset().powerRegen, nil, "out of combat")
end)

test("Heroic Strike with spare rage, once; Cleave and Whirlwind on several targets", function()
    local s, RH = Fight({ rage = 80 })
    eq(Queue(s, 2), "heroic_strike, bloodthirst", "spare rage: next swing, off the GCD")
    s.current["Heroic Strike"] = true
    eq(Queue(s, 1), "bloodthirst", "already queued")
    s.current["Heroic Strike"] = nil
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Queue(s, 2), "cleave, whirlwind", "AoE")
end)

test("Slam with Bloodsurge; Execute below 20%", function()
    local s = Fight()
    s.cooldowns["Bloodthirst"] = { s.time, 4 }
    s.cooldowns["Whirlwind"] = { s.time, 10 }
    falsy(Queue(s, 1):find("^slam"), "no Bloodsurge")
    s:AddAura("player", { name = "Slam!", spellId = 46916, duration = 5, expires = s.time + 5 })
    eq(Queue(s, 1), "slam", "Bloodsurge")
    truthy(s.env.RotationHelper.recommendations[1].usesProc == "bloodsurge", "marked as spending the proc")
    s.auras.player = {}
    s:AddAura("player", { name = "Battle Shout", spellId = 47436, duration = 120, expires = s.time + 120 })
    s.target.health = 15
    eq(Queue(s, 1), "execute", "execute")
end)

test("rage generators when short, and big cooldowns with Death Wish", function()
    local s, RH = Fight({ rage = 20, cooldowns = true })
    eq(Queue(s, 4), "death_wish, recklessness, berserker_rage, bloodrage", "cooldowns and rage")
    local Abilities = s.ns.Abilities
    near(Abilities.CooldownDuration(RH.classData.abilities.death_wish), 180 * 0.67, "Intensify Rage 3/3")
    eq(Abilities.PowerCost(RH.classData.abilities.heroic_strike), 12, "Improved Heroic Strike 3/3")
    eq(Abilities.PowerGain(RH.classData.abilities.berserker_rage), 20, "Improved Berserker Rage 2/2")
end)

test("out of combat: Bloodrage for the rage, then Battle Shout", function()
    local s = Fight({ rage = 0, outOfCombat = true, noShout = true })
    eq(Queue(s, 2), "bloodrage, battle_shout", "shout")
end)

test("pre-pull checklist: Berserker Stance", function()
    local s, RH = Fight({ outOfCombat = true })
    s.form = 1
    s:Tick(0.1)
    truthy(RH.checklist and table.concat(RH.checklist, ", "):find("Berserker Stance", 1, true), "battle stance")
    s.form = 3
    s:Tick(0.1)
    falsy(RH.checklist and table.concat(RH.checklist, ", "):find("Berserker Stance", 1, true), "berserker stance")
    eq(Eval(s, "stance.berserker"), 1, "stance.berserker")
end)

test("simulator: Fury with rage income and Bloodsurge", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.bloodthirst or 0) > 12, "Bloodthirst per minute " .. tostring(casts.bloodthirst))
    truthy((casts.whirlwind or 0) > 5, "Whirlwind per minute " .. tostring(casts.whirlwind))
    truthy((casts.slam or 0) > 1, "Slam per minute " .. tostring(casts.slam))
    truthy((casts.heroic_strike or 0) > 5, "Heroic Strike per minute " .. tostring(casts.heroic_strike))
end)
