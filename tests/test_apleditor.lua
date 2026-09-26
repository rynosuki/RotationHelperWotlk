local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local SPELLS = { "Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
    "Horn of Winter" }

-- An editor widget with the few AceGUI base methods it relies on.
local function Editor()
    local s, RH = newAddon()
    s:Learn(unpack(SPELLS))
    local w = s.ns.APLEditor.Construct()
    w.fired = {}
    w.SetWidth = function(self, width)
        self.frame:SetWidth(width)
        self:OnWidthSet(width)
    end
    w.SetHeight = function(self, height) self.frame:SetHeight(height) end
    w.Fire = function(self, event, ...) self.fired[#self.fired + 1] = { event, ... } end
    w:OnAcquire()
    w:SetWidth(700)
    w.frame:Show()
    return s, RH, w
end

local DEFAULT_START = "actions.precombat=horn_of_winter"

---------------------------------------------------------------------------
test("plain text in, plain text out; colored in between", function()
    local s, RH, w = Editor()
    local text = "actions=obliterate,if=runes.frost=2|runes.unholy=2\n# note | here"
    w:SetText(text)
    local raw = w.editBox:GetText()
    truthy(raw:find("|c"), "colored")
    truthy(raw:find("||runes.unholy", 1, true) or raw:find("||", 1, true), "'|' escaped")
    eq(w:GetText(), text, "exact text back")
    falsy(w.accept:IsEnabled(), "nothing to accept yet")
end)

test("without syntax colors the text is only escaped", function()
    local s, RH, w = Editor()
    RH.db.profile.editor.syntaxColors = false
    w:SetText("actions=obliterate,if=1|0")
    eq(w.editBox:GetText(), "actions=obliterate,if=1||0", "escaped only")
end)

test("the status line and error lines follow the text", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate\nactions+=/frost_strik\nactions+=/icy_touch,if=(")
    truthy(w.status:GetText():find("^line 2, col 11: unknown action 'frost_strik'  %(%+1 more%)"), w.status:GetText())
    truthy(w.errorLines[2] and w.errorLines[3], "lines 2 and 3 marked")
    falsy(w.errorLines[1], "line 1 fine")
    truthy(w.marks[2]:IsShown() and w.marks[3]:IsShown(), "highlights shown")
    w:SetText("actions=obliterate")
    eq(w.status:GetText(), "Compiles: 1 actions in 1 lists.", "fixed")
    falsy(w.marks[2]:IsShown(), "highlight gone")
end)

test("line numbers: one per line", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate\n\nactions+=/icy_touch")
    eq(w.numbers[1]:GetText(), 1, "first")
    eq(w.numbers[3]:GetText(), 3, "third")
    truthy(w.numbers[3]:IsShown(), "shown")
    w:SetText("actions=obliterate")
    falsy(w.numbers[2]:IsShown(), "extra numbers hidden")
end)

test("typing enables Accept and refreshes shortly after", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate")
    w.editBox:SetCursorPosition(#w.editBox:GetText())
    w.editBox:Insert("\nactions+=/frost_strik")
    truthy(w.accept:IsEnabled(), "Accept enabled")
    eq(w.status:GetText(), "Compiles: 1 actions in 1 lists.", "not checked yet while typing")
    s:Tick(0.1)
    s:Tick(0.3)
    truthy(w.status:GetText():find("unknown action 'frost_strik'"), "checked after the pause")
    eq(w:GetText(), "actions=obliterate\nactions+=/frost_strik", "text intact")
end)

test("recoloring keeps the cursor where it was", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate")
    local X = s.ns.APLText
    w.editBox:SetCursorPosition(X.PlainToRaw(w.editBox:GetText(), #"actions=obli"))
    w.editBox:Insert("x") -- "actions=oblixterate"
    s:Tick(0.1)
    s:Tick(0.3)
    local raw = w.editBox:GetText()
    eq(X.RawToPlain(raw, w.editBox:GetCursorPosition()), #"actions=oblix", "cursor after the typed x")
    eq(w:GetText(), "actions=oblixterate", "text")
end)

test("Accept hands the plain text to the option", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate")
    w.editBox:Insert(",if=1|0")
    w.accept.scripts.OnClick(w.accept)
    eq(w.fired[1][1], "OnEnterPressed", "event")
    eq(w.fired[1][2], ",if=1|0actions=obliterate", "plain text, '|' not doubled")
    falsy(w.accept:IsEnabled(), "Accept off again")
end)

---------------------------------------------------------------------------
-- Name picker
---------------------------------------------------------------------------
test("name picker: search, then click inserts at the cursor", function()
    local s, RH, w = Editor()
    w:SetText("actions=frost_strike,if=")
    w.editBox:SetCursorPosition(#w.editBox:GetText())
    local fullWidth = w.editBox.width
    w:TogglePicker()
    truthy(w.picker:IsShown(), "open")
    truthy(w.editBox.width < fullWidth, "the editor makes room")
    w.picker.search:SetText("killing_machine.up")
    local row = w.picker.rows[1]
    eq(row.entry.text, "buff.killing_machine.up", "found")
    falsy(w.picker.rows[2]:IsShown(), "only matches listed")
    row.scripts.OnClick(row)
    eq(w:GetText(), "actions=frost_strike,if=buff.killing_machine.up", "inserted")
    truthy(w.accept:IsEnabled(), "counts as an edit")
    w:TogglePicker()
    falsy(w.picker:IsShown(), "closed")
    eq(w.editBox.width, fullWidth, "full width again")
end)

---------------------------------------------------------------------------
-- Export / import
---------------------------------------------------------------------------
test("export shows an RH1 string ready to copy", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate,if=1|0")
    s.ns.APLEditor.ShowExport(w)
    local box = s.env.RotationHelperAPLPopup.box
    eq(box:GetText(), "RH1:frost:actions=obliterate,if=1\\p0", "export string")
    truthy(box.highlighted and box.focused, "selected for Ctrl+C")
end)

test("import puts the rotation in the editor, unsaved", function()
    local s, RH, w = Editor()
    w:SetText("actions=obliterate")
    local ok = s.ns.APLEditor.ApplyImport(w, "RH1:frost:actions=icy_touch\\nactions+=/obliterate")
    truthy(ok, "imported")
    eq(w:GetText(), "actions=icy_touch\nactions+=/obliterate", "in the editor")
    truthy(w.accept:IsEnabled(), "Accept to save")
    truthy(w.status:GetText():find("press Accept to save"), "told so")
    eq((RH.db.profile.customAPLs.DEATHKNIGHT or {}).frost, nil, "not saved")
end)

test("import: another spec is noted, junk is refused", function()
    local s, RH, w = Editor()
    s.ns.APLEditor.ApplyImport(w, "RH1:unholy:actions=obliterate")
    truthy(w.status:GetText():find("Imported a unholy rotation into the frost editor"), w.status:GetText())
    local ok, err = s.ns.APLEditor.ApplyImport(w, "hello there")
    falsy(ok, "refused")
    eq(err, "not a rotation or an RH1: string", "why")
end)

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------
test("sharing: checks, then paced addon messages", function()
    local s = Editor()
    local Share = s.ns.APLShare
    local ok, message = Share:Send("WHISPER", "  ", "frost", "actions=obliterate")
    falsy(ok, "needs a name")
    eq(message, "Type the player's name first.", "message")
    ok, message = Share:Send("PARTY", nil, "frost", "actions=obliterate")
    falsy(ok, "not in a party")
    ok, message = Share:Send("WHISPER", " Arthas ", "frost", string.rep("actions+=/obliterate\n", 30))
    truthy(ok, message)
    eq(#s.addonMessages, 0, "nothing sent at once")
    for _ = 1, 40 do s:Tick(0.1) end
    local first = s.addonMessages[1]
    eq(first.prefix, "RotHelperAPL", "prefix")
    eq(first.channel .. " " .. first.target, "WHISPER Arthas", "to the player, name trimmed")
    truthy(first.text:find("^H:%d+:%d+$"), "header first")
    truthy(s.addonMessages[2].text:find("^D:%d+:1:RH1:frost:"), "then the data")
    for _, m in ipairs(s.addonMessages) do truthy(#m.text <= 250, "short enough") end
end)

test("receiving: assembled, confirmed, opened unsaved", function()
    local sender = Editor()
    sender.ns.APLShare:Send("WHISPER", "Receiver", "frost", "actions=icy_touch\nactions+=/obliterate,if=1|0")
    for _ = 1, 20 do sender:Tick(0.1) end

    local s, RH = newAddon()
    s:Learn(unpack(SPELLS))
    -- Deliver out of order, with a duplicate.
    local messages = sender.addonMessages
    local order = { 1, 3, 2, 2 }
    for i = 4, #messages do order[#order + 1] = i end
    for _, i in ipairs(order) do
        if messages[i] then
            s:FireEvent("CHAT_MSG_ADDON", "RotHelperAPL", messages[i].text, "WHISPER", "Sender")
        end
    end
    eq(#s.popups, 1, "asked once")
    local popup = s.popups[1]
    eq(popup.text1, "Sender sent you a frost rotation.", "question")
    eq(popup.data.text, "actions=icy_touch\nactions+=/obliterate,if=1|0", "text intact")

    local opened
    s.ns.Options.Open = function(_, tab) opened = tab end
    s.env.StaticPopupDialogs.ROTATIONHELPER_RECEIVED_APL.OnAccept(nil, popup.data)
    eq(opened, "rotation", "editor opened")
    eq(s.ns.Options:RotationText("frost"), popup.data.text, "in the editor")
    eq((RH.db.profile.customAPLs.DEATHKNIGHT or {}).frost, nil, "not saved")
end)

test("receiving ignores our own messages and other addons", function()
    local s = newAddon()
    s:FireEvent("CHAT_MSG_ADDON", "RotHelperAPL", "H:1234:1", "WHISPER", "Tester")
    s:FireEvent("CHAT_MSG_ADDON", "RotHelperAPL", "D:1234:1:RH1:frost:actions=x", "WHISPER", "Tester")
    s:FireEvent("CHAT_MSG_ADDON", "OtherAddon", "D:1234:1:RH1:frost:actions=x", "WHISPER", "Someone")
    eq(#s.popups, 0, "nothing")
end)
