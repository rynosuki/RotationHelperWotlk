-- Beast Mastery Hunter: Kill Command and Bestial Wrath need the pet, The
-- Beast Within halves costs, Rapid Fire with Bestial Wrath.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Steady Shot", "Arcane Shot", "Aimed Shot", "Multi-Shot", "Serpent Sting", "Kill Shot", "Hunter's Mark",
    "Rapid Fire", "Kill Command", "Bestial Wrath", "Aspect of the Dragonhawk", "Aspect of the Viper", "Auto Shot" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "HUNTER" })
    s.talentTabs = {
        { name = "Beast Mastery", talents = { { "Bestial Wrath", 1 }, { "The Beast Within", 1 }, { "Longevity", 3 },
            { "Ferocious Inspiration", 3 }, { "Kindred Spirits", 5 } } },
        { name = "Marksmanship", talents = { { "Lethal Shots", 5 } } },
        { name = "Survival", talents = { { "Catlike Reflexes", 3 } } },
    }
    s.power = { type = 0, current = 22000, max = 22000 }
    s:Learn(unpack(SPELLS))
    s.castTimes["Steady Shot"] = 1600
    s.hasTarget = true
    s.petAlive = opts.noPet ~= true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Aspect of the Dragonhawk", spellId = 61847, duration = 0, expires = 0 })
    s:AddAura("target", { name = "Hunter's Mark", spellId = 53338, duration = 300, expires = s.time + 300, harmful = true })
    s:AddAura("target", { name = "Serpent Sting", spellId = 49001, duration = 15, expires = s.time + 12, harmful = true })
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

test("beast mastery: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(s.ns.Spec.key, "beast_mastery", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Beast Mastery (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("Kill Command (off the GCD), Aimed Shot, Arcane Shot, Steady Shot", function()
    local s = Fight()
    eq(Queue(s, 4), "kill_command, aimed_shot, arcane_shot +1.5, steady_shot +3.0", "rotation")
end)

test("no pet: no Kill Command or Bestial Wrath", function()
    local s = Fight({ noPet = true, cooldowns = true })
    local queue = Queue(s, 4)
    falsy(queue:find("kill_command", 1, true) or queue:find("bestial_wrath", 1, true), queue)
end)

test("Bestial Wrath with Rapid Fire; The Beast Within halves costs", function()
    local s, RH = Fight({ cooldowns = true })
    eq(Queue(s, 3), "bestial_wrath, rapid_fire, kill_command", "cooldowns")
    s:AddAura("player", { name = "The Beast Within", spellId = 34471, duration = 18, expires = s.time + 18 })
    local st = s.ns.State:Reset()
    near(s.ns.Abilities.PowerCost(RH.classData.abilities.aimed_shot, st), 0.08 * 5046 / 2, "half")
    local A = s.ns.Abilities
    eq(A.CooldownDuration(RH.classData.abilities.bestial_wrath), 84, "Longevity 3/3")
    eq(A.CooldownDuration(RH.classData.abilities.kill_command), 30, "Catlike Reflexes 3/3")
end)

test("simulator: Beast Mastery", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.kill_command or 0) > 1.5, "Kill Command per minute " .. tostring(casts.kill_command))
    truthy((casts.steady_shot or 0) > 10, "Steady Shot per minute " .. tostring(casts.steady_shot))
    truthy((casts.bestial_wrath or 0) > 0.5, "Bestial Wrath per minute " .. tostring(casts.bestial_wrath))
end)
