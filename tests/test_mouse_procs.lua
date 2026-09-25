local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

-- In combat with a dummy, diseases up, display locked.
local function Fight()
    local s, RH = newAddon()
    s:Learn("Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
        "Horn of Winter")
    s.hasTarget = true
    s:FireEvent("PLAYER_REGEN_DISABLED")
    RH.db.profile.toggles.cooldowns = false
    s:Slash("ACECONSOLE_RH", "lock")
    s:AddAura("target", { name = "Frost Fever", spellId = 55095, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("target", { name = "Blood Plague", spellId = 55078, duration = 15, expires = s.time + 900, harmful = true })
    s:AddAura("player", { name = "Horn of Winter", spellId = 57623, duration = 120, expires = s.time + 900 })
    return s, RH
end

local function Hover(s, i)
    local b = s.ns.Display.buttons[i]
    b.scripts.OnEnter(b)
    return s.env.GameTooltip
end

local function Buff(s, name, spellId, remains)
    s:AddAura("player", { name = name, spellId = spellId, duration = 30, expires = s.time + remains })
end

---------------------------------------------------------------------------
-- A6: Shift mouse mode
---------------------------------------------------------------------------
test("Shift turns on mouse input, releasing it turns it off", function()
    local s = Fight()
    local D = s.ns.Display
    s:Tick(0.1)
    falsy(D.buttons[1].mouseEnabled, "click-through normally")
    s.shift = true
    s:Tick(0.02)
    truthy(D.buttons[1].mouseEnabled, "icons take the mouse")
    truthy(D.frame.cdChip.mouseEnabled, "chips too")
    Hover(s, 1)
    truthy(s.env.GameTooltip.shown, "tooltip")
    s.shift = false
    s:Tick(0.02)
    falsy(D.buttons[1].mouseEnabled, "back to click-through")
    falsy(s.env.GameTooltip.shown, "tooltip hidden")
end)

test("no mouse mode while unlocked, or when turned off", function()
    local s, RH = Fight()
    local D = s.ns.Display
    s.shift = true
    RH.db.profile.display.shiftInteract = false
    s:Tick(0.1)
    falsy(D.mouseMode, "setting off")
    RH.db.profile.display.shiftInteract = true
    s:Slash("ACECONSOLE_RH", "lock") -- unlock
    s:Tick(0.1)
    falsy(D.mouseMode, "unlocked: dragging instead")
end)

test("tooltip explains the recommendation", function()
    local s = Fight()
    s:Tick(0.1)
    local tip = Hover(s, 1)
    eq(tip.link, "spell:51425", "spell tooltip (Obliterate)")
    local text = tip:Text()
    truthy(text:find("Frost %(default%), main list, line %d+"), "which line")
    truthy(text:find("obliterate,if=runes.frost=2||runes.unholy=2"), "the line, '|' escaped")
    truthy(text:find("Ready now"), "readiness")
    tip = Hover(s, 2)
    truthy(tip:Text():find("Predicted: assumes"), "queue icons say they're predictions")
end)

test("tooltip says what a waiting ability waits on", function()
    local s = Fight()
    for i = 1, 6 do s.runes[i].readyAt = s.time + 3 end
    s:Tick(0.1)
    truthy(Hover(s, 1):Text():find("Ready in 2%.%ds %(waiting on runes%)"), "waiting on runes")
end)

test("sample icons get a sample tooltip", function()
    local s = Fight()
    s:Slash("ACECONSOLE_RH", "test")
    s:Tick(0.1)
    truthy(Hover(s, 1):Text():find("Sample icon"), "sample")
end)

test("Shift-click on the chips toggles cooldowns and the AoE mode", function()
    local s, RH = Fight()
    local D = s.ns.Display
    s.shift = true
    s:Tick(0.1)
    eq(D:GetStatusText(), "CD  AUTO", "AUTO chip shown while Shift is held")
    D.frame.cdChip.scripts.OnClick(D.frame.cdChip)
    eq(RH.db.profile.toggles.cooldowns, true, "cooldowns toggled on")
    D.frame.aoeChip.scripts.OnClick(D.frame.aoeChip)
    eq(RH.db.profile.toggles.aoeMode, "single", "AoE mode cycled")
    s.shift = false
    s:Tick(0.1)
    eq(D:GetStatusText(), "CD  ST", "normal status")
end)

---------------------------------------------------------------------------
-- A7: proc glow and sound
---------------------------------------------------------------------------
test("abilities that spend a proc are marked", function()
    local s = Fight()
    Buff(s, "Killing Machine", 51124, 10)
    local st = s.ns.State:Reset()
    local Abilities = s.ns.Abilities
    eq(Abilities.ProcUsed(st, "frost_strike", st.now), "killing_machine", "Frost Strike spends KM")
    eq(Abilities.ProcUsed(st, "icy_touch", st.now), "killing_machine", "so does Icy Touch")
    eq(Abilities.ProcUsed(st, "obliterate", st.now), nil, "Obliterate doesn't (3.3.5)")
    eq(Abilities.ProcUsed(st, "frost_strike", st.now + 11), nil, "not after it expires")
end)

test("the icon spending Killing Machine glows", function()
    local s = Fight()
    for i = 3, 6 do s.runes[i].readyAt = s.time + 5 end
    s.power.current = 60
    Buff(s, "Killing Machine", 51124, 10)
    s:Tick(0.1)
    local D = s.ns.Display
    eq(s.env.RotationHelper.recommendations[1].name, "frost_strike", "Frost Strike")
    truthy(D.buttons[1].glow:IsShown(), "glows")
    falsy(D.buttons[2].glow:IsShown(), "the next one doesn't (KM is used up)")
    truthy(Hover(s, 1):Text():find("Spends Killing Machine"), "tooltip says so")
end)

test("free Howling Blast (Rime) glows; nothing glows without procs", function()
    local s, RH = Fight()
    for i = 1, 6 do s.runes[i].readyAt = s.time + 5 end
    Buff(s, "Freezing Fog", 59052, 10)
    s:Tick(0.1)
    eq(RH.recommendations[1].name, "howling_blast", "Howling Blast")
    truthy(s.ns.Display.buttons[1].glow:IsShown(), "glows")
    s.auras.player = {}
    s:Tick(0.1)
    for i = 1, 4 do falsy(s.ns.Display.buttons[i].glow:IsShown(), "no glow " .. i) end
end)

test("glow can be turned off", function()
    local s, RH = Fight()
    for i = 1, 6 do s.runes[i].readyAt = s.time + 5 end
    Buff(s, "Freezing Fog", 59052, 10)
    RH.db.profile.display.procGlow = false
    s:Tick(0.1)
    falsy(s.ns.Display.buttons[1].glow:IsShown(), "off")
end)

test("proc sound: off by default, then once per new proc", function()
    local s, RH = Fight()
    for i = 1, 6 do s.runes[i].readyAt = s.time + 5 end
    Buff(s, "Freezing Fog", 59052, 10)
    s:Tick(0.1)
    eq(#s.sounds, 0, "off by default")
    RH.db.profile.display.procSound = "MapPing"
    s:Tick(0.1)
    s:Tick(0.1)
    eq(table.concat(s.sounds, ","), "MapPing", "once, not every update")
    s.auras.player = {}
    Buff(s, "Freezing Fog", 59052, 12) -- a new Rime proc
    s:Tick(0.1)
    eq(#s.sounds, 2, "again for the new proc")
end)

test("options for the new display settings validate", function()
    local s = newAddon()
    local registry = s.env.LibStub("AceConfigRegistry-3.0")
    local ok, err = pcall(registry.ValidateOptionsTable, registry, s.ns.Options:GetOptionsTable(), "RotationHelper")
    truthy(ok, tostring(err))
    local args = s.ns.Options:GetOptionsTable().args.display.args
    eq(args.procSound.values().MapPing, "Ping", "sound choices")
end)
