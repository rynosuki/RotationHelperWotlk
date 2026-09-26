local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function near(actual, expected, what)
    if math.abs(actual - expected) > 1e-6 then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function snapshot(s)
    return s.ns.State:Reset()
end

---------------------------------------------------------------------------
-- Class data
---------------------------------------------------------------------------
test("Death Knight class data resolves every spell ID", function()
    local s, RH = newAddon()
    eq(#RH.classData.badSpellIds, 0, "bad IDs: " .. table.concat(RH.classData.badSpellIds, ", "))
    eq(RH.classData.abilities.obliterate.name, "Obliterate", "ability name")
    eq(RH.classData.gcdSpellName, "Death Coil", "GCD spell name")
    falsy(s:ChatContains("Unknown spell IDs"), "no warning")
end)

test("RegisterClass reports unknown spell IDs", function()
    local s = newAddon()
    local data = { abilities = { bogus = { id = 1 } }, auras = { missing = { id = 2 } }, specs = {} }
    s.ns.RegisterClass("TESTCLASS", data)
    eq(table.concat(data.badSpellIds, ","), "bogus (1),missing (2)", "bad IDs")
end)

---------------------------------------------------------------------------
-- Spec
---------------------------------------------------------------------------
test("detects spec, talents and glyphs", function()
    local s = newAddon()
    s.glyphs[1] = 58647
    s:FireEvent("GLYPH_ADDED")
    local Spec = s.ns.Spec
    eq(Spec.key, "frost", "spec")
    eq(table.concat(Spec.points, "/"), "3/10/2", "points")
    eq(Spec:TalentRank("blood_of_the_north"), 3, "talent rank")
    eq(Spec:TalentRank("butchery"), 0, "untaken talent")
    eq(Spec:HasGlyph("frost_strike"), true, "glyph")
    eq(Spec.supported, true, "frost supported")
end)

-- Loads the addon while the talent API still returns nothing, as it can
-- right after login. Returns the session and the real talent data.
local function addonWithTalentsNotLoaded()
    local Mock = require("wowmock")
    local s = Mock.NewSession()
    local talentTabs = s.talentTabs
    s.talentTabs = {}
    s:LoadAddon()
    return s, talentTabs
end

test("retries until talent data is available after login", function()
    local s, talentTabs = addonWithTalentsNotLoaded()
    local Spec = s.ns.Spec
    eq(Spec.loaded, false, "not loaded at login")
    eq(Spec.key, nil, "no spec yet")
    s.talentTabs = talentTabs
    s:Tick(1)
    eq(Spec.loaded, false, "not retried before the delay")
    s:Tick(1.5)
    eq(Spec.loaded, true, "loaded after retry")
    eq(Spec.key, "frost", "spec after retry")
    eq(Spec:TalentRank("killing_machine"), 5, "talents after retry")
end)

test("stops retrying after the retry limit", function()
    local s = addonWithTalentsNotLoaded()
    local Spec = s.ns.Spec
    for _ = 1, 40 do s:Tick(2.1) end
    eq(Spec.retries, 30, "retries capped")
    eq(Spec.retryTimer, nil, "no timer pending")
end)

test("/rh snapshot explains missing talent data", function()
    local s = addonWithTalentsNotLoaded()
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "snapshot")
    truthy(s:ChatContains("talent API returned no points %(0 trees, talent group 1%)"), "diagnostic")
end)

test("/rh snapshot re-reads talents", function()
    local s, talentTabs = addonWithTalentsNotLoaded()
    s.talentTabs = talentTabs -- loaded, but no event or retry has run yet
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "snapshot")
    truthy(s:ChatContains("frost %(3/10/2%)"), "fresh spec")
end)

test("a spec without a rotation is flagged unsupported", function()
    local s = newAddon()
    s.env.RotationHelper.classData.specs.blood = false -- as if Blood had no rotation
    s.talentTabs[1].talents[1][2] = 51
    s:FireEvent("PLAYER_TALENT_UPDATE")
    eq(s.ns.Spec.key, "blood", "spec")
    eq(s.ns.Spec.supported, false, "blood unsupported")
end)

test("known abilities follow the spellbook", function()
    local s = newAddon()
    falsy(s.ns.Spec.known.howling_blast, "not learned yet")
    s:Learn("Howling Blast", "Obliterate")
    truthy(s.ns.Spec.known.howling_blast, "learned")
    truthy(s.ns.Spec.known.obliterate, "learned")
end)

---------------------------------------------------------------------------
-- Runes and power
---------------------------------------------------------------------------
test("reads rune types and recharge times", function()
    local s = newAddon()
    s.runes[1].readyAt = s.time + 3.2
    s.runes[5].type = 4 -- frost rune converted to death
    local st = snapshot(s)
    eq(st.runes[1].type, "blood", "rune 1 type")
    near(st.runes[1].readyAt - st.now, 3.2, "rune 1 wait")
    eq(st.runes[2].readyAt, st.now, "rune 2 ready")
    eq(st.runes[5].type, "death", "death rune")
    local R = s.ns.Resources
    eq(R.RunesReady(st, "blood", st.now), 1, "blood ready")
    eq(R.RunesReady(st, "frost", st.now), 1, "frost ready")
    eq(R.RunesReady(st, "death", st.now), 1, "death ready")
    eq(R.RunesReady(st, "blood", st.now + 3.2), 2, "blood ready later")
end)

test("learns hasted rune regen from a recharging rune", function()
    local s = newAddon()
    eq(snapshot(s).runeRegen, 10, "base regen")
    s.runeRegen = 9
    s.runes[3].readyAt = s.time + 4
    eq(snapshot(s).runeRegen, 9, "hasted regen")
end)

test("reads runic power", function()
    local s = newAddon()
    s.power.current = 85
    local st = snapshot(s)
    eq(st.powerType, "runic_power", "type")
    eq(st.power, 85, "current")
    eq(st.powerMax, 130, "max")
end)

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------
test("reads tracked buffs and our debuffs", function()
    local s = newAddon()
    s.hasTarget = true
    s:AddAura("player", { name = "Killing Machine", spellId = 51124, duration = 30, expires = s.time + 12 })
    s:AddAura("player", { name = "Frost Presence", spellId = 48263 })
    s:AddAura("player", { name = "Some Trinket", spellId = 99999, duration = 10, expires = s.time + 5 })
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 9,
        harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + 7,
        harmful = true, caster = "party1" })
    local st = snapshot(s)
    near(st.buffs.killing_machine.expires - st.now, 12, "KM remaining")
    eq(st.buffs.frost_presence.expires, math.huge, "permanent aura")
    falsy(st.buffs.some_trinket, "untracked aura ignored")
    near(st.debuffs.frost_fever.expires - st.now, 9, "our frost fever")
    falsy(st.debuffs.blood_plague, "someone else's blood plague ignored")
end)

test("matches auras by name when the spell ID differs", function()
    local s = newAddon()
    s:AddAura("player", { name = "Freezing Fog", spellId = 12345, count = 2, duration = 15, expires = s.time + 10 })
    local st = snapshot(s)
    truthy(st.buffs.freezing_fog, "matched by name")
    eq(st.buffs.freezing_fog.stacks, 2, "stacks")
end)

test("expired auras disappear on the next snapshot", function()
    local s = newAddon()
    s:AddAura("player", { name = "Killing Machine", spellId = 51124, duration = 30, expires = s.time + 12 })
    truthy(snapshot(s).buffs.killing_machine, "present")
    s.auras.player = {}
    falsy(snapshot(s).buffs.killing_machine, "gone")
end)

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
test("reads GCD from the reference spell", function()
    local s = newAddon()
    s.cooldowns["Death Coil"] = { s.time - 0.5, 1.5 }
    local st = snapshot(s)
    near(st.gcdRemains, 1.0, "GCD remaining")
    eq(st.gcdDuration, 1.5, "GCD duration")
end)

test("GCD is 1s in Unholy Presence", function()
    local s = newAddon()
    s:AddAura("player", { name = "Unholy Presence", spellId = 48265 })
    eq(snapshot(s).gcdDuration, 1.0, "unholy presence GCD")
end)

test("reads real cooldowns and ignores GCD and rune recharge", function()
    local s = newAddon()
    s.cooldowns["Howling Blast"] = { s.time - 2, 8 }
    s.cooldowns["Unbreakable Armor"] = { s.time - 0.5, 1.5 } -- just the GCD
    s.cooldowns["Death and Decay"] = { s.time - 4, 10 }       -- rune recharge, not its 30s CD
    s.cooldowns["Horn of Winter"] = { s.time - 5, 20 }
    local st = snapshot(s)
    local Remains = s.ns.Cooldowns.Remains
    near(Remains(st.cooldowns.howling_blast, st.now), 6, "howling blast")
    eq(Remains(st.cooldowns.unbreakable_armor, st.now), 0, "GCD ignored")
    eq(Remains(st.cooldowns.death_and_decay, st.now), 0, "rune recharge ignored")
    near(Remains(st.cooldowns.horn_of_winter, st.now), 15, "horn (no runes, 20s cd)")
    falsy(st.cooldowns.obliterate, "no entry for abilities without a cooldown")
end)

---------------------------------------------------------------------------
-- Target
---------------------------------------------------------------------------
test("reads target info", function()
    local s = newAddon()
    local st = snapshot(s)
    eq(st.target.exists, false, "no target")
    s.hasTarget = true
    s.target.health = 25
    st = snapshot(s)
    eq(st.target.exists, true, "has target")
    eq(st.target.name, "Training Dummy", "name")
    eq(st.target.healthPct, 25, "health %")
    eq(st.target.level, -1, "boss level")
    eq(st.target.canAttack, true, "attackable")
end)

---------------------------------------------------------------------------
-- /rh snapshot
---------------------------------------------------------------------------
test("/rh snapshot prints the state", function()
    local s = newAddon()
    s.hasTarget = true
    s.glyphs[1] = 58647
    s:Learn("Howling Blast", "Horn of Winter")
    s.runes[4].readyAt = s.time + 2.5
    s.power.current = 60
    s.cooldowns["Howling Blast"] = { s.time - 2, 8 }
    s:AddAura("player", { name = "Killing Machine", spellId = 51124, duration = 30, expires = s.time + 12 })
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 9, harmful = true })
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "snapshot")
    local out = table.concat(s.chat, "\n")
    truthy(out:find("frost %(3/10/2%)"), "spec line")
    truthy(out:find("B ready | B ready | U ready | U 2.5 | F ready | F ready"), "runes line")
    truthy(out:find("runic_power 60/130"), "power line")
    truthy(out:find("killing_machine 12"), "buff")
    truthy(out:find("Training Dummy, level %?%?"), "target line")
    truthy(out:find("frost_fever 9.0"), "debuff")
    truthy(out:find("howling_blast 6.0"), "cooldown")
    truthy(out:find("obliterate"), "not in spellbook list")
    truthy(out:find("blood_of_the_north 3"), "talent")
    truthy(out:find("frost_strike"), "glyph")
end)

test("/rh snapshot on an unsupported class says so", function()
    local s = newAddon({ class = "MONK" })
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "snapshot")
    truthy(s:ChatContains("No class data for MONK"), "message")
end)
