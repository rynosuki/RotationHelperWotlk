-- Demonology Warlock: Metamorphosis and Immolation Aura, Decimation Soul
-- Fire, Molten Core Incinerate (three charges), Demonic Empowerment.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Shadow Bolt", "Incinerate", "Soul Fire", "Immolate", "Corruption", "Curse of Doom", "Curse of Agony",
    "Metamorphosis", "Immolation Aura", "Demonic Empowerment", "Life Tap", "Fel Armor", "Demon Skin", "Searing Pain" }

local function near(actual, expected, what, tolerance)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-6) then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

-- A Demonology warlock with a Felguard, in combat with a boss; `setUp` puts
-- Immolate, Corruption and Curse of Doom up and Demonic Empowerment on cooldown.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon({ class = "WARLOCK" })
    s.talentTabs = {
        { name = "Affliction", talents = { { "Improved Corruption", 5 } } },
        { name = "Demonology", talents = { { "Metamorphosis", 1 }, { "Decimation", 2 }, { "Molten Core", 3 },
            { "Demonic Empowerment", 1 }, { "Nemesis", 3 }, { "Summon Felguard", 1 } } },
        { name = "Destruction", talents = { { "Bane", 5 } } },
    }
    s.power = { type = 0, current = 20000, max = 20000 }
    s:Learn(unpack(SPELLS))
    s.hasTarget = true
    s.petAlive = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Fel Armor", spellId = 47893, duration = 1800, expires = s.time + 1800 })
    if opts.setUp then
        s:AddAura("target", { name = "Immolate", spellId = 47811, duration = 15, expires = s.time + 12, harmful = true })
        s:AddAura("target", { name = "Corruption", spellId = 47813, duration = 18, expires = s.time + 15, harmful = true })
        s:AddAura("target", { name = "Curse of Doom", spellId = 47867, duration = 60, expires = s.time + 50, harmful = true })
        s.cooldowns["Demonic Empowerment"] = { s.time, 60 }
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

test("demonology: the rotation loads cleanly", function()
    local s, RH = Fight()
    eq(#RH.classData.badSpellIds, 0, "spell IDs")
    eq(s.ns.Spec.key, "demonology", "spec")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Demonology (default)", "rotation")
    eq(#apl.errors, 0, "compiles")
    Queue(s, 1)
    eq(#RH.errors, 0, "no errors while running (" .. tostring(RH.errors[1] and RH.errors[1].message) .. ")")
end)

test("opener: Demonic Empowerment, Immolate, Corruption, Curse of Doom", function()
    local s = Fight()
    eq(Queue(s, 4), "demonic_empowerment, immolate, corruption +1.5, curse_of_doom +3.0", "opener")
end)

test("Molten Core: a faster Incinerate, one of three charges", function()
    local s, RH = Fight({ setUp = true })
    eq(Queue(s, 1), "shadow_bolt", "no Molten Core")
    s:AddAura("player", { name = "Molten Core", spellId = 71165, count = 3, duration = 15, expires = s.time + 15 })
    eq(Queue(s, 1), "incinerate", "Molten Core")
    near(Eval(s, "action.incinerate.cast_time"), 2.5 * 0.7, "30% faster")
    s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, "incinerate", v.now)
    eq(v.buffs.molten_core.stacks, 2, "two charges left")
end)

test("Decimation: a fast Soul Fire", function()
    local s = Fight({ setUp = true })
    s:AddAura("player", { name = "Decimation", spellId = 63167, duration = 10, expires = s.time + 10 })
    eq(Queue(s, 1), "soul_fire", "Decimation")
    near(Eval(s, "action.soul_fire.cast_time"), (6 - 2) * 0.6, "Bane 5/5, 40% faster")
end)

test("Metamorphosis, then Immolation Aura during it", function()
    local s, RH = Fight({ setUp = true, cooldowns = true })
    eq(Queue(s, 2), "metamorphosis, immolation_aura +1.5", "cooldowns")
    near(s.ns.Abilities.CooldownDuration(RH.classData.abilities.metamorphosis), 126, "Nemesis 3/3")
end)

test("no demon: no Demonic Empowerment; the checklist wants it out", function()
    local s, RH = Fight()
    s.petAlive = false
    falsy(Queue(s, 3):find("demonic_empowerment", 1, true), "no pet")
    s:FireEvent("PLAYER_REGEN_ENABLED")
    s:Tick(0.1)
    truthy(RH.checklist and table.concat(RH.checklist, ", "):find("Pet", 1, true), "checklist")
end)

test("simulator: Demonology", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy(summary.gcdUsage > 95, "time spent casting " .. summary.gcdUsage)
    truthy((casts.shadow_bolt or 0) > 8, "Shadow Bolt per minute " .. tostring(casts.shadow_bolt))
    truthy((casts.incinerate or 0) > 3, "Incinerate per minute " .. tostring(casts.incinerate))
    truthy((casts.immolation_aura or 0) > 0.5, "Immolation Aura per minute " .. tostring(casts.immolation_aura))
end)
