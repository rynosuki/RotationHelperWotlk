-- Subtlety Rogue: Shadow Dance opening Ambush and Premeditation, Hemorrhage
-- upkeep, Backstab.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Hemorrhage", "Backstab", "Ambush", "Premeditation", "Shadow Dance", "Slice and Dice", "Rupture",
    "Eviscerate", "Kick", "Sinister Strike" }

local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "ROGUE" })
    s.talentTabs = {
        { name = "Assassination", talents = { { "Malice", 5 } } },
        { name = "Combat", talents = { { "Precision", 5 } } },
        { name = "Subtlety", talents = { { "Shadow Dance", 1 }, { "Premeditation", 1 }, { "Hemorrhage", 1 },
            { "Slaughter from the Shadows", 5 }, { "Relentless Strikes", 5 }, { "Honor Among Thieves", 3 } } },
    }
    s.power = { type = 3, current = opts.energy or 100, max = 100 }
    s.combo = opts.combo or 0
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Slice and Dice", spellId = 6774, duration = 30, expires = s.time + 20 })
    if opts.hemo then
        s:AddAura("target", { name = "Hemorrhage", spellId = 48660, count = 8, duration = 15, expires = s.time + 12, harmful = true })
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

test("subtlety: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(s.ns.Spec.key, "subtlety", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Subtlety (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("Hemorrhage for its debuff, then Backstab (40 energy with Slaughter from the Shadows)", function()
    local s, RH = Fight()
    eq(Queue(s, 2), "hemorrhage, backstab +1.0", "no debuff")
    local st = s.ns.State:Reset()
    eq(s.ns.Abilities.PowerCost(RH.classData.abilities.backstab, st), 40, "Backstab cost")
    s = Fight({ hemo = true })
    eq(Queue(s, 1), "backstab", "debuff up")
end)

test("Shadow Dance on cooldown: Premeditation and Ambush during it", function()
    local s = Fight({ hemo = true, energy = 100, combo = 0, cooldowns = true })
    eq(Queue(s, 3), "shadow_dance, premeditation, ambush", "Shadow Dance, 2 points, Ambush")
    s = Fight({ hemo = true, energy = 100 })
    falsy(Queue(s, 3):find("ambush", 1, true), "no Ambush outside Shadow Dance (CD off)")
    s:AddAura("player", { name = "Shadow Dance", spellId = 51713, duration = 6, expires = s.time + 5 })
    eq(Queue(s, 1), "premeditation", "during Shadow Dance")
end)

test("setting 'Not behind the target': Hemorrhage instead of Backstab and Ambush", function()
    local s = Fight({ hemo = true })
    s.ns.APLOptions.Set("subtlety", "not_behind", true)
    eq(Queue(s, 1), "hemorrhage", "Hemorrhage as the builder")
    s:AddAura("player", { name = "Shadow Dance", spellId = 51713, duration = 6, expires = s.time + 5 })
    falsy(Queue(s, 3):find("ambush", 1, true), "no Ambush during Shadow Dance")
end)

test("5 points: Rupture, then Eviscerate", function()
    local s = Fight({ hemo = true, combo = 5, energy = 50 })
    eq(Queue(s, 1), "rupture", "Rupture")
end)

test("simulator: Subtlety", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.backstab or 0) > 8, "Backstab per minute " .. tostring(casts.backstab))
    truthy((casts.ambush or 0) > 1.5, "Ambush per minute " .. tostring(casts.ambush))
    truthy((casts.rupture or 0) > 1.5 and (casts.eviscerate or 0) > 0.5, "finishers (Honor Among Thieves points)")
    truthy((casts.shadow_dance or 0) > 0.7, "Shadow Dance per minute " .. tostring(casts.shadow_dance))
end)
