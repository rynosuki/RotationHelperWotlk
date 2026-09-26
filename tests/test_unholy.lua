local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local ALL_SPELLS = {
    "Icy Touch", "Plague Strike", "Scourge Strike", "Blood Strike", "Death Coil", "Pestilence",
    "Blood Boil", "Death and Decay", "Horn of Winter", "Raise Dead", "Ghoul Frenzy",
    "Summon Gargoyle", "Bone Shield", "Blood Tap", "Empower Rune Weapon",
}

-- An Unholy DK (0/17/54-ish) with a ghoul, fighting a dummy. Horn of
-- Winter and Bone Shield are up and cooldowns are off unless asked, to keep
-- scenarios focused.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon()
    s.talentTabs = {
        { name = "Blood", talents = { { "Subversion", 3 } } },
        { name = "Frost", talents = { { "Icy Talons", 5 }, { "Improved Icy Talons", 1 } } },
        { name = "Unholy", talents = {
            { "Reaping", 3 }, { "Desolation", 5 }, { "Dirge", 2 }, { "Master of Ghouls", 1 },
            { "Epidemic", 2 }, { "Ghoul Frenzy", 1 }, { "Bone Shield", 1 }, { "Summon Gargoyle", 1 },
        } },
    }
    s:Learn(unpack(ALL_SPELLS))
    s.hasTarget = true
    s.petAlive = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    if not opts.noBuffs then
        s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 120 })
        s:AddAura("player", { name = "Bone Shield", spellId = 49222, duration = 300, expires = s.time + 300 })
    end
    return s, RH
end

local function Diseases(s)
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 21, expires = s.time + 20, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 21, expires = s.time + 20, harmful = true })
end

local function Desolation(s)
    s:AddAura("player", { name = "Desolation", spellId = 66803, duration = 20, expires = s.time + 15 })
end

-- Ghoul Frenzy was just cast, so its line_cd keeps it out of the way.
local function GhoulFrenzyUsed(s)
    s:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Ghoul Frenzy", "")
end

local function RunesDown(s, seconds, ...)
    for i = 1, select("#", ...) do s.runes[(select(i, ...))].readyAt = s.time + seconds end
end

local function Recommend(s)
    local st = s.ns.State:Reset()
    local action, t, limitedBy = s.ns.Recommender:Evaluate(st)
    if not action then return nil end
    local wait = t - st.now
    if wait < 1e-9 then return action.name end
    return ("%s +%.1f (%s)"):format(action.name, wait, tostring(limitedBy))
end

local function Queue(s, count)
    s.ns.State:Reset()
    local recs, n = s.ns.Recommender:Predict(count)
    local out = {}
    for i = 1, n do
        local e = recs[i]
        out[i] = e.name .. (e.wait > 1e-6 and (" +%.1f"):format(e.wait) or "")
    end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------------
test("the default Unholy APL compiles cleanly and is picked for Unholy", function()
    local s = Fight()
    eq(s.ns.Spec.key, "unholy", "spec")
    local apl = s.ns.Recommender:GetAPL()
    local messages = {}
    for _, err in ipairs(apl.errors) do messages[#messages + 1] = s.ns.APL.Compiler.FormatError(err) end
    eq(table.concat(messages, "\n"), "", "errors")
    eq(apl.name, "Unholy (default)", "name")
end)

test("opener on a fresh target", function()
    local s = Fight()
    -- Plague Strike, Icy Touch, Blood Strike for Desolation, Ghoul Frenzy,
    -- then the other blood rune: frost and unholy runes are all recharging.
    eq(Queue(s, 5), "plague_strike, icy_touch +1.5, blood_strike +3.0, ghoul_frenzy +4.5, blood_strike +6.0", "queue")
end)

test("Scourge Strike with runes up, Desolation up", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    eq(Recommend(s), "scourge_strike", "recommendation")
end)

test("Blood Strike first when Desolation is about to drop", function()
    local s = Fight()
    Diseases(s)
    GhoulFrenzyUsed(s)
    s:AddAura("player", { name = "Desolation", spellId = 66803, duration = 20, expires = s.time + 1 })
    eq(Recommend(s), "blood_strike", "refresh Desolation")
end)

test("Blood Strike spends blood runes when Scourge Strike can't go", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    RunesDown(s, 5, 3, 4, 5, 6)
    eq(Recommend(s), "blood_strike", "recommendation")
end)

test("Death Coil when the runes are down", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    RunesDown(s, 5, 1, 2, 3, 4, 5, 6)
    s.power.current = 50
    eq(Recommend(s), "death_coil", "recommendation")
end)

test("Death Coil before capping runic power, even with runes up", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    s.power.current = 125
    eq(Recommend(s), "death_coil", "recommendation")
end)

test("Reaping death runes feed Scourge Strike", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    RunesDown(s, 8, 3, 4, 5, 6)
    s.cooldowns["Horn of Winter"] = { s.time, 20 }
    -- Two Blood Strikes turn both blood runes into death runes (ready 10s
    -- later), which then pay for Scourge Strike's frost + unholy.
    eq(Queue(s, 3), "blood_strike, blood_strike +1.5, scourge_strike +8.0", "queue")
end)

test("simulated casts: Dirge runic power and Desolation", function()
    local s = Fight()
    s.ns.State:Reset()
    local v = s.ns.State:Virtual()
    s.ns.Abilities.Apply(v, "scourge_strike", v.now)
    eq(v.power, 20, "15 + 5 from Dirge")
    s.ns.Abilities.Apply(v, "blood_strike", v.now + 1.5)
    truthy(v.buffs.desolation, "Desolation applied")
    eq(v.runes[1].type, "death", "Reaping made a death rune")
end)

---------------------------------------------------------------------------
-- The ghoul
---------------------------------------------------------------------------
test("Ghoul Frenzy about every 25 seconds, only with a ghoul", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    RunesDown(s, 5, 5, 6) -- no frost rune: no Scourge Strike
    RunesDown(s, 5, 1, 2)
    eq(Recommend(s), "ghoul_frenzy", "with a ghoul")
    GhoulFrenzyUsed(s)
    falsy(Recommend(s) == "ghoul_frenzy", "not again right after")
    s.time = s.time + 26
    s.auras.target, s.auras.player = {}, {}
    Diseases(s)
    Desolation(s)
    s:AddAura("player", { name = "Bone Shield", spellId = 49222, duration = 300, expires = s.time + 300 })
    RunesDown(s, 5, 1, 2, 5, 6)
    eq(Recommend(s), "ghoul_frenzy", "again after 25s")
end)

test("no ghoul: skip Ghoul Frenzy, suggest Raise Dead", function()
    local s = Fight()
    s.petAlive = false
    Diseases(s)
    Desolation(s)
    RunesDown(s, 5, 1, 2, 5, 6)
    eq(Recommend(s), "raise_dead", "resummon")
end)

test("out of combat: Horn, ghoul, Bone Shield", function()
    local s = Fight({ noBuffs = true })
    s:FireEvent("PLAYER_REGEN_ENABLED")
    s.hasTarget = false
    s.petAlive = false
    eq(Queue(s, 3), "horn_of_winter, raise_dead +1.5, bone_shield +3.0", "precombat")
end)

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
test("Summon Gargoyle waits for a burst window, 15s at most", function()
    local s = Fight({ cooldowns = true })
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    s.power.current = 60
    eq(Recommend(s), "scourge_strike", "held right after it became ready")
    s:AddAura("player", { name = "Bloodlust", spellId = 2825, duration = 40, expires = s.time + 40 })
    eq(Recommend(s), "summon_gargoyle", "Bloodlust")
    s.power.current = 50
    eq(Recommend(s), "scourge_strike", "not enough runic power")

    s = Fight({ cooldowns = true })
    Diseases(s)
    Desolation(s)
    s.power.current = 60
    Recommend(s)
    s.time = s.time + 16
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    eq(Recommend(s), "summon_gargoyle", "ready for more than 15s")
end)

test("Blood Tap for Bone Shield when no unholy rune is ready", function()
    local s = Fight({ cooldowns = true, noBuffs = true })
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 120 })
    Diseases(s)
    Desolation(s)
    GhoulFrenzyUsed(s)
    RunesDown(s, 6, 3, 4)
    eq(Queue(s, 2), "blood_tap, bone_shield", "the death rune pays for Bone Shield")
end)

---------------------------------------------------------------------------
-- AoE
---------------------------------------------------------------------------
test("two enemies: Pestilence, then Death and Decay", function()
    local s = Fight()
    Diseases(s)
    Desolation(s)
    local Mock = require("wowmock")
    s:CombatLog("SPELL_DAMAGE", Mock.PLAYER_GUID, Mock.FLAGS_ME, "mob2", Mock.FLAGS_HOSTILE_NPC)
    eq(Queue(s, 2), "pestilence, death_and_decay +1.5", "queue")
end)
