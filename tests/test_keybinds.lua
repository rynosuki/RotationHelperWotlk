local T = require("testlib")
local test, eq, falsy, newAddon = T.test, T.eq, T.falsy, T.newAddon

local function keybinds(s) return s.ns.Keybinds end

test("FormatKey abbreviates modifiers and special keys", function()
    local s = newAddon()
    local F = keybinds(s).FormatKey
    eq(F("SHIFT-3"), "S3", "shift")
    eq(F("CTRL-ALT-Q"), "CAQ", "ctrl+alt")
    eq(F("BUTTON4"), "M4", "mouse button")
    eq(F("MOUSEWHEELUP"), "MwU", "wheel up")
    eq(F("SHIFT-MOUSEWHEELDOWN"), "SMwD", "shift+wheel down")
    eq(F("NUMPADPLUS"), "N+", "numpad plus")
    eq(F("f"), "F", "uppercased")
end)

test("finds keys on the default action bars", function()
    local s = newAddon()
    s:PlaceSpell(3, 51425, "ACTIONBUTTON3", "3")
    s:PlaceSpell(27, 55268, "MULTIACTIONBAR3BUTTON3", "SHIFT-E")
    s:PlaceSpell(62, 49909, "MULTIACTIONBAR1BUTTON2", "CTRL-2")
    local K = keybinds(s)
    eq(K:Get("Obliterate"), "3", "main bar")
    eq(K:Get("Frost Strike"), "SE", "right bar")
    eq(K:Get("Icy Touch"), "C2", "bottom left bar")
    falsy(K:Get("Howling Blast"), "spell not on bars")
end)

test("unbound slots are skipped in favour of a bound copy", function()
    local s = newAddon()
    s:PlaceSpell(1, 51425) -- no binding
    s:PlaceSpell(5, 51425, "ACTIONBUTTON5", "5")
    eq(keybinds(s):Get("Obliterate"), "5", "bound slot wins")
end)

test("macros resolve through GetMacroSpell", function()
    local s = newAddon()
    s.actions[4] = { "macro", 7 }
    s.macros[7] = "Howling Blast"
    s.bindings.ACTIONBUTTON4 = "Q"
    s:FireEvent("UPDATE_MACROS")
    eq(keybinds(s):Get("Howling Blast"), "Q", "macro")
end)

test("bar addons: CLICK bindings to their buttons' action slots", function()
    local s = newAddon()
    local button = s.env.CreateFrame("CheckButton", "BT4Button3")
    button.action = 3
    s:PlaceSpell(3, 51425)
    s.bindings["CLICK BT4Button3:LeftButton"] = "SHIFT-F"
    s:FireEvent("UPDATE_BINDINGS")
    eq(keybinds(s):Get("Obliterate"), "SF", "Bartender-style button")
end)

test("bar addons: action slot from the secure attribute", function()
    local s = newAddon()
    local button = s.env.CreateFrame("CheckButton", "ElvUI_Bar1Button4")
    button:SetAttribute("action", 4)
    s:PlaceSpell(4, 55268)
    s.bindings["CLICK ElvUI_Bar1Button4:LeftButton"] = "E"
    s:FireEvent("UPDATE_BINDINGS")
    eq(keybinds(s):Get("Frost Strike"), "E", "attribute slot")
end)

test("ElvUI: override bindings through the hidden Blizzard buttons' commands", function()
    local s = newAddon()
    s.env.ElvUI = {}
    -- ElvUI hides the Blizzard bars; the keys stay on their commands.
    local blizzard = s.env.CreateFrame("CheckButton", "ActionButton3")
    blizzard.action = 3
    blizzard:Hide()
    local function Elv(bar, i, slot, target)
        local b = s.env.CreateFrame("CheckButton", ("ElvUI_Bar%dButton%d"):format(bar, i))
        b._state_type, b._state_action = "action", slot
        b.keyBoundTarget = target
        return b
    end
    Elv(1, 3, 3, "ACTIONBUTTON3")
    Elv(2, 1, 13, "ELVUIBAR2BUTTON1")
    Elv(3, 2, 26, nil) -- no keyBoundTarget: ElvUI's default command for bar 3
    local spellButton = Elv(4, 1, nil, "MULTIACTIONBAR4BUTTON1")
    spellButton._state_type, spellButton._state_action = "spell", 49909
    local hidden = Elv(5, 1, 50, "MULTIACTIONBAR2BUTTON1")
    hidden:Hide()
    s:PlaceSpell(3, 51425, "ACTIONBUTTON3", "3")
    s:PlaceSpell(13, 55268, "ELVUIBAR2BUTTON1", "SHIFT-1")
    s:PlaceSpell(26, 51411, "MULTIACTIONBAR3BUTTON2", "CTRL-Q")
    s:PlaceSpell(50, 45529, "MULTIACTIONBAR2BUTTON1", "F")
    s.bindings.MULTIACTIONBAR4BUTTON1 = "G"
    s:FireEvent("UPDATE_BINDINGS")
    local K = keybinds(s)
    eq(K:Get("Obliterate"), "3", "bar 1 via ACTIONBUTTON3")
    eq(K:Get("Frost Strike"), "S1", "bar 2's own command")
    eq(K:Get("Howling Blast"), "CQ", "default command when the button doesn't say")
    eq(K:Get("Icy Touch"), "G", "a spell state")
    falsy(K:Get("Blood Tap"), "hidden bar skipped")
end)

test("DragonUI-style extra bar buttons with a spell or macro attribute", function()
    local s = newAddon()
    local spellButton = s.env.CreateFrame("CheckButton", "DragonUIExtraBarButton1")
    spellButton:SetAttribute("type", "spell")
    spellButton:SetAttribute("spell", "Howling Blast")
    local idButton = s.env.CreateFrame("CheckButton", "DragonUIExtraBarButton2")
    idButton:SetAttribute("type", "spell")
    idButton:SetAttribute("spell", 49909)
    local macroButton = s.env.CreateFrame("CheckButton", "DragonUIExtraBarButton3")
    macroButton:SetAttribute("type", "macro")
    macroButton:SetAttribute("macro", 5)
    s.macros[5] = "Plague Strike"
    s.bindings["CLICK DragonUIExtraBarButton1:LeftButton"] = "Z"
    s.bindings["CLICK DragonUIExtraBarButton2:LeftButton"] = "X"
    s.bindings["CLICK DragonUIExtraBarButton3:LeftButton"] = "C"
    s:FireEvent("UPDATE_BINDINGS")
    local K = keybinds(s)
    eq(K:Get("Howling Blast"), "Z", "spell name attribute")
    eq(K:Get("Icy Touch"), "X", "spell ID attribute")
    eq(K:Get("Plague Strike"), "C", "macro attribute")
end)

test("hidden buttons are skipped (Blizzard bars replaced by a bar addon)", function()
    local s = newAddon()
    local blizzard = s.env.CreateFrame("CheckButton", "ActionButton3")
    blizzard.action = 3
    blizzard:Hide()
    local bt4 = s.env.CreateFrame("CheckButton", "BT4Button3")
    bt4.action = 3
    s:PlaceSpell(3, 51425, "ACTIONBUTTON3", "3")
    s.bindings["CLICK BT4Button3:LeftButton"] = "SHIFT-F"
    s:FireEvent("UPDATE_BINDINGS")
    eq(keybinds(s):Get("Obliterate"), "SF", "only the visible button's key")
end)

test("unknown CLICK buttons are ignored", function()
    local s = newAddon()
    s.bindings["CLICK NoSuchButton:LeftButton"] = "Q"
    s:FireEvent("UPDATE_BINDINGS")
    eq(keybinds(s):Get("Obliterate"), nil, "nothing")
end)

test("Blizzard buttons follow bar paging", function()
    local s = newAddon()
    local button = s.env.CreateFrame("CheckButton", "ActionButton3")
    button.action = 75 -- a bonus bar page
    s:PlaceSpell(75, 55268, "ACTIONBUTTON3", "3")
    s:PlaceSpell(3, 51425)
    eq(keybinds(s):Get("Frost Strike"), "3", "the current page's spell")
    eq(keybinds(s):Get("Obliterate"), nil, "not the page-1 spell")
end)

test("ACTIONBUTTON12 is slot 12, not ACTIONBUTTON1 + 2", function()
    local s = newAddon()
    s:PlaceSpell(12, 51425, "ACTIONBUTTON12", "=")
    eq(keybinds(s):Get("Obliterate"), "=", "slot 12")
end)

test("binding changes rebuild the map", function()
    local s = newAddon()
    s:PlaceSpell(3, 51425, "ACTIONBUTTON3", "3")
    local K = keybinds(s)
    eq(K:Get("Obliterate"), "3", "before")
    s.bindings.ACTIONBUTTON3 = "R"
    eq(K:Get("Obliterate"), "3", "cached until an event")
    s:FireEvent("UPDATE_BINDINGS")
    eq(K:Get("Obliterate"), "R", "after UPDATE_BINDINGS")
end)

test("/rh keys lists what was found", function()
    local s = newAddon()
    s:PlaceSpell(3, 51425, "ACTIONBUTTON3", "3")
    s:Slash("ACECONSOLE_RH", "keys")
    T.truthy(s:ChatContains("Keybinds found for 1 spells"), "header")
    T.truthy(s:ChatContains("Obliterate: 3"), "the key")
end)
