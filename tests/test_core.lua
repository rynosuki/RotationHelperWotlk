local T = require("testlib")
local test, eq, truthy, newAddon = T.test, T.eq, T.truthy, T.newAddon

test("loads and initializes", function()
    local s, RH = newAddon()
    truthy(RH, "RotationHelper global")
    truthy(RH.db, "AceDB database")
    eq(RH.version, s.toc.Version, "version from TOC")
    eq(RH.playerClass, "DEATHKNIGHT", "class")
    eq(RH.classSupported, true, "classSupported")
    truthy(s.env.SlashCmdList.ACECONSOLE_RH, "/rh registered")
    truthy(s.env.SlashCmdList.ACECONSOLE_ROTATIONHELPER, "/rotationhelper registered")
end)

test("unsupported class stays idle and says so", function()
    local s, RH = newAddon({ class = "MAGE" })
    eq(RH.classSupported, false, "classSupported")
    eq(RH:IsActive(), false, "IsActive")
    truthy(s:ChatContains("No rotation available for MAGE"), "idle notice")
end)

test("/rh with no args prints help", function()
    local s = newAddon()
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "")
    truthy(s:ChatContains("/rh cd"), "help lists commands")
end)

test("/rh cd toggles cooldowns", function()
    local s, RH = newAddon()
    eq(RH.db.profile.toggles.cooldowns, true, "default")
    s:Slash("ACECONSOLE_RH", "cd")
    eq(RH.db.profile.toggles.cooldowns, false, "after toggle")
    s:Slash("ACECONSOLE_RH", "CD")
    eq(RH.db.profile.toggles.cooldowns, true, "case-insensitive toggle back")
end)

test("/rh aoe cycles auto -> single -> aoe -> auto", function()
    local s, RH = newAddon()
    local seen = { RH.db.profile.toggles.aoeMode }
    for _ = 1, 3 do
        s:Slash("ACECONSOLE_RH", "aoe")
        seen[#seen + 1] = RH.db.profile.toggles.aoeMode
    end
    eq(table.concat(seen, ","), "auto,single,aoe,auto", "cycle")
end)

test("/rh reset restores defaults", function()
    local s, RH = newAddon()
    s:Slash("ACECONSOLE_RH", "cd")
    s:Slash("ACECONSOLE_RH", "lock")
    s:Slash("ACECONSOLE_RH", "reset")
    eq(RH.db.profile.toggles.cooldowns, true, "cooldowns")
    eq(RH.db.profile.display.locked, false, "locked")
end)

test("unknown command reports and shows help", function()
    local s = newAddon()
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "bogus")
    truthy(s:ChatContains("Unknown command 'bogus'"), "error message")
    truthy(s:ChatContains("/rh status"), "help")
end)

test("/rh scale and /rh icons validate their argument", function()
    local s, RH = newAddon()
    s:Slash("ACECONSOLE_RH", "scale 1.5")
    eq(RH.db.profile.display.scale, 1.5, "scale")
    s:Slash("ACECONSOLE_RH", "scale 10")
    eq(RH.db.profile.display.scale, 1.5, "out-of-range scale ignored")
    s:ClearChat()
    s:Slash("ACECONSOLE_RH", "icons abc")
    truthy(s:ChatContains("Usage: /rh icons"), "usage message")
    s:Slash("ACECONSOLE_RH", "icons 2.6")
    eq(RH.db.profile.display.numIcons, 3, "icons rounded")
end)

test("key binding globals exist", function()
    local s = newAddon()
    eq(s.env.BINDING_HEADER_ROTATIONHELPER, "RotationHelper", "header")
    truthy(s.env.BINDING_NAME_ROTATIONHELPER_TOGGLE_COOLDOWNS, "cooldowns binding name")
end)

test("update loop is throttled and respects invalidate/pause", function()
    local s, RH = newAddon()
    local calls = 0
    RH:RegisterUpdater(function() calls = calls + 1 end)

    s:Tick(0.05) -- dirty from load -> runs as soon as spacing allows
    eq(calls, 1, "first tick")
    s:Tick(0.05)
    eq(calls, 1, "nothing changed: waits for the 0.1s interval")
    s:Tick(0.06)
    eq(calls, 2, "after interval")
    RH:Invalidate()
    s:Tick(0.02)
    eq(calls, 2, "a change still waits for the 0.05s spacing")
    s:Tick(0.03)
    eq(calls, 3, "invalidate forces an early update")

    s:Slash("ACECONSOLE_RH", "pause")
    s:Tick(0.2)
    eq(calls, 3, "paused")
    s:Slash("ACECONSOLE_RH", "pause")
    s:Tick(0.05)
    eq(calls, 4, "resumed")
end)

test("constant changes still cap updates at 20 per second", function()
    local s, RH = newAddon()
    local calls = 0
    RH:RegisterUpdater(function() calls = calls + 1 end)
    for _ = 1, 60 do -- one second at 60 fps, something changing every frame
        RH:Invalidate()
        s:Tick(1 / 60)
    end
    truthy(calls <= 20 and calls >= 15, "updates in one second: " .. calls)
end)

test("updaters run by order, not registration order", function()
    local s, RH = newAddon()
    local calls = {}
    RH:RegisterUpdater(function() calls[#calls + 1] = "late" end, 200)
    RH:RegisterUpdater(function() calls[#calls + 1] = "early" end, 1)
    RH:RegisterUpdater(function() calls[#calls + 1] = "default" end)
    s.ns.Recommender.Update = function() end
    s:Tick(0.2)
    eq(table.concat(calls, ","), "early,default,late", "order")
end)

test("combat events set inCombat", function()
    local s, RH = newAddon()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    eq(RH.inCombat, true, "entering combat")
    s:FireEvent("PLAYER_REGEN_ENABLED")
    eq(RH.inCombat, false, "leaving combat")
end)
