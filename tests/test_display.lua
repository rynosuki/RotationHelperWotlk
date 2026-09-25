local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local function display(s) return s.ns.Display end

-- Loads the addon with the display locked (the in-combat look). These tests
-- set RH.recommendations by hand, so the real recommender is switched off.
local function lockedAddon(opts)
    local s, RH = newAddon(opts)
    s.ns.Recommender.Update = function() end
    s:Slash("ACECONSOLE_RH", "lock")
    return s, RH
end

test("unlocked display shows preview icons and drag label", function()
    local s = newAddon()
    local D = display(s)
    truthy(D.frame:IsShown(), "frame shown")
    truthy(D.frame.label:IsShown(), "label shown")
    truthy(D.frame:IsMouseEnabled(), "draggable")
    eq(D.buttons[1].icon:GetTexture(), "Interface\\Icons\\Spell_DeathKnight_ClassIcon", "preview main icon")
    truthy(D.buttons[4]:IsShown(), "4 icons by default")
    falsy(D.buttons[5]:IsShown(), "5th icon hidden")
end)

test("locked display is click-through and hidden without recommendations", function()
    local s = lockedAddon()
    local D = display(s)
    falsy(D.frame:IsMouseEnabled(), "click-through")
    falsy(D.frame:IsShown(), "hidden")
end)

test("unsupported class shows nothing even when unlocked", function()
    local s = newAddon({ class = "MAGE" })
    falsy(display(s).frame:IsShown(), "hidden for MAGE")
end)

test("/rh test shows sample icons while locked", function()
    local s = lockedAddon()
    local D = display(s)
    s:Slash("ACECONSOLE_RH", "test")
    truthy(D.frame:IsShown(), "shown in test mode")
    falsy(D.frame.label:IsShown(), "no drag label when locked")
    s:Slash("ACECONSOLE_RH", "test")
    falsy(D.frame:IsShown(), "hidden again")
end)

test("renders recommendations with keybinds", function()
    local s, RH = lockedAddon()
    s:PlaceSpell(2, 55268, "ACTIONBUTTON2", "SHIFT-2")
    RH.recommendations = { { spellId = 55268 }, { spellId = 49909 } }
    s:Tick(0.2)
    local D = display(s)
    truthy(D.frame:IsShown(), "shown")
    eq(D.buttons[1].icon:GetTexture(), "Interface\\Icons\\Spell_DeathKnight_EmpowerRuneBlade2", "main icon")
    eq(D.buttons[1].key:GetText(), "S2", "main keybind")
    eq(D.buttons[2].key:GetText(), "", "unbound spell shows no key")
    falsy(D.buttons[3]:IsShown(), "no third entry")
end)

test("numIcons limits the queue", function()
    local s, RH = lockedAddon()
    RH.recommendations = { { spellId = 51425 }, { spellId = 55268 }, { spellId = 51411 } }
    s:Slash("ACECONSOLE_RH", "icons 2")
    local D = display(s)
    truthy(D.buttons[2]:IsShown(), "second shown")
    falsy(D.buttons[3]:IsShown(), "third hidden")
end)

test("out of range and missing resources tint the icon", function()
    local s, RH = lockedAddon()
    local D = display(s)
    RH.recommendations = { { spellId = 51425 }, { spellId = 55268, lacksResources = true } }
    s.hasTarget = true
    s.range["Obliterate"] = 0
    s:Tick(0.2)
    eq(D.buttons[1].icon.vertexColor[2], 0.25, "red when out of range")
    eq(D.buttons[2].icon.vertexColor[3], 1, "blue when lacking resources")
    eq(D.buttons[2].icon.vertexColor[1], 0.4, "blue when lacking resources (r)")
    s.range["Obliterate"] = 1
    s:Tick(0.2)
    eq(D.buttons[1].icon.vertexColor[2], 1, "normal when in range")
end)

test("cooldown swipe only restarts when the ready time moves", function()
    local s, RH = lockedAddon()
    local cd = display(s).buttons[1].cooldown
    RH.recommendations = { { spellId = 51425, wait = 1.0 } }
    s:Tick(0.2)
    truthy(cd:IsShown(), "swipe shown")
    local firstStart = cd.cooldownStart
    eq(cd.cooldownDuration, 1.0, "duration")

    RH.recommendations[1].wait = 0.9 -- same ready time, 0.1s later
    s:Tick(0.1)
    eq(cd.cooldownStart, firstStart, "not restarted")

    RH.recommendations[1].wait = 2.0 -- ready time pushed back
    s:Tick(0.1)
    truthy(cd.cooldownStart > firstStart, "restarted")

    RH.recommendations[1].wait = 0
    s:Tick(0.1)
    falsy(cd:IsShown(), "hidden when ready")
end)

test("hide out of combat", function()
    local s, RH = lockedAddon()
    RH.db.profile.display.hideOutOfCombat = true
    RH.recommendations = { { spellId = 51425 } }
    s:Tick(0.2)
    local D = display(s)
    falsy(D.frame:IsShown(), "hidden out of combat")
    s:FireEvent("PLAYER_REGEN_DISABLED")
    truthy(D.frame:IsShown(), "shown in combat")
end)

test("pause hides the locked display", function()
    local s, RH = lockedAddon()
    RH.recommendations = { { spellId = 51425 } }
    s:Tick(0.2)
    truthy(display(s).frame:IsShown(), "shown")
    s:Slash("ACECONSOLE_RH", "pause")
    falsy(display(s).frame:IsShown(), "hidden while paused")
end)

test("dragging saves the position", function()
    local s, RH = newAddon()
    local f = display(s).frame
    f.scripts.OnDragStart(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", s.env.UIParent, "BOTTOMLEFT", 300, 400)
    f.scripts.OnDragStop(f)
    local p = RH.db.profile.display.point
    eq(table.concat({ p[1], p[2], p[3], p[4], p[5] }, ","), "TOPLEFT,UIParent,BOTTOMLEFT,300,400", "saved point")
end)

test("queue grows in the configured direction", function()
    local s, RH = newAddon()
    RH.db.profile.display.direction = "DOWN"
    RH:OnConfigChanged()
    local b2 = display(s).buttons[2]
    local point, rel, relPoint, x, y = b2:GetPoint(1)
    eq(point .. "/" .. relPoint, "TOP/BOTTOM", "anchors")
    eq(rel, display(s).buttons[1], "anchored to previous")
    eq(x .. "," .. y, "0,-4", "offset")
    eq(b2.width, 40, "queue icon size")
end)
