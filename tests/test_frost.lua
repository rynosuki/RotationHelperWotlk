local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local ALL_SPELLS = {
    "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
    "Pestilence", "Blood Boil", "Death and Decay", "Death Coil", "Death Strike", "Horn of Winter",
    "Blood Tap", "Unbreakable Armor", "Empower Rune Weapon", "Deathchill", "Army of the Dead",
    "Raise Dead", "Mind Freeze",
}

-- A Frost DK in combat with a training dummy, every ability learned.
-- Cooldowns are off unless `cooldowns` is set, to keep scenarios focused.
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
    if frostFever then
        s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15,
            expires = s.time + frostFever, harmful = true })
    end
    if bloodPlague then
        s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15,
            expires = s.time + bloodPlague, harmful = true })
    end
end

local function Buff(s, name, spellId, remains)
    s:AddAura("player", { name = name, spellId = spellId, duration = 30, expires = s.time + remains })
end

-- Rune slots: 1-2 blood, 3-4 unholy, 5-6 frost.
local function RunesDown(s, seconds, ...)
    for i = 1, select("#", ...) do
        s.runes[(select(i, ...))].readyAt = s.time + seconds
    end
end

-- Returns "action" or "action +wait (limitedBy)".
local function Recommend(s)
    local st = s.ns.State:Reset()
    local action, t, limitedBy = s.ns.Recommender:Evaluate(st)
    if not action then return nil end
    local wait = t - st.now
    if wait < 1e-9 then return action.name end
    return ("%s +%.1f (%s)"):format(action.name, wait, tostring(limitedBy))
end

---------------------------------------------------------------------------
test("the default Frost APL compiles cleanly", function()
    local s = Fight()
    local apl = s.ns.Recommender:GetAPL()
    truthy(apl, "APL")
    local messages = {}
    for _, err in ipairs(apl.errors) do messages[#messages + 1] = s.ns.APL.Compiler.FormatError(err) end
    eq(table.concat(messages, "\n"), "", "errors")
    eq(apl.name, "Frost (default)", "name")
    falsy(s:ChatContains("problem"), "no warnings printed")
end)

test("fresh target: Icy Touch first", function()
    local s = Fight()
    eq(Recommend(s), "icy_touch", "recommendation")
end)

test("Frost Fever up: Plague Strike", function()
    local s = Fight()
    Diseases(s, 15)
    eq(Recommend(s), "plague_strike", "recommendation")
end)

test("both diseases up, runes ready: Obliterate", function()
    local s = Fight()
    Diseases(s, 15, 15)
    eq(Recommend(s), "obliterate", "recommendation")
end)

test("Killing Machine: Frost Strike when runes are down", function()
    local s = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 5, 3, 4, 5, 6)
    s.power.current = 50
    Buff(s, "Killing Machine", 51124, 20)
    eq(Recommend(s), "frost_strike", "recommendation")
end)

test("Frost Strike to avoid capping runic power", function()
    local s = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 5, 3, 4, 5, 6)
    s.power.current = 110
    eq(Recommend(s), "frost_strike", "deficit < 25")
end)

test("Blood Strike with a blood rune and no runic power", function()
    local s = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 5, 3, 4, 5, 6)
    s.power.current = 10
    eq(Recommend(s), "blood_strike", "recommendation")
end)

test("Blood Strike doesn't spend death runes", function()
    local s = Fight()
    Diseases(s, 15, 15)
    s.runes[1].type, s.runes[2].type = 4, 4 -- both blood runes are death runes
    RunesDown(s, 5, 3, 4, 5, 6)
    s.power.current = 10
    s.cooldowns["Horn of Winter"] = { s.time, 20 }
    -- Death runes can pay for Obliterate's frost+unholy.
    eq(Recommend(s), "obliterate", "death runes go to Obliterate")
end)

test("Rime: free Howling Blast when nothing else is ready", function()
    local s = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 5, 1, 2, 3, 4, 5, 6)
    Buff(s, "Freezing Fog", 59052, 10)
    eq(Recommend(s), "howling_blast", "recommendation")
end)

test("Horn of Winter only when the buff is missing", function()
    local s = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 5, 1, 2, 3, 4, 5, 6)
    eq(Recommend(s), "horn_of_winter", "buff missing")
    Buff(s, "Horn of Winter", 57623, 100)
    eq(Recommend(s), "obliterate +5.0 (runes)", "buff up: no filler, next ability counts down")
end)

test("with nothing ready, show what comes next and when", function()
    local s = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 3, 1, 2, 3, 4)
    RunesDown(s, 5, 5, 6)
    s.cooldowns["Horn of Winter"] = { s.time, 20 }
    eq(Recommend(s), "blood_strike +3.0 (runes)", "blood runes come back first")
end)

test("during the GCD the next action waits for it", function()
    local s = Fight()
    Diseases(s, 15, 15)
    s.cooldowns["Death Coil"] = { s.time - 0.5, 1.5 }
    eq(Recommend(s), "obliterate +1.0 (gcd)", "recommendation")
end)

test("disease refresh is judged at the time of casting", function()
    local s = Fight()
    Diseases(s, 2.5, 15)
    eq(Recommend(s), "obliterate", "2.5s left now: not yet")
    s.cooldowns["Death Coil"] = { s.time - 0.5, 1.5 } -- 1s of GCD left
    eq(Recommend(s), "icy_touch +1.0 (gcd)", "1.5s left when the GCD ends")
end)

test("Glyph of Disease: Pestilence refreshes both diseases", function()
    local s = Fight()
    Diseases(s, 3, 10)
    eq(Recommend(s), "obliterate", "no glyph: wait for Icy Touch")
    s.glyphs[1] = 99999
    s.spells[99999] = { "Glyph of Disease", "i" }
    s:FireEvent("GLYPH_ADDED")
    eq(Recommend(s), "pestilence", "glyph: Pestilence")
end)

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
test("cooldowns off: no Unbreakable Armor", function()
    local s = Fight()
    Diseases(s, 15, 15)
    eq(Recommend(s), "obliterate", "recommendation")
end)

test("cooldowns on: Unbreakable Armor off the GCD", function()
    local s = Fight({ cooldowns = true })
    Diseases(s, 15, 15)
    s.cooldowns["Death Coil"] = { s.time - 0.5, 1.5 }
    eq(Recommend(s), "unbreakable_armor", "used during the GCD")
end)

test("cooldowns on: Blood Tap before Unbreakable Armor with the talent", function()
    local s = Fight({ cooldowns = true })
    table.insert(s.talentTabs[2].talents, { "Unbreakable Armor", 1 })
    s:FireEvent("PLAYER_TALENT_UPDATE")
    Diseases(s, 15, 15)
    eq(Recommend(s), "blood_tap", "recommendation")
    s.cooldowns["Blood Tap"] = { s.time, 60 }
    eq(Recommend(s), "unbreakable_armor", "after Blood Tap")
end)

test("cooldowns on: Deathchill only when Obliterate is castable", function()
    local s = Fight({ cooldowns = true })
    Diseases(s, 15, 15)
    s.cooldowns["Unbreakable Armor"] = { s.time, 60 }
    eq(Recommend(s), "deathchill", "runes ready")
    RunesDown(s, 5, 3, 4)
    s.power.current = 50
    eq(Recommend(s), "blood_strike", "no unholy rune: hold Deathchill")
end)

test("cooldowns on: Empower Rune Weapon when every rune is down", function()
    local s = Fight({ cooldowns = true })
    Diseases(s, 15, 15)
    s.cooldowns["Unbreakable Armor"] = { s.time, 60 }
    s.cooldowns["Horn of Winter"] = { s.time, 20 }
    RunesDown(s, 5, 1, 2, 3, 4, 5, 6)
    eq(Recommend(s), "empower_rune_weapon", "recommendation")
    RunesDown(s, 1.5, 1)
    falsy(Recommend(s) == "empower_rune_weapon", "not when a rune is almost back")
end)

---------------------------------------------------------------------------
-- AoE and targets
---------------------------------------------------------------------------
test("AoE mode: Pestilence spreads, then Howling Blast", function()
    local s, RH = Fight()
    RH.db.profile.toggles.aoeMode = "aoe"
    Diseases(s, 15, 15)
    eq(Recommend(s), "pestilence", "spread diseases")
    s:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Pestilence", "")
    s.runes[1].readyAt = s.time + 10
    eq(Recommend(s), "howling_blast", "after Pestilence (line_cd)")
end)

test("no recommendation without a hostile target in combat", function()
    local s = Fight()
    s.hasTarget = false
    eq(Recommend(s), nil, "no target")
    s.hasTarget = true
    s.target.dead = true
    eq(Recommend(s), nil, "dead target")
    s.target.dead = false
    s.target.canAttack = false
    eq(Recommend(s), nil, "friendly target")
end)

test("out of combat: Horn of Winter if the buff is missing", function()
    local s = Fight()
    s:FireEvent("PLAYER_REGEN_ENABLED")
    s.hasTarget = false
    eq(Recommend(s), "horn_of_winter", "precombat")
    Buff(s, "Horn of Winter", 57623, 100)
    eq(Recommend(s), nil, "buff up, no target")
    s.hasTarget = true
    eq(Recommend(s), "icy_touch", "buff up, target: main list")
end)

test("a spec without an APL recommends nothing", function()
    local s = Fight()
    s.talentTabs[1].talents[1][2] = 51
    s:FireEvent("PLAYER_TALENT_UPDATE")
    eq(Recommend(s), nil, "blood")
end)

---------------------------------------------------------------------------
-- Integration
---------------------------------------------------------------------------
test("the display shows the recommendation", function()
    local s, RH = Fight()
    s:Slash("ACECONSOLE_RH", "lock")
    Diseases(s, 15, 15)
    s:Tick(0.2)
    eq(RH.recommendations[1].spellId, 51425, "obliterate recommended")
    local D = s.ns.Display
    truthy(D.frame:IsShown(), "display shown")
    eq(D.buttons[1].icon:GetTexture(), "Interface\\Icons\\Spell_DeathKnight_ClassIcon", "obliterate icon")
    s.hasTarget = false
    s:Tick(0.2)
    eq(RH.recommendations, nil, "cleared without a target")
    falsy(D.frame:IsShown(), "display hidden")
end)

test("rune-limited recommendations are flagged for the blue tint", function()
    local s, RH = Fight()
    Diseases(s, 15, 15)
    RunesDown(s, 3, 1, 2, 3, 4)
    RunesDown(s, 5, 5, 6)
    s.cooldowns["Horn of Winter"] = { s.time, 20 }
    s:Tick(0.2)
    eq(RH.recommendations[1].lacksResources, true, "lacks resources")
    eq(math.floor(RH.recommendations[1].wait * 10 + 0.5), 28, "wait (3s minus the 0.2s tick)")
end)

test("/rh snapshot shows the decision", function()
    local s = Fight()
    Diseases(s, 15, 15)
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "snapshot")
    truthy(s:ChatContains("Recommendation:.*obliterate.* > "), "recommendation line with queue")
    truthy(s:ChatContains("default:obliterate  best so far"), "trace")
end)

test("/rh snapshot explains no recommendation", function()
    local s = Fight()
    s:ClearChat()
    s.hasTarget = false
    s:Slash("ACECONSOLE_RH", "snapshot")
    truthy(s:ChatContains("none %(no hostile target%)"), "reason")
end)
