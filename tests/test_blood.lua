-- Blood Death Knight: DPS rotation, tanking in Frost Presence, Rune Strike.
local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local ALL_SPELLS = { "Icy Touch", "Plague Strike", "Blood Strike", "Pestilence", "Blood Boil", "Death and Decay",
    "Death Coil", "Death Strike", "Horn of Winter", "Blood Tap", "Empower Rune Weapon", "Army of the Dead",
    "Heart Strike", "Rune Strike", "Dancing Rune Weapon", "Hysteria", "Rune Tap", "Vampiric Blood", "Mind Freeze" }

-- A 51/0/20 style Blood DK in combat with a dummy, Horn up.
local function Fight(opts)
    opts = opts or {}
    local s, RH = newAddon()
    s.talentTabs = {
        { name = "Blood", talents = {
            { "Heart Strike", 1 }, { "Dancing Rune Weapon", 1 }, { "Hysteria", 1 }, { "Rune Tap", 1 },
            { "Vampiric Blood", 1 }, { "Butchery", 2 }, { "Subversion", 3 }, { "Bladed Armor", 5 },
            { "Blood-Caked Blade", 3 }, { "Veteran of the Third War", 3 }, { "Might of Mograine", 3 },
            { "Bloody Vengeance", 3 }, { "Improved Death Strike", 2 }, { "Sudden Doom", 3 },
            { "Blood Gorged", 5 }, { "Dark Conviction", 5 }, { "Abomination's Might", 2 },
        } },
        { name = "Frost", talents = { { "Improved Icy Touch", 3 } } },
        { name = "Unholy", talents = { { "Epidemic", 2 }, { "Virulence", 3 }, { "Morbidity", 3 } } },
    }
    s:Learn(unpack(ALL_SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_TALENT_UPDATE")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = opts.cooldowns or false
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 900 })
    if opts.tank then s:AddAura("player", { name = "Frost Presence", spellId = 48263, duration = 0, expires = 0 }) end
    return s, RH
end

local function Diseases(s)
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 21, expires = s.time + 20, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 21, expires = s.time + 20, harmful = true })
end

-- The predicted queue: "name +wait, ...".
local function Queue(s, count)
    s:Tick(0.1)
    local out = {}
    for i, e in ipairs(s.env.RotationHelper.recommendations or {}) do
        if i > count then break end
        out[#out + 1] = e.wait < 0.05 and e.name or ("%s +%.1f"):format(e.name, e.wait)
    end
    return table.concat(out, ", ")
end

test("blood is a supported spec with its own rotation", function()
    local s = Fight()
    eq(s.ns.Spec.key, "blood", "spec")
    truthy(s.ns.Spec.supported, "supported")
    local apl = s.ns.Recommender:GetAPL()
    eq(apl.name, "Blood (default)", "rotation")
    eq(#apl.errors, 0, "compiles cleanly")
end)

---------------------------------------------------------------------------
-- DPS
---------------------------------------------------------------------------
test("DPS: diseases first, then Heart Strike and Death Strike", function()
    local s = Fight()
    eq(Queue(s, 4), "icy_touch, plague_strike +1.5, heart_strike +3.0, death_strike +4.5", "opener")
end)

test("DPS: Death Strike with full frost/unholy pairs, Heart Strike with the blood runes", function()
    local s = Fight()
    Diseases(s)
    eq(Queue(s, 4), "death_strike, heart_strike +1.5, death_strike +3.0, heart_strike +4.5", "diseases up")
end)

test("DPS: Death Coil at the runic power cap", function()
    local s = Fight()
    Diseases(s)
    s.power.current = 125
    eq(Queue(s, 1), "death_coil", "cap")
end)

test("DPS cooldowns: Dancing Rune Weapon and Hysteria", function()
    local s = Fight({ cooldowns = true })
    Diseases(s)
    s.power.current = 60
    eq(Queue(s, 3), "dancing_rune_weapon, hysteria, death_strike +1.5", "cooldowns")
    s.power.current = 50
    eq(Queue(s, 2), "hysteria, death_strike", "not enough runic power for the weapon")
end)

test("DPS AoE: Pestilence spreads, Death and Decay, Blood Boil on 4+", function()
    local s, RH = Fight()
    Diseases(s)
    RH.db.profile.toggles.aoeMode = "aoe"
    eq(Queue(s, 2), "pestilence, death_and_decay +1.5", "3 targets (forced)")
end)

---------------------------------------------------------------------------
-- Tanking
---------------------------------------------------------------------------
test("tank: Frost Presence switches to the tank list", function()
    local s = Fight({ tank = true })
    Diseases(s)
    s.power.current = 40
    eq(Queue(s, 4), "death_strike, death_strike +1.5, heart_strike +3.0, heart_strike +4.5", "strikes")
end)

test("tank: Rune Strike after a dodge or parry, not while queued or without runic power", function()
    local s = Fight({ tank = true })
    Diseases(s)
    s.power.current = 40
    s.usable["Rune Strike"] = true
    eq(Queue(s, 2), "rune_strike, death_strike", "usable: off the GCD")
    s.current["Rune Strike"] = true
    eq(Queue(s, 1), "death_strike", "already queued for the next swing")
    s.current["Rune Strike"] = false
    s.power.current = 10
    eq(Queue(s, 1), "death_strike", "not enough runic power")
    s.usable["Rune Strike"] = false
    s.power.current = 40
    eq(Queue(s, 1), "death_strike", "no dodge or parry")
end)

test("tank: Rune Tap and Vampiric Blood when hurt", function()
    local s = Fight({ tank = true })
    Diseases(s)
    s.player.health = 14000 -- 70%
    eq(Queue(s, 2), "rune_tap, death_strike", "70%")
    s.player.health = 8000 -- 40%
    eq(Queue(s, 3), "rune_tap, vampiric_blood, death_strike", "40%")
    local st = s.ns.State:Reset()
    eq(math.floor(st.healthPct + 0.5), 40, "health.pct")
end)

test("tank: runic power is kept for Rune Strike; Death Coil only near the cap", function()
    local s = Fight({ tank = true })
    Diseases(s)
    s.power.current = 90
    eq(Queue(s, 1), "death_strike", "90: kept")
    s.power.current = 110
    eq(Queue(s, 1), "death_coil", "110: near the cap")
end)

test("simulator: the Blood DPS rotation looks sane", function()
    local s = Fight()
    local summary = s.ns.Sim.Summarize(s.ns.Recommender:GetAPL(), { seconds = 180, cooldowns = true }, 2)
    truthy(summary.gcdUsage > 80, "time spent casting " .. summary.gcdUsage)
    local casts = {}
    for _, c in ipairs(summary.casts) do casts[c.key] = c.perMinute end
    truthy((casts.heart_strike or 0) > 8, "Heart Strike per minute " .. tostring(casts.heart_strike))
    truthy((casts.death_strike or 0) > 5, "Death Strike per minute " .. tostring(casts.death_strike))
    for _, d in ipairs(summary.debuffs) do truthy(d.uptime > 85, d.key .. " uptime " .. d.uptime) end
end)
