local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

-- In combat with a dummy, every rune recharging (no waste) to start with.
local function Fight()
    local s, RH = newAddon()
    s:Learn("Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Blood Strike")
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    s:Slash("ACECONSOLE_RH", "lock")
    for i = 1, 6 do s.runes[i].readyAt = s.time + 100 end
    return s, RH
end

local function Check(s, RH)
    return s.ns.Waste:Check(s.ns.State:Reset(), RH.db.profile.waste)
end

test("a capped rune pair warns after the grace period", function()
    local s, RH = Fight()
    s.runes[5].readyAt, s.runes[6].readyAt = s.time, s.time -- frost pair full
    falsy(Check(s, RH).runes, "not yet: within the grace period")
    s.time = s.time + 1
    falsy(Check(s, RH).runes, "1s: still within 1.5s")
    s.time = s.time + 0.6
    truthy(Check(s, RH).runes, "1.6s: warning")
    s.runes[5].readyAt = s.time + 10 -- spend one frost rune
    falsy(Check(s, RH).runes, "gone once a rune is spent")
end)

test("one ready rune per pair is fine", function()
    local s, RH = Fight()
    s.runes[1].readyAt, s.runes[3].readyAt, s.runes[5].readyAt = s.time, s.time, s.time
    s.time = s.time + 5
    falsy(Check(s, RH).runes, "no pair capped")
end)

test("runic power near the cap warns", function()
    local s, RH = Fight()
    s.power.current = 119
    falsy(Check(s, RH).runicPower, "119: fine")
    s.power.current = 120
    Check(s, RH)
    s.time = s.time + 2
    truthy(Check(s, RH).runicPower, "120 of 130 for 2s: warning")
    truthy(Check(s, RH).any, "any")
end)

test("no warnings out of combat, and the timer starts over", function()
    local s, RH = Fight()
    s.runes[1].readyAt, s.runes[2].readyAt = s.time, s.time
    s:FireEvent("PLAYER_REGEN_ENABLED")
    s.time = s.time + 10
    falsy(Check(s, RH).runes, "out of combat")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    falsy(Check(s, RH).runes, "grace starts again after re-entering combat")
end)

test("settings turn warnings off", function()
    local s, RH = Fight()
    s.runes[1].readyAt, s.runes[2].readyAt = s.time, s.time
    s.power.current = 130
    Check(s, RH)
    s.time = s.time + 2
    RH.db.profile.waste.runes = false
    local w = Check(s, RH)
    falsy(w.runes, "runes off")
    truthy(w.runicPower, "runic power still on")
    RH.db.profile.waste.enabled = false
    falsy(Check(s, RH).any, "all off")
end)

test("the display pulses and names the waste", function()
    local s, RH = Fight()
    s.power.current = 125
    s:Tick(0.1)
    s.time = s.time + 2
    s:Tick(0.1)
    local main = s.ns.Display.buttons[1]
    truthy(main.warn:IsShown(), "border shown")
    local a = main.warn.alpha
    s:Tick(0.07)
    truthy(main.warn.alpha ~= a, "pulsing")
    truthy(s.ns.Display:GetStatusText():find("RP"), "status names it")
    s.power.current = 0
    s:Tick(0.1)
    falsy(main.warn:IsShown(), "gone")
end)

test("the 'Enabled' option stays usable when warnings are off", function()
    local s, RH = newAddon()
    local args = s.ns.Options:GetOptionsTable().args.display.args
    RH.db.profile.waste.enabled = false
    falsy(args.enabled.disabled, "can be turned back on")
    truthy(args.runes.disabled(), "the others are greyed out")
    args.enabled.set({ "display", "enabled" }, true)
    eq(RH.db.profile.waste.enabled, true, "back on")
end)
