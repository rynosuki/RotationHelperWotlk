-- Marksmanship Hunter: Auto Shot timing (Steady Shot doesn't clip it when
-- waiting is cheaper), ranged haste, Chimera refreshing Serpent Sting,
-- Readiness, aspects.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Steady Shot", "Arcane Shot", "Chimera Shot", "Aimed Shot", "Multi-Shot", "Serpent Sting", "Kill Shot",
    "Hunter's Mark", "Silencing Shot", "Rapid Fire", "Readiness", "Kill Command", "Aspect of the Dragonhawk",
    "Aspect of the Viper", "Auto Shot" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Marksmanship hunter in combat with a boss, 25% ranged haste (Steady
-- Shot 1.6s), Auto Shot every 2.4s; `setUp` puts Hunter's Mark and Serpent
-- Sting up and the shots on cooldown.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "HUNTER" })
    s.talentTabs = {
        { name = "Beast Mastery", talents = { { "Improved Aspect of the Hawk", 5 } } },
        { name = "Marksmanship", talents = { { "Chimera Shot", 1 }, { "Rapid Killing", 2 }, { "Readiness", 1 },
            { "Silencing Shot", 1 }, { "Aimed Shot", 1 } } },
        { name = "Survival", talents = { { "Hunting Party", 5 } } },
    }
    s.power = { type = 0, current = opts.mana or 22000, max = 22000 }
    s:Learn(unpack(SPELLS))
    s.castTimes["Steady Shot"] = 1600
    s.hasTarget = true
    s.petAlive = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Aspect of the Dragonhawk", spellId = 61847, duration = 0, expires = 0 })
    s:AddAura("target", { name = "Hunter's Mark", spellId = 53338, duration = 300, expires = s.time + 300, harmful = true })
    if opts.setUp then
        s:AddAura("target", { name = "Serpent Sting", spellId = 49001, duration = 15, expires = s.time + 12, harmful = true })
        for _, name in ipairs({ "Chimera Shot", "Aimed Shot", "Arcane Shot" }) do s.cooldowns[name] = { s.time, 10 } end
    end
    return s, RH
end

-- An Auto Shot fires now.
local function AutoShot(s)
    s:FireEvent("START_AUTOREPEAT_SPELL")
    s:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Auto Shot", "")
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

test("hunter: class data and the Marksmanship rotation load cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "marksmanship", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Marksmanship (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Serpent Sting, Chimera Shot, Aimed Shot, Arcane Shot; the GCD isn't hasted", function()
    local s = Fight()
    eq(Queue(s, 4), "serpent_sting, chimera_shot +1.5, aimed_shot +3.0, arcane_shot +4.5", "opener")
    local st = s.ns.State:Reset()
    eq(st.gcdDuration, 1.5, "GCD")
    near(Eval(s, "action.steady_shot.cast_time"), 1.6, "Steady Shot with ranged haste")
end)

test("Auto Shot: tracked from the game; Steady Shot right after each one", function()
    local s = Fight({ setUp = true })
    AutoShot(s)
    near(Eval(s, "auto_shot.remains"), 2.4, "next Auto Shot")
    eq(Queue(s, 3), "steady_shot, steady_shot +2.3, steady_shot +4.7", "after each Auto Shot")
end)

test("Auto Shot soon: wait for it when that's cheaper than delaying it", function()
    local s, RH = Fight({ setUp = true })
    AutoShot(s)
    s.time = s.time + 1.9 -- Auto Shot in 0.5s; a 1.6s Steady Shot would delay it 1.1s
    eq(Queue(s, 1), "steady_shot +0.4", "wait for the Auto Shot")
    eq(RH.recommendations[1].limitedBy, "auto shot", "waits on Auto Shot")
    s = Fight({ setUp = true })
    AutoShot(s)
    s.time = s.time + 1.3 -- Auto Shot in 1.1s: waiting costs more than the 0.5s delay
    eq(Queue(s, 1), "steady_shot", "cast now")
end)

test("instants fill the wait for the Auto Shot", function()
    local s = Fight({ setUp = true })
    AutoShot(s)
    s.time = s.time + 1.9
    s.cooldowns["Arcane Shot"] = nil
    eq(Queue(s, 2), "arcane_shot, steady_shot +1.5", "Arcane Shot, then Steady Shot after the GCD")
end)

test("Chimera Shot refreshes Serpent Sting; Kill Shot below 20%", function()
    local s = Fight({ setUp = true })
    s.ns.State:Reset()
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "chimera_shot", st.now)
    near(st.debuffs.serpent_sting.expires, st.now + 15, "refreshed")
    s.target.health = 15
    eq(Queue(s, 1), "kill_shot", "execute")
end)

test("Readiness resets Rapid Fire (not trinkets); aspects for mana", function()
    local s, RH = Fight({ setUp = true, cooldowns = true })
    s.cooldowns["Rapid Fire"] = { s.time - 10, 180 }
    s.items[50000] = { "Some Trinket", "i", "Some Use",
        tooltip = { "Some Trinket", "Use: Increases attack power by 1024 for 20 sec. (2 Min Cooldown)" } }
    s.equipped[13] = 50000
    s.itemCooldowns[50000] = { s.time - 10, 120 }
    s:FireEvent("PLAYER_EQUIPMENT_CHANGED")
    s.ns.State:Reset()
    local st = s.ns.State:Virtual()
    s.ns.Abilities.Apply(st, "readiness", st.now)
    near(st.cooldowns.rapid_fire.readyAt, st.now, "Rapid Fire ready")
    truthy(st.cooldowns.trinket1.readyAt > st.now + 100, "the trinket isn't")
    s = Fight({ setUp = true, mana = 1500 })
    eq(Queue(s, 1), "aspect_of_the_viper", "low mana")
end)

test("pre-pull checklist wants the pet out", function()
    local s, RH = Fight()
    s:FireEvent("PLAYER_REGEN_ENABLED")
    s.petAlive = false
    s:Tick(0.1)
    truthy(RH.checklist and table.concat(RH.checklist, ", "):find("Pet", 1, true), "no pet")
end)

test("simulator: Marksmanship with Auto Shot", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.steady_shot or 0) > 10, "Steady Shot per minute " .. tostring(casts.steady_shot))
    truthy((casts.chimera_shot or 0) > 4, "Chimera Shot per minute " .. tostring(casts.chimera_shot))
    truthy(summary.debuffs[1] and summary.debuffs[1].uptime > 90, "Serpent Sting uptime")
end)
