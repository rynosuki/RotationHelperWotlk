local ADDON_NAME, ns = ...
local RH = ns.RH

-- The rotation editor: an AceGUI widget ("RotationHelper-APLEditor") that
-- the Rotation tab uses instead of a plain text box (dialogControl).
--
--   toolbar      Accept (saves via the option's set), Names, Export,
--                Import, Share
--   editor       line numbers, error lines highlighted, syntax colors
--   status line  "Compiles: 23 actions" or the first error, updated
--                shortly after you stop typing
--   name picker  searchable list of every name; click inserts at the cursor
--
-- The widget works in plain rotation text: SetText takes it, GetText and
-- OnEnterPressed give it. Escaping '|' and the color codes stay inside
-- (UI/APLText.lua). It styles itself, so UI/Skin.lua leaves it alone.
local APLEditor = {}
ns.APLEditor = APLEditor

local APLText = ns.APLText
local CreateFrame = CreateFrame
local format, max, min, floor = string.format, math.max, math.min, math.floor

APLEditor.TYPE = "RotationHelper-APLEditor"
local VERSION = 1

local LABEL_HEIGHT, TOOLBAR_HEIGHT, STATUS_HEIGHT = 18, 24, 20
local GUTTER_WIDTH = 30
local FONT_SIZE = 13
local DEBOUNCE = 0.35 -- seconds after the last keystroke
local PICKER_WIDTH, PICKER_ROWS, PICKER_ROW_HEIGHT = 240, 18, 16

local KIND_COLORS = { ability = { 1, 0.82, 0 }, name = { 0.5, 0.84, 0.5 }, template = { 0.62, 0.77, 0.91 } }

---------------------------------------------------------------------------
-- Small themed pieces
---------------------------------------------------------------------------
local function Theme() return ns.Skin.theme end

local function FlatButton(parent, text, width, onClick)
    local T = Theme()
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width)
    b:SetHeight(TOOLBAR_HEIGHT - 2)
    ns.Window.Flat(b, T.control, T.border)
    b.label = ns.Window.Text(b, 13, T.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropColor(unpack(T.controlHover)) end
    end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(T.control)) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function SetButtonEnabled(b, enabled)
    if enabled then
        b:Enable()
        b.label:SetTextColor(unpack(Theme().text))
    else
        b:Disable()
        b.label:SetTextColor(unpack(Theme().textDim))
    end
end

---------------------------------------------------------------------------
-- Coloring and validation
---------------------------------------------------------------------------
local SPECIAL_ACTIONS = { call_action_list = true, run_action_list = true, variable = true, wait = true }

local function IsAbility(word)
    return SPECIAL_ACTIONS[word] or (RH.classData and RH.classData.abilities[word] ~= nil) or false
end

local function IsName(word)
    if word:find("^variable%.") then return true end
    local resolver = ns.Recommender.resolver
    return resolver ~= nil and resolver(word) ~= nil
end

function APLEditor.Colorize(plain)
    return APLText.Colorize(plain, IsAbility, IsName)
end

---------------------------------------------------------------------------
-- Methods
---------------------------------------------------------------------------
local methods = {}

function methods:OnAcquire()
    self:SetNumLines(20)
    self:SetDisabled(false)
    self:SetLabel("")
    self.editBox:SetText("")
    self.picker:Hide()
    self.status:SetText("")
    SetButtonEnabled(self.accept, false)
end

function methods:OnRelease()
    self.editBox:ClearFocus()
    self.picker:Hide()
    self.frame:SetScript("OnUpdate", nil)
    APLEditor.HidePopup()
end

function methods:SetLabel(text)
    self.label:SetText(text or "")
end

function methods:SetNumLines(lines)
    self.numLines = lines or 20
    local editorHeight = self.numLines * FONT_SIZE + 10
    self.box:SetHeight(editorHeight)
    self:SetHeight(LABEL_HEIGHT + TOOLBAR_HEIGHT + editorHeight + STATUS_HEIGHT + 4)
end

function methods:SetDisabled(disabled)
    self.disabled = disabled
    self.editBox:EnableMouse(not disabled)
    for _, b in ipairs(self.toolbarButtons) do SetButtonEnabled(b, not disabled) end
    if not disabled then SetButtonEnabled(self.accept, self.changed) end
end

-- Plain rotation text in; shown escaped (and colored).
function methods:SetText(plain)
    plain = plain or ""
    self.changed = false
    SetButtonEnabled(self.accept, false)
    self.editBox:SetText(self:Display(plain))
    self.editBox:SetCursorPosition(0)
    self:Refresh(plain)
end

function methods:GetText()
    return APLText.Strip(self.editBox:GetText())
end

function methods:Display(plain)
    if RH.db.profile.editor.syntaxColors then return APLEditor.Colorize(plain) end
    return APLText.Escape(plain)
end

-- Accept: hand the plain text to the option's set (AceConfigDialog).
function methods:Accept()
    self.editBox:ClearFocus()
    self.changed = false
    SetButtonEnabled(self.accept, false)
    self:Fire("OnEnterPressed", self:GetText())
end

-- Inserts `text` at the cursor (used by the name picker).
function methods:Insert(text)
    self.editBox:SetFocus()
    self.editBox:Insert(text)
    self:MarkChanged()
end

function methods:MarkChanged()
    self.changed = true
    SetButtonEnabled(self.accept, not self.disabled)
    self.pendingAt = GetTime() + DEBOUNCE
    self.frame:SetScript("OnUpdate", self.OnUpdateScript)
end

-- Validates, recolors (keeping the cursor) and redraws line numbers.
function methods:Refresh(plain)
    local editBox = self.editBox
    plain = plain or APLText.Strip(editBox:GetText())

    local apl = ns.Recommender:Compile(plain)
    local T = Theme()
    self.errorLines = self.errorLines or {}
    for k in pairs(self.errorLines) do self.errorLines[k] = nil end
    if #apl.errors == 0 then
        local actions = 0
        for _, list in pairs(apl.lists) do actions = actions + #list end
        self.status:SetText(format("Compiles: %d actions in %d lists.", actions, #apl.listOrder))
        self.status:SetTextColor(0.4, 0.9, 0.5)
    else
        local first = apl.errors[1]
        self.status:SetText((ns.APL.Compiler.FormatError(first):gsub("|", "||"))
            .. (#apl.errors > 1 and format("  (+%d more)", #apl.errors - 1) or ""))
        self.status:SetTextColor(1, 0.4, 0.4)
        for _, err in ipairs(apl.errors) do self.errorLines[err.line] = true end
    end
    self.errorCount = #apl.errors

    local raw = editBox:GetText()
    local wanted = self:Display(plain)
    if wanted ~= raw then
        local plainCursor = APLText.RawToPlain(raw, editBox:GetCursorPosition())
        self.recoloring = true
        editBox:SetText(wanted)
        editBox:SetCursorPosition(APLText.PlainToRaw(wanted, plainCursor))
        self.recoloring = false
    end
    self:LayoutGutter(plain)
end

-- Line numbers and error highlights, one per rotation line, placed at the
-- height each line takes once wrapped (measured with a hidden font string).
function methods:LayoutGutter(plain)
    local width = max(10, self.editBox:GetWidth())
    local measure, lineHeight = self.measure, self.lineHeight
    measure:SetWidth(width)
    local y, n = 0, 0
    for line in (plain .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local number = self.numbers[n]
        if not number then
            number = ns.Window.Text(self.inner, 11, Theme().textDim)
            number:SetJustifyH("RIGHT")
            number:SetWidth(GUTTER_WIDTH - 6)
            self.numbers[n] = number
        end
        number:ClearAllPoints()
        number:SetPoint("TOPLEFT", self.inner, "TOPLEFT", 0, -y - 1)
        number:SetText(n)
        number:Show()

        measure:SetText(line == "" and " " or APLText.Escape(line))
        local height = measure:GetHeight()
        if not height or height < lineHeight then height = lineHeight end
        height = floor(height / lineHeight + 0.5) * lineHeight

        local mark = self.marks[n]
        if self.errorLines[n] then
            if not mark then
                mark = self.inner:CreateTexture(nil, "BACKGROUND")
                mark:SetTexture(1, 0.2, 0.2, 0.18)
                self.marks[n] = mark
            end
            mark:ClearAllPoints()
            mark:SetPoint("TOPLEFT", self.inner, "TOPLEFT", GUTTER_WIDTH - 2, -y)
            mark:SetPoint("RIGHT", self.inner, "RIGHT")
            mark:SetHeight(height)
            mark:Show()
        elseif mark then
            mark:Hide()
        end
        y = y + height
    end
    for i = n + 1, #self.numbers do self.numbers[i]:Hide() end
    -- marks only exists for lines that once had an error, so it has holes
    -- and # can't be trusted: go through all of them.
    for i, mark in pairs(self.marks) do
        if i > n then mark:Hide() end
    end
    self.inner:SetHeight(max(y + 6, self.box:GetHeight()))
end

function methods:OnWidthSet(width)
    local pickerShown = self.picker:IsShown()
    local editorWidth = width - 10 - (pickerShown and (PICKER_WIDTH + 6) or 0)
    self.scroll:SetWidth(editorWidth)
    self.inner:SetWidth(editorWidth)
    self.editBox:SetWidth(editorWidth - GUTTER_WIDTH - 4)
    self:LayoutGutter(self:GetText())
end

function methods:TogglePicker()
    local picker = self.picker
    if picker:IsShown() then
        picker:Hide()
    else
        picker.names = APLText.Names(RH.classData)
        picker.search:SetText("")
        picker.offset = 0
        self:FillPicker()
        picker:Show()
    end
    self:OnWidthSet(self.frame:GetWidth())
end

function methods:FillPicker()
    local picker = self.picker
    picker.filtered = APLText.Filter(picker.names, picker.search:GetText(), picker.filtered)
    local offset = picker.offset or 0
    for i, row in ipairs(picker.rows) do
        local entry = picker.filtered[i + offset]
        if entry then
            row.entry = entry
            row.text:SetText(entry.text)
            row.text:SetTextColor(unpack(KIND_COLORS[entry.kind]))
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function CreatePicker(self)
    local T = Theme()
    local picker = CreateFrame("Frame", nil, self.frame)
    picker:SetWidth(PICKER_WIDTH)
    picker:SetPoint("TOPRIGHT", self.box, "TOPRIGHT")
    picker:SetPoint("BOTTOMRIGHT", self.box, "BOTTOMRIGHT")
    ns.Window.Flat(picker, T.panel, T.border)
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = max(0, #(picker.filtered or {}) - PICKER_ROWS)
        picker.offset = max(0, min(maxOffset, (picker.offset or 0) - delta * 3))
        self:FillPicker()
    end)

    local search = CreateFrame("EditBox", nil, picker)
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", 6, -6)
    search:SetPoint("TOPRIGHT", -6, -6)
    search:SetAutoFocus(false)
    search:SetFont(T.font, 13, "")
    search:SetTextInsets(4, 4, 0, 0)
    ns.Window.Flat(search, T.control, T.border)
    search:SetScript("OnTextChanged", function()
        picker.offset = 0
        self:FillPicker()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    picker.search = search

    picker.rows = {}
    for i = 1, PICKER_ROWS do
        local row = CreateFrame("Button", nil, picker)
        row:SetHeight(PICKER_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4 - (i - 1) * PICKER_ROW_HEIGHT)
        row:SetPoint("RIGHT", picker, "RIGHT", -6, 0)
        row.text = ns.Window.Text(row, 12, T.text)
        row.text:SetPoint("LEFT", 2, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(r) if r.entry then self:Insert(r.entry.text) end end)
        picker.rows[i] = row
    end
    picker:Hide()
    return picker
end

-- Builds the widget's frames and methods (without registering it with
-- AceGUI, so tests can build one directly).
function APLEditor.Construct()
    local T = Theme()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    local self = { type = APLEditor.TYPE, frame = frame, numbers = {}, marks = {}, errorLines = {} }
    for name, fn in pairs(methods) do self[name] = fn end

    self.label = ns.Window.Text(frame, 13, T.textDim)
    self.label:SetPoint("TOPLEFT", 0, -2)

    -- Toolbar
    self.accept = FlatButton(frame, "Accept", 80, function() self:Accept() end)
    self.accept:SetPoint("TOPLEFT", 0, -LABEL_HEIGHT)
    local names = FlatButton(frame, "Names", 70, function() self:TogglePicker() end)
    names:SetPoint("LEFT", self.accept, "RIGHT", 6, 0)
    local export = FlatButton(frame, "Export", 70, function() APLEditor.ShowExport(self) end)
    export:SetPoint("LEFT", names, "RIGHT", 6, 0)
    local import = FlatButton(frame, "Import", 70, function() APLEditor.ShowImport(self) end)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    local share = FlatButton(frame, "Share", 70, function() APLEditor.ShowShare(self) end)
    share:SetPoint("LEFT", import, "RIGHT", 6, 0)
    self.toolbarButtons = { names, export, import, share }

    -- Editor box with a scroll frame; its scroll child holds the gutter,
    -- the error highlights and the edit box.
    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT", 0, -(LABEL_HEIGHT + TOOLBAR_HEIGHT + 2))
    box:SetPoint("RIGHT", frame, "RIGHT")
    ns.Window.Flat(box, T.panel, T.border)
    self.box = box

    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMLEFT", 4, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
        local maxScroll = max(0, self.inner:GetHeight() - s:GetHeight())
        s:SetVerticalScroll(max(0, min(maxScroll, s:GetVerticalScroll() - delta * FONT_SIZE * 3)))
    end)
    scroll:SetScript("OnMouseUp", function() self.editBox:SetFocus() end)
    self.scroll = scroll

    local inner = CreateFrame("Frame", nil, scroll)
    inner:SetHeight(100)
    scroll:SetScrollChild(inner)
    self.inner = inner

    local editBox = CreateFrame("EditBox", nil, inner)
    editBox:SetPoint("TOPLEFT", inner, "TOPLEFT", GUTTER_WIDTH, 0)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(T.font, FONT_SIZE, "")
    editBox:SetTextColor(unpack(T.text))
    editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
    editBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput and not self.recoloring then self:MarkChanged() end
    end)
    -- Keep the cursor in view while typing.
    editBox:SetScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
        y = -y
        local offset = scroll:GetVerticalScroll()
        if y < offset then
            scroll:SetVerticalScroll(y)
        elseif y + cursorHeight > offset + scroll:GetHeight() then
            scroll:SetVerticalScroll(y + cursorHeight - scroll:GetHeight())
        end
    end)
    self.editBox = editBox

    -- Measures how tall a line is once wrapped.
    local measure = inner:CreateFontString(nil, "BACKGROUND")
    measure:SetFont(T.font, FONT_SIZE, "")
    measure:SetAlpha(0)
    measure:SetText("X")
    self.measure = measure
    self.lineHeight = max(FONT_SIZE, measure:GetHeight() or 0)

    self.status = ns.Window.Text(frame, 13, T.text)
    self.status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
    self.status:SetPoint("RIGHT", frame, "RIGHT")
    self.status:SetJustifyH("LEFT")

    self.picker = CreatePicker(self)

    -- Debounced refresh after typing.
    self.OnUpdateScript = function()
        if self.pendingAt and GetTime() >= self.pendingAt then
            self.pendingAt = nil
            frame:SetScript("OnUpdate", nil)
            self:Refresh()
        end
    end

    frame.obj = self
    return self
end

---------------------------------------------------------------------------
-- Export / import / share popup
---------------------------------------------------------------------------
local popup

local function Popup(title)
    if not popup then
        local T = Theme()
        popup = ns.Window.Create({ name = "RotationHelperAPLPopup", title = title, width = 560, height = 150 })
        popup:SetFrameLevel(popup:GetFrameLevel() + 20)
        local box = CreateFrame("EditBox", nil, popup.content)
        box:SetHeight(24)
        box:SetPoint("TOPLEFT", 0, -4)
        box:SetPoint("RIGHT", popup.content, "RIGHT")
        box:SetAutoFocus(false)
        box:SetFont(T.font, 13, "")
        box:SetTextInsets(6, 6, 0, 0)
        ns.Window.Flat(box, T.control, T.border)
        box:SetScript("OnEscapePressed", function() popup:Hide() end)
        popup.box = box
        popup.hint = ns.Window.Text(popup.content, 13, T.textDim)
        popup.hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
        popup.hint:SetPoint("RIGHT", popup.content, "RIGHT")
        popup.hint:SetJustifyH("LEFT")
        popup.buttons = {}
    end
    popup.title:SetText(title)
    popup:Raise() -- above the options window
    for _, b in ipairs(popup.buttons) do b:Hide() end
    popup.box:SetScript("OnEnterPressed", nil)
    return popup
end

local function PopupButton(i, text, onClick)
    local b = popup.buttons[i]
    if not b then
        b = FlatButton(popup.content, text, 110, nil)
        b:SetPoint("BOTTOMLEFT", (i - 1) * 116, 0)
        popup.buttons[i] = b
    end
    b.label:SetText(text)
    b:SetScript("OnClick", onClick)
    SetButtonEnabled(b, true)
    b:Show()
    return b
end

function APLEditor.HidePopup()
    if popup then popup:Hide() end
end

function APLEditor.ShowExport(editor)
    local p = Popup("Export rotation")
    p.box:SetText(APLText.Export(ns.Options:EditSpec(), editor:GetText()))
    p.hint:SetText("Press Ctrl+C to copy, then paste it wherever you share it. Import reads it back.")
    PopupButton(1, "Close", function() p:Hide() end)
    p:Show()
    p.box:SetFocus()
    p.box:HighlightText()
end

-- Puts imported text into the editor (not saved until Accept).
function APLEditor.ApplyImport(editor, str)
    local specKey, text, err = APLText.Import(str)
    if not text then
        return false, err
    end
    editor:SetText(text)
    editor:MarkChanged()
    local note = "Imported: check it, then press Accept to save."
    if specKey and specKey ~= ns.Options:EditSpec() then
        note = format("Imported a %s rotation into the %s editor: check it, then press Accept to save.",
            specKey, tostring(ns.Options:EditSpec()))
    end
    editor.status:SetText(note)
    editor.status:SetTextColor(1, 0.82, 0)
    return true
end

function APLEditor.ShowImport(editor)
    local p = Popup("Import rotation")
    p.box:SetText("")
    p.hint:SetText("Paste an RH1: string (or plain rotation text) and press Import.")
    local function DoImport()
        local ok, err = APLEditor.ApplyImport(editor, p.box:GetText())
        if ok then p:Hide() else p.hint:SetText("|cffff6060" .. err .. "|r") end
    end
    p.box:SetScript("OnEnterPressed", DoImport)
    PopupButton(1, "Import", DoImport)
    PopupButton(2, "Cancel", function() p:Hide() end)
    p:Show()
    p.box:SetFocus()
end

function APLEditor.ShowShare(editor)
    local p = Popup("Share rotation")
    p.box:SetText("")
    p.hint:SetText("Send the editor's rotation to your party, raid, or a player (type a name above). "
        .. "They're asked before anything opens.")
    local function Send(channel, target)
        local ok, message = ns.APLShare:Send(channel, target, ns.Options:EditSpec(), editor:GetText())
        p.hint:SetText(ok and ("|cff66e080" .. message .. "|r") or ("|cffff6060" .. message .. "|r"))
    end
    PopupButton(1, "Party", function() Send("PARTY") end)
    PopupButton(2, "Raid", function() Send("RAID") end)
    PopupButton(3, "Whisper", function() Send("WHISPER", p.box:GetText()) end)
    PopupButton(4, "Close", function() p:Hide() end)
    p:Show()
end

---------------------------------------------------------------------------
-- Registration with AceGUI
---------------------------------------------------------------------------
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if AceGUI then
    AceGUI:RegisterWidgetType(APLEditor.TYPE, function()
        return AceGUI:RegisterAsWidget(APLEditor.Construct())
    end, VERSION)
end
