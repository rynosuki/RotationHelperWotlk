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

test("Bartender4 bindings take priority", function()
    local s = newAddon()
    s.env.Bartender4 = {}
    s:PlaceSpell(3, 51425, "ACTIONBUTTON3", "3")
    s.bindings["CLICK BT4Button3:LeftButton"] = "SHIFT-F"
    s:FireEvent("UPDATE_BINDINGS")
    eq(keybinds(s):Get("Obliterate"), "SF", "BT4 binding")
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
