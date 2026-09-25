-- Offline test runner. From the repo root:
--   lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local Mock = require("wowmock")

local passed, failed = 0, 0
local current

local function test(name, fn)
    current = name
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  PASS  " .. name)
    else
        failed = failed + 1
        print("  FAIL  " .. name .. "\n        " .. tostring(err))
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(v, what)
    if not v then error((what or "value") .. " was not truthy", 2) end
end

---------------------------------------------------------------------------
print("Syntax")
---------------------------------------------------------------------------
-- Compile (but don't run) every .lua file in the addon, libraries included.
local listing = io.popen('dir /s /b "RotationHelper\\*.lua" 2>nul') or io.popen('find RotationHelper -name "*.lua"')
for path in listing:lines() do
    path = path:gsub("\r", "")
    test("compiles " .. path:match("RotationHelper[\\/].*$"), function()
        local chunk, err = loadfile(path)
        truthy(chunk, err)
    end)
end
listing:close()

---------------------------------------------------------------------------
print("Core")
---------------------------------------------------------------------------
local function newAddon(class)
    local s = Mock.NewSession({ class = class })
    local RH = s:LoadAddon()
    return s, RH
end

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
    local s, RH = newAddon("MAGE")
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

test("key binding globals exist", function()
    local s = newAddon()
    eq(s.env.BINDING_HEADER_ROTATIONHELPER, "RotationHelper", "header")
    truthy(s.env.BINDING_NAME_ROTATIONHELPER_TOGGLE_COOLDOWNS, "cooldowns binding name")
end)

test("update loop is throttled and respects invalidate/pause", function()
    local s, RH = newAddon()
    local calls = 0
    RH:RegisterUpdater(function() calls = calls + 1 end)

    s:Tick(0.01) -- dirty from load -> runs immediately
    eq(calls, 1, "first tick")
    s:Tick(0.05)
    eq(calls, 1, "throttled")
    s:Tick(0.06)
    eq(calls, 2, "after interval")
    RH:Invalidate()
    s:Tick(0.01)
    eq(calls, 3, "invalidate forces update")

    s:Slash("ACECONSOLE_RH", "pause")
    s:Tick(0.2)
    eq(calls, 3, "paused")
    s:Slash("ACECONSOLE_RH", "pause")
    s:Tick(0.01)
    eq(calls, 4, "resumed")
end)

test("combat events set inCombat", function()
    local s, RH = newAddon()
    s:FireEvent("PLAYER_REGEN_DISABLED")
    eq(RH.inCombat, true, "entering combat")
    s:FireEvent("PLAYER_REGEN_ENABLED")
    eq(RH.inCombat, false, "leaving combat")
end)

---------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
