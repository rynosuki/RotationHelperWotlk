local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local ALL_SPELLS = {
    "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
    "Pestilence", "Horn of Winter", "Death Coil", "Unbreakable Armor", "Blood Tap",
    "Empower Rune Weapon", "Deathchill",
}

-- A DK mid-fight: diseases up, some runes recharging, procs, keybinds, the
-- display locked and showing the full queue.
local function MidFight()
    local s, RH = newAddon()
    s:Learn(unpack(ALL_SPELLS))
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s:Slash("ACECONSOLE_RH", "lock")
    s:Slash("ACECONSOLE_RH", "icons 5")
    s:PlaceSpell(1, 51425, "ACTIONBUTTON1", "1")
    s:PlaceSpell(2, 55268, "ACTIONBUTTON2", "2")
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("player", { name = "Killing Machine", spellId = 51124, duration = 30, expires = s.time + 900 })
    s.runes[3].readyAt = s.time + 4
    s.power.current = 70
    return s, RH
end

test("/rh perf reports updates and memory", function()
    local s = MidFight()
    for _ = 1, 20 do s:Tick(0.1) end
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "perf")
    truthy(s:ChatContains("Updates:.*%(%d+%.%d per second%)"), "update rate")
    truthy(s:ChatContains("ms average"), "timing")
    truthy(s:ChatContains("Memory: 250 KB"), "memory")
    truthy(s:ChatContains("/console scriptProfile 1"), "hint when profiling is off")
end)

test("/rh perf shows CPU when script profiling is on, and resets", function()
    local s, RH = MidFight()
    s.cvars.scriptProfile = "1"
    s.cpuMs = 1234
    s:Tick(0.1)
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "perf")
    truthy(s:ChatContains("Total CPU: 1234 ms"), "cpu")
    s:Slash("ACECONSOLE_RH", "perf reset")
    eq(RH.perf.updates, 0, "reset")
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "perf")
    truthy(s:ChatContains("Updates: none yet"), "empty after reset")
end)

test("a full update cycle creates no garbage", function()
    local s = MidFight()
    for _ = 1, 50 do s:Tick(0.1) end -- warm up pools and caches
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 500 do s:Tick(0.1) end
    local perUpdate = (collectgarbage("count") - before) * 1024 / 500
    collectgarbage("restart")
    -- Allow a few bytes for the mock's own bookkeeping.
    truthy(perUpdate < 16, ("%.1f bytes of garbage per update"):format(perUpdate))
end)

test("the display skips client calls when nothing changed", function()
    local s = MidFight()
    s:Tick(0.1)
    local icon = s.ns.Display.buttons[1].icon
    local calls = 0
    local original = icon.SetTexture
    icon.SetTexture = function(...) calls = calls + 1; return original(...) end
    for _ = 1, 10 do s:Tick(0.1) end
    eq(calls, 0, "no SetTexture while the recommendation is unchanged")
end)

test("no garbage per update while a spell that just landed is applied", function()
    local s = MidFight()
    -- The cast event itself goes through Ace3's dispatch (once per cast);
    -- it's measured separately and left out.
    local eventKB = 0
    local function Cycle()
        local before = collectgarbage("count")
        s:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Icy Touch")
        eventKB = eventKB + collectgarbage("count") - before
        for _ = 1, 5 do s:Tick(0.1) end -- inside the 1 second grace
    end
    for _ = 1, 20 do Cycle() end -- warm up
    collectgarbage("collect")
    collectgarbage("stop")
    eventKB = 0
    local before = collectgarbage("count")
    for _ = 1, 100 do Cycle() end
    local perUpdate = (collectgarbage("count") - before - eventKB) * 1024 / 500
    collectgarbage("restart")
    truthy(perUpdate < 16, ("%.1f bytes of garbage per update"):format(perUpdate))
end)
