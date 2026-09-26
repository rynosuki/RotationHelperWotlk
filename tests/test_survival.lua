-- Survival Hunter: Explosive Shot with Lock and Load (skips its cooldown,
-- free, two charges), Black Arrow, Serpent Sting, Auto Shot timing.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Explosive Shot", "Black Arrow", "Steady Shot", "Arcane Shot", "Aimed Shot", "Multi-Shot", "Serpent Sting",
    "Kill Shot", "Hunter's Mark", "Rapid Fire", "Kill Command", "Aspect of the Dragonhawk", "Aspect of the Viper",
    "Auto Shot" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "HUNTER" })
    s.talentTabs = {
        { name = "Beast Mastery", talents = { { "Improved Aspect of the Hawk", 5 } } },
        { name = "Marksmanship", talents = { { "Lethal Shots", 5 } } },
        { name = "Survival", talents = { { "Lock and Load", 3 }, { "Explosive Shot", 1 }, { "Black Arrow", 1 },
            { "Hunting Party", 5 }, { "Expose Weakness", 3 } } },
    }
    s.power = { type = 0, current = 22000, max = 22000 }
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
        s:AddAura("target", { name = "Black Arrow", spellId = 63672, duration = 15, expires = s.time + 12, harmful = true })
        s.cooldowns["Black Arrow"] = { s.time, 30 }
        s.cooldowns["Explosive Shot"] = { s.time, 6 }
        s.cooldowns["Aimed Shot"] = { s.time, 10 }
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

test("survival: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "survival", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Survival (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Explosive Shot, Black Arrow, Serpent Sting, Aimed Shot", function()
    local s = Fight()
    eq(Queue(s, 4), "explosive_shot, black_arrow +1.5, serpent_sting +3.0, aimed_shot +4.5", "opener")
end)

test("Lock and Load: two Explosive Shots, free and without the cooldown", function()
    local s, RH = Fight({ setUp = true })
    falsy(Queue(s, 1) == "explosive_shot", "on cooldown")
    s:AddAura("player", { name = "Lock and Load", spellId = 56453, count = 2, duration = 12, expires = s.time + 12 })
    eq(Queue(s, 2), "explosive_shot, explosive_shot +1.5", "both charges")
    eq(RH.recommendations[1].usesProc, "lock_and_load", "glows")
    local st = s.ns.State:Reset()
    eq(s.ns.Abilities.PowerCost(RH.classData.abilities.explosive_shot, st), 0, "free")
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, "explosive_shot", v.now)
    eq(v.buffs.lock_and_load.stacks, 1, "one charge left")
    near(v.cooldowns.explosive_shot.readyAt, st.cooldowns.explosive_shot.readyAt, "the cooldown isn't restarted")
end)

test("filler: Steady Shot", function()
    local s = Fight({ setUp = true })
    eq(Queue(s, 1), "steady_shot", "everything on cooldown")
end)

test("simulator: Survival with Lock and Load", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts, uptime = {}, {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    for _, d in ipairs(summary.debuffs) do uptime[d.key] = d.uptime end
    truthy((casts.explosive_shot or 0) > 9, "Explosive Shot per minute (more than the 6s cooldown allows) " .. tostring(casts.explosive_shot))
    truthy((casts.black_arrow or 0) > 1.5, "Black Arrow per minute " .. tostring(casts.black_arrow))
    truthy((uptime.serpent_sting or 0) > 90, "Serpent Sting uptime")
end)
