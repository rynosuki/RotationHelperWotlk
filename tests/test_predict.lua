local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function near(actual, expected, what)
    if type(actual) ~= "number" or math.abs(actual - expected) > 1e-6 then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local ALL_SPELLS = {
    "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
    "Pestilence", "Blood Boil", "Death and Decay", "Death Coil", "Death Strike", "Horn of Winter",
    "Blood Tap", "Unbreakable Armor", "Empower Rune Weapon", "Deathchill",
}

local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon()
    s:Learn(unpack(ALL_SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    return s, RH
end

local function Diseases(s, frostFever, bloodPlague)
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + frostFever, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + bloodPlague, harmful = true })
end

local function Buff(s, name, spellId, remains)
    s:AddAura("player", { name = name, spellId = spellId, duration = 30, expires = s.time + remains })
end

-- The predicted queue as "a, b +1.5, c +3.0".
local function Queue(s, count)
    s.ns.State:Reset()
    local recs, n = s.ns.Recommender:Predict(count or 4)
    local out = {}
    for i = 1, n do
        local e = recs[i]
        out[i] = e.name .. (e.wait > 1e-6 and ("%s +%.1f"):format("", e.wait) or "")
    end
    return table.concat(out, ", ")
end

-- A virtual copy of the current state with `key` applied at `t` seconds.
local function Simulate(s, key, t)
    s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, key, v.now + (t or 0))
    return v
end

local function RuneTypes(v)
    local out = {}
    for i, rune in ipairs(v.runes) do
        out[i] = rune.type:sub(1, 1) .. (rune.readyAt > v.now and "*" or "")
    end
    return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- The virtual state
---------------------------------------------------------------------------
test("virtual state is an independent copy", function()
    local s = Fight()
    Buff(s, "Killing Machine", 51124, 10)
    local real = s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    v.runes[1].readyAt = v.now + 10
    v.power = 99
    v.buffs.killing_machine.expires = 0
    v.cooldowns.horn_of_winter.readyAt = v.now + 20
    eq(real.runes[1].readyAt, real.now, "real rune untouched")
    eq(real.power, 0, "real power untouched")
    truthy(real.buffs.killing_machine.expires > real.now, "real buff untouched")
    eq(real.cooldowns.horn_of_winter.readyAt, real.now, "real cooldown untouched")
    eq(v.target, real.target, "target shared")
end)

test("copying again drops buffs that are gone", function()
    local s = Fight()
    Buff(s, "Killing Machine", 51124, 10)
    s.ns.State:Reset()
    s.ns.State:Virtual()
    s.auras.player = {}
    s.ns.State:Reset()
    falsy(s.ns.State:Virtual().buffs.killing_machine, "gone from the copy")
end)

---------------------------------------------------------------------------
-- Simulating abilities
---------------------------------------------------------------------------
test("apply: runes, runic power, GCD", function()
    local s = Fight()
    local v = Simulate(s, "obliterate")
    eq(RuneTypes(v), "b b u* u f* f", "one unholy and one frost rune spent")
    near(v.runes[3].readyAt - v.now, 10, "rune regen")
    eq(v.power, 15 + 5, "15 RP + Chill of the Grave (rank 2)")
    near(v.gcdEnd - v.now, 1.5, "GCD")
    eq(v.lastCast.obliterate, v.now, "last cast recorded")
end)

test("apply: death runes pay when a type runs out, then revert", function()
    local s = Fight()
    s.runes[1].type = 4 -- blood slot is a death rune
    s.runes[5].readyAt, s.runes[6].readyAt = s.time + 5, s.time + 5
    local v = Simulate(s, "icy_touch")
    eq(RuneTypes(v), "b* b u u f* f*", "the death rune paid and went back to blood")
end)

test("apply: Blood of the North turns blood runes into death runes", function()
    local s = Fight()
    local v = Simulate(s, "blood_strike")
    eq(RuneTypes(v), "d* b u u f f", "converted")
    s.talentTabs[2].talents[1][2] = 2 -- only rank 2
    s:FireEvent("PLAYER_TALENT_UPDATE")
    v = Simulate(s, "blood_strike")
    eq(RuneTypes(v), "b* b u u f f", "no conversion below rank 3")
end)

test("apply: Death Rune Mastery converts Obliterate's runes", function()
    local s = Fight()
    table.insert(s.talentTabs[3].talents, { "Death Rune Mastery", 3 })
    s:FireEvent("PLAYER_TALENT_UPDATE")
    eq(RuneTypes(Simulate(s, "obliterate")), "b b d* u d* f", "converted")
end)

test("apply: cooldowns, buffs and debuffs", function()
    local s = Fight()
    local v = Simulate(s, "horn_of_winter")
    near(v.cooldowns.horn_of_winter.readyAt - v.now, 20, "cooldown")
    near(v.buffs.horn_of_winter.expires - v.now, 120, "buff")
    v = Simulate(s, "icy_touch")
    near(v.debuffs.frost_fever.expires - v.now, 15 + 3 * 2, "Frost Fever with Epidemic rank 2")
    v = Simulate(s, "plague_strike")
    near(v.debuffs.blood_plague.expires - v.now, 21, "Blood Plague")
end)

test("apply: procs are used up", function()
    local s = Fight()
    s.power.current = 60
    Buff(s, "Killing Machine", 51124, 10)
    Buff(s, "Freezing Fog", 59052, 10)
    local v = Simulate(s, "frost_strike")
    falsy(v.buffs.killing_machine, "KM used by Frost Strike")
    truthy(v.buffs.freezing_fog, "Rime untouched")
    eq(v.power, 20, "40 RP spent")
    v = Simulate(s, "howling_blast")
    falsy(v.buffs.freezing_fog, "Rime used by Howling Blast")
    eq(RuneTypes(v), "b b u u f f", "free: no runes spent")
end)

test("apply: Empower Rune Weapon and Blood Tap", function()
    local s = Fight()
    for i = 1, 6 do s.runes[i].readyAt = s.time + 6 end
    local v = Simulate(s, "empower_rune_weapon")
    eq(RuneTypes(v), "b b u u f f", "all runes ready")
    eq(v.power, 25, "25 RP")
    eq(v.gcdEnd, v.now, "off the GCD")

    s.runes[1].readyAt = s.time + 3
    s.runes[2].readyAt = s.time + 8
    v = Simulate(s, "blood_tap")
    eq(RuneTypes(v):sub(1, 4), "b* d", "the longer-recharging blood rune became a ready death rune")
end)

test("apply: Glyph of Disease makes Pestilence refresh diseases", function()
    local s = Fight()
    Diseases(s, 3, 5)
    s.glyphs[1] = 99999
    s.spells[99999] = { "Glyph of Disease", "i" }
    s:FireEvent("GLYPH_ADDED")
    local v = Simulate(s, "pestilence")
    near(v.debuffs.frost_fever.expires - v.now, 21, "frost fever refreshed")
    near(v.debuffs.blood_plague.expires - v.now, 21, "blood plague refreshed")
end)

---------------------------------------------------------------------------
-- Predicted queues
---------------------------------------------------------------------------
test("queue: opener on a fresh target", function()
    local s = Fight()
    -- IT (frost), PS (unholy), Obliterate (last frost+unholy), then
    -- Blood Strike with a blood rune: every other rune is recharging.
    eq(Queue(s), "icy_touch, plague_strike +1.5, obliterate +3.0, blood_strike +4.5", "queue")
end)

test("queue: follows the runes as they come back", function()
    local s = Fight()
    Diseases(s, 30, 30)
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 120 })
    -- Two Obliterates (20 RP each) and two Blood Strikes (10 each) leave
    -- 60 RP: Frost Strike fills the gap until the runes are back at +10.
    eq(Queue(s, 5), "obliterate, obliterate +1.5, blood_strike +3.0, blood_strike +4.5, frost_strike +6.0", "queue")
end)

test("queue: Killing Machine is used once", function()
    local s = Fight()
    Diseases(s, 30, 30)
    for i = 3, 6 do s.runes[i].readyAt = s.time + 8 end
    s.power.current = 90
    Buff(s, "Killing Machine", 51124, 10)
    local queue = Queue(s, 3)
    eq(queue, "frost_strike, blood_strike +1.5, blood_strike +3.0", "queue")
end)

test("queue: off-GCD cooldowns go first, without taking a GCD", function()
    local s = Fight({ cooldowns = true })
    Diseases(s, 30, 30)
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 120 })
    s.cooldowns["Deathchill"] = { s.time, 120 }
    eq(Queue(s, 3), "unbreakable_armor, obliterate, blood_strike +1.5", "queue")
end)

test("queue length follows the icon setting", function()
    local s, RH = Fight()
    s:Slash("ACECONSOLE_RH", "icons 2")
    s:Tick(0.2)
    eq(#RH.recommendations, 2, "two entries")
    s:Slash("ACECONSOLE_RH", "icons 5")
    s:Tick(0.2)
    eq(#RH.recommendations, 5, "five entries")
end)

test("the display shows the whole queue", function()
    local s, RH = Fight()
    s:Slash("ACECONSOLE_RH", "lock")
    s:Tick(0.2)
    local D = s.ns.Display
    for i = 1, 4 do truthy(D.buttons[i]:IsShown(), "icon " .. i) end
    eq(RH.recommendations[2].spellId, 49921, "second icon is Plague Strike")
end)

test("predicting doesn't change the real state", function()
    local s = Fight()
    local real = s.ns.State:Reset()
    s.ns.Recommender:Predict(5)
    eq(real.runes[5].readyAt, real.now, "runes")
    eq(real.power, 0, "runic power")
    falsy(real.debuffs.frost_fever, "debuffs")
end)
