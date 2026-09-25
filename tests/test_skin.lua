local T = require("testlib")
local test, eq, truthy, falsy, newAddon = T.test, T.eq, T.truthy, T.falsy, T.newAddon

local s = newAddon()
local Skin = s.ns.Skin
local CreateFrame = s.env.CreateFrame
local ARIAL_NARROW = "Fonts\\ARIALN.TTF"

-- Fake AceGUI widgets, shaped like the r960 ones.
local function Widget(widgetType, fields)
    local w = fields or {}
    w.type = widgetType
    w.frame = w.frame or CreateFrame("Frame")
    w.releases = 0
    w.OnRelease = function(self) self.releases = self.releases + 1 end
    return w
end

local function CheckBox()
    local frame = CreateFrame("Button")
    local checkbg = frame:CreateTexture(nil, "ARTWORK")
    checkbg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    local check = frame:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetAllPoints(checkbg)
    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    return Widget("CheckBox", { frame = frame, checkbg = checkbg, check = check, highlight = highlight, text = text })
end

local function Shown(tex) return tex:IsShown() and tex:GetAlpha() > 0 end

---------------------------------------------------------------------------
test("checkbox: styled, then fully restored on release", function()
    local w = CheckBox()
    Skin.Apply(w)
    eq(w.checkbg:GetAlpha(), 0, "Blizzard box hidden")
    eq(w.highlight:GetAlpha(), 0, "Blizzard highlight hidden")
    eq(w.check:GetTexture(), nil, "check is a solid color")
    eq(w.check.color[3], Skin.theme.accent[3], "accent colored")
    eq((w.text:GetFont()), ARIAL_NARROW, "theme font")
    truthy(Shown(w.rhTextures.boxFill), "our box shown")

    w:OnRelease()
    eq(w.releases, 1, "the widget's own OnRelease still ran")
    eq(w.checkbg:GetAlpha(), 1, "Blizzard box back")
    eq(w.highlight:GetAlpha(), 1, "highlight back")
    eq(w.check:GetTexture(), "Interface\\Buttons\\UI-CheckBox-Check", "check texture back")
    eq((w.text:GetFont()), "Fonts\\FRIZQT__.TTF", "font back")
    falsy(w.rhTextures.boxFill:IsShown(), "our box hidden")
    falsy(w.rhSkinned, "not marked as styled")
    w:OnRelease()
    eq(w.releases, 2, "OnRelease is the original again")
end)

test("a widget styled again after reuse keeps our own textures visible", function()
    local w = CheckBox()
    Skin.Apply(w)
    w:OnRelease()
    Skin.Apply(w)
    truthy(Shown(w.rhTextures.boxFill), "fill visible")
    truthy(Shown(w.rhTextures.boxEdge), "edge visible")
    eq(w.checkbg:GetAlpha(), 0, "Blizzard box hidden again")
    w:OnRelease()
    eq(w.checkbg:GetAlpha(), 1, "and restored again")
end)

test("styling twice is a no-op", function()
    local w = CheckBox()
    Skin.Apply(w)
    local undo = #w.rhUndo
    Skin.Apply(w)
    eq(#w.rhUndo, undo, "nothing recorded twice")
end)

test("button: hover recolors our box only while styled", function()
    local frame = CreateFrame("Button", "AceGUI30Button1")
    frame:CreateTexture("AceGUI30Button1Left")
    frame.fontString = frame:CreateFontString()
    local w = Widget("Button", { frame = frame, text = frame.fontString })
    Skin.Apply(w)
    local fill = frame.rhHoverBox
    frame.scripts.OnEnter(frame)
    eq(fill.color[1], Skin.theme.controlHover[1], "hover color")
    frame.scripts.OnLeave(frame)
    eq(fill.color[1], Skin.theme.control[1], "normal color")
    eq(s.env.AceGUI30Button1Left:GetAlpha(), 0, "template texture hidden")
    w:OnRelease()
    eq(frame.rhHoverBox, nil, "hover target cleared")
    frame.scripts.OnEnter(frame) -- the hook stays but does nothing now
    eq(s.env.AceGUI30Button1Left:GetAlpha(), 1, "template texture back")
end)

test("backdrops are restored exactly", function()
    local frame = CreateFrame("Frame")
    local border = CreateFrame("Frame", nil, frame)
    local original = { bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "x", edgeSize = 16 }
    border:SetBackdrop(original)
    border:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    border:SetBackdropBorderColor(0.4, 0.4, 0.4)
    local content = CreateFrame("Frame", nil, border)
    local w = Widget("InlineGroup", { frame = frame, content = content, titletext = frame:CreateFontString() })
    Skin.Apply(w)
    eq(border:GetBackdrop(), Skin.BACKDROP, "flat backdrop")
    w:OnRelease()
    eq(border:GetBackdrop(), original, "original backdrop")
    eq(table.concat({ border:GetBackdropColor() }, ","), "0.1,0.1,0.1,0.5", "original color")
    eq(table.concat({ border:GetBackdropBorderColor() }, ","), "0.4,0.4,0.4", "original border")
end)

test("frames without a backdrop get none back", function()
    local frame = CreateFrame("Frame")
    local label = frame:CreateFontString()
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    local scrollBG = CreateFrame("Frame", nil, frame) -- no backdrop at all
    scrollFrame:SetPoint("TOPLEFT", scrollBG, "TOPLEFT", 5, -6)
    local button = CreateFrame("Button", nil, frame)
    local bar = CreateFrame("Slider", "MultiLineEditBox1ScrollFrameScrollBar", frame)
    bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local up = CreateFrame("Button", "MultiLineEditBox1ScrollFrameScrollBarScrollUpButton", bar)
    local w = Widget("MultiLineEditBox", { frame = frame, label = label, scrollFrame = scrollFrame,
        editBox = CreateFrame("EditBox", nil, scrollFrame), button = button, scrollBar = bar })
    Skin.Apply(w)
    eq(scrollBG:GetBackdrop(), Skin.BACKDROP, "styled")
    eq(bar:GetThumbTexture():GetTexture(), nil, "flat thumb")
    eq(up:GetAlpha(), 0, "arrow button hidden")
    w:OnRelease()
    eq(scrollBG:GetBackdrop(), nil, "no backdrop again")
    eq(bar:GetThumbTexture():GetTexture(), "Interface\\Buttons\\UI-ScrollBar-Knob", "thumb back")
    eq(up:GetAlpha(), 1, "arrow button back")
end)

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function Tab(group, id, selected)
    local tab = CreateFrame("Button", "AceGUITabGroup1Tab" .. id, group.border)
    tab:CreateTexture("AceGUITabGroup1Tab" .. id .. "Left")
    tab.text = tab:CreateFontString()
    tab.id = id
    tab.selected = selected
    tab.SetSelected = function(frame, value)
        frame.selected = value
        frame.blizzardLook = value and "selected" or "normal"
    end
    group.tabs[id] = tab
    return tab
end

local function TabGroup()
    local frame = CreateFrame("Frame")
    local border = CreateFrame("Frame", nil, frame)
    return Widget("TabGroup", { frame = frame, border = border, titletext = frame:CreateFontString(), tabs = {},
        content = CreateFrame("Frame", nil, border) })
end

test("tabs: selected tab in the accent color, follows selection", function()
    local group = TabGroup()
    local general = Tab(group, 1, true)
    local display = Tab(group, 2, false)
    Skin.Apply(group)
    eq(general.rhFill.color[1], Skin.theme.accent[1], "selected tab accent")
    eq(display.rhFill.color[1], Skin.theme.control[1], "other tab plain")
    general:SetSelected(false)
    display:SetSelected(true)
    eq(general.rhFill.color[1], Skin.theme.control[1], "deselected")
    eq(display.rhFill.color[1], Skin.theme.accent[1], "selected")
    eq(display.blizzardLook, "selected", "the original SetSelected still runs")
end)

test("tabs created later are styled on the next sweep", function()
    local group = TabGroup()
    Tab(group, 1, true)
    Skin.ApplyTree(group)
    local late = Tab(group, 2, false)
    falsy(late.rhSkinned, "not yet")
    Skin.ApplyTree(group)
    truthy(late.rhSkinned, "styled")
end)

test("tabs: release restores SetSelected and the Blizzard look", function()
    local group = TabGroup()
    local tab = Tab(group, 1, true)
    local original = tab.SetSelected
    Skin.Apply(group)
    group:OnRelease()
    eq(tab.SetSelected, original, "original method")
    falsy(tab.rhSkinned, "unmarked")
    eq(tab.blizzardLook, "selected", "Blizzard look re-applied")
    eq(s.env.AceGUITabGroup1Tab1Left:GetAlpha(), 1, "textures back")
end)

---------------------------------------------------------------------------
test("labels measure themselves again after the font change", function()
    local frame = CreateFrame("Frame")
    local w = Widget("Label", { frame = frame, label = frame:CreateFontString() })
    w.label:SetText("Some description")
    w.SetText = function(self, text) self.measuredWith = (self.label:GetFont()) end
    Skin.Apply(w)
    eq(w.measuredWith, ARIAL_NARROW, "re-measured with the new font")
end)

test("ApplyTree counts new widgets; Relayout lays out inner containers first", function()
    local order = {}
    local function Container(name, children)
        local c = Widget("SimpleGroup", { children = children or {} })
        c.DoLayout = function() order[#order + 1] = name end
        return c
    end
    local inner = Container("inner", { CheckBox(), CheckBox() })
    local outer = Container("outer", { inner })
    eq(Skin.ApplyTree(outer), 2, "two checkboxes styled")
    eq(Skin.ApplyTree(outer), 0, "nothing new the second time")
    Skin.Relayout(outer)
    eq(table.concat(order, ","), "inner,outer", "innermost first")
end)

test("ApplyTree walks children and ignores unknown widget types", function()
    local parent = Widget("SimpleGroup", { children = {} })
    local box = CheckBox()
    local unknown = Widget("Keybinding")
    parent.children = { box, unknown }
    Skin.ApplyTree(parent)
    truthy(box.rhSkinned, "child styled")
    falsy(unknown.rhSkinned, "unknown type left alone")
    falsy(parent.rhSkinned, "SimpleGroup has nothing to style")
end)
